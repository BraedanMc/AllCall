#!/usr/bin/env bash
# Cohort sample ids must match write_sheets (CRLF-safe).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'sample,fastq_1,fastq_2\r\nS1,%s/a.fastq.gz,%s/b.fastq.gz\r\nS2,%s/c.fastq.gz,%s/d.fastq.gz\r\n' \
  "$tmp" "$tmp" "$tmp" "$tmp" >"${tmp}/cohort.csv"

mapfile -t ids < <(cohort_sample_ids "${tmp}/cohort.csv")
[[ "${#ids[@]}" -eq 2 ]] || {
  echo "test_cohort_sample_ids: expected 2 samples, got ${#ids[@]}" >&2
  exit 1
}
[[ "${ids[0]}" == S1 && "${ids[1]}" == S2 ]] || {
  echo "test_cohort_sample_ids: unexpected ids: ${ids[*]}" >&2
  exit 1
}
for id in "${ids[@]}"; do
  [[ "$id" != *$'\r'* ]] || {
    echo "test_cohort_sample_ids: CR in sample id '${id}'" >&2
    exit 1
  }
done

printf 'sample,fastq_1,fastq_2\nS1,%s/a.fastq.gz,%s/b.fastq.gz\nS1,%s/c.fastq.gz,%s/d.fastq.gz\nS2,%s/e.fastq.gz,%s/f.fastq.gz\n' \
  "$tmp" "$tmp" "$tmp" "$tmp" "$tmp" "$tmp" >"${tmp}/dup.csv"
mapfile -t deduped < <(cohort_sample_ids "${tmp}/dup.csv")
[[ "${#deduped[@]}" -eq 2 && "${deduped[0]}" == S1 && "${deduped[1]}" == S2 ]] || {
  echo "test_cohort_sample_ids: duplicate rows should dedupe to S1 S2 (got ${deduped[*]})" >&2
  exit 1
}

echo "test_cohort_sample_ids: ok"
