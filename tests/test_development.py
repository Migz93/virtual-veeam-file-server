"""Verify that lifecycle operations preserve other work and active commands."""
import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import call, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("vvfs_manager", ROOT / ".devcontainer/manage.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


def container():
    return {
        "Id": "development-container-id",
        "Config": {"Labels": {"devcontainer.local_folder": str(manager.WORKSPACE)}},
        "Mounts": [{"Type": "bind", "Source": str(manager.WORKSPACE),
                    "Destination": manager.TARGET, "RW": True}],
        "HostConfig": {},
        "State": {"Running": True},
    }


class DevelopmentTests(unittest.TestCase):
    def test_preserves_other_checkouts_and_unexpected_configuration(self):
        for mutation in ("owner", "credentials", "volume", "privileged", "ports", "tmpfs"):
            with self.subTest(mutation=mutation):
                data = container()
                if mutation == "owner":
                    data["Config"]["Labels"]["devcontainer.local_folder"] = "/another/checkout"
                elif mutation == "credentials":
                    data["Mounts"].append({"Type": "bind", "Source": "/private/auth",
                                           "Destination": "/home/vscode/.ssh", "RW": True})
                elif mutation == "volume":
                    data["Mounts"][0]["Type"] = "volume"
                elif mutation == "privileged":
                    data["HostConfig"]["Privileged"] = True
                elif mutation == "ports":
                    data["HostConfig"]["PortBindings"] = {"22/tcp": []}
                else:
                    data["HostConfig"]["Tmpfs"] = {"/retained": ""}
                with self.assertRaises(SystemExit):
                    manager.verify(data)

    def test_daemon_errors_do_not_mean_container_is_absent(self):
        error = subprocess.CompletedProcess([], 1, stdout="", stderr="Cannot connect to Docker daemon")
        with patch.object(manager.subprocess, "run", return_value=error):
            with self.assertRaisesRegex(SystemExit, "inspection failed"):
                manager.inspect()

    def test_missing_container_is_absent(self):
        error = subprocess.CompletedProcess([], 1, stdout="", stderr="No such container: test")
        with patch.object(manager.subprocess, "run", return_value=error):
            self.assertIsNone(manager.inspect())

    def invoke_down(self, commands, running=True):
        data = container()
        data["State"]["Running"] = running
        with tempfile.TemporaryDirectory() as temp:
            with (
                patch.object(manager.Path, "home", return_value=Path(temp)),
                patch.object(sys, "argv", ["manage.py", "down"]),
                patch.object(manager.shutil, "which", return_value="/tools/devcontainer"),
                patch.object(manager, "inspect", return_value=data),
                patch.object(manager.subprocess, "check_output", return_value=commands),
                patch.object(manager, "run") as action,
                patch("builtins.print"),
            ):
                try:
                    manager.main()
                except SystemExit:
                    action.assert_not_called()
                    raise
                return action.call_args_list

    def test_active_process_prevents_cleanup(self):
        with self.assertRaisesRegex(SystemExit, "cleanup deferred"):
            self.invoke_down("PID COMMAND\n1 sh\n2 python3\n")

    def test_commandless_process_row_defers_cleanup(self):
        with self.assertRaisesRegex(SystemExit, "Unrecognised process list; cleanup deferred"):
            self.invoke_down("PID COMMAND\n1 sh\n2\n")

    def test_exec_forwards_documented_command_and_literal_glob(self):
        command = ["python3", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"]
        with tempfile.TemporaryDirectory() as temp:
            with (
                patch.object(manager.Path, "home", return_value=Path(temp)),
                patch.object(sys, "argv", ["manage.py", "exec", *command]),
                patch.object(manager.shutil, "which", return_value="/tools/devcontainer"),
                patch.object(manager, "inspect", return_value=container()),
                patch.object(manager, "run") as action,
            ):
                manager.main()
                action.assert_called_once_with("/tools/devcontainer", "exec",
                                               "--workspace-folder", str(manager.WORKSPACE),
                                               *command)

    def test_up_rejects_unexpected_container_without_reporting_ready(self):
        unexpected = container()
        unexpected["Config"]["Labels"]["devcontainer.local_folder"] = "/another/checkout"
        with tempfile.TemporaryDirectory() as temp:
            with (
                patch.object(manager.Path, "home", return_value=Path(temp)),
                patch.object(sys, "argv", ["manage.py", "up"]),
                patch.object(manager.shutil, "which", return_value="/tools/devcontainer"),
                patch.object(manager, "inspect", side_effect=[None, unexpected]),
                patch.object(manager.subprocess, "run",
                             return_value=subprocess.CompletedProcess([], 0)) as startup,
                patch.object(manager, "run") as action,
                patch("builtins.print") as output,
            ):
                with self.assertRaisesRegex(SystemExit, "another checkout; preserved"):
                    manager.main()
                startup.assert_called_once()
                action.assert_not_called()
                output.assert_not_called()

    def test_failed_runtime_build_does_not_start_cleanup_container(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            fake_docker = work / "docker"
            log = work / "docker-calls"
            fake_docker.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$VVFS_TEST_DOCKER_LOG"\nexit 42\n')
            fake_docker.chmod(0o755)
            env = dict(os.environ, PATH=str(work) + os.pathsep + os.environ["PATH"],
                       TMPDIR=str(work), VVFS_TEST_DOCKER_LOG=str(log),
                       IMAGE_NAME="virtual-veeam-file-server:synthetic-build-failure")
            result = subprocess.run(["bash", str(ROOT / "tests/run-container-tests.sh")],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            calls = log.read_text().splitlines()
            self.assertEqual(len(calls), 1, calls)
            self.assertTrue(calls[0].startswith("build "), calls)
            self.assertFalse(list(work.glob("zdev-virtual-veeam-file-server-e2e.*")))

    def test_extra_shell_prevents_cleanup(self):
        with self.assertRaisesRegex(SystemExit, "cleanup deferred"):
            self.invoke_down("PID COMMAND\n1 sh\n2 sh\n3 sleep\n")

    def test_idle_container_is_removed_by_verified_id(self):
        self.assertEqual(self.invoke_down("PID COMMAND\n1 sh\n2 sleep\n"), [
            call("docker", "stop", "development-container-id"),
            call("docker", "rm", "development-container-id"),
        ])

    def test_stopped_container_is_removed_without_stop(self):
        self.assertEqual(self.invoke_down("", running=False), [
            call("docker", "rm", "development-container-id"),
        ])

    def test_contended_lock_prevents_docker_operations(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / ".local/state/virtual-veeam-file-server-dev"
            state.mkdir(parents=True)
            with (state / "lifecycle.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with (
                    patch.object(manager.Path, "home", return_value=Path(temp)),
                    patch.object(sys, "argv", ["manage.py", "down"]),
                    patch.object(manager.shutil, "which", return_value="/tools/devcontainer"),
                    patch.object(manager, "inspect") as inspect,
                    patch.object(manager, "run") as action,
                ):
                    with self.assertRaisesRegex(SystemExit, "command is active"):
                        manager.main()
                    inspect.assert_not_called()
                    action.assert_not_called()


if __name__ == "__main__":
    unittest.main()
