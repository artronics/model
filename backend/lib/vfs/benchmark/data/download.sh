#!/usr/bin/env sh

set -e

rm -rf zig
commit_id="91daf1c8d8a64133f18dcec2b96e9f9f4326fe36"
git clone https://github.com/ziglang/zig
cd zig
git reset --hard $commit_id
rm -rf .git
cd ..
