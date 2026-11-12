#!/bin/sh
# Build the asm-ssz library, the test runner and the bench for one Windows ISA.
# Usage: platform/windows/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh.
# The library uses the pinned LLVM; the test runner and the bench use llvm-mingw for the Windows C runtime.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
crypto=$root/build/deps/asm-crypto

case "$isa" in
  x86_64) target=x86_64-w64-windows-gnu;  march="-march=x86-64"; mingw=x86_64-w64-mingw32 ;;
  arm64)  target=aarch64-w64-windows-gnu; march="-march=armv8-a"; mingw=aarch64-w64-mingw32 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target $march -I"$root/include" -I"$root/platform/windows" \
    -c "$root/asm/core/$isa/ssz.s" -o "$out/ssz.o"
rm -f "$out/libasm-ssz.a"
llvm-ar rcs "$out/libasm-ssz.a" "$out/ssz.o"
clang --target=$target $march -I"$crypto/include" -I"$crypto/platform/windows" \
    -c "$crypto/asm/core/$isa/sha256.s" -o "$out/sha256.o"

/opt/llvm-mingw/bin/$mingw-clang $march -std=c11 -O2 -Wall -Wextra -Werror -static \
    "$root/tests/runner/runner.c" "$out/libasm-ssz.a" "$out/sha256.o" -o "$out/runner.exe"
/opt/llvm-mingw/bin/$mingw-clang $march -std=c11 -O2 -Wall -Wextra -Werror -static \
    "$root/bench/bench.c" "$out/libasm-ssz.a" "$out/sha256.o" -ladvapi32 -o "$out/bench.exe"
