"""Verify that lifecycle operations preserve other work and active commands."""
import fcntl
import importlib.util
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
