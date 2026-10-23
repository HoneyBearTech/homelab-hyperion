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
    "steerhouse": "/data",
    "steerhouse-postgres": "/var/lib/postgresql",
}
# Mounts that aren't app data: the downloads, finished and incomplete (never backed up), and the Docker socket.
OTHER_MOUNTS = {
    "${DOWNLOADS_PATH:?set DOWNLOADS_PATH in .env}:/downloads",
    "${INCOMPLETE_PATH:?set INCOMPLETE_PATH in .env}:/incomplete",
    "/var/run/docker.sock:/var/run/docker.sock:ro",
}
# Another app's folder, read-only: Steerhouse's workers read the API's Galaxy roles and collections.
SHARED_MOUNTS = {
    "steerhouse-worker": {f"{CONFIG_ROOT}/steerhouse/config/galaxy:/galaxy:ro"},
}
# Steerhouse's secrets: Docker secret files in its folder under CONFIG_ROOT (never backed up), for the database and
# the API only.
STEERHOUSE_SECRETS = {
    "steerhouse-postgres": {"postgres_password"},
    "steerhouse": {
        "database_url",
        "auth_secret_key",
        "credential_encryption_key",
        "admin_password",
        "grafana_db_password",
    },
}
# The certificate and key Dozzle and its agents authenticate each other with: Docker secret files in Dozzle's folder
# under CONFIG_ROOT (never backed up), so it never uses the pair built into every Dozzle image.
DOZZLE_SECRETS = {
    "dozzle_cert": "dozzle/certs/dozzle_cert.pem",
    "dozzle_key": "dozzle/certs/dozzle_key.pem",
}


def mount(volume: str | dict) -> str:
    """A volume as Compose's short syntax (``source:target``, ``:ro`` when read-only), from either syntax."""
    if isinstance(volume, str):
        return volume
    return f"{volume['source']}:{volume['target']}" + (":ro" if volume.get("read_only") else "")


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
        assert f"{CONFIG_ROOT}/{app}/config:{path}" in [mount(v) for v in services[app]["volumes"]]


def test_every_data_mount_comes_from_the_apps_folder_under_config_root() -> None:
    for name, service in compose()["services"].items():
        for volume in map(mount, service.get("volumes") or []):
            if volume in OTHER_MOUNTS or volume in SHARED_MOUNTS.get(name, set()):
                continue
            assert re.fullmatch(re.escape(f"{CONFIG_ROOT}/{name}/") + r"[a-z0-9-]+:/[^:]+", volume), (
                f"{name} mounts {volume}, not a folder under CONFIG_ROOT/{name}/"
            )


def test_no_named_volumes() -> None:
    config = compose()
    assert "volumes" not in config
    for name, service in config["services"].items():
        for volume in service.get("volumes") or []:
            assert isinstance(volume, str) or volume["type"] == "bind", f"{name} mounts a named volume: {volume}"
            assert mount(volume).startswith(("/", "${")), f"{name} mounts a named volume: {volume}"


def test_no_path_points_into_docker_volumes() -> None:
    settings = re.findall(r"^[A-Z][A-Z0-9_]*=(.*)$", read(".env.example"), re.MULTILINE)
    assert not [value for value in settings if "/var/lib/docker" in value]
    for name, service in compose()["services"].items():
        for volume in map(mount, service.get("volumes") or []):
            assert "/var/lib/docker" not in volume, f"{name} mounts {volume}"


def test_the_docs_warn_against_docker_volumes_for_app_data() -> None:
    for path in ("docs/installing.md", "CLAUDE.md"):
        text = " ".join(read(path).split())
        assert "/var/lib/docker/volumes" in text, path
        assert "docker volume prune" in text, path


def test_steerhouse_secrets_are_files_under_config_root_for_the_database_and_api_only() -> None:
    config = compose()
    for name, secret in config["secrets"].items():
        if name in DOZZLE_SECRETS:
            continue
        target = name.removeprefix("steerhouse_")
        assert secret == {"file": f"{CONFIG_ROOT}/steerhouse/secrets/{target}"}, name
    for name, service in config["services"].items():
        if name == "dozzle":
            continue
        targets = {s["target"] for s in service.get("secrets") or []}
        assert targets == STEERHOUSE_SECRETS.get(name, set()), name
        assert all(s["source"] == f"steerhouse_{s['target']}" for s in service.get("secrets") or []), name


def test_dozzle_reads_its_certificate_and_key_from_secret_files_under_config_root() -> None:
    config = compose()
    for name, path in DOZZLE_SECRETS.items():
        assert config["secrets"][name] == {"file": f"{CONFIG_ROOT}/{path}"}, name
    dozzle = config["services"]["dozzle"]
    assert dozzle["secrets"] == list(DOZZLE_SECRETS)
    assert dozzle["environment"]["DOZZLE_CERT"] == "/run/secrets/dozzle_cert"
    assert dozzle["environment"]["DOZZLE_KEY"] == "/run/secrets/dozzle_key"


def test_steerhouse_env_example_has_the_tokens_only() -> None:
    keys = re.findall(r"^([A-Z][A-Z0-9_]*)=(.*)$", read("steerhouse.env.example"), re.MULTILINE)
    assert keys == [("WORKER_TOKEN", ""), ("METRICS_TOKEN", "")]
    interfaces = read("docs/interfaces.md")
    for key, _ in keys:
        assert f"`{key}`" in interfaces


def test_steerhouse_database_admits_remote_logins_over_tls_for_grafana_ro_only() -> None:
    service = compose()["services"]["steerhouse-postgres"]
    rules = [line.split() for line in service["environment"]["PG_HBA"].splitlines() if not line.startswith("#")]
    assert rules == [
        ["local", "all", "all", "trust"],
        [
            "host",
            "steerhouse",
            "steerhouse",
            "${STEERHOUSE_DB_SUBNET:?set",
            "STEERHOUSE_DB_SUBNET",
            "in",
            ".env}",
            "scram-sha-256",
        ],
        ["hostssl", "steerhouse", "grafana_ro", "all", "scram-sha-256"],
        ["host", "all", "all", "all", "reject"],
    ]
    assert "ssl=on" in service["command"]
    assert "hba_file=/tmp/pg_hba.conf" in service["command"]
    db = compose()["networks"]["steerhouse-db"]
    assert db["internal"] is True
    assert db["ipam"]["config"] == [{"subnet": "${STEERHOUSE_DB_SUBNET:?set STEERHOUSE_DB_SUBNET in .env}"}]
