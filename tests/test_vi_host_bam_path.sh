#!/usr/bin/env bash
# Host BAM path for sex inference must match nf-core/viralintegration 0.1.1 STAR_ALIGN_HOST outputs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

grep -q 'star/\${sample}\.host\.Aligned\.sortedByCoord\.out\.bam' "${ROOT}/bin/run_cohort.sh" || {
  echo "test_vi_host_bam_path: run_cohort.sh missing expected VI host BAM path" >&2
  exit 1
}

if grep -q 'star_align/' "${ROOT}/bin/run_cohort.sh"; then
  echo "test_vi_host_bam_path: obsolete star_align path still present" >&2
  exit 1
fi

echo "test_vi_host_bam_path: ok"
