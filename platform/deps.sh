#!/bin/sh
# Fetch the dependencies that the README pins into build/deps/.
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
crypto=$root/build/deps/asm-crypto
commit=a364b8c3c06b55607834f93cda7b7e315323b3b8    # asm-crypto, README Dependencies
if [ "$(git -C "$crypto" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
    rm -rf "$crypto"
    git init -q "$crypto"
    git -C "$crypto" fetch -q --depth 1 https://github.com/bitminetech/asm-crypto "$commit"
    git -C "$crypto" checkout -q FETCH_HEAD
fi
