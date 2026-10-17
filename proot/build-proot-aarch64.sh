#!/bin/bash
# Builds the patched proot + loader bundled in the APK as
# app/app/src/main/jniLibs/arm64-v8a/libproot.so and libproot-loader.so.
#
# Sources are the same ones octo4a-bootstrap-builder uses for bootstrap 1.11.3-4f6ff958
# (feelfreelinux/proot and the talloc vendored in the builder), plus
# 0001-untag-tracee-pointers.patch. Works from Git Bash on Windows, Linux or macOS
# with only the Android NDK; no make/waf needed.
#
# Usage: NDK=/path/to/ndk ./build-proot-aarch64.sh [work-dir]
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$HERE/build}"
JNILIBS="$HERE/../app/app/src/main/jniLibs/arm64-v8a"

PROOT_REPO=https://github.com/feelfreelinux/proot
PROOT_COMMIT=21247cf56df80a695020a61a7e52fc179fc798e3
BUILDER_REPO=https://github.com/feelfreelinux/octo4a-bootstrap-builder
BUILDER_COMMIT=4f6ff9580f5af6400eec790b3a33d75ad57984df

NDK="${NDK:-${ANDROID_NDK_HOME:-$LOCALAPPDATA/Android/Sdk/ndk/27.0.12077973}}"
BIN="$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)"
EXE=""; [ -f "$BIN/clang.exe" ] && EXE=".exe"
# -ffile-prefix-map keeps local paths (embedded by talloc's __location__) out of the binaries
CC="$BIN/clang$EXE --target=aarch64-linux-android21 -ffile-prefix-map=$WORK/="
AR="$BIN/llvm-ar$EXE"
READELF="$BIN/llvm-readelf$EXE"
STRIP="$BIN/llvm-strip$EXE"
PAGE_FLAGS="-z,noexecstack,-z,max-page-size=16384"

fetch() { # repo commit dir
	if [ ! -d "$3" ]; then
		git clone -q "$1" "$3"
	fi
	git -C "$3" checkout -q -f "$2"
}

mkdir -p "$WORK"
fetch "$PROOT_REPO" "$PROOT_COMMIT" "$WORK/proot"
fetch "$BUILDER_REPO" "$BUILDER_COMMIT" "$WORK/builder"
git -C "$WORK/proot" apply "$HERE/0001-untag-tracee-pointers.patch"

OUT="$WORK/out"
rm -rf "$OUT" && mkdir -p "$OUT/obj" "$OUT/talloc"

# talloc (static). config.h stands in for the one waf's configure would generate.
T="$WORK/builder/external/talloc"
cat > "$OUT/talloc/config.h" <<'EOF'
#define HAVE_STDBOOL_H 1
#define HAVE_BOOL 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STDLIB_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_FCNTL_H 1
#define HAVE_ERRNO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDARG_H 1
#define HAVE_SYS_AUXV_H 1
#define HAVE_INTPTR_T 1
#define HAVE_UINTPTR_T 1
#define HAVE_PTRDIFF_T 1
#define HAVE_VA_COPY 1
#define HAVE_C99_VSNPRINTF 1
#define HAVE_STRNLEN 1
#define HAVE_STRNDUP 1
#define HAVE_MEMMOVE 1
#define HAVE_VSNPRINTF 1
#define HAVE_SNPRINTF 1
#define HAVE_GETAUXVAL 1
#define HAVE_CONSTRUCTOR_ATTRIBUTE 1
#define HAVE_DESTRUCTOR_ATTRIBUTE 1
#define HAVE___ATTRIBUTE__ 1
#define HAVE_INCOHERENT_MMAP 0
#define TALLOC_BUILD_VERSION_MAJOR 2
#define TALLOC_BUILD_VERSION_MINOR 4
#define TALLOC_BUILD_VERSION_RELEASE 1
#define HAVE_USLEEP 1
#define HAVE_MEMSET_S 1
#define HAVE_SETENV 1
#define HAVE_UNSETENV 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR_R 1
#define HAVE_MKDTEMP 1
#define HAVE_SETEUID 1
#define HAVE_SETEGID 1
#define HAVE_SETLINEBUF 1
#define HAVE_VASPRINTF 1
#define HAVE_ASPRINTF 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOULL 1
#define HAVE_STRTOK_R 1
#define HAVE_STRSEP 1
#define HAVE_FTRUNCATE 1
#define HAVE_PREAD 1
#define HAVE_PWRITE 1
#define HAVE_DLOPEN 1
#define HAVE_DLSYM 1
#define HAVE_DLERROR 1
#define HAVE_DLCLOSE 1
#define HAVE_SYS_TIME_H 1
#define HAVE_TIME_H 1
#define HAVE_POLL_H 1
#define HAVE_DIRENT_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_NETDB_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_MMAP 1
#define HAVE_MREMAP 1
#define HAVE_SHARED_MMAP 1
#define HAVE_GETPAGESIZE 1
#define HAVE_SECURE_MKSTEMP 1
#define HAVE_DLFCN_H 1
EOF
$CC -O2 -fPIC -D_GNU_SOURCE -D__STDC_WANT_LIB_EXT1__=1 -include dlfcn.h \
	-I"$OUT/talloc" -I"$T" -I"$T/lib/replace" -c "$T/talloc.c" -o "$OUT/talloc/talloc.o"
"$AR" rcs "$OUT/talloc/libtalloc.a" "$OUT/talloc/talloc.o"
cp "$T/talloc.h" "$OUT/talloc/"

cd "$WORK/proot/src"

# build.h normally comes from the Makefile's feature checks. process_vm_* is left out
# because Bionic only has it from API 23, matching the bootstrap's own proot.
cat > "$OUT/build.h" <<EOF
#ifndef BUILD_H
#define BUILD_H
#undef VERSION
#define VERSION "$(git describe --tags --always --abbrev=8)-untag"
#define HAVE_SECCOMP_FILTER
#endif
EOF

# 64-bit loader (static, freestanding, fixed load address from arch.h)
LOADER_CFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I. -I$OUT -O2 -fPIC -ffreestanding"
$CC $LOADER_CFLAGS -c loader/loader.c -o "$OUT/obj/loader.o"
$CC $LOADER_CFLAGS -c loader/assembly.S -o "$OUT/obj/assembly.o"
$CC -o "$OUT/loader" "$OUT/obj/loader.o" "$OUT/obj/assembly.o" \
	-static -nostdlib -Wl,--build-id=none,-Ttext=0x2000000000,$PAGE_FLAGS
"$READELF" -s "$OUT/loader" | awk -f loader/loader-info.awk > "$OUT/loader-info.c"

# proot, with the object list taken from GNUmakefile
OBJECTS=$(sed -n '/^OBJECTS += \\/,/^$/p' GNUmakefile | grep -oE '[a-z0-9_/-]+\.o' | grep -v '^loader/')
OBJECTS="$OBJECTS extension/mountinfo/mountinfo.o"
CFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -DARG_MAX=131072 -I. -I$OUT -I$OUT/talloc -O2
	-DPROOT_UNBUNDLE_LOADER=\"../libexec/proot\""
LINK_OBJS=""
for o in $OBJECTS; do
	mkdir -p "$OUT/obj/$(dirname "$o")"
	$CC $CFLAGS -w -c "${o%.o}.c" -o "$OUT/obj/$o"
	LINK_OBJS="$LINK_OBJS $OUT/obj/$o"
done
$CC $CFLAGS -c "$OUT/loader-info.c" -o "$OUT/obj/loader-info.o"
$CC -o "$OUT/proot" $LINK_OBJS "$OUT/obj/loader-info.o" -L"$OUT/talloc" -ltalloc -Wl,$PAGE_FLAGS

"$STRIP" "$OUT/proot" "$OUT/loader"
mkdir -p "$JNILIBS"
cp "$OUT/proot" "$JNILIBS/libproot.so"
cp "$OUT/loader" "$JNILIBS/libproot-loader.so"
ls -la "$JNILIBS"
