#!/usr/bin/env bash
# HPC VI STAR builder must stay aligned with config/pin.yaml reference MD5s.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HPC="${ROOT}/bin/hpc_build_vi_star_indices.sh"
PIN="${ROOT}/config/pin.yaml"

extract_hpc_md5() {
  local var="$1"
  grep -E "^${var}='" "$HPC" | head -1 | sed -E "s/^${var}='([^']+)'.*/\1/"
}

pin_ref_md5() {
  local species="$1" field="$2"
  awk -v sp="$species" -v f="$field" '
    $0 ~ "^  " sp ":$" { in_sp=1 }
    in_sp && $0 ~ "^  [a-z]" && $0 !~ "^  " sp ":" { in_sp=0 }
    in_sp && $1 == f":" { print $2; exit }
  ' "$PIN"
}

expect_match() {
  local label="$1" hpc="$2" pin="$3"
  [[ -n "$hpc" && -n "$pin" ]] || {
    echo "test_hpc_build_pin_sync: missing ${label} checksum" >&2
    exit 1
  }
  [[ "$hpc" == "$pin" ]] || {
    echo "test_hpc_build_pin_sync: ${label} drift (hpc=${hpc} pin=${pin})" >&2
    exit 1
  }
}

expect_match "human fasta" \
  "$(extract_hpc_md5 HUMAN_FASTA_MD5)" \
  "$(pin_ref_md5 human fasta_md5)"
expect_match "human gtf" \
  "$(extract_hpc_md5 HUMAN_GTF_MD5)" \
  "$(pin_ref_md5 human gtf_md5)"
expect_match "mouse fasta" \
  "$(extract_hpc_md5 MOUSE_FASTA_MD5)" \
  "$(pin_ref_md5 mouse fasta_md5)"
expect_match "mouse gtf" \
  "$(extract_hpc_md5 MOUSE_GTF_MD5)" \
  "$(pin_ref_md5 mouse gtf_md5)"

grep -q 'HOST_OUT="${OUT_ROOT}/host_star"' "$HPC" || {
  echo "test_hpc_build_pin_sync: expected host_star output root" >&2
  exit 1
}
grep -q 'star/Genome' "$HPC" || {
  echo "test_hpc_build_pin_sync: expected STAR Genome layout" >&2
  exit 1
}

echo "test_hpc_build_pin_sync: ok"
