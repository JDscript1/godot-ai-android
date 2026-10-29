# Native Android runtime build

This directory builds PRoot and its loader for Android ARM64/API 29+. The
result depends on Android system libraries, not on an installed Termux app.
Python and make are build tools only. The current source also packages a pinned
Debian filesystem which prepares automatically on first launch;
Python/Node/Git/ripgrep/Blender are optional in-app installs.
Blender and third-party agent harnesses have not been validated in the Godot APK.

```sh
python3 build.py --ndk /path/to/android-ndk \
  --work /path/to/build-cache --output /path/to/generated-runtime
```

An Android/ARM64 development host can instead use `--native-android` with
Clang, llvm-ar, llvm-strip and patchelf installed. This mode is for compilation
and ELF inspection; executing its loader from writable app data may be refused
by Android. The APK must package the generated `.so` files as extracted native
libraries. Pass `PROOT_LOADER` and `PROOT_TMP_DIR` explicitly at runtime.

Output:

- `jniLibs/arm64-v8a/libai_proot.so`: PRoot with static talloc/shmem dependencies.
- `jniLibs/arm64-v8a/libai_proot_loader.so`: freestanding 64-bit guest loader.
- `assets/godot_ai/embedded/linux-probe`: tiny libc-free Linux ELF guest.
- `assets/godot_ai/embedded/manifest.json`: component versions and file hashes.
- `assets/godot_ai/embedded/licenses/`: upstream license notices.
- `corresponding-sources.tar.gz`: original upstream archives, pinned checksums,
  build instructions and the script containing all source changes.

The sources are pinned in `sources.json`. The script applies these changes:
disable the 32-bit guest loader; use explicit runtime loader/temp paths; make
shmem key files use the supplied private temp directory with bounds checks; use
Samba's portable `memset_explicit` at API 29; and remove the Termux-specific
diagnostic path. No runtime component is copied from the host Termux install.
The ashmem extension also receives its missing explicit `string.h` include,
required by the NDK's headers.
PRoot's generated version is pinned instead of inheriting the enclosing Godot
repository's git tag.

PRoot's COPYING, talloc's LGPLv3 license and libandroid-shmem's BSD license are
preserved from their source archives. The exact source/build bundle accompanies
the CI APK as an artifact. Regenerate it whenever changing a source or build rule.

## Persistent Linux filesystem

`rootfs.py --work <cache> --output <generated>` fetches the exact official
Debian ARM64 layer pinned in `rootfs.json`, verifies its SHA-256 and repackages
it as `assets/godot_ai/linux/rootfs.zip` plus `package.json`. Gradle invokes
this after building PRoot. Source and installed-package copyright files stay
in the filesystem. No Termux bootstrap or tar executable is used on Android.
The base is about 33 MB zipped and 104 MB of regular files before optional tools.

The installer validates each file's size/hash, defers links until regular files
are written, rejects paths through links and publishes the installed directory
only after extraction. PRoot's packaged native loader executes the Linux files;
Android does not directly execute an extracted Debian ELF. Only the selected
Godot project is mounted as `/workspace` for an agent command. PRoot is not a
security sandbox and cannot grant kernel features absent from Android.

`python test_rootfs.py` checks archive traversal, link handling, budgets and
reproducible packaging. `tests/RuntimeArchiveTest.kt` exercises the actual Kotlin
unpacker with malicious manifests. `tests/RuntimeSmoke.kt` runs an installation,
optional tool installs and command/cancellation checks using supplied native
files. `tests/ZivaPackageTest.kt` and `tests/ZivaGodotTest.kt` exercise the
optional Ziva addon and official Godot installers with fixtures: archive and
binary hashes, unsafe paths, cancellation and preservation of the previous
install. These development controls are distinct from the installed Godot service.
See [the runtime document](../../docs/AI_LINUX_RUNTIME.md) for current evidence.

Ziva lifecycle coverage now also includes `tests/ZivaSessionTest.kt` (kernel
lease ownership, process death, stale saved status and PID-specific endpoint
hints) and `tests/ZivaUpdatesTest.kt` (official stable ARM64 metadata, digest,
URL and version ordering). Run their JVM entry points with the portable runtime
classes, Kotlin standard library and org.json; compiling the update bridge also
requires Android SDK stubs. These do not replace Android Activity/Binder tests.
