#!/usr/bin/env bash
# Run bazel-7 (bzlmod) for cva6_with_rvtester inside the cvm podman image.
# Usage: infra/run-bazel.sh build --config=bzlmod //dv/cva6/verilator:cva6_tb_verilator
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="aus-gitlab.local.tenstorrent.com:5005/riscv/dv/cvm:0.1.3"

# Bazel outputs + fetches live on the regression area (roomier than the
# /proj_risc home area). The transient sandbox goes on the container-local
# /tmp (see .bazelrc --sandbox_base) so the "copy inputs into sandbox" step
# doesn't run on a network filesystem.
OUTPUT_ROOT="/proj_risc_regr/asc/a0/user_regr/areddy/cva6_bazel_root"

exec podman run --rm \
  -v /proj_risc:/proj_risc \
  -v /proj_risc_regr:/proj_risc_regr \
  -v /tools_vendor:/tools_vendor \
  -v /tools_risc:/tools_risc \
  -v /tech:/tech \
  -v /localdev:/localdev \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
  -w "$REPO" \
  "$IMAGE" \
  bazel-7 --output_user_root="$OUTPUT_ROOT" "$@"
