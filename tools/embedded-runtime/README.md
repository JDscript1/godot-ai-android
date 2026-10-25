# Native Android runtime build

This directory builds PRoot and its loader for Android ARM64/API 29+. The
result depends on Android system libraries, not on an installed Termux app.
Python and make are build tools only. Blender is not included in this milestone.

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
