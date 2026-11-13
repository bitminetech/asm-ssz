#!/bin/sh
# Build the asm-ssz library, the test runner and the bench for one Linux ISA.
# Usage: platform/linux/build.sh ISA OUT_DIR    (ISA: x86_64, arm64 or riscv64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
crypto=$root/build/deps/asm-crypto

case "$isa" in
  x86_64)  target=x86_64-linux-gnu;  march="-march=x86-64" ;;
  arm64)   target=aarch64-linux-gnu; march="-march=armv8-a" ;;
  riscv64) target=riscv64-linux-gnu; march="-march=rv64gc -mabi=lp64d" ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

mkdir -p "$out"
clang --target=$target $march -I"$root/include" -I"$root/platform/linux" \
    -c "$root/asm/core/$isa/ssz.s" -o "$out/ssz.o"
rm -f "$out/libasm-ssz.a"
llvm-ar rcs "$out/libasm-ssz.a" "$out/ssz.o"
clang --target=$target $march -I"$crypto/include" -I"$crypto/platform/linux" \
    -c "$crypto/asm/core/$isa/sha256.s" -o "$out/sha256.o"

# Test runner (C), linked statically so QEMU user mode needs no target libraries.
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/runner/runner.c" -I"$root/platform/linux" "$root/tests/runner/abi_$isa.s" "$out/libasm-ssz.a" "$out/sha256.o" -o "$out/runner"

# Bench (C), linked the same way.
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/bench/bench.c" "$out/libasm-ssz.a" "$out/sha256.o" -o "$out/bench"
