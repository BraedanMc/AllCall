#!/usr/bin/env bash
# Pin manifest: Nextflow version and UCSC hg38 GTF MD5 (regression for Mac setup fetch).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pin="${ROOT}/config/pin.yaml"

grep -qE '^  version: "24\.10\.5"' "$pin" || {
  echo "test_pin_manifest: nextflow.version must stay 24.10.5 until viralintegration NF26 fix" >&2
  exit 1
}

human_gtf_md5="$(
  awk '
    $0 ~ /^  human:/ { in_human=1; next }
    in_human && $0 ~ /^  [a-z]/ && $0 !~ /^    / { in_human=0 }
    in_human && $0 ~ /gtf_md5:/ { print $2; exit }
  ' "$pin"
)"
[[ "$human_gtf_md5" == "6a585655a3e67150264b792b758372a2" ]] || {
  echo "test_pin_manifest: unexpected human gtf_md5 (got ${human_gtf_md5})" >&2
  exit 1
}

echo "test_pin_manifest: ok"
