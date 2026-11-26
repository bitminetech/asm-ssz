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
commit=a364b8c3c06b55607834f93cda7b7e315323b3b8    # asm-crypto
if [ "$(git -C "$crypto" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
    rm -rf "$crypto"
    git init -q "$crypto"
    git -C "$crypto" fetch -q --depth 1 https://github.com/bitminetech/asm-crypto "$commit"
    git -C "$crypto" checkout -q FETCH_HEAD
fi
