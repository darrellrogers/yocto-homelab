#!/bin/bash
# Repeatable Yocto build runner.
# Usage: ./run-build.sh [target]   (default target: core-image-minimal)
#
# Assumes a sibling layout:
#   <root>/poky/          # cloned poky, scarthgap branch
#   <root>/build/         # build dir (created by oe-init-build-env)
# Run from <root>, or set YOCTO_ROOT.
set -euo pipefail

YOCTO_ROOT="${YOCTO_ROOT:-$HOME/yocto}"
TARGET="${1:-core-image-minimal}"

cd "$YOCTO_ROOT"
# shellcheck disable=SC1091
source poky/oe-init-build-env build

echo "=== bitbake ${TARGET} starting $(date) ==="
bitbake "$TARGET"
echo "=== bitbake ${TARGET} finished $(date) ==="

cat <<EOF

Done. Boot it with:
  source poky/oe-init-build-env build
  runqemu qemux86-64 nographic       # login: root  (exit: Ctrl-A then X)
EOF
