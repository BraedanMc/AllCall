#!/usr/bin/env bash
# Stage FASTQs into viannam layout: sample_R1.fastq.gz, sample_R2.fastq.gz + Sample-genotypes.txt
set -euo pipefail

KGWAS_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${KGWAS_BIN}/kgwas_lib.sh"

usage() {
  echo "Usage: $0 [--params PATH]" >&2
  exit 2
}

PARAMS="${KGWAS_ROOT}/config/kmer_gwas.params.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --params) PARAMS="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) kgwas_die "unknown argument: $1" ;;
  esac
done

kgwas_load_params "$PARAMS"

SAMPLESHEET="$(kgwas_path_from_params '.samplesheet')"
STAGING="$(kgwas_path_from_params '.fastq_staging_dir')"
GENO_LIST="${STAGING}/Sample-genotypes.txt"

[[ -f "$SAMPLESHEET" ]] || kgwas_die "samplesheet not found: ${SAMPLESHEET}"

mkdir -p "${STAGING}"
: >"${GENO_LIST}"

tail -n +2 "${SAMPLESHEET}" | while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  sample="${line%%,*}"
  rest="${line#*,}"
  fq1="${rest%%,*}"
  fq2="${rest#*,}"
  if [[ "$fq1" == PLACEHOLDER_* ]] || [[ "$fq2" == PLACEHOLDER_* ]]; then
    kgwas_die "replace PLACEHOLDER_FASTQ (or other PLACEHOLDER_*) paths in ${SAMPLESHEET} before staging"
  fi
  if [[ "$fq1" != /* ]]; then
    fq1="${PROJECT_ROOT}/${fq1}"
  fi
  if [[ "$fq2" != /* ]]; then
    fq2="${PROJECT_ROOT}/${fq2}"
  fi
  [[ -e "$fq1" ]] || kgwas_die "missing fastq_1: ${fq1}"
  [[ -e "$fq2" ]] || kgwas_die "missing fastq_2: ${fq2}"
  ln -sf "${fq1}" "${STAGING}/${sample}_R1.fastq.gz"
  ln -sf "${fq2}" "${STAGING}/${sample}_R2.fastq.gz"
  echo "${sample}" >>"${GENO_LIST}"
done

echo "Staged $(wc -l <"${GENO_LIST}" | tr -d ' ') samples under ${STAGING}"
echo "Wrote ${GENO_LIST}"
