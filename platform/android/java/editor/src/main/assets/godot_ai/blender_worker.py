#!/usr/bin/env python3
"""Optional Termux Blender backend. Python stdlib only; never an agent runtime.

Bound exclusively to loopback. All routes require a per-editor random token.
Job IDs and manifests survive reconnects; identical submissions never run twice.
PRoot is a compatibility layer, not a security sandbox for Python scripts.
"""
import argparse
import hashlib
import hmac
import http.server
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import subprocess
import threading
import time
import urllib.parse

PROTOCOL = 1
MAX_FILE = 512 * 1024 * 1024
MAX_TOTAL = 1024 * 1024 * 1024
FORMATS = {"glb", "gltf", "bin", "blend", "fbx", "obj", "mtl", "stl", "ply",
           "png", "jpg", "jpeg", "webp", "usd", "usda", "usdc", "usdz", "3mf"}
ID_RE = re.compile(r"^[a-f0-9-]{36}$")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")


class Fault(Exception):
    def __init__(self, code, message, status=400):
        super().__init__(message)
        self.code, self.status = code, status


def atomic_json(path, data):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def read_json(path, default=None):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(256 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def relative(value):
    if not isinstance(value, str) or not value or len(value) > 1024 or "\\" in value or "\x00" in value:
        raise Fault("invalid_path", "Cale de fișier invalidă.")
    path = PurePosixPath(value)
    if path.is_absolute() or any(p in ("", ".", "..") or p.startswith(".") for p in value.split("/")):
        raise Fault("invalid_path", "Calea trebuie să rămână în directorul sarcinii.")
    return path.as_posix()


class Backend:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        (self.root / "jobs").mkdir(exist_ok=True, mode=0o700)
        self.lock = threading.RLock()
        self.active = None
        self.cancelled = set()
        self.runtime = read_json(self.root / "runtime.json", {})
        # The previous process cannot own jobs after this worker acquired its lock.
        for path in (self.root / "jobs").glob("*/state.json"):
            state = read_json(path, {})
            if state.get("status") in ("running", "queued"):
                pid = state.get("pid", 0)
                try:
                    command_line = Path(f"/proc/{pid}/cmdline").read_bytes()
                    if pid > 1 and str(path.parent).encode() in command_line and os.getpgid(pid) == pid:
                        os.killpg(pid, signal.SIGKILL)
                except (OSError, ProcessLookupError):
                    pass
                state.update(status="interrupted", code="interrupted",
                             error="Execuție întreruptă. Rezultatele nu sunt declarate finalizate.")
                atomic_json(path, state)

    def directory(self, job_id):
        if not isinstance(job_id, str) or not ID_RE.fullmatch(job_id):
            raise Fault("invalid_id", "Identificator de sarcină invalid.")
        return self.root / "jobs" / job_id

    def state(self, job_id):
        with self.lock:
            value = read_json(self.directory(job_id) / "state.json")
            if not isinstance(value, dict):
                raise Fault("missing_job", "Sarcina nu există.", 404)
            log = self.directory(job_id) / "activity.log"
            if log.exists():
                with log.open("rb") as handle:
                    handle.seek(max(0, log.stat().st_size - 16000))
                    value["log"] = handle.read(16000).decode("utf-8", errors="replace")
            return value

    def update(self, job_id, **values):
        with self.lock:
            path = self.directory(job_id) / "state.json"
            state = read_json(path, {})
            state.update(values, updated=time.time())
            atomic_json(path, state)

    def step(self, job_id, message):
        self.update(job_id, stage=message)
        with (self.directory(job_id) / "activity.log").open("ab") as handle:
            handle.write(("\n" + message + "\n").encode())

    def create(self, request):
        if not isinstance(request, dict) or request.get("kind") not in ("discover", "install", "uninstall", "verify", "run"):
            raise Fault("invalid_job", "Tip de sarcină invalid.")
        job_id = request.get("id")
        folder = self.directory(job_id)
        fingerprint = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
        args = request.get("args", {})
        if not isinstance(args, dict):
            raise Fault("invalid_job", "Parametri invalizi.")
        if request["kind"] == "run":
            self.validate_run(args)
        with self.lock:
            previous = read_json(folder / "request.json")
            if previous:
                if previous.get("fingerprint") != fingerprint:
                    raise Fault("job_conflict", "ID deja folosit pentru alți parametri.", 409)
                return self.state(job_id)
            if self.active is not None:
                raise Fault("busy", "Blender are deja o sarcină în lucru.", 409)
            folder.mkdir(mode=0o700)
            (folder / "project").mkdir()
            (folder / "output").mkdir()
            atomic_json(folder / "request.json", dict(request, fingerprint=fingerprint))
            atomic_json(folder / "state.json", {"id": job_id, "kind": request["kind"],
                        "status": "staging" if request["kind"] == "run" else "queued", "created": time.time()})
            if request["kind"] != "run":
                self.start(job_id)
            return self.state(job_id)

    @staticmethod
    def validate_run(args):
        script = relative(args.get("script"))
        if not script.endswith(".py"):
            raise Fault("invalid_script", "Scriptul trebuie să fie Python.")
        inputs = args.get("inputs", [])
        if not isinstance(inputs, list) or not 1 <= len(inputs) <= 128:
            raise Fault("invalid_inputs", "Selectează cel mult 128 de fișiere de intrare.")
        names, total = set(), 0
        for item in inputs:
            if not isinstance(item, dict):
                raise Fault("invalid_inputs", "Manifest invalid.")
            name = relative(item.get("path"))
            size = item.get("bytes")
            if name in names or type(size) is not int or not 0 <= size <= MAX_FILE or not re.fullmatch(r"[a-f0-9]{64}", str(item.get("sha256", ""))):
                raise Fault("invalid_inputs", "Dimensiune, hash sau nume invalid.")
            names.add(name)
            total += size
        if total > MAX_TOTAL or script not in names:
            raise Fault("invalid_inputs", "Script absent sau intrări prea mari.")
        blend = args.get("blend", "")
        if blend and (relative(blend) not in names or not blend.endswith(".blend")):
            raise Fault("invalid_blend", "Fișierul .blend nu apare în manifest.")
        seconds = args.get("seconds", 120)
        if type(seconds) is not int or not 1 <= seconds <= 600:
            raise Fault("invalid_timeout", "Durata trebuie să fie între 1 și 600 de secunde.")

    def upload(self, job_id, name, stream, length):
        name = relative(name)
        # Serialize upload/start/cancel to prevent a file changing after validation.
        with self.lock:
            if self.state(job_id)["status"] != "staging":
                raise Fault("invalid_state", "Sarcina nu mai acceptă intrări.", 409)
            request = read_json(self.directory(job_id) / "request.json")
            item = next((v for v in request["args"]["inputs"] if v["path"] == name), None)
            if not item or length != item["bytes"]:
                raise Fault("invalid_upload", "Fișierul nu corespunde manifestului.")
            if shutil.disk_usage(self.root).free < length + 32 * 1024 * 1024:
                raise Fault("disk_full", "Spațiu insuficient în Termux.")
            target = self.directory(job_id) / "project" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(target.name + ".upload")
            try:
                with temporary.open("wb") as handle:
                    remaining = length
                    while remaining:
                        chunk = stream.read(min(256 * 1024, remaining))
                        if not chunk:
                            raise Fault("interrupted_upload", "Transfer întrerupt.")
                        handle.write(chunk)
                        remaining -= len(chunk)
                if digest(temporary) != item["sha256"]:
                    raise Fault("hash_mismatch", "Fișierul primit are alt hash.")
                temporary.replace(target)
            finally:
                temporary.unlink(missing_ok=True)

    def start(self, job_id):
        with self.lock:
            state = self.state(job_id)
            if state["status"] not in ("staging", "queued"):
                return state  # Completed/interrupted jobs are never replayed.
            if self.active is not None:
                raise Fault("busy", "Blender are deja o sarcină în lucru.", 409)
            request = read_json(self.directory(job_id) / "request.json")
            for item in request.get("args", {}).get("inputs", []):
                file = self.directory(job_id) / "project" / item["path"]
                if not file.is_file() or file.stat().st_size != item["bytes"] or digest(file) != item["sha256"]:
                    raise Fault("missing_input", "Transferul intrărilor nu este complet.")
            self.active = job_id
            self.update(job_id, status="running")
            threading.Thread(target=self.execute, args=(job_id, request), daemon=True).start()
            return self.state(job_id)

    def cancel(self, job_id):
        with self.lock:
            state = self.state(job_id)
            if state["status"] in ("queued", "staging"):
                self.update(job_id, status="cancelled", code="cancelled")
            elif state["status"] == "running":
                self.cancelled.add(job_id)
                self.update(job_id, cancel_requested=True)
            return self.state(job_id)

    def acknowledge(self, job_id):
        with self.lock:
            state = self.state(job_id)
            if state["status"] != "completed":
                raise Fault("invalid_state", "Importul poate fi confirmat doar pentru o sarcină finalizată.", 409)
            # Keep the immutable request/state for idempotency; release only our job workspace.
            folder = self.directory(job_id)
            for name in ("project", "output"):
                path = folder / name
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
            for name in ("runner.py", "verify.py", "render.py", "capabilities.json"):
                (folder / name).unlink(missing_ok=True)
            log = folder / "activity.log"
            if log.exists() and log.stat().st_size > 16000:
                with log.open("rb") as handle:
                    handle.seek(-16000, 2)
                    tail = handle.read()
                log.write_bytes(tail)
            self.update(job_id, acknowledged=True)
            return self.state(job_id)

    def command(self, job_id, argv, timeout=60, interruptible=True, env=None):
        if job_id in self.cancelled:
            raise Fault("cancelled", "Sarcina a fost oprită.")
        log = self.directory(job_id) / "activity.log"
        with log.open("ab") as handle:
            process = subprocess.Popen(argv, stdout=handle, stderr=subprocess.STDOUT,
                                       stdin=subprocess.DEVNULL, start_new_session=True, env=env)
            self.update(job_id, pid=process.pid)
            deadline = time.monotonic() + timeout
            reason = ""
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    reason = "timeout"
                elif interruptible and job_id in self.cancelled:
                    reason = "cancelled"
                elif log.stat().st_size > 32 * 1024 * 1024:
                    reason = "log_limit"
                elif shutil.disk_usage(self.root).free < 32 * 1024 * 1024:
                    reason = "disk_full"
                if reason:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                    raise Fault(reason, "Execuție oprită: " + reason)
                time.sleep(0.1)
            if process.returncode:
                raise Fault("process_failed", "Comanda s-a încheiat cu codul " + str(process.returncode) + ". Consultă jurnalul.")
            if job_id in self.cancelled:
                raise Fault("cancelled", "Oprit după încheierea tranzacției curente.")

    def probe(self, prefix):
        process = None
        try:
            process = subprocess.Popen(prefix + ["--version"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                       text=True, stdin=subprocess.DEVNULL, start_new_session=True)
            output, _ = process.communicate(timeout=15)
            version = re.search(r"(?m)^Blender [0-9][^\r\n]*", output)
            return version.group(0) if process.returncode == 0 and version else ""
        except (OSError, subprocess.TimeoutExpired):
            if process is not None and process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate()
            return ""

    def prefix(self, runtime):
        if runtime.get("kind") == "native":
            return [runtime["executable"]]
        return ["proot-distro", "login", runtime["container"], "--", runtime["executable"]]

    @staticmethod
    def binary_stamp(runtime):
        paths = []
        if runtime.get("kind") == "native":
            paths.append(Path(runtime["executable"]))
        elif runtime.get("kind") == "proot":
            prefix = Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"))
            container = runtime["container"]
            executable = runtime["executable"].lstrip("/")
            paths.extend([prefix / "var/lib/proot-distro/containers" / container / "rootfs" / executable,
                          prefix / "var/lib/proot-distro/installed-rootfs" / container / executable])
        for path in paths:
            try:
                stat = path.stat()
                return f"{stat.st_size}:{stat.st_mtime_ns}"
            except OSError:
                pass
        return ""

    def snapshot(self):
        value = dict(self.runtime)
        if value:
            stamp = self.binary_stamp(value)
            if not stamp:
                return {}
            if value.get("binary_stamp") != stamp:
                value["binary_stamp"] = stamp
                value.pop("capabilities", None)
        return value

    def discover(self, job_id):
        self.step(job_id, "Detectare Blender")
        candidates = []
        if self.runtime:
            candidates.append(self.runtime)
        binary = shutil.which("blender")
        if binary:
            candidates.append({"kind": "native", "executable": binary})
        prefix = Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"))
        if shutil.which("proot-distro"):
            names = set()
            for base in (prefix / "var/lib/proot-distro/containers", prefix / "var/lib/proot-distro/installed-rootfs"):
                if base.is_dir():
                    names.update(p.name for p in base.iterdir() if p.is_dir() and NAME_RE.fullmatch(p.name))
            for name in sorted(names)[:16]:
                candidates.append({"kind": "proot", "container": name, "executable": "/usr/bin/blender"})
        seen = set()
        for candidate in candidates:
            if job_id in self.cancelled:
                raise Fault("cancelled", "Detectare oprită.")
            identity = (candidate.get("kind"), candidate.get("container"), candidate.get("executable"))
            if identity in seen:
                continue
            seen.add(identity)
            version = self.probe(self.prefix(candidate))
            if version:
                stamp = self.binary_stamp(candidate)
                self.runtime = dict(candidate, version=version, binary_stamp=stamp)
                if candidate.get("binary_stamp") != stamp or candidate.get("version") != version:
                    self.runtime.pop("capabilities", None)
                atomic_json(self.root / "runtime.json", self.runtime)
                return dict(self.runtime, found=True)
        self.runtime = {}
        atomic_json(self.root / "runtime.json", {})
        return {"found": False}

    def install(self, job_id, repair=False):
        found = self.discover(job_id)
        if found.get("found"):
            return dict(found, reused=True)
        if shutil.disk_usage(self.root).free < 2 * 1024**3:
            raise Fault("disk_full", "Instalarea necesită cel puțin 2 GB liberi în Termux.")
        if not shutil.which("proot-distro"):
            self.step(job_id, "Instalare PRoot-Distro")
            self.command(job_id, ["pkg", "update", "-y"], 900, False)
            self.command(job_id, ["pkg", "install", "-y", "proot-distro"], 900, False)
        help_text = subprocess.run(["proot-distro", "install", "--help"], capture_output=True,
                                   text=True, timeout=15).stdout
        if "--name" not in help_text or "Docker" not in help_text:
            raise Fault("proot_update_required", "Instalarea automată cere PRoot-Distro 5.x. Actualizează-l din Termux; containerele existente nu sunt migrate de aplicație.")
        prefix = Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"))
        name = "godot-ai-blender"
        container = prefix / "var/lib/proot-distro/containers" / name
        marker = self.root / "managed-container.json"
        metadata = read_json(marker, {})
        if container.exists() and not metadata.get("owned"):
            raise Fault("container_conflict", "Numele godot-ai-blender este deja folosit de un mediu existent.")
        if container.exists() and metadata.get("phase") == "image" and not read_json(container / "manifest.json"):
            if not repair:
                raise Fault("incomplete_image", "Pregătirea Debian a fost întreruptă. Folosește Repară pentru mediul temporar al aplicației.")
            self.step(job_id, "Reparare mediu Debian incomplet al aplicației")
            self.command(job_id, ["proot-distro", "remove", name], 600, False)
        if not container.exists():
            self.step(job_id, "Descărcare și pregătire Debian 13")
            atomic_json(marker, {"owned": True, "image": "debian:13-slim", "phase": "image"})
            self.command(job_id, ["proot-distro", "install", "--name", name, "debian:13-slim"], 1800, False)
        atomic_json(marker, {"owned": True, "image": "debian:13-slim", "phase": "packages"})
        shell = ["proot-distro", "login", name, "--", "env", "DEBIAN_FRONTEND=noninteractive"]
        self.step(job_id, "Verificare stare pachete Debian")
        self.command(job_id, shell + ["dpkg", "--configure", "-a"], 900, False)
        self.step(job_id, "Actualizare catalog Debian")
        self.command(job_id, shell + ["apt-get", "update"], 900, False)
        self.step(job_id, "Instalare Blender")
        self.command(job_id, shell + ["apt-get", "-o", "DPkg::Lock::Timeout=120", "install", "-y",
                                     "--no-install-recommends", "blender"], 1800, False)
        runtime = {"kind": "proot", "container": name, "executable": "/usr/bin/blender"}
        version = self.probe(self.prefix(runtime))
        if not version:
            raise Fault("missing_blender", "Blender instalat nu a trecut verificarea de pornire.")
        self.runtime = dict(runtime, version=version, binary_stamp=self.binary_stamp(runtime))
        atomic_json(self.root / "runtime.json", self.runtime)
        return dict(self.runtime, found=True, reused=False)

    def uninstall(self, job_id, expected):
        current = self.snapshot()
        identity = ("kind", "container", "executable", "version", "binary_stamp")
        if not current or not isinstance(expected, dict) or any(current.get(key) != expected.get(key) for key in identity):
            raise Fault("runtime_changed", "Instalarea Blender s-a schimbat. Repetă verificarea înainte de dezinstalare.")
        # Remove only the Blender package, including in a reused container. Never
        # remove a container, Python, Termux or generated/user files.
        if current.get("kind") == "proot" and current.get("executable") == "/usr/bin/blender" and NAME_RE.fullmatch(current.get("container", "")):
            shell = ["proot-distro", "login", current["container"], "--", "env", "LC_ALL=C", "DEBIAN_FRONTEND=noninteractive"]
        elif current.get("kind") == "native" and current.get("executable") == str(Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr")) / "bin/blender"):
            shell = ["env", "LC_ALL=C", "DEBIAN_FRONTEND=noninteractive"]
        else:
            raise Fault("uninstall_unsupported", "Această instalare Blender nu este gestionată de apt. Fișierele au fost păstrate.")
        self.step(job_id, "Verificare dezinstalare Blender")
        try:
            plan = subprocess.run(shell + ["apt-get", "--simulate", "--no-auto-remove", "remove", "blender"],
                                  capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            raise Fault("uninstall_unsupported", "Nu pot verifica dezinstalarea pachetului Blender. Fișierele au fost păstrate.")
        packages = re.findall(r"(?m)^Remv (\S+)", plan.stdout)
        if plan.returncode or not packages or any(name.split(":")[0] != "blender" for name in packages):
            raise Fault("uninstall_conflict", "Dezinstalarea ar afecta alte pachete sau Blender nu este gestionat de apt. Nu am modificat instalarea.")
        # Check again after planning; never remove an executable that changed.
        if any(self.snapshot().get(key) != current.get(key) for key in identity):
            raise Fault("runtime_changed", "Instalarea Blender s-a schimbat înainte de dezinstalare.")
        self.step(job_id, "Dezinstalare Blender")
        # dpkg removes this exact package and refuses broken reverse dependencies,
        # even if another package transaction changed the plan in the meantime.
        self.command(job_id, shell + ["dpkg", "--remove", "blender"], 900, False)
        if self.binary_stamp(current):
            raise Fault("uninstall_failed", "Executabilul Blender există încă. Verifică jurnalul.")
        self.runtime = {}
        atomic_json(self.root / "runtime.json", {})
        return {"removed": True, "found": False}

    def blender(self, job_id, script, blend="", timeout=120):
        if not self.runtime:
            raise Fault("missing_blender", "Detectează Blender înainte de rulare.")
        folder = self.directory(job_id)
        if self.runtime["kind"] == "proot":
            base = "/work"
            command = ["proot-distro", "login", self.runtime["container"], "--isolated", "--bind",
                       str(folder) + ":/work", "--work-dir", "/work/project", "--", self.runtime["executable"]]
        else:
            base = str(folder)
            command = [self.runtime["executable"]]
        command += ["--background", "--factory-startup", "--disable-autoexec", "--threads", "2"]
        if blend:
            command.append(base + "/project/" + blend)
        command += ["--python-exit-code", "1", "--python", base + "/" + script]
        self.command(job_id, command, timeout)

    def verify(self, job_id):
        if not self.discover(job_id).get("found"):
            raise Fault("missing_blender", "Blender nu este instalat.")
        folder = self.directory(job_id)
        self.step(job_id, "Probă modelare și export GLB")
        (folder / "verify.py").write_text('''import bpy, json, os
root = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(root, "output")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cube_add()
bpy.ops.export_scene.gltf(filepath=os.path.join(out,"probe.glb"),export_format="GLB")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out,"probe.blend"))
formats = ["glb", "gltf", "blend"]
for name, module, operation in [("fbx","export_scene","fbx"),("obj","wm","obj_export"),("stl","wm","stl_export"),("ply","wm","ply_export")]:
    try:
        getattr(getattr(bpy.ops,module),operation).get_rna_type()
        formats.append(name)
    except Exception:
        pass
with open(os.path.join(root,"capabilities.json"),"w") as f: json.dump({"formats":formats},f)
''', encoding="utf-8")
        self.blender(job_id, "verify.py", timeout=120)
        capabilities = read_json(folder / "capabilities.json", {"formats": ["glb", "blend"]})
        self.step(job_id, "Probă randare CPU")
        (folder / "render.py").write_text('''import bpy, os
out = os.path.join(os.path.dirname(os.path.abspath(__file__)),"output")
bpy.ops.mesh.primitive_cube_add()
bpy.ops.object.camera_add(location=(3,-4,3))
cam = bpy.context.object
cam.rotation_euler = (-cam.location).to_track_quat("-Z","Y").to_euler()
scene = bpy.context.scene
scene.camera = cam
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
scene.cycles.use_denoising = False
scene.render.resolution_x = 32
scene.render.resolution_y = 32
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = os.path.join(out,"probe.png")
bpy.ops.render.render(write_still=True)
''', encoding="utf-8")
        try:
            self.blender(job_id, "render.py", timeout=60)
            capabilities["render_cpu"] = (folder / "output/probe.png").is_file()
        except Fault as error:
            if error.code == "cancelled":
                raise
            capabilities["render_cpu"] = False
            self.step(job_id, "Randare CPU indisponibilă; modelarea a trecut proba.")
        self.runtime["capabilities"] = capabilities
        atomic_json(self.root / "runtime.json", self.runtime)
        return {"runtime": self.runtime, "artifacts": self.artifacts(job_id)}

    def run(self, job_id, args):
        folder = self.directory(job_id)
        self.step(job_id, "Executare script Blender")
        (folder / "runner.py").write_text('''import os, runpy, sys
root = os.path.dirname(os.path.abspath(__file__))
project = os.path.join(root,"project")
os.environ["GODOT_AI_PROJECT_DIR"] = project
os.environ["GODOT_AI_OUTPUT_DIR"] = os.path.join(root,"output")
os.chdir(project)
sys.path.insert(0,project)
script = os.path.join(project, %r)
sys.argv = [script]
runpy.run_path(script,run_name="__main__")
''' % args["script"], encoding="utf-8")
        self.blender(job_id, "runner.py", args.get("blend", ""), args.get("seconds", 120))
        return {"exit_code": 0, "artifacts": self.artifacts(job_id), "runtime": self.runtime}

    def artifacts(self, job_id):
        root = self.directory(job_id) / "output"
        results, total = [], 0
        for path in sorted(root.rglob("*")):
            if path.is_symlink():
                raise Fault("invalid_artifact", "Rezultatele nu pot include legături simbolice.")
            if not path.is_file():
                continue
            name = relative(path.relative_to(root).as_posix())
            if path.suffix.lower().lstrip(".") not in FORMATS:
                continue
            size = path.stat().st_size
            total += size
            if not 0 < size <= MAX_FILE or total > MAX_TOTAL or len(results) >= 256:
                raise Fault("artifact_limit", "Rezultatele depășesc limitele de transfer.")
            results.append({"path": name, "bytes": size, "sha256": digest(path)})
        return results

    def execute(self, job_id, request):
        try:
            kind = request["kind"]
            if kind == "discover":
                result = self.discover(job_id)
            elif kind == "install":
                result = self.install(job_id, repair=request.get("args", {}).get("repair") is True)
            elif kind == "uninstall":
                result = self.uninstall(job_id, request.get("args", {}).get("runtime"))
            elif kind == "verify":
                result = self.verify(job_id)
            else:
                result = self.run(job_id, request["args"])
            with self.lock:
                self.update(job_id, status="completed", result=result, stage="Finalizat")
                self.active = None
        except Exception as error:
            code = error.code if isinstance(error, Fault) else "backend_error"
            self.update(job_id, status="cancelled" if code == "cancelled" else "failed",
                        code=code, error=str(error), stage="Oprit" if code == "cancelled" else "Eroare")
        finally:
            with self.lock:
                self.active = None
                self.cancelled.discard(job_id)


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "GodotBlender/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass  # Never log bearer tokens, file names or request payloads to Android.

    def reply(self, data, status=200):
        encoded = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def dispatch(self, method):
        try:
            self.connection.settimeout(30)
            if self.headers.get("Origin") or not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + self.server.token):
                raise Fault("unauthorized", "Conexiune locală neautorizată.", 401)
            self.server.last_activity = time.monotonic()
            location = urllib.parse.urlsplit(self.path)
            parts = urllib.parse.unquote(location.path).strip("/").split("/")
            backend = self.server.backend
            if method == "GET" and parts == ["v1", "health"]:
                self.reply({"ok": True, "protocol": PROTOCOL, "revision": 2, "active": backend.active, "runtime": backend.snapshot()})
                return
            length = int(self.headers.get("Content-Length", "0"))
            if method == "POST":
                if not 0 <= length <= 65536:
                    raise Fault("request_too_large", "Cerere prea mare.")
                body = json.loads(self.rfile.read(length) or b"{}")
                if parts == ["v1", "jobs"]:
                    self.reply({"ok": True, "result": backend.create(body)})
                    return
                if len(parts) == 4 and parts[:2] == ["v1", "jobs"]:
                    action = {"start": backend.start, "cancel": backend.cancel, "ack": backend.acknowledge}.get(parts[3])
                    if action:
                        self.reply({"ok": True, "result": action(parts[2])})
                        return
            if len(parts) >= 3 and parts[:2] == ["v1", "jobs"]:
                job_id = parts[2]
                if method == "GET" and len(parts) == 3:
                    self.reply({"ok": True, "result": backend.state(job_id)})
                    return
                if method == "PUT" and len(parts) >= 5 and parts[3] == "inputs":
                    if not 0 <= length <= MAX_FILE:
                        raise Fault("request_too_large", "Fișier prea mare.")
                    backend.upload(job_id, "/".join(parts[4:]), self.rfile, length)
                    self.reply({"ok": True})
                    return
                if method == "GET" and len(parts) >= 5 and parts[3] == "outputs":
                    state = backend.state(job_id)
                    name = relative("/".join(parts[4:]))
                    item = next((v for v in state.get("result", {}).get("artifacts", []) if v["path"] == name), None)
                    if state["status"] != "completed" or not item:
                        raise Fault("missing_artifact", "Rezultat indisponibil.", 404)
                    path = backend.directory(job_id) / "output" / name
                    if not path.is_file():
                        raise Fault("missing_artifact", "Fișierul temporar a fost eliberat după import.", 404)
                    if path.is_symlink() or not path.resolve().is_relative_to((backend.directory(job_id) / "output").resolve()) or digest(path) != item["sha256"]:
                        raise Fault("changed_artifact", "Rezultatul a fost modificat după execuție.")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Length", str(item["bytes"]))
                    self.end_headers()
                    with path.open("rb") as handle:
                        shutil.copyfileobj(handle, self.wfile, 256 * 1024)
                    return
            raise Fault("not_found", "Rută necunoscută.", 404)
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            self.close_connection = True
        except Exception as error:
            status = error.status if isinstance(error, Fault) else 400
            code = error.code if isinstance(error, Fault) else "invalid_request"
            self.close_connection = True
            self.reply({"ok": False, "code": code, "error": str(error)}, status)

    def do_GET(self):
        self.dispatch("GET")

    def do_POST(self):
        self.dispatch("POST")

    def do_PUT(self):
        self.dispatch("PUT")


def main():
    import fcntl
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    # Token comes through stdin, never through the process argument list.
    token = input().strip()
    if not re.fullmatch(r"[a-f0-9]{64}", token) or not 1024 <= args.port <= 65535:
        raise SystemExit("Invalid local connection")
    root = Path(args.root)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (root / "worker.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("Blender connector already running; reconnect instead")
        server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
        server.daemon_threads = True
        server.token = token
        server.backend = Backend(root)
        server.last_activity = time.monotonic()
        finished = threading.Event()
        def idle_monitor():
            while not finished.wait(30):
                if server.backend.active is None and time.monotonic() - server.last_activity > 600:
                    server.shutdown()
                    return
        threading.Thread(target=idle_monitor, daemon=True).start()
        try:
            server.serve_forever()
        finally:
            finished.set()
            server.server_close()


if __name__ == "__main__":
    main()
