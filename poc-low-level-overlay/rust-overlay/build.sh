#!/bin/bash
set -e
cd "$(dirname "$0")"
cargo build --release
cp target/release/power-mode-overlay .
echo "Built: ./power-mode-overlay ($(du -h power-mode-overlay | cut -f1))"
