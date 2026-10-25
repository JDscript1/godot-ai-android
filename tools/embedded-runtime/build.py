#!/usr/bin/env python3
"""Build a relocatable Android ARM64 PRoot with static non-system dependencies.

Only the build uses Python/make. The APK runs its native files directly.
Downloads are pinned; no package is installed into the build host's prefix.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download(archive, spec):
    partial = archive.with_suffix(archive.suffix + ".part")
    urls = [spec["url"], *spec.get("mirrors", [])]
    for attempt in range(4):
        url = urls[attempt % len(urls)]
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "GodotEmbeddedRuntimeBuild/1"})
            with urllib.request.urlopen(request, timeout=90) as response, partial.open("wb") as target:
                shutil.copyfileobj(response, target)
            if digest(partial) != spec["sha256"]:
                raise RuntimeError(f"Checksum mismatch: {url}")
            partial.replace(archive)
            return
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if attempt == 3:
                raise RuntimeError(f"Could not download verified source: {url}") from error
            print(f"Source download unavailable; retry {attempt + 1}/3", flush=True)
            time.sleep(2 ** attempt)
        finally:
            partial.unlink(missing_ok=True)


def run(args, cwd, env, log):
    with log.open("a") as stream:
        stream.write("\n$ " + shlex.join(map(str, args)) + "\n")
        stream.flush()
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); {log}\n" + log.read_text(errors="replace")[-5000:])


def source(work, name, spec):
    cache = work / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / Path(spec["url"]).name
    if not archive.exists():
        download(archive, spec)
    if digest(archive) != spec["sha256"]:
        raise RuntimeError(f"Checksum mismatch: {archive}")
    directory = work / "src" / spec["directory"]
    if not directory.exists():
        directory.parent.mkdir(parents=True, exist_ok=True)
        if zipfile.is_zipfile(archive):
            with zipfile.ZipFile(archive) as bundle:
                for item in bundle.infolist():
                    if Path(item.filename).is_absolute() or ".." in Path(item.filename).parts:
                        raise RuntimeError("Unsafe source archive path")
                bundle.extractall(directory.parent)
        else:
            with tarfile.open(archive) as bundle:
                bundle.extractall(directory.parent, filter="data")
    print(f"Source {name} {spec['version']}: verified", flush=True)
    return directory


def elf(path, executable_type):
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<HH", data, 16) != (executable_type, 183):
        raise RuntimeError(f"Unexpected ELF format: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    compiler = parser.add_mutually_exclusive_group(required=True)
    compiler.add_argument("--ndk", type=Path)
    compiler.add_argument("--native-android", action="store_true")
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work, output = args.work.resolve(), args.output.resolve()
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    log = work / "build.log"
    env = os.environ.copy()
    for key in ["CFLAGS", "CPPFLAGS", "LDFLAGS", "LD_LIBRARY_PATH", "PROOT_UNBUNDLE_LOADER"]:
        env.pop(key, None)
    env["PYTHONHASHSEED"] = "1"
    if args.ndk:
        host = "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64"
        tools = args.ndk.resolve() / "toolchains/llvm/prebuilt" / host / "bin"
        cc = tools / "aarch64-linux-android29-clang"
        ar, strip = tools / "llvm-ar", tools / "llvm-strip"
        env["PATH"] = str(tools) + os.pathsep + env["PATH"]
    else:
        cc, ar, strip = [Path(shutil.which(name) or "missing") for name in ("clang", "llvm-ar", "llvm-strip")]
        check = subprocess.run([cc, "-dM", "-E", "-"], input="", text=True, capture_output=True, check=True)
        if "__ANDROID__" not in check.stdout or "__aarch64__" not in check.stdout:
            raise RuntimeError("--native-android requires Android/AArch64 clang")
    if not cc.is_file():
        raise RuntimeError(f"NDK compiler unavailable: {cc}")
    env["CC"], env["AR"] = str(cc), str(ar)
    specs = json.loads((HERE / "sources.json").read_text())
    sources = {name: source(work, name, spec) for name, spec in specs.items()}
    prefix = work / "sysroot"
    (prefix / "include/sys").mkdir(parents=True, exist_ok=True)
    (prefix / "lib").mkdir(parents=True, exist_ok=True)

    talloc = sources["talloc"]
    talloc_identity = hashlib.sha256((str(cc) + specs["talloc"]["sha256"] + digest(HERE / "cross-answers.txt") + "portable-memset-v1").encode()).hexdigest()
    stamp = prefix / "talloc-build.txt"
    if not (prefix / "lib/libtalloc.a").exists() or not stamp.exists() or stamp.read_text() != talloc_identity:
        # Use waf through the current Python; ./configure drops Termux's exec
        # preload and its /usr/bin/env shebang cannot run on the Android host.
        shutil.copyfile(HERE / "cross-answers.txt", talloc / "cross-answers.txt")
        run([sys.executable, "buildtools/bin/waf", "configure", f"--prefix={prefix}", "--disable-rpath",
             "--disable-python", "--cross-compile", "--cross-answers=cross-answers.txt"], talloc, env, log)
        # Native Android builds can see a newer libc than their API-29 headers.
        # Use Samba's portable memset_explicit rather than a newer system symbol.
        config = talloc / "bin/default/config.h"
        config.write_text(config.read_text().replace("#define HAVE_MEMSET_EXPLICIT 1", "/* Use portable memset_explicit at API 29. */"))
        run([sys.executable, "buildtools/bin/waf", "build", "--targets=talloc", "-j4"], talloc, env, log)
        objects = sorted((talloc / "bin/default").glob("talloc*.o"))
        objects += [talloc / "bin/default/lib/replace" / name for name in ("replace.c.1.o", "closefrom.c.1.o")]
        if not objects:
            raise RuntimeError("talloc objects missing")
        run([ar, "rcs", prefix / "lib/libtalloc.a", *objects], talloc, env, log)
        shutil.copyfile(talloc / "talloc.h", prefix / "include/talloc.h")
        stamp.write_text(talloc_identity)

    shmem = sources["libandroid-shmem"]
    code = shmem / "shmem.c"
    code.write_text(code.read_text().replace("sprintf(symlink_path, ASHV_KEY_SYMLINK_PATH, key);", '''const char *tmp = getenv("PROOT_TMP_DIR");
        if (tmp == NULL || snprintf(symlink_path, sizeof(symlink_path), "%s/ashv_key_%d", tmp, key) >= sizeof(symlink_path)) {
            pthread_mutex_unlock(&mutex);
            errno = ENAMETOOLONG;
            return -1;
        }'''))
    run([cc, "-fPIC", "-O2", "-std=c11", "-c", "shmem.c", "-o", "shmem.o"], shmem, env, log)
    run([ar, "rcs", prefix / "lib/libandroid-shmem.a", "shmem.o"], shmem, env, log)
    shutil.copyfile(shmem / "shm.h", prefix / "include/sys/shm.h")

    proot = sources["proot"]
    ashmem = proot / "src/extension/ashmem_memfd/ashmem_memfd.c"
    if "#include <string.h>" not in ashmem.read_text():
        ashmem.write_text("#include <string.h>\n" + ashmem.read_text())
    # Ship only the 64-bit loader. Blender and this rootfs are ARM64-only.
    arch = proot / "src/arch.h"
    text = arch.read_text()
    start, end = text.index("#elif defined(ARCH_ARM64)"), text.index("#elif defined(ARCH_X86)")
    text = text[:start] + text[start:end].replace("#define HAS_LOADER_32BIT true", "/* Godot ARM64 runtime: no 32-bit guest. */") + text[end:]
    arch.write_text(text)
    cli = proot / "src/cli/cli.c"
    cli.write_text(cli.read_text().replace("is prepending /data/data/com.termux/... to executable paths", "is rewriting executable paths"))
    temp = proot / "src/path/temp.c"
    temp.write_text(temp.read_text().replace("temp_directory = P_tmpdir;", 'temp_directory = "/tmp";'))
    env["CPPFLAGS"] = f"-I{prefix / 'include'} -DARG_MAX=131072 -DVERSION=\\\"{specs['proot']['version']}\\\""
    env["LDFLAGS"] = f"-L{prefix / 'lib'} -llog -landroid -Wl,-z,max-page-size=16384"
    env["PROOT_UNBUNDLE_LOADER"] = "/__godot_requires_PROOT_LOADER__"
    run(["make", "-C", "src", "-j4", "PROOT_WITH_LIBANDROID_SHMEM=true", f"STRIP={strip}"], proot, env, log)
    libraries = output / "jniLibs/arm64-v8a"
    libraries.mkdir(parents=True, exist_ok=True)
    for name, original in [("libai_proot.so", proot / "src/proot"), ("libai_proot_loader.so", proot / "src/loader/loader")]:
        target = libraries / name
        shutil.copyfile(original, target)
        target.chmod(0o755)
        run([strip, target], output, env, log)
        if args.native_android and name == "libai_proot.so":
            # The Termux development compiler injects an rpath. The NDK does not.
            run(["patchelf", "--set-rpath", "", target], output, env, log)
            run(["patchelf", "--remove-rpath", target], output, env, log)
        if b"/data/data/com.termux/" in target.read_bytes():
            raise RuntimeError(f"Termux-private path leaked into {target}")
        elf(target, 3 if name == "libai_proot.so" else 2)
    guest = output / "assets/godot_ai/embedded/linux-probe"
    guest.parent.mkdir(parents=True, exist_ok=True)
    run([cc, "-nostdlib", "-static", "-Wl,-e,_start,--build-id=none,-z,max-page-size=16384", HERE / "linux_probe.S", "-o", guest], output, env, log)
    elf(guest, 2)
    notices = guest.parent / "licenses"
    notices.mkdir(exist_ok=True)
    for name, spec in specs.items():
        shutil.copyfile(sources[name] / spec["license_file"], notices / f"{name}.txt")
    manifest = {"schema": 1, "abi": "arm64-v8a", "min_sdk": 29, "components": specs,
                "files": {str(p.relative_to(output)): {"sha256": digest(p), "size": p.stat().st_size}
                          for p in [libraries / "libai_proot.so", libraries / "libai_proot_loader.so", guest]}}
    (guest.parent / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # Preserve the original upstream archives and every local build modification.
    # Consumers can rebuild the native GPL/LGPL components with the Android NDK.
    with tarfile.open(output / "corresponding-sources.tar.gz", "w:gz") as bundle:
        for spec in specs.values():
            archive = work / "downloads" / Path(spec["url"]).name
            bundle.add(archive, arcname="downloads/" + archive.name)
        for path in sorted(HERE.iterdir()):
            if path.is_file() and path.suffix in [".py", ".json", ".txt", ".S", ".md"]:
                bundle.add(path, arcname="build/" + path.name)
    print(json.dumps(manifest, indent=2), flush=True)


if __name__ == "__main__":
    main()
