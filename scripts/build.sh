#!/usr/bin/env bash
# Build a Cinder program: wrapper around `main.rb build`.
# Usage: scripts/build.sh <file.cnd> [--target=...] [--emit=...] [--mode=...] [-o out] [-I dir]
set -euo pipefail

cd "$(dirname "$0")/.."
exec ruby main.rb build "$@"
