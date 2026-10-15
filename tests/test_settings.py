import re
from pathlib import Path

import yaml

ROOT = Path(__file__).parent.parent
CONFIG_ROOT = "${CONFIG_ROOT:?set CONFIG_ROOT in .env}"
# Each app's data path in its container, mounted from CONFIG_ROOT/<app>/config.
APPS = {
    "prowlarr": "/config",
    "qbittorrent": "/config",
    "heimdall": "/config",
    "dozzle": "/data",
    "minecraft": "/data",
}
# Mounts that aren't app data: the downloads (never backed up) and the Docker socket.
OTHER_MOUNTS = {
    "${DOWNLOADS_PATH:?set DOWNLOADS_PATH in .env}:/downloads",
    "/var/run/docker.sock:/var/run/docker.sock:ro",
}


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def compose() -> dict:
    return yaml.safe_load(read("compose.yaml"))


def test_every_setting_is_in_env_example_and_interfaces() -> None:
    used = set(re.findall(r"\$\{([A-Z][A-Z0-9_]*)", read("compose.yaml")))
    example = set(re.findall(r"^([A-Z][A-Z0-9_]*)=", read(".env.example"), re.MULTILINE))
    table = re.findall(r"^\| (`[A-Z][^|]*) \|", read("docs/interfaces.md"), re.MULTILINE)
    documented = {name for cell in table for name in re.findall(r"`([A-Z][A-Z0-9_]*)`", cell)}
    assert used == example
    assert used <= documented


def test_each_app_keeps_its_data_in_its_folder_under_config_root() -> None:
    services = compose()["services"]
    for app, path in APPS.items():
        assert f"{CONFIG_ROOT}/{app}/config:{path}" in services[app]["volumes"]


def test_every_data_mount_comes_from_the_apps_folder_under_config_root() -> None:
    for name, service in compose()["services"].items():
        for volume in service.get("volumes") or []:
            if volume in OTHER_MOUNTS:
                continue
            assert re.fullmatch(re.escape(f"{CONFIG_ROOT}/{name}/") + r"[a-z0-9-]+:/[^:]+", volume), (
                f"{name} mounts {volume}, not a folder under CONFIG_ROOT/{name}/"
            )


def test_no_named_volumes() -> None:
    config = compose()
    assert "volumes" not in config
    for name, service in config["services"].items():
        for volume in service.get("volumes") or []:
            assert volume.startswith(("/", "${")), f"{name} mounts a named volume: {volume}"


def test_no_path_points_into_docker_volumes() -> None:
    settings = re.findall(r"^[A-Z][A-Z0-9_]*=(.*)$", read(".env.example"), re.MULTILINE)
    assert not [value for value in settings if "/var/lib/docker" in value]
    for name, service in compose()["services"].items():
        for volume in service.get("volumes") or []:
            assert "/var/lib/docker" not in volume, f"{name} mounts {volume}"


def test_the_docs_warn_against_docker_volumes_for_app_data() -> None:
    for path in ("docs/installing.md", "CLAUDE.md"):
        text = " ".join(read(path).split())
        assert "/var/lib/docker/volumes" in text, path
        assert "docker volume prune" in text, path
