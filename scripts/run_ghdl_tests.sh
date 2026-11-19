#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

make -C "$ROOT_DIR" clean
make -C "$ROOT_DIR" test-unit
make -C "$ROOT_DIR" sim
