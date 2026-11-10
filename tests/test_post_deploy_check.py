"""scripts/post-deploy-check.sh: after a deploy, Dozzle sees every agent, or it is restarted once.

The script runs against a stand-in `docker` (a shell script first on PATH) and a local HTTP server that serves a
page like Dozzle's: its hosts in a `config__json` element. `docker compose restart dozzle` makes the stand-in
publish a page with every host available, or leave it as it is (an agent whose host is really down).
"""

from __future__ import annotations

import http.server
import json
import os
import shutil
import subprocess
import threading
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Iterator

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "post-deploy-check.sh"
BASH = shutil.which("bash") or "/bin/bash"
HOSTS = ["local", "agent-one.example.com:7007"]

DOCKER = """#!/usr/bin/env bash
case "$*" in
  "compose ps --status running --quiet dozzle")
    if [ "$STUB_RUNNING" = yes ]; then echo abc123; fi ;;
  "compose config --format json")
    printf '{"services":{"dozzle":{"environment":{"DOZZLE_REMOTE_AGENT":"%s"}}}}\\n' "$STUB_AGENTS" ;;
  "compose restart dozzle")
    echo restarted >>"$STUB_LOG"
    if [ "$STUB_RESTART_FIXES" = yes ]; then cp "$STUB_FIXED_PAGE" "$STUB_PAGE"; fi ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
"""


def page(unavailable: list[str]) -> str:
    hosts = [{"endpoint": host, "available": host not in unavailable} for host in HOSTS]
    config = json.dumps({"hosts": hosts})
    return f'<html><script type="application/json" id="config__json">{config}</script></html>'


class Handler(http.server.BaseHTTPRequestHandler):
    """Serves the file named by the server's `page` attribute, read at each request."""

    def do_GET(self) -> None:
        body = Path(self.server.page).read_bytes()  # type: ignore[attr-defined]
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args: object) -> None:
        """Keeps the test output quiet."""


@pytest.fixture
def server(tmp_path: Path) -> Iterator[http.server.HTTPServer]:
    httpd = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    httpd.page = tmp_path / "page.html"  # type: ignore[attr-defined]
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield httpd
    httpd.shutdown()
    httpd.server_close()


def run_check(  # noqa: PLR0913 - one switch for each thing the stand-in docker can do
    tmp_path: Path,
    server: http.server.HTTPServer,
    *,
    unavailable: list[str],
    restart_fixes: bool = True,
    running: bool = True,
    agents: str = "agent-one.example.com:7007",
) -> tuple[subprocess.CompletedProcess[str], int]:
    """Runs the script from a copy, so its `cd ..` lands in tmp_path; returns the result and the restart count."""
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    shutil.copy(SCRIPT, scripts / SCRIPT.name)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "docker").write_text(DOCKER, encoding="utf-8")
    (bin_dir / "docker").chmod(0o755)
    Path(server.page).write_text(page(unavailable), encoding="utf-8")  # type: ignore[attr-defined]
    (tmp_path / "fixed.html").write_text(page([]), encoding="utf-8")
    env = os.environ | {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "STUB_RUNNING": "yes" if running else "no",
        "STUB_AGENTS": agents,
        "STUB_RESTART_FIXES": "yes" if restart_fixes else "no",
        "STUB_LOG": str(tmp_path / "log"),
        "STUB_PAGE": str(server.page),  # type: ignore[attr-defined]
        "STUB_FIXED_PAGE": str(tmp_path / "fixed.html"),
        "DOZZLE_CHECK_URL": f"http://127.0.0.1:{server.server_port}/",
        "DOZZLE_CHECK_WAIT": "0",
    }
    # The script is this repository's own, run from a copy.
    result = subprocess.run(  # noqa: S603
        [BASH, str(scripts / SCRIPT.name)], env=env, capture_output=True, text=True, timeout=60, check=False
    )
    log = tmp_path / "log"
    restarts = len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0
    return result, restarts


def test_passes_without_a_restart_when_every_host_is_available(tmp_path: Path, server: http.server.HTTPServer) -> None:
    result, restarts = run_check(tmp_path, server, unavailable=[])
    assert result.returncode == 0, result.stderr
    assert "Dozzle sees every host" in result.stdout
    assert restarts == 0


def test_restarts_dozzle_once_when_a_host_is_unavailable(tmp_path: Path, server: http.server.HTTPServer) -> None:
    result, restarts = run_check(tmp_path, server, unavailable=[HOSTS[1]])
    assert result.returncode == 0, result.stderr
    assert "doesn't see: agent-one.example.com:7007; restarting it" in result.stdout
    assert "after the restart" in result.stdout
    assert restarts == 1


def test_fails_when_a_host_is_still_unavailable_after_the_restart(
    tmp_path: Path, server: http.server.HTTPServer
) -> None:
    result, restarts = run_check(tmp_path, server, unavailable=[HOSTS[1]], restart_fixes=False)
    assert result.returncode == 1
    assert "still doesn't see: agent-one.example.com:7007" in result.stderr
    assert restarts == 1


def test_nothing_to_check_without_agents(tmp_path: Path, server: http.server.HTTPServer) -> None:
    result, restarts = run_check(tmp_path, server, unavailable=[HOSTS[1]], agents="")
    assert result.returncode == 0, result.stderr
    assert "nothing to check" in result.stdout
    assert restarts == 0


def test_nothing_to_check_when_dozzle_is_not_running(tmp_path: Path, server: http.server.HTTPServer) -> None:
    result, restarts = run_check(tmp_path, server, unavailable=[HOSTS[1]], running=False)
    assert result.returncode == 0, result.stderr
    assert "isn't running" in result.stdout
    assert restarts == 0


def test_rejects_a_wait_that_is_not_a_number(tmp_path: Path, server: http.server.HTTPServer) -> None:
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    shutil.copy(SCRIPT, scripts / SCRIPT.name)
    env = os.environ | {"DOZZLE_CHECK_WAIT": "soon", "DOZZLE_CHECK_URL": f"http://127.0.0.1:{server.server_port}/"}
    result = subprocess.run(  # noqa: S603
        [BASH, str(scripts / SCRIPT.name)], env=env, capture_output=True, text=True, timeout=60, check=False
    )
    assert result.returncode == 2
    assert "must be a number of seconds" in result.stderr
