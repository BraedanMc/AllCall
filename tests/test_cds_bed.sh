#!/usr/bin/env bash
# CDS BED from GTF: end column, flank, merge, and coordinate clamping.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cds="${ROOT}/bin/cds_bed.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_bed() {
  local label="$1" expected="$2" bed="$3"
  if ! diff -u "$expected" "$bed"; then
    echo "test_cds_bed: ${label} mismatch" >&2
    exit 1
  fi
}

cat >"${tmp}/wide.gtf" <<'GTF'
chr1	source	CDS	100	500	.	+	0	.
GTF
"${cds}" "${tmp}/wide.gtf" "${tmp}/wide.bed" 10
printf 'chr1\t89\t510\n' >"${tmp}/wide.expected"
assert_bed "CDS end column with flank" "${tmp}/wide.expected" "${tmp}/wide.bed"

cat >"${tmp}/start.gtf" <<'GTF'
chr1	source	CDS	3	12	.	+	0	.
GTF
"${cds}" "${tmp}/start.gtf" "${tmp}/start.bed" 10
printf 'chr1\t0\t22\n' >"${tmp}/start.expected"
assert_bed "flank clamps start at zero" "${tmp}/start.expected" "${tmp}/start.bed"

cat >"${tmp}/merge.gtf" <<'GTF'
chr1	source	CDS	10	30	.	+	0	.
chr1	source	CDS	25	50	.	+	0	.
chr2	source	CDS	1	10	.	+	0	.
chr1	source	exon	10	50	.	+	.	.
GTF
"${cds}" "${tmp}/merge.gtf" "${tmp}/merge.bed" 0
cat >"${tmp}/merge.expected" <<'BED'
chr1	9	50
chr2	0	10
BED
assert_bed "overlapping CDS merged per chromosome" "${tmp}/merge.expected" "${tmp}/merge.bed"

echo "test_cds_bed: ok"
