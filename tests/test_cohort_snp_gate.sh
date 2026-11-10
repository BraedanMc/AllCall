#!/usr/bin/env bash
# SNP launch gate: wait for SV pass and all CDS filters before starting Sarek SNP.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
out_sv="${tmp}/sarek_sv"

mk_sv_bam() {
  local sample="$1"
  mkdir -p "${out_sv}/preprocessing/markduplicates/${sample}"
  : >"${out_sv}/preprocessing/markduplicates/${sample}/${sample}.md.cram"
}

declare -a samples=(S1 S2)
declare -A STATUS

expect_gate() {
  local label="$1" expect_settled="$2" sv_done="$3"
  if cohort_cds_filter_settled "$sv_done" "$out_sv" samples STATUS; then
    [[ "$expect_settled" == yes ]] || {
      echo "test_cohort_snp_gate: ${label} expected not settled" >&2
      exit 1
    }
  else
    [[ "$expect_settled" == no ]] || {
      echo "test_cohort_snp_gate: ${label} expected settled" >&2
      exit 1
    }
  fi
}

expect_gate "SV cohort pass not finished" no 0

mk_sv_bam S1
STATUS["S1|cds_filter"]=succeeded
expect_gate "SV done; sample without SV BAM skipped" yes 1

mk_sv_bam S2
STATUS["S2|cds_filter"]=not_started
expect_gate "SV BAM present; cds_filter not_started" no 1

STATUS["S2|cds_filter"]=succeeded
expect_gate "all SV BAMs cds-filtered" yes 1

samples=(Solo)
STATUS=()
STATUS["Solo|cds_filter"]=not_started
mk_sv_bam Solo
expect_gate "single sample waiting on cds_filter" no 1

STATUS["Solo|cds_filter"]=failed
expect_gate "terminal cds_filter status counts as settled" yes 1

expect_vi_gate() {
  local label="$1" vi_enabled="$2" vi_finished="$3" expect_ok="$4"
  if cohort_vi_finished_for_snp "$vi_enabled" "$vi_finished"; then
    [[ "$expect_ok" == yes ]] || {
      echo "test_cohort_snp_gate: ${label} expected VI gate closed" >&2
      exit 1
    }
  else
    [[ "$expect_ok" == no ]] || {
      echo "test_cohort_snp_gate: ${label} expected VI gate open" >&2
      exit 1
    }
  fi
}

expect_vi_gate "VI disabled ignores vi_finished" false 0 yes
expect_vi_gate "VI enabled; cohort pass still running" true 0 no
expect_vi_gate "VI enabled; cohort pass finished" true 1 yes

echo "test_cohort_snp_gate: ok"
