#!/bin/sh
# Build the asm-ssz library for one macOS ISA.
# Usage: platform/macos/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh, so
# the library uses the pinned LLVM. link-runner.sh links the test runner on a Mac.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
crypto=$root/build/deps/asm-crypto

case "$isa" in
  x86_64) target=x86_64-apple-macos11 ;;
  arm64)  target=arm64-apple-macos11 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target -I"$root/include" -I"$root/platform/macos" \
    -c "$root/asm/core/$isa/ssz.s" -o "$out/ssz.o"
rm -f "$out/libasm-ssz.a"
llvm-ar --format=darwin rcs "$out/libasm-ssz.a" "$out/ssz.o"
clang --target=$target -I"$crypto/include" -I"$crypto/platform/macos" \
    -c "$crypto/asm/core/$isa/sha256.s" -o "$out/sha256.o"
