"""Backend tests use isolated directories; no package installation or user assets."""
import hashlib
import base64
import http.server
import importlib.util
import io
import json
import os
import socket
import shutil
import signal
import subprocess
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
WORKER = ROOT / "platform/android/java/editor/src/main/assets/godot_ai/blender_worker.py"
spec = importlib.util.spec_from_file_location("blender_worker", WORKER)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class BootstrapTests(unittest.TestCase):
    def script(self, port, token):
        template = WORKER.with_name("blender_bootstrap.sh").read_text()
        return (template.replace("__GODOT_INSTALL_PYTHON__", "false")
                .replace("__GODOT_WORKER_BASE64__", base64.b64encode(WORKER.read_bytes()).decode())
                .replace("__GODOT_PORT__", str(port)).replace("__GODOT_TOKEN__", token))

    def test_pasted_command_starts_authenticated_worker_without_android_intent(self):
        with tempfile.TemporaryDirectory(prefix="godot-blender-pairing-") as home:
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            token = "c" * 64
            encoded = base64.b64encode(self.script(port, token).encode()).decode()
            command = f"printf '%s' '{encoded}' | base64 -d | bash"
            process = subprocess.Popen([shutil.which("bash"), "-c", command],
                                       env={**os.environ, "HOME": home}, start_new_session=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 10
                request = urllib.request.Request(f"http://127.0.0.1:{port}/v1/health",
                                                 headers={"Authorization": "Bearer " + token})
                while True:
                    try:
                        with urllib.request.urlopen(request, timeout=1) as response:
                            health = json.load(response)
                        break
                    except urllib.error.URLError:
                        self.assertIsNone(process.poll(), "Bootstrap exited before serving health")
                        self.assertLess(time.monotonic(), deadline)
                        time.sleep(.05)
                self.assertEqual(health["protocol"], 1)
                self.assertTrue(health["ok"])
                installed = Path(home)/".local/share/godot-ai/blender/worker.py"
                self.assertEqual(installed.read_bytes(), WORKER.read_bytes())
                self.assertEqual(installed.stat().st_mode & 0o777, 0o600)
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/health", timeout=1)
                self.assertEqual(error.exception.code, 401)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=5)
                self.assertNotIn(token.encode(), stdout + stderr)

    def test_missing_python_reports_failure_without_installation(self):
        with tempfile.TemporaryDirectory(prefix="godot-blender-no-python-") as home:
            result = subprocess.run([shutil.which("bash"), "-s"], input=self.script(12345, "d" * 64),
                                    text=True, capture_output=True, timeout=5,
                                    env={**os.environ, "HOME": home, "PATH": str(Path(home)/"empty")})
            self.assertEqual(result.returncode, 42)
            self.assertIn("Python lipsește", result.stderr)
            self.assertFalse((Path(home)/".local").exists())


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="godot-blender-unit-")
        self.backend = worker.Backend(self.scratch.name)

    def tearDown(self):
        self.scratch.cleanup()

    def request(self, script=b"print('fixture')\n"):
        return {"id": str(uuid.uuid4()), "kind": "run", "args": {
            "script": "scripts/create.py", "inputs": [{"path": "scripts/create.py", "bytes": len(script),
                "sha256": hashlib.sha256(script).hexdigest()}], "seconds": 5}}

    def stage(self, script=b"print('fixture')\n"):
        request = self.request(script)
        self.backend.create(request)
        self.backend.upload(request["id"], "scripts/create.py", io.BytesIO(script), len(script))
        return request

    def wait(self, job_id):
        deadline = time.monotonic() + 5
        while self.backend.state(job_id)["status"] not in ("completed", "failed", "cancelled"):
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.03)
        return self.backend.state(job_id)

    def test_paths_and_manifest_validation(self):
        for name in ("../escape", "/absolute", "a/../b", "a//b", ".ssh/key", "a\\b", "a\x00b"):
            with self.subTest(name=name), self.assertRaises(worker.Fault):
                worker.relative(name)
        for key, value in (("seconds", 1.5), ("seconds", 601), ("script", "other.py"), ("blend", "missing.blend")):
            request = self.request()
            request["args"][key] = value
            with self.subTest(key=key), self.assertRaises(worker.Fault):
                self.backend.create(request)

    def test_upload_hash_and_unlisted_input_rejected(self):
        request = self.request(b"expected")
        self.backend.create(request)
        with self.assertRaises(worker.Fault):
            self.backend.upload(request["id"], "scripts/create.py", io.BytesIO(b"modified"), 8)
        with self.assertRaises(worker.Fault):
            self.backend.upload(request["id"], "foreign.py", io.BytesIO(b"x"), 1)
        with self.assertRaises(worker.Fault):
            self.backend.start(request["id"])
        self.assertFalse((self.backend.directory(request["id"]) / "project/scripts/create.py.upload").exists())

    def test_repeated_submission_executes_once(self):
        request = self.stage()
        calls = []
        with patch.object(self.backend, "run", side_effect=lambda *_args: calls.append(1) or {"artifacts": []}):
            self.backend.start(request["id"])
            self.wait(request["id"])
            self.assertEqual(self.backend.create(request)["status"], "completed")
            self.assertEqual(self.backend.start(request["id"])["status"], "completed")
        self.assertEqual(calls, [1])
        request["args"]["seconds"] = 6
        with self.assertRaises(worker.Fault) as failure:
            self.backend.create(request)
        self.assertEqual(failure.exception.code, "job_conflict")

    def test_one_process_at_a_time_and_cancel(self):
        request = self.stage()
        gate = threading.Event()
        with patch.object(self.backend, "run", side_effect=lambda *_args: gate.wait(2) or {}):
            self.backend.start(request["id"])
            with self.assertRaises(worker.Fault) as failure:
                self.backend.create(self.request())
            self.assertEqual(failure.exception.code, "busy")
            gate.set()
            self.wait(request["id"])
        other = self.stage()
        self.assertEqual(self.backend.cancel(other["id"])["status"], "cancelled")
        self.assertEqual(self.backend.start(other["id"])["status"], "cancelled")

    def test_cancel_kills_only_owned_process_group(self):
        request = self.stage()
        def run(job_id, _args):
            self.backend.command(job_id, [sys.executable, "-c", "import time; time.sleep(30)"], 20)
        with patch.object(self.backend, "run", side_effect=run):
            self.backend.start(request["id"])
            time.sleep(0.2)
            self.backend.cancel(request["id"])
            self.assertEqual(self.wait(request["id"])["code"], "cancelled")

    def test_package_transaction_finishes_before_cancel(self):
        request = self.stage()
        marker = Path(self.scratch.name) / "transaction-done"
        def run(job_id, _args):
            self.backend.command(job_id, [sys.executable, "-c", "import time,pathlib; time.sleep(.4); pathlib.Path(" + repr(str(marker)) + ").touch()"], 5, False)
        with patch.object(self.backend, "run", side_effect=run):
            self.backend.start(request["id"])
            time.sleep(0.15)
            self.backend.cancel(request["id"])
            self.assertEqual(self.wait(request["id"])["code"], "cancelled")
        self.assertTrue(marker.exists())

    def test_restart_marks_incomplete_job_without_replaying(self):
        request = self.stage()
        self.backend.update(request["id"], status="running")
        restarted = worker.Backend(self.scratch.name)
        self.assertEqual(restarted.state(request["id"])["status"], "interrupted")
        self.assertEqual(restarted.create(request)["status"], "interrupted")

    def test_artifact_symlinks_rejected(self):
        request = self.stage()
        root = self.backend.directory(request["id"]) / "output"
        (root / "model.glb").write_bytes(b"example")
        artifacts = self.backend.artifacts(request["id"])
        self.assertEqual(artifacts[0]["sha256"], hashlib.sha256(b"example").hexdigest())
        (root / "foreign.glb").symlink_to(WORKER)
        with self.assertRaises(worker.Fault):
            self.backend.artifacts(request["id"])

    def test_acknowledged_job_releases_only_its_workspace(self):
        request = self.stage()
        folder = self.backend.directory(request["id"])
        (folder / "output/model.glb").write_bytes(b"result")
        self.backend.update(request["id"], status="completed", result={"artifacts": self.backend.artifacts(request["id"])})
        untouched = Path(self.scratch.name) / "user-project.blend"
        untouched.write_bytes(b"preserved")
        self.backend.acknowledge(request["id"])
        self.assertFalse((folder / "project").exists())
        self.assertFalse((folder / "output").exists())
        self.assertTrue(self.backend.create(request)["acknowledged"])
        self.assertEqual(self.backend.start(request["id"])["status"], "completed")
        self.assertEqual(untouched.read_bytes(), b"preserved")

    def test_existing_blender_is_reused_without_package_commands(self):
        runtime = {"found": True, "version": "Blender fixture"}
        with patch.object(self.backend, "discover", return_value=runtime), patch.object(self.backend, "command") as command:
            self.assertTrue(self.backend.install("unused")["reused"])
            command.assert_not_called()

    def uninstall_fixture(self, native=False):
        prefix = Path(self.scratch.name) / "prefix"
        runtime = ({"kind": "native", "executable": str(prefix / "bin/blender")} if native else
                   {"kind": "proot", "container": "existing-debian", "executable": "/usr/bin/blender"})
        binary = (prefix / "bin/blender" if native else
                  prefix / "var/lib/proot-distro/containers/existing-debian/rootfs/usr/bin/blender")
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"fixture executable")
        runtime["version"] = "Blender fixture"
        with patch.dict(os.environ, {"PREFIX": str(prefix)}):
            runtime["binary_stamp"] = self.backend.binary_stamp(runtime)
        self.backend.runtime = dict(runtime)
        return prefix, runtime, binary

    def test_uninstall_removes_only_blender_package_and_preserves_files(self):
        for native in (False, True):
            with self.subTest(native=native):
                prefix, runtime, binary = self.uninstall_fixture(native)
                asset = binary.parent / "user-project.blend"
                asset.write_bytes(b"preserved")
                commands = []
                def remove_package(_id, argv, *_args):
                    commands.append(argv)
                    binary.unlink()
                plan = type("Plan", (), {"returncode": 0, "stdout": "Remv blender [4.3.2]\n"})()
                with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
                     patch.object(worker.subprocess, "run", return_value=plan), \
                     patch.object(self.backend, "command", side_effect=remove_package):
                    result = self.backend.uninstall(self.stage()["id"], runtime)
                self.assertTrue(result["removed"])
                self.assertEqual(commands[0][-3:], ["dpkg", "--remove", "blender"])
                self.assertEqual(len(commands), 1)
                self.assertEqual(asset.read_bytes(), b"preserved")
                self.assertTrue(binary.parent.exists())
                self.assertEqual(self.backend.runtime, {})
                self.assertEqual(worker.read_json(self.backend.root / "runtime.json"), {})

    def test_uninstall_refuses_changed_runtime_before_package_commands(self):
        prefix, runtime, _binary = self.uninstall_fixture()
        changed = dict(runtime, binary_stamp="stale")
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), patch.object(self.backend, "command") as command:
            with self.assertRaises(worker.Fault) as failure:
                self.backend.uninstall("unused", changed)
            self.assertEqual(failure.exception.code, "runtime_changed")
            command.assert_not_called()

    def test_uninstall_refuses_dependency_removal_and_unknown_package_managers(self):
        prefix, runtime, binary = self.uninstall_fixture()
        for result in (type("Plan", (), {"returncode": 0, "stdout": "Remv blender [4.3]\nRemv user-addon [1]\n"})(),
                       type("Plan", (), {"returncode": 100, "stdout": ""})()):
            with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
                 patch.object(worker.subprocess, "run", return_value=result), \
                 patch.object(self.backend, "command") as command:
                with self.assertRaises(worker.Fault) as failure:
                    self.backend.uninstall(self.stage()["id"], runtime)
                self.assertEqual(failure.exception.code, "uninstall_conflict")
                command.assert_not_called()
        self.assertTrue(binary.exists())

    def test_uninstall_rechecks_executable_after_package_plan(self):
        prefix, runtime, binary = self.uninstall_fixture()
        def plan(*_args, **_kwargs):
            binary.write_bytes(b"changed executable")
            return type("Plan", (), {"returncode": 0, "stdout": "Remv blender [4.3]\n"})()
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(worker.subprocess, "run", side_effect=plan), \
             patch.object(self.backend, "command") as command:
            with self.assertRaises(worker.Fault) as failure:
                self.backend.uninstall(self.stage()["id"], runtime)
            self.assertEqual(failure.exception.code, "runtime_changed")
            command.assert_not_called()

    def test_uninstall_does_not_report_success_if_executable_remains(self):
        prefix, runtime, _binary = self.uninstall_fixture()
        plan = type("Plan", (), {"returncode": 0, "stdout": "Remv blender [4.3]\n"})()
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(worker.subprocess, "run", return_value=plan), \
             patch.object(self.backend, "command"):
            with self.assertRaises(worker.Fault) as failure:
                self.backend.uninstall(self.stage()["id"], runtime)
            self.assertEqual(failure.exception.code, "uninstall_failed")
        self.assertEqual(self.backend.runtime, runtime)

    def test_repeated_uninstall_job_is_not_executed_twice(self):
        request = {"id": str(uuid.uuid4()), "kind": "uninstall", "args": {"runtime": {"kind": "fixture"}}}
        with patch.object(self.backend, "uninstall", return_value={"removed": True}) as uninstall:
            self.backend.create(request)
            self.assertEqual(self.wait(request["id"])["status"], "completed")
            self.assertEqual(self.backend.create(request)["status"], "completed")
            self.assertEqual(self.backend.start(request["id"])["status"], "completed")
            self.assertEqual(uninstall.call_count, 1)

    def test_changed_or_removed_executable_invalidates_capabilities(self):
        binary = Path(self.scratch.name) / "blender"
        binary.write_bytes(b"original")
        runtime = {"kind": "native", "executable": str(binary), "capabilities": {"formats": ["glb"]}}
        runtime["binary_stamp"] = self.backend.binary_stamp(runtime)
        self.backend.runtime = runtime
        self.assertIn("capabilities", self.backend.snapshot())
        binary.write_bytes(b"changed executable")
        self.assertNotIn("capabilities", self.backend.snapshot())
        binary.unlink()
        self.assertEqual(self.backend.snapshot(), {})

    def test_new_install_uses_own_container_and_no_system_upgrade(self):
        prefix = Path(self.scratch.name) / "prefix"
        commands = []
        job_id = self.stage()["id"]
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(self.backend, "discover", return_value={"found": False}), \
             patch.object(worker.shutil, "disk_usage", return_value=type("Disk", (), {"free": 4 * 1024**3})()), \
             patch.object(worker.shutil, "which", return_value="/fixture/proot-distro"), \
             patch.object(worker.subprocess, "run", return_value=type("Help", (), {"stdout": "Docker --name"})()), \
             patch.object(self.backend, "command", side_effect=lambda _id, command, *_args: commands.append(command)), \
             patch.object(self.backend, "probe", return_value="Blender fixture"):
            result = self.backend.install(job_id)
        self.assertEqual(result["container"], "godot-ai-blender")
        self.assertIn(["proot-distro", "install", "--name", "godot-ai-blender", "debian:13-slim"], commands)
        self.assertFalse(any("upgrade" in command or "reset" in command or "remove" in command for command in commands))
        self.assertTrue(any("DPkg::Lock::Timeout=120" in command for command in commands))

    def test_reinstall_uses_previously_verified_container_without_downloading_image(self):
        prefix = Path(self.scratch.name) / "prefix"
        (prefix / "var/lib/proot-distro/containers/debian").mkdir(parents=True)
        self.backend.runtime = {"kind": "proot", "container": "debian", "executable": "/usr/bin/blender"}
        commands = []
        def discover(_job):
            self.backend.runtime = {}
            return {"found": False}
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(self.backend, "discover", side_effect=discover), \
             patch.object(worker.shutil, "disk_usage", return_value=type("Disk", (), {"free": 4 * 1024**3})()), \
             patch.object(worker.shutil, "which", return_value="/fixture/proot-distro"), \
             patch.object(worker.subprocess, "run", return_value=type("Plan", (), {"stdout": "Inst blender (4.3.2)", "returncode": 0})()), \
             patch.object(self.backend, "command", side_effect=lambda _id, command, *_args: commands.append(command)), \
             patch.object(self.backend, "probe", return_value="Blender fixture"):
            result = self.backend.install(self.stage()["id"])
        self.assertEqual(result["container"], "debian")
        self.assertFalse(any(command[:2] == ["proot-distro", "install"] for command in commands))
        self.assertEqual(sum("install" in command for command in commands), 1)

    def test_reinstall_refuses_package_plan_that_removes_other_packages(self):
        prefix = Path(self.scratch.name) / "prefix"
        (prefix / "var/lib/proot-distro/containers/debian").mkdir(parents=True)
        self.backend.runtime = {"kind": "proot", "container": "debian", "executable": "/usr/bin/blender"}
        def discover(_job):
            self.backend.runtime = {}
            return {"found": False}
        commands = []
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(self.backend, "discover", side_effect=discover), \
             patch.object(worker.shutil, "disk_usage", return_value=type("Disk", (), {"free": 4 * 1024**3})()), \
             patch.object(worker.shutil, "which", return_value="/fixture/proot-distro"), \
             patch.object(worker.subprocess, "run", return_value=type("Plan", (), {"stdout": "Remv user-package [1.0]", "returncode": 0})()), \
             patch.object(self.backend, "command", side_effect=lambda _id, command, *_args: commands.append(command)):
            with self.assertRaises(worker.Fault) as failure:
                self.backend.install(self.stage()["id"])
        self.assertEqual(failure.exception.code, "install_plan_unsafe")
        self.assertFalse(any("install" in command for command in commands))

    def test_existing_unmanaged_container_is_never_modified(self):
        prefix = Path(self.scratch.name) / "prefix"
        (prefix / "var/lib/proot-distro/containers/godot-ai-blender").mkdir(parents=True)
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(self.backend, "discover", return_value={"found": False}), \
             patch.object(worker.shutil, "disk_usage", return_value=type("Disk", (), {"free": 4 * 1024**3})()), \
             patch.object(worker.shutil, "which", return_value="/fixture/proot-distro"), \
             patch.object(worker.subprocess, "run", return_value=type("Help", (), {"stdout": "Docker --name"})()), \
             patch.object(self.backend, "command") as command:
            with self.assertRaises(worker.Fault) as failure:
                self.backend.install("unused")
            self.assertEqual(failure.exception.code, "container_conflict")
            command.assert_not_called()

    def test_unsupported_proot_is_not_upgraded_automatically(self):
        with patch.object(self.backend, "discover", return_value={"found": False}), \
             patch.object(worker.shutil, "disk_usage", return_value=type("Disk", (), {"free": 4 * 1024**3})()), \
             patch.object(worker.shutil, "which", return_value="/fixture/proot-distro"), \
             patch.object(worker.subprocess, "run", return_value=type("Help", (), {"stdout": "Legacy distro aliases"})()), \
             patch.object(self.backend, "command") as command:
            with self.assertRaises(worker.Fault) as failure:
                self.backend.install("unused")
            self.assertEqual(failure.exception.code, "proot_update_required")
            command.assert_not_called()

    def test_partial_image_requires_explicit_repair(self):
        prefix = Path(self.scratch.name) / "prefix"
        container = prefix / "var/lib/proot-distro/containers/godot-ai-blender"
        container.mkdir(parents=True)
        worker.atomic_json(self.backend.root / "managed-container.json", {"owned": True, "phase": "image"})
        job_id = self.stage()["id"]
        commands = []
        def command(_id, argv, *_args):
            commands.append(argv)
            if argv[:2] == ["proot-distro", "remove"]:
                worker.shutil.rmtree(container)
        with patch.dict(os.environ, {"PREFIX": str(prefix)}), \
             patch.object(self.backend, "discover", return_value={"found": False}), \
             patch.object(worker.shutil, "disk_usage", return_value=type("Disk", (), {"free": 4 * 1024**3})()), \
             patch.object(worker.shutil, "which", return_value="/fixture/proot-distro"), \
             patch.object(worker.subprocess, "run", return_value=type("Help", (), {"stdout": "Docker --name"})()), \
             patch.object(self.backend, "command", side_effect=command), \
             patch.object(self.backend, "probe", return_value="Blender fixture"):
            with self.assertRaises(worker.Fault) as failure:
                self.backend.install(job_id)
            self.assertEqual(failure.exception.code, "incomplete_image")
            self.assertEqual(commands, [])
            self.backend.install(job_id, repair=True)
        self.assertEqual(commands[0], ["proot-distro", "remove", "godot-ai-blender"])


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="godot-blender-http-")
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), worker.Handler)
        self.server.daemon_threads = True
        self.server.backend = worker.Backend(self.scratch.name)
        self.server.token = "a" * 64
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.scratch.cleanup()

    def test_authentication_and_browser_origins(self):
        for headers in ({}, {"Authorization": "Bearer wrong"}, {"Authorization": "Bearer " + self.server.token, "Origin": "http://example.com"}):
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(urllib.request.Request(self.url + "/v1/health", headers=headers))
            self.assertEqual(error.exception.code, 401)
        request = urllib.request.Request(self.url + "/v1/health", headers={"Authorization": "Bearer " + self.server.token})
        with urllib.request.urlopen(request) as response:
            self.assertEqual(json.load(response)["protocol"], 1)

    def test_completed_file_changed_before_download(self):
        job_id = str(uuid.uuid4())
        request = {"id": job_id, "kind": "run", "args": {"script": "x.py", "inputs": [{"path": "x.py", "bytes": 0, "sha256": hashlib.sha256(b"").hexdigest()}]}}
        self.server.backend.create(request)
        path = self.server.backend.directory(job_id) / "output/model.glb"
        path.write_bytes(b"original")
        artifacts = self.server.backend.artifacts(job_id)
        self.server.backend.update(job_id, status="completed", result={"artifacts": artifacts})
        path.write_bytes(b"modified")
        request = urllib.request.Request(self.url + f"/v1/jobs/{job_id}/outputs/model.glb", headers={"Authorization": "Bearer " + self.server.token})
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request)
        self.assertEqual(json.load(error.exception)["code"], "changed_artifact")


class WorkerProcessTests(unittest.TestCase):
    def test_real_entrypoint_authentication_and_single_owner(self):
        with tempfile.TemporaryDirectory(prefix="godot-blender-process-") as folder:
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            command = [sys.executable, str(WORKER), "--root", folder, "--port", str(port)]
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            process.stdin.write(b"c" * 64 + b"\n")
            process.stdin.close()
            try:
                deadline = time.monotonic() + 5
                while True:
                    try:
                        request = urllib.request.Request(f"http://127.0.0.1:{port}/v1/health", headers={"Authorization": "Bearer " + "c" * 64})
                        with urllib.request.urlopen(request, timeout=1) as response:
                            self.assertEqual(json.load(response)["protocol"], 1)
                        break
                    except urllib.error.URLError:
                        self.assertLess(time.monotonic(), deadline)
                        time.sleep(.05)
                second = subprocess.run(command, input=b"c" * 64 + b"\n", capture_output=True, timeout=5)
                self.assertNotEqual(second.returncode, 0)
                self.assertIn(b"already running", second.stderr)
            finally:
                process.terminate()
                process.wait(timeout=5)
                process.stderr.close()


if __name__ == "__main__":
    unittest.main()
