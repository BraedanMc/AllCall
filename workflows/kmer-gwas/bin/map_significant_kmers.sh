#!/usr/bin/env bash
# Optional post-GWAS: map significant k-mers to a reference FASTA with Bowtie2.
set -euo pipefail

KGWAS_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${KGWAS_BIN}/kgwas_lib.sh"

usage() {
  echo "Usage: $0 --params PATH [--kmers-list FILE]" >&2
  exit 2
}

PARAMS="${KGWAS_ROOT}/config/kmer_gwas.params.yaml"
KMERS_LIST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --params) PARAMS="$2"; shift 2 ;;
    --kmers-list) KMERS_LIST="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) kgwas_die "unknown argument: $1" ;;
  esac
done

kgwas_load_params "$PARAMS"

ENABLED="$(kparam '.post_gwas.enabled')"
[[ "$ENABLED" == "true" ]] || kgwas_die "post_gwas.enabled is false in params"

REF="$(kgwas_resolve_path "$(kparam '.reference.fasta')")"
[[ -f "$REF" ]] || kgwas_die "reference FASTA missing (run AllCall ./bin/setup.sh): ${REF}"

INDEX_DIR="$(kgwas_path_from_params '.post_gwas.bowtie2_index_dir')"
OUT_DIR="$(kgwas_path_from_params '.post_gwas.mapping_results_dir')"
mkdir -p "${INDEX_DIR}" "${OUT_DIR}"

if [[ -z "$KMERS_LIST" ]]; then
  KMERS_LIST="$(kparam '.post_gwas.significant_kmers_list')"
  KMERS_LIST="$(kgwas_subst_run_name "$KMERS_LIST")"
  [[ "$KMERS_LIST" = /* ]] || KMERS_LIST="${PROJECT_ROOT}/${KMERS_LIST}"
fi
[[ -f "$KMERS_LIST" ]] || kgwas_die "significant k-mers list not found: ${KMERS_LIST} (set post_gwas.significant_kmers_list)"

BOWTIE2_IMAGE="${BOWTIE2_IMAGE:-quay.io/biocontainers/bowtie2:2.5.4--h57737a8_1}"
SAMTOOLS="${SAMTOOLS:-${PROJECT_ROOT}/opt/tools/bin/samtools}"

run_bowtie2() {
  if command -v bowtie2-build >/dev/null 2>&1 && command -v bowtie2 >/dev/null 2>&1; then
    bowtie2-build "${REF}" "${INDEX_DIR}/hg38"
    bowtie2 -f -x "${INDEX_DIR}/hg38" -U "${KMERS_LIST}" -S "${OUT_DIR}/significant_kmers.sam"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm -v "${PROJECT_ROOT}:${PROJECT_ROOT}" -w "${OUT_DIR}" \
      "${BOWTIE2_IMAGE}" bowtie2-build "${REF}" "${INDEX_DIR}/hg38"
    docker run --rm -v "${PROJECT_ROOT}:${PROJECT_ROOT}" -w "${OUT_DIR}" \
      "${BOWTIE2_IMAGE}" bowtie2 -f -x "${INDEX_DIR}/hg38" -U "${KMERS_LIST}" -S "${OUT_DIR}/significant_kmers.sam"
  else
    kgwas_die "install bowtie2 or docker with ${BOWTIE2_IMAGE}"
  fi
}

run_bowtie2

if [[ -x "${SAMTOOLS}" ]]; then
  "${SAMTOOLS}" view -bS "${OUT_DIR}/significant_kmers.sam" | "${SAMTOOLS}" sort -o "${OUT_DIR}/significant_kmers.bam"
  "${SAMTOOLS}" index "${OUT_DIR}/significant_kmers.bam"
  echo "Wrote ${OUT_DIR}/significant_kmers.bam"
else
  echo "SAM at ${OUT_DIR}/significant_kmers.sam (install samtools via AllCall setup for BAM)"
fi
