#!/usr/bin/env bash
# HPC VI STAR builder: CLI validation and reference MD5 pins aligned with config/pin.yaml.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
script="${ROOT}/bin/hpc_build_vi_star_indices.sh"
pin="${ROOT}/config/pin.yaml"

"${script}" --help >/dev/null || {
  echo "test_hpc_build_vi_star_indices: --help failed" >&2
  exit 1
}

set +e
"${script}" --species not_a_species --root "${ROOT}" 2>/dev/null
rc=$?
set -e
[[ "$rc" -eq 2 ]] || {
  echo "test_hpc_build_vi_star_indices: invalid species expected exit 2 (got ${rc})" >&2
  exit 1
}

human_fasta="$(yq -r '.species.human.references.fasta_md5' "$pin")"
human_gtf="$(yq -r '.species.human.references.gtf_md5' "$pin")"
mouse_fasta="$(yq -r '.species.mouse.references.fasta_md5' "$pin")"
mouse_gtf="$(yq -r '.species.mouse.references.gtf_md5' "$pin")"

grep -q "HUMAN_FASTA_MD5='${human_fasta}'" "$script" || {
  echo "test_hpc_build_vi_star_indices: human FASTA MD5 drift vs pin.yaml" >&2
  exit 1
}
grep -q "HUMAN_GTF_MD5='${human_gtf}'" "$script" || {
  echo "test_hpc_build_vi_star_indices: human GTF MD5 drift vs pin.yaml" >&2
  exit 1
}
grep -q "MOUSE_FASTA_MD5='${mouse_fasta}'" "$script" || {
  echo "test_hpc_build_vi_star_indices: mouse FASTA MD5 drift vs pin.yaml" >&2
  exit 1
}
grep -q "MOUSE_GTF_MD5='${mouse_gtf}'" "$script" || {
  echo "test_hpc_build_vi_star_indices: mouse GTF MD5 drift vs pin.yaml" >&2
  exit 1
}

grep -q 'HOST_OUT="${OUT_ROOT}/host_star"' "$script" || {
  echo "test_hpc_build_vi_star_indices: missing host_star output path" >&2
  exit 1
}
grep -q 'PLUS_OUT="${OUT_ROOT}/plus_star"' "$script" || {
  echo "test_hpc_build_vi_star_indices: missing plus_star output path" >&2
  exit 1
}
grep -q 'star/Genome' "$script" || {
  echo "test_hpc_build_vi_star_indices: STAR index must land under star/Genome" >&2
  exit 1
}

echo "test_hpc_build_vi_star_indices: ok"
