#!/usr/bin/env python3
"""Host-only management for this checkout's disposable Dev Container."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess
import sys

NAME = "zdev-virtual-veeam-file-server"
WORKSPACE = Path(__file__).resolve().parent.parent
TARGET = "/workspaces/virtual-veeam-file-server"


def inspect():
    result = subprocess.run(["docker", "container", "inspect", NAME],
                            capture_output=True, text=True)
    if result.returncode:
        if "No such container" in result.stderr or "No such object" in result.stderr:
            return None
        raise SystemExit("Docker inspection failed; no resources changed.")
    return json.loads(result.stdout)[0]


def verify(container):
    labels = container["Config"].get("Labels") or {}
    if labels.get("devcontainer.local_folder") != str(WORKSPACE):
        raise SystemExit("Container belongs to another checkout; preserved.")
    mounts = container.get("Mounts", [])
    if len(mounts) != 1 or not (
        mounts[0]["Type"] == "bind" and mounts[0]["Source"] == str(WORKSPACE)
        and mounts[0]["Destination"] == TARGET and mounts[0]["RW"]
    ):
        raise SystemExit("Unexpected mounts; preserved for inspection.")
    host = container["HostConfig"]
    if host.get("Privileged") or host.get("PortBindings") or host.get("Tmpfs"):
        raise SystemExit("Unexpected container configuration; preserved.")


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["up", "exec", "down", "status"])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "exec" and not args.command:
        parser.error("exec requires a command")
    if args.action != "exec" and args.command:
        parser.error("only exec accepts a command")
    cli = shutil.which("devcontainer")
    if not cli:
        raise SystemExit("Install the official Dev Container CLI on the host.")
    state = Path.home() / ".local/state/virtual-veeam-file-server-dev"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    with (state / "lifecycle.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("Another Virtual Veeam File Server container command is active; try later.")
        container = inspect()
        if container:
            verify(container)
        if args.action == "up":
            log = state / "up.log"
            with log.open("w") as output:
                log.chmod(0o600)
                result = subprocess.run([cli, "up", "--workspace-folder", str(WORKSPACE)],
                                        stdout=output, stderr=subprocess.STDOUT)
            if result.returncode:
                raise SystemExit("Startup failed; inspect private log: " + str(log))
            container = inspect()
            if not container:
                raise SystemExit("Startup did not create the expected container.")
            verify(container)
            print("Ready: " + NAME)
        elif args.action == "exec":
            if not container or not container["State"]["Running"]:
                raise SystemExit("Start the Virtual Veeam File Server devcontainer first.")
            run(cli, "exec", "--workspace-folder", str(WORKSPACE), *args.command)
        elif args.action == "down" and container:
            if container["State"]["Running"]:
                rows = subprocess.check_output(
                    ["docker", "top", container["Id"], "-eo", "pid,comm"], text=True
                ).splitlines()[1:]
                commands = []
                for row in rows:
                    parts = row.split(maxsplit=1)
                    if len(parts) != 2:
                        raise SystemExit("Unrecognised process list; cleanup deferred.")
                    commands.append(parts[1].strip())
                if any(command not in {"sh", "sleep", "docker-init", "tini"}
                       for command in commands) or commands.count("sh") > 1:
                    raise SystemExit("Development processes remain; cleanup deferred.")
                run("docker", "stop", container["Id"])
            run("docker", "rm", container["Id"])
            print("Removed: " + NAME)
        elif args.action == "status":
            print(container["State"]["Status"] if container else "absent")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
