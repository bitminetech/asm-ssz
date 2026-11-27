#!/bin/sh
# Pin the dependencies, fetch them into build/deps/, and name the functions
# this repo calls in them (ARCHITECTURE.md section 5).
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
#
# The functions this repo calls in each dependency. platform/check.py rejects
# a call to any other function.
# uses asm-crypto: crypto_sha256

set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
crypto=$root/build/deps/asm-crypto
commit=6df4597fa0c3584d5eef4f89cbc647797316853d    # asm-crypto
if [ "$(git -C "$crypto" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
    rm -rf "$crypto"
    git init -q "$crypto"
    git -C "$crypto" fetch -q --depth 1 https://github.com/bitminetech/asm-crypto "$commit"
    git -C "$crypto" checkout -q FETCH_HEAD
fi
