#!/usr/bin/env bash
# CDS BAM freshness vs Sarek SV CRAM (resume / re-filter when CRAM is newer).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sv="${tmp}/S1.md.cram"
cds="${tmp}/S1.cds.bam"

touch -t 202601010000 "$sv"
touch -t 202601020000 "$cds"
cohort_cds_bam_stale "$sv" "$cds" && {
  echo "test_cds_filter_resume: expected fresh CDS BAM not stale" >&2
  exit 1
}

touch -t 202601030000 "$sv"
cohort_cds_bam_stale "$sv" "$cds" || {
  echo "test_cds_filter_resume: expected stale CDS after newer CRAM" >&2
  exit 1
}

rm -f "$cds"
cohort_cds_bam_stale "$sv" "$cds" || {
  echo "test_cds_filter_resume: missing CDS should be stale" >&2
  exit 1
}

echo "test_cds_filter_resume: ok"
