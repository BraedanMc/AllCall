#!/usr/bin/env bash
# Build nf-core/viralintegration STAR indices (host + host+virus) on an HPC node.
#
# Downloads hg38/mm39 FASTA+GTF and merged virus FASTA via AllCall pin/config, then runs
# the same STAR genomeGenerate steps as NFCORE_VIRALINTEGRATION:STAR_GENOMEGENERATE_*.
#
# Request a large-memory node (hg38 host index often needs ~32–64 GiB RAM).
#
# Example (SLURM):
#   #SBATCH --job-name=vi-star-index
#   #SBATCH --cpus-per-task=16
#   #SBATCH --mem=64G
#   #SBATCH --time=8:00:00
#   cd "$SLURM_SUBMIT_DIR"
#   ./bin/hpc_build_vi_star_indices.sh site.config.yaml
#
# Example (interactive):
#   module load apptainer   # or singularity
#   ./bin/hpc_build_vi_star_indices.sh --threads 16 --mem-gb 64 site.config.yaml
#
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

CONFIG=""
OUT_BASE="ref/vi_star"
THREADS="${VI_STAR_THREADS:-16}"
MEM_GB="${VI_STAR_MEM_GB:-64}"
USE_CONTAINER=1

usage() {
  sed -n '2,20p' "$0"
  echo "usage: hpc_build_vi_star_indices.sh [options] <site.config.yaml>"
  echo "  --out-base DIR   Output under PROJECT_ROOT (default: ref/vi_star)"
  echo "  --threads N      STAR --runThreadN (default: 16 or VI_STAR_THREADS)"
  echo "  --mem-gb N       STAR --limitGenomeGenerateRAM budget in GiB (default: 64 or VI_STAR_MEM_GB)"
  echo "  --no-container   Use STAR/samtools/gawk on PATH (must match biocontainers ~2.7.9a)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out-base) OUT_BASE="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --mem-gb) MEM_GB="$2"; shift 2 ;;
    --no-container) USE_CONTAINER=0; shift ;;
    *) CONFIG="$1"; shift ;;
  esac
done

[[ -n "$CONFIG" ]] || { usage >&2; exit 2; }
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
load_config "$CONFIG"

need_cmd curl
mkdir -p "$(abs_path "$(cfg '.virus.local_dir')")"

echo "hpc_build_vi_star_indices: downloading references (pin + species)..."
references_download
"${ALLCALL_BIN}/merge_virus_fasta.sh" "$CONFIG"

FASTA="$(abs_path "$(cfg '.references.fasta')")"
GTF="$(abs_path "$(cfg '.references.gtf')")"
VIRAL="$(abs_path "$(cfg '.virus.merged_fasta')")"
OUT_ROOT="$(abs_path "$OUT_BASE")"
HOST_OUT="${OUT_ROOT}/host_star"
PLUS_OUT="${OUT_ROOT}/plus_star"
PLUS_FASTA="${OUT_ROOT}/$(basename "$FASTA" .fa)_plus_viraldb.fasta"
MANIFEST="${OUT_ROOT}/manifest.tsv"

[[ -f "$FASTA" && -f "$GTF" && -f "$VIRAL" ]] ||
  die "hpc_build_vi_star_indices: missing fasta/gtf/viral after setup"

mkdir -p "$OUT_ROOT"
if [[ ! -f "$PLUS_FASTA" ]]; then
  echo "hpc_build_vi_star_indices: building ${PLUS_FASTA}..."
  cat "$FASTA" "$VIRAL" >"$PLUS_FASTA"
fi

STAR_IMAGE='docker://quay.io/biocontainers/mulled-v2-1fa26d1ce03c295fe2fdcf85831a92fbcbd7e8c2:1c4c32d87798d425c970ececfbadd155e7560277-0'

container_runner() {
  local engine
  if [[ "$USE_CONTAINER" -eq 0 ]]; then
    need_cmd STAR
    need_cmd samtools
    need_cmd gawk
    return 0
  fi
  if command -v apptainer >/dev/null 2>&1; then
    engine=apptainer
  elif command -v singularity >/dev/null 2>&1; then
    engine=singularity
  else
    die "hpc_build_vi_star_indices: apptainer/singularity not found (use --no-container if STAR is on PATH)"
  fi
  printf '%s' "$engine"
}

# Args: fasta gtf output_dir (directory that will contain star/)
run_star_genome_generate() {
  local fasta="$1" gtf="$2" out_dir="$3"
  local engine ram_bytes work fasta_bn gtf_bn
  ram_bytes=$((MEM_GB * 1024 * 1024 * 1024 - 100000000))
  mkdir -p "$out_dir"
  work="$(mktemp -d "${TMPDIR:-/tmp}/vi-star.XXXXXX")"
  fasta_bn="$(basename "$fasta")"
  gtf_bn="$(basename "$gtf")"
  cp -f "$fasta" "$work/$fasta_bn"
  cp -f "$gtf" "$work/$gtf_bn"
  out_bn="$(basename "$out_dir")"

  star_script="${work}/run_star_genome_generate.sh"
  cat >"$star_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd '$work'
samtools faidx '$fasta_bn'
NUM_BASES=\$(gawk '{sum = sum + \$2}END{if ((log(sum)/log(2))/2 - 1 > 14) {printf "%.0f", 14} else {printf "%.0f", (log(sum)/log(2))/2 - 1}}' '${fasta_bn}.fai')
mkdir -p star
STAR \\
  --runMode genomeGenerate \\
  --genomeDir star/ \\
  --genomeFastaFiles '$fasta_bn' \\
  --sjdbGTFfile '$gtf_bn' \\
  --runThreadN '$THREADS' \\
  --genomeSAindexNbases "\$NUM_BASES" \\
  --limitGenomeGenerateRAM '$ram_bytes'
EOF
  chmod +x "$star_script"

  if [[ "$USE_CONTAINER" -eq 0 ]]; then
    "$star_script"
  else
    engine="$(container_runner)"
    "$engine" exec --bind "$work:$work" "$STAR_IMAGE" bash "$star_script"
  fi

  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  mv "$work/star" "$out_dir/"
  rm -rf "$work"
}

if [[ "$USE_CONTAINER" -eq 1 ]]; then
  container_runner >/dev/null
fi

echo "hpc_build_vi_star_indices: STAR host index -> ${HOST_OUT} (${THREADS} threads, ${MEM_GB} GiB cap)..."
run_star_genome_generate "$FASTA" "$GTF" "$HOST_OUT"

echo "hpc_build_vi_star_indices: STAR plus (host+virus) index -> ${PLUS_OUT}..."
run_star_genome_generate "$PLUS_FASTA" "$GTF" "$PLUS_OUT"

{
  echo -e "artifact\tpath\tbytes"
  echo -e "host_fasta\t${FASTA}\t$(stat -c '%s' "$FASTA" 2>/dev/null || stat -f '%z' "$FASTA")"
  echo -e "gtf\t${GTF}\t$(stat -c '%s' "$GTF" 2>/dev/null || stat -f '%z' "$GTF")"
  echo -e "viral_merged\t${VIRAL}\t$(stat -c '%s' "$VIRAL" 2>/dev/null || stat -f '%z' "$VIRAL")"
  echo -e "plus_fasta\t${PLUS_FASTA}\t$(stat -c '%s' "$PLUS_FASTA" 2>/dev/null || stat -f '%z' "$PLUS_FASTA")"
  echo -e "host_star_index\t${HOST_OUT}\t$(du -sb "$HOST_OUT" 2>/dev/null | awk '{print $1}' || du -sk "$HOST_OUT" | awk '{print $1*1024}')"
  echo -e "plus_star_index\t${PLUS_OUT}\t$(du -sb "$PLUS_OUT" 2>/dev/null | awk '{print $1}' || du -sk "$PLUS_OUT" | awk '{print $1*1024}')"
} >"$MANIFEST"

echo "hpc_build_vi_star_indices: ok"
echo "  host STAR index: ${HOST_OUT}"
echo "  plus STAR index: ${PLUS_OUT}"
echo "  manifest:        ${MANIFEST}"
echo ""
echo "Next: run full VI on this cluster with ./bin/run_cohort.sh (apptainer profile), or rsync ref/hg38 ref/virus and ref/vi_star to another host."
echo "nf-core/viralintegration does not yet skip STAR_GENOMEGENERATE when these exist; prefer completing VI on HPC or seeding Nextflow cache separately."
