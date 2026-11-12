#!/usr/bin/env bash
# HPC VI STAR builder must stay aligned with config/pin.yaml and small_host layout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/bin/hpc_build_vi_star_indices.sh"
PIN="${ROOT}/config/pin.yaml"

hpc_const() {
  local name="$1"
  grep "^${name}=" "$SCRIPT" | head -1 | sed "s/^${name}=//" | tr -d "'"
}

for species in human mouse; do
  case "$species" in
    human)
      want_fasta="$(hpc_const HUMAN_FASTA_MD5)"
      want_gtf="$(hpc_const HUMAN_GTF_MD5)"
      ;;
    mouse)
      want_fasta="$(hpc_const MOUSE_FASTA_MD5)"
      want_gtf="$(hpc_const MOUSE_GTF_MD5)"
      ;;
  esac
  pin_fasta="$(yq -r ".species.${species}.references.fasta_md5" "$PIN")"
  pin_gtf="$(yq -r ".species.${species}.references.gtf_md5" "$PIN")"
  [[ "$want_fasta" == "$pin_fasta" ]] || {
    echo "test_hpc_build_vi_star_indices: ${species} FASTA MD5 mismatch with pin" >&2
    exit 1
  }
  [[ "$want_gtf" == "$pin_gtf" ]] || {
    echo "test_hpc_build_vi_star_indices: ${species} GTF MD5 mismatch with pin" >&2
    exit 1
  }
done

grep -q 'HOST_OUT=.*host_star' "$SCRIPT" || {
  echo "test_hpc_build_vi_star_indices: script must define host_star output" >&2
  exit 1
}
grep -q 'PLUS_OUT=.*plus_star' "$SCRIPT" || {
  echo "test_hpc_build_vi_star_indices: script must define plus_star output" >&2
  exit 1
}
grep -q 'star/Genome' "$SCRIPT" || {
  echo "test_hpc_build_vi_star_indices: script must build STAR star/Genome" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
set +e
out="$("${SCRIPT}" --species bogus --root "$tmp" 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || {
  echo "test_hpc_build_vi_star_indices: expected exit 2 for unknown species (got ${rc})" >&2
  exit 1
}
echo "$out" | grep -q 'species must be human or mouse' || {
  echo "test_hpc_build_vi_star_indices: missing species error message" >&2
  exit 1
}

"${SCRIPT}" -h | grep -q 'ref/vi_star' || {
  echo "test_hpc_build_vi_star_indices: help should mention ref/vi_star default" >&2
  exit 1
}

echo "test_hpc_build_vi_star_indices: ok"
