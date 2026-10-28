#!/usr/bin/env bash
# Parameterized kmersGWAS cohort run (Linux amd64; SLURM or local).
set -euo pipefail

KGWAS_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${KGWAS_BIN}/kgwas_lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --params PATH     Params YAML (default: config/kmer_gwas.params.yaml)
  --stage-only      Symlink FASTQs and write Sample-genotypes.txt only
  --dry-run         Print paths and generated pipeline script, do not execute
  --local           Force local bash even when executor is slurm

Run from any directory. Requires staged FASTQs, voichek binaries, and Linux (or container).
EOF
  exit 2
}

PARAMS="${KGWAS_ROOT}/config/kmer_gwas.params.yaml"
STAGE_ONLY=false
DRY_RUN=false
FORCE_LOCAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --params) PARAMS="$2"; shift 2 ;;
    --stage-only) STAGE_ONLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --local) FORCE_LOCAL=true; shift ;;
    -h | --help) usage ;;
    *) kgwas_die "unknown argument: $1" ;;
  esac
done

kgwas_load_params "$PARAMS"

STAGING="$(kgwas_path_from_params '.fastq_staging_dir')"
WORK_DIR="$(kgwas_path_from_params '.work_dir')"
RESULTS_DIR="$(kgwas_path_from_params '.results_dir')"
PHENO_SHEET="$(kgwas_path_from_params '.phenotype_sheet')"
export WORK_DIR

KMER_LENGTH="$(kparam '.kmer_length')"
KMC_MIN="$(kparam '.kmc_min_count')"
THREADS="$(kparam '.kmers_gwas.threads')"
MAC="$(kparam '.kmers_gwas.minor_allele_count')"
STRAND_P="$(kparam '.kmers_gwas.strand_min_percent')"
MAF="$(kparam '.kmers_gwas.minor_allele_freq')"
KMERS_NUM="$(kparam '.kmers_gwas.kmers_number')"
N_PERM="$(kparam '.kmers_gwas.n_permutations')"
MIN_DP="$(kparam '.kmers_gwas.min_data_points')"

KMERS_BIN="$(kgwas_resolve_path "$(kparam '.tools.kmers_bin')")"
KMC="$(kgwas_resolve_path "$(kparam '.tools.kmc')")"
KMERS_GWAS_PY="$(kgwas_resolve_path "$(kparam '.tools.kmers_gwas_py')")"
PYTHON2="$(kparam '.tools.python2')"

REF_FASTA="$(kgwas_resolve_path "$(kparam '.reference.fasta')")"

"${KGWAS_BIN}/stage_inputs.sh" --params "${PARAMS}"
if $STAGE_ONLY; then
  exit 0
fi

GENO_LIST="${STAGING}/Sample-genotypes.txt"
[[ -f "${GENO_LIST}" ]] || kgwas_die "missing ${GENO_LIST} after staging"

mkdir -p "${WORK_DIR}" "${RESULTS_DIR}" "${RESULTS_DIR}/gwas" "${RESULTS_DIR}/logs" "${WORK_DIR}/kmers"

PIPE_SCRIPT="${WORK_DIR}/run_kmers_gwas_pipeline.sh"

cat >"${PIPE_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
STAGING=$(printf '%q' "${STAGING}")
WORK_DIR=$(printf '%q' "${WORK_DIR}")
RESULTS_DIR=$(printf '%q' "${RESULTS_DIR}")
GENO_LIST=$(printf '%q' "${GENO_LIST}")
PHENO_SHEET=$(printf '%q' "${PHENO_SHEET}")
KMERS_BIN=$(printf '%q' "${KMERS_BIN}")
KMC=$(printf '%q' "${KMC}")
KMERS_GWAS_PY=$(printf '%q' "${KMERS_GWAS_PY}")
PYTHON2=$(printf '%q' "${PYTHON2}")
KMER_LENGTH=$(printf '%q' "${KMER_LENGTH}")
KMC_MIN=$(printf '%q' "${KMC_MIN}")
THREADS=$(printf '%q' "${THREADS}")
MAC=$(printf '%q' "${MAC}")
STRAND_P=$(printf '%q' "${STRAND_P}")
MAF=$(printf '%q' "${MAF}")
KMERS_NUM=$(printf '%q' "${KMERS_NUM}")
N_PERM=$(printf '%q' "${N_PERM}")
MIN_DP=$(printf '%q' "${MIN_DP}")
PROJECT_ROOT=$(printf '%q' "${PROJECT_ROOT}")

export PATH="\${KMERS_BIN}:\${PATH}"

cd "\${WORK_DIR}"
KMERS_LIST="\${WORK_DIR}/kmers_list_paths.txt"
: >"\${KMERS_LIST}"

while IFS= read -r SAMPLE_ID; do
  [[ -z "\${SAMPLE_ID}" ]] && continue
  SAMPLE_PATH="\${WORK_DIR}/kmers/\${SAMPLE_ID}"
  mkdir -p "\${SAMPLE_PATH}"
  R1="\${STAGING}/\${SAMPLE_ID}_R1.fastq.gz"
  R2="\${STAGING}/\${SAMPLE_ID}_R2.fastq.gz"
  INPUT_LIST="\${SAMPLE_PATH}/input_files.txt"
  printf '%s\\n' "\${R1}" "\${R2}" >"\${INPUT_LIST}"
  cd "\${SAMPLE_PATH}"
  "\${KMC}" -t"\${THREADS}" -k"\${KMER_LENGTH}" -ci"\${KMC_MIN}" @"\${INPUT_LIST}" output_kmc_canon "\${SAMPLE_PATH}/tmp_kmc" 
  "\${KMC}" -t"\${THREADS}" -k"\${KMER_LENGTH}" -ci0 -b @"\${INPUT_LIST}" output_kmc_all "\${SAMPLE_PATH}/tmp_kmc2"
  kmers_add_strand_information -c output_kmc_canon -n output_kmc_all -k "\${KMER_LENGTH}" -o kmers_with_strand
  echo "\${SAMPLE_PATH}/kmers_with_strand" >>"\${KMERS_LIST}"
  cd "\${WORK_DIR}"
done <"\${GENO_LIST}"

list_kmers_found_in_multiple_samples \\
  -l "\${KMERS_LIST}" \\
  -k "\${KMER_LENGTH}" \\
  --mac "\${MAC}" \\
  -p "\${STRAND_P}" \\
  -o kmers_to_use

build_kmers_table -l "\${KMERS_LIST}" -k "\${KMER_LENGTH}" -a kmers_to_use -o kmers_table

emma_kinship_kmers -t kmers_table -k "\${KMER_LENGTH}" --maf "\${MAF}" > kmers_table.kinship

tail -n +2 "\${PHENO_SHEET}" | while IFS=\$'\t' read -r PHENO_NAME PHENO_REL; do
  [[ -z "\${PHENO_NAME}" ]] && continue
  if [[ "\${PHENO_REL}" != /* ]]; then
    PHENO_FILE="\${PROJECT_ROOT}/\${PHENO_REL}"
  else
    PHENO_FILE="\${PHENO_REL}"
  fi
  OUTDIR="\${RESULTS_DIR}/gwas/\${PHENO_NAME}"
  mkdir -p "\${OUTDIR}"
  "\${PYTHON2}" "\${KMERS_GWAS_PY}" \\
    --pheno "\${PHENO_FILE}" \\
    --kmers_table kmers_table \\
    -l "\${KMER_LENGTH}" \\
    -p "\${THREADS}" \\
    -k "\${KMERS_NUM}" \\
    --permutations "\${N_PERM}" \\
    --min_data_points "\${MIN_DP}" \\
    --maf "\${MAF}" \\
    --mac "\${MAC}" \\
    --pattern_counter \\
    --dont_remove_intermediates \\
    --outdir "\${OUTDIR}/"
done

echo "GWAS finished; results under \${RESULTS_DIR}/gwas"
EOF

chmod +x "${PIPE_SCRIPT}"

POST_ENABLED="$(kparam '.post_gwas.enabled')"
if [[ "${POST_ENABLED}" == "true" ]]; then
  MAP_SCRIPT="${KGWAS_BIN}/map_significant_kmers.sh"
  {
    echo ""
    echo "\"${MAP_SCRIPT}\" --params $(printf '%q' "${KGWAS_PARAMS}")"
  } >>"${PIPE_SCRIPT}"
fi

echo "Pipeline script: ${PIPE_SCRIPT}"
echo "Work dir: ${WORK_DIR}"
echo "Results dir: ${RESULTS_DIR}"
echo "Reference (post-GWAS): ${REF_FASTA}"

if $DRY_RUN; then
  echo "--- dry-run: not executing ---"
  exit 0
fi

EXECUTOR="$(kparam '.executor')"
if [[ "${EXECUTOR}" == "slurm" ]] && ! $FORCE_LOCAL; then
  ACCOUNT="$(kparam '.slurm.account')"
  PARTITION="$(kparam '.slurm.partition')"
  QOS="$(kparam '.slurm.qos')"
  TIME="$(kparam '.slurm.time')"
  MEM="$(kparam '.slurm.mem')"
  CPUS="$(kparam '.slurm.cpus_per_task')"
  SBATCH_SCRIPT="${WORK_DIR}/submit_kmers_gwas.sbatch"
  {
    echo "#!/bin/bash"
    echo "#SBATCH --job-name=kmers_gwas"
    echo "#SBATCH --nodes=1"
    echo "#SBATCH --cpus-per-task=${CPUS}"
    echo "#SBATCH --mem=${MEM}"
    echo "#SBATCH --time=${TIME}"
    if [[ "${ACCOUNT}" != PLACEHOLDER_* ]] && [[ -n "${ACCOUNT}" ]] && [[ "${ACCOUNT}" != "null" ]]; then
      echo "#SBATCH --account=${ACCOUNT}"
    fi
    if [[ "${PARTITION}" != PLACEHOLDER_* ]] && [[ -n "${PARTITION}" ]] && [[ "${PARTITION}" != "null" ]]; then
      echo "#SBATCH --partition=${PARTITION}"
    fi
    if [[ -n "${QOS}" ]] && [[ "${QOS}" != "null" ]]; then
      echo "#SBATCH --qos=${QOS}"
    fi
    echo "#SBATCH --output=${RESULTS_DIR}/logs/kmers_gwas_%j.out"
    echo "#SBATCH --error=${RESULTS_DIR}/logs/kmers_gwas_%j.err"
    echo "set -euo pipefail"
    if [[ "$(kparam '.container.enabled')" == "true" ]]; then
      echo "# Run inside container (adjust image in params):"
      echo "# apptainer exec --bind ${PROJECT_ROOT} ${PIPE_SCRIPT}"
      echo "bash $(printf '%q' "${PIPE_SCRIPT}")"
    else
      echo "bash $(printf '%q' "${PIPE_SCRIPT}")"
    fi
  } >"${SBATCH_SCRIPT}"
  chmod +x "${SBATCH_SCRIPT}"
  command -v sbatch >/dev/null 2>&1 || kgwas_die "sbatch not found; use --local on a Linux node or set executor: local"
  sbatch "${SBATCH_SCRIPT}"
else
  kgwas_exec bash "${PIPE_SCRIPT}"
fi
