#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

if ! command -v ghdl >/dev/null 2>&1; then
    printf '%s\n' "GHDL is required to run the VHDL testbenches." >&2
    exit 1
fi

cd "$ROOT_DIR"

ghdl -a --std=08 --workdir="$BUILD_DIR" src/rtl/o1_pkg.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" src/rtl/register_file.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" src/rtl/alu.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" src/rtl/instruction_memory.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" src/rtl/data_memory.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" tests/tb_register_file.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" tests/tb_alu.vhd
ghdl -a --std=08 --workdir="$BUILD_DIR" tests/tb_memories.vhd

for testbench in tb_register_file tb_alu tb_memories; do
    ghdl -e --std=08 --workdir="$BUILD_DIR" "$testbench"
    ghdl -r --std=08 --workdir="$BUILD_DIR" "$testbench" --assert-level=error
done
