# Bundled proot

The bootstrap's proot (feelfreelinux/proot) fails on 64-bit ARM with Android 11+: Bionic tags
heap pointers (top byte, e.g. `0xb4...`), and the kernel rejects those addresses in
`ptrace(PTRACE_PEEKDATA)`. Every intercepted syscall then fails with
`execve("/bin/sh"): Function not implemented` / `Bad address` and
`proot warning: ptrace(PEEKDATA): I/O error`.

`0001-untag-tracee-pointers.patch` strips the tag before proot reads or writes tracee memory.
The patched proot and loader ship in the APK as `jniLibs/arm64-v8a/libproot.so` and
`libproot-loader.so`. `BootstrapRepository.installBundledProot()` copies them over the
bootstrap's `bin/proot` and `libexec/proot/loader` after download and on every start.
Other architectures keep the bootstrap's binaries.

## Rebuilding

```
NDK=/path/to/android-ndk ./build-proot-aarch64.sh
```

It clones feelfreelinux/proot and octo4a-bootstrap-builder (for talloc) at the commits used by
bootstrap `1.11.3-4f6ff958`, applies the patch, builds with the NDK only (works from Git Bash
on Windows), and copies the results into `jniLibs`.
