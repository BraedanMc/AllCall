#!/usr/bin/env bash
# Apptainer overlay for HPC local runs (post-Docker singularity.enabled fix).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

overlay="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$overlay" ]] || {
  echo "test_nextflow_apptainer_overlay: missing ${overlay}" >&2
  exit 1
}

grep -q 'enabled = true' "$overlay" || {
  echo "test_nextflow_apptainer_overlay: singularity.enabled must be true" >&2
  exit 1
}
grep -q 'autoMounts = false' "$overlay" || {
  echo "test_nextflow_apptainer_overlay: autoMounts false required for -u runs" >&2
  exit 1
}
grep -q -- '-u --containall --no-home' "$overlay" || {
  echo "test_nextflow_apptainer_overlay: expected containall runOptions" >&2
  exit 1
}

# local.config must not re-enable singularity when docker profile is selected.
base="${ROOT}/config/nextflow/local.config"
if grep -A8 '^singularity {' "$base" | grep -q 'enabled = true'; then
  echo "test_nextflow_apptainer_overlay: local.config must not set singularity.enabled true" >&2
  exit 1
fi

echo "test_nextflow_apptainer_overlay: ok"
