#!/usr/bin/env bash
# Run KMC (canonical + non-canonical) on one sample to estimate disk and runtime.
set -euo pipefail

KGWAS_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${KGWAS_BIN}/kgwas_lib.sh"

usage() {
  echo "Usage: $0 --sample SAMPLE_ID [--params PATH]" >&2
  exit 2
}

SAMPLE=""
PARAMS="${KGWAS_ROOT}/config/kmer_gwas.params.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample) SAMPLE="$2"; shift 2 ;;
    --params) PARAMS="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) kgwas_die "unknown argument: $1" ;;
  esac
done
[[ -n "$SAMPLE" ]] || usage

kgwas_load_params "$PARAMS"
"${KGWAS_BIN}/stage_inputs.sh" --params "${PARAMS}"

STAGING="$(kgwas_path_from_params '.fastq_staging_dir')"
PILOT_DIR="$(kgwas_subst_run_name "${PROJECT_ROOT}/workflows/kmer-gwas/scratch/PLACEHOLDER_RUN_NAME/pilot_kmc/${SAMPLE}")"
mkdir -p "${PILOT_DIR}"

KMC="$(kgwas_resolve_path "$(kparam '.tools.kmc')")"
KMER_LENGTH="$(kparam '.kmer_length')"
KMC_MIN="$(kparam '.kmc_min_count')"
THREADS="$(kparam '.kmers_gwas.threads')"

R1="${STAGING}/${SAMPLE}_R1.fastq.gz"
R2="${STAGING}/${SAMPLE}_R2.fastq.gz"
[[ -e "$R1" ]] || kgwas_die "missing staged R1 for ${SAMPLE}: ${R1}"

INPUT_LIST="${PILOT_DIR}/input_files.txt"
printf '%s\n' "${R1}" "${R2}" >"${INPUT_LIST}"

echo "Pilot KMC for ${SAMPLE} in ${PILOT_DIR}"
echo "Start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
START=$(date +%s)

kgwas_exec "${KMC}" -t"${THREADS}" -k"${KMER_LENGTH}" -ci"${KMC_MIN}" \
  @"${INPUT_LIST}" output_kmc_canon "${PILOT_DIR}/tmp_kmc"
kgwas_exec "${KMC}" -t"${THREADS}" -k"${KMER_LENGTH}" -ci0 -b \
  @"${INPUT_LIST}" output_kmc_all "${PILOT_DIR}/tmp_kmc2"

END=$(date +%s)
echo "End: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Elapsed_seconds: $((END - START))"
du -sh "${PILOT_DIR}" || true
echo "Extrapolate to 20 samples: scale disk and wall time accordingly (full WGS often TB-scale cumulative)."
