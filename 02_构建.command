#!/bin/zsh
set -eu
atlas_root="$(cd -- "$(dirname -- "$0")" && pwd)"
export TMPDIR="$atlas_root/work/tmp"
export LC_ALL=en_US.UTF-8
export OMP_NUM_THREADS=2
export VECLIB_MAXIMUM_THREADS=2
mkdir -p "$TMPDIR" "$atlas_root/checks"
Rscript --vanilla "$atlas_root/scripts/prepare.R" > "$atlas_root/checks/prepare.log" 2>&1
Rscript --vanilla "$atlas_root/scripts/check.R" > "$atlas_root/checks/r_checks.log" 2>&1
Rscript --vanilla "$atlas_root/scripts/export.R" > "$atlas_root/checks/export.log" 2>&1
python3 -B "$atlas_root/scripts/manifest.py"
