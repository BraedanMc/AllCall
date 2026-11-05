#!/usr/bin/env bash
# Apptainer overlay for HPC local sites (Mac docker profile uses local.config singularity off).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="${ROOT}/config/nextflow/local.apptainer.config"

[[ -f "$OVERLAY" ]] || {
  echo "test_apptainer_overlay: missing ${OVERLAY}" >&2
  exit 1
}
grep -qE '^singularity \{' "$OVERLAY" || {
  echo "test_apptainer_overlay: expected singularity block" >&2
  exit 1
}
grep -A5 '^singularity {' "$OVERLAY" | grep -q 'enabled = true' || {
  echo "test_apptainer_overlay: apptainer overlay must enable singularity" >&2
  exit 1
}
grep -q 'containall' "$OVERLAY" || {
  echo "test_apptainer_overlay: expected contained runOptions" >&2
  exit 1
}

local_config="${ROOT}/config/nextflow/local.config"
grep -A5 '^singularity {' "$local_config" | grep -q 'enabled = false' || {
  echo "test_apptainer_overlay: local.config must keep singularity disabled for docker profile" >&2
  exit 1
}

echo "test_apptainer_overlay: ok"
