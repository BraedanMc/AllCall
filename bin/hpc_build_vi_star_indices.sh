#!/usr/bin/env bash
# Self-contained HPC job: download host reference + virus DB, build VI STAR indices (host + plus).
# No site.config.yaml, pin.yaml, or ./bin/setup.sh required — only curl, gzip, python3,
# and apptainer|singularity (or STAR on PATH with --no-container).
#
# Example (SLURM):
#   #SBATCH --cpus-per-task=16
#   #SBATCH --mem=64G
#   #SBATCH --time=8:00:00
#   cd /path/to/AllCall
#   ./bin/hpc_build_vi_star_indices.sh
#
set -euo pipefail

SPECIES=human
ROOT="${PWD}"
OUT_BASE="ref/vi_star"
THREADS="${VI_STAR_THREADS:-16}"
MEM_GB="${VI_STAR_MEM_GB:-64}"
USE_CONTAINER=1
FORCE=0

# Pinned assets (keep in sync with config/pin.yaml when bumping references).
HUMAN_FASTA_URL='https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz'
HUMAN_FASTA_MD5='1c9dcaddfa41027f17cd8f7a82c7293b'
HUMAN_GTF_URL='https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/genes/hg38.ncbiRefSeq.gtf.gz'
HUMAN_GTF_MD5='6a585655a3e67150264b792b758372a2'

MOUSE_FASTA_URL='https://hgdownload.soe.ucsc.edu/goldenPath/mm39/bigZips/mm39.fa.gz'
MOUSE_FASTA_MD5='41ace1b7157b98b393746aef5d1287a8'
MOUSE_GTF_URL='https://hgdownload.soe.ucsc.edu/goldenPath/mm39/bigZips/genes/mm39.ncbiRefSeq.gtf.gz'
MOUSE_GTF_MD5='25e15ef5bdd7afc6d3447a757e5fa487'

VIRUS_BUNDLED_URL='https://data.broadinstitute.org/Trinity/CTAT_RESOURCE_LIB/VIRUS_INSERTION_FINDING_LIB_SUPPLEMENT/virus_db.nr.fasta'

STAR_IMAGE='docker://quay.io/biocontainers/mulled-v2-1fa26d1ce03c295fe2fdcf85831a92fbcbd7e8c2:1c4c32d87798d425c970ececfbadd155e7560277-0'

die() { echo "hpc_build_vi_star_indices: $*" >&2; exit 2; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

usage() {
  cat <<'EOF'
usage: hpc_build_vi_star_indices.sh [options]

Build nf-core/viralintegration STAR indices (host + host+virus) on a large-memory node.

options:
  --root DIR       Project root for ref/ output (default: current working directory)
  --species NAME   human (hg38, default) or mouse (mm39)
  --out-base DIR   STAR output under ROOT (default: ref/vi_star)
  --threads N      STAR --runThreadN (default: 16, or VI_STAR_THREADS)
  --mem-gb N       STAR RAM budget in GiB (default: 64, or VI_STAR_MEM_GB)
  --no-container   Use STAR, samtools, gawk on PATH
  --force          Re-download and rebuild even if outputs exist
  -h, --help       This message

Optional: drop extra virus FASTA(s) in ref/virus/local/ before running; they are merged
into ref/virus/viral.fasta the same way as AllCall merge_virus_fasta.sh (bundled wins on name clash).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --species) SPECIES="$2"; shift 2 ;;
    --out-base) OUT_BASE="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --mem-gb) MEM_GB="$2"; shift 2 ;;
    --no-container) USE_CONTAINER=0; shift ;;
    --force) FORCE=1; shift ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

case "$SPECIES" in
  human)
    FASTA_URL="$HUMAN_FASTA_URL" FASTA_MD5="$HUMAN_FASTA_MD5"
    GTF_URL="$HUMAN_GTF_URL" GTF_MD5="$HUMAN_GTF_MD5"
    REF_TAG=hg38
    ;;
  mouse)
    FASTA_URL="$MOUSE_FASTA_URL" FASTA_MD5="$MOUSE_FASTA_MD5"
    GTF_URL="$MOUSE_GTF_URL" GTF_MD5="$MOUSE_GTF_MD5"
    REF_TAG=mm39
    ;;
  *) die "species must be human or mouse (got '${SPECIES}')" ;;
esac

ROOT="$(cd "$ROOT" && pwd)"
REF_DIR="${ROOT}/ref/${REF_TAG}"
VIRUS_DIR="${ROOT}/ref/virus"
VIRUS_LOCAL="${VIRUS_DIR}/local"
FASTA_GZ="${REF_DIR}/${REF_TAG}.fa.gz"
FASTA="${REF_DIR}/${REF_TAG}.fa"
GTF_GZ="${REF_DIR}/${REF_TAG}.ncbiRefSeq.gtf.gz"
GTF="${REF_DIR}/${REF_TAG}.ncbiRefSeq.gtf"
BUNDLED_VIRUS="${VIRUS_DIR}/ctat_virus_db.fasta"
MERGED_VIRUS="${VIRUS_DIR}/viral.fasta"
OUT_ROOT="${ROOT}/${OUT_BASE}"
HOST_OUT="${OUT_ROOT}/host_star"
PLUS_OUT="${OUT_ROOT}/plus_star"
PLUS_FASTA="${OUT_ROOT}/${REF_TAG}_plus_viraldb.fasta"
MANIFEST="${OUT_ROOT}/manifest.tsv"

md5_file() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'
  else md5 -q "$1"
  fi
}

download_if_needed() {
  local url="$1" dest_gz="$2" expect_md5="$3" label="$4"
  mkdir -p "$(dirname "$dest_gz")"
  if [[ "$FORCE" -eq 0 && -f "$dest_gz" ]] && [[ "$(md5_file "$dest_gz")" == "$expect_md5" ]]; then
    echo "hpc_build_vi_star_indices: ${label} gzip ok (cached)"
    return 0
  fi
  need_cmd curl
  local partial="${dest_gz}.partial"
  echo "hpc_build_vi_star_indices: downloading ${label}..."
  rm -f "$partial"
  curl -fsSL --retry 3 --retry-delay 2 -o "$partial" "$url" || { rm -f "$partial"; die "download failed: ${url}"; }
  mv "$partial" "$dest_gz"
  [[ "$(md5_file "$dest_gz")" == "$expect_md5" ]] || { rm -f "$dest_gz"; die "${label} MD5 mismatch after download"; }
}

decompress_if_needed() {
  local gz="$1" out="$2" stamp_md5="$3"
  if [[ "$FORCE" -eq 1 || ! -f "$out" ]]; then
    need_cmd gzip
    gzip -dc "$gz" >"${out}.partial"
    mv "${out}.partial" "$out"
  fi
  echo "$stamp_md5" >"${out}.stamp"
}

fetch_virus_bundled() {
  mkdir -p "$VIRUS_DIR" "$VIRUS_LOCAL"
  if [[ "$FORCE" -eq 0 && -f "$BUNDLED_VIRUS" ]]; then
    echo "hpc_build_vi_star_indices: virus bundle ok (cached)"
    return 0
  fi
  need_cmd curl
  echo "hpc_build_vi_star_indices: downloading virus bundle..."
  curl -fsSL --retry 3 --retry-delay 2 -o "${BUNDLED_VIRUS}.partial" "$VIRUS_BUNDLED_URL" \
    || die "virus bundle download failed"
  mv "${BUNDLED_VIRUS}.partial" "$BUNDLED_VIRUS"
}

merge_virus_fasta() {
  need_cmd python3
  export BUNDLED="$BUNDLED_VIRUS" LOCAL_DIR="$VIRUS_LOCAL" MERGED="$MERGED_VIRUS"
  if [[ "$FORCE" -eq 0 && -f "$MERGED_VIRUS" ]]; then
    echo "hpc_build_vi_star_indices: merged virus FASTA ok (cached; use --force to rebuild)"
    return 0
  fi
  echo "hpc_build_vi_star_indices: merging virus FASTA..."
  python3 <<'PY'
import gzip
import os
import textwrap
from pathlib import Path

bundled = Path(os.environ["BUNDLED"])
local_dir = Path(os.environ["LOCAL_DIR"])
merged = Path(os.environ["MERGED"])

def read_fasta(path: Path):
    open_fn = gzip.open if path.name.endswith(".gz") else open
    mode = "rt" if path.name.endswith(".gz") else "r"
    recs, header, parts, seen = [], None, [], set()
    with open_fn(path, mode) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    name = header.split()[0].lstrip(">")
                    if name in seen:
                        raise SystemExit(f"duplicate sequence '{name}' in {path}")
                    seen.add(name)
                    recs.append((name, header, "".join(parts)))
                header, parts = line[1:], []
            else:
                parts.append(line.upper())
    if header is not None:
        name = header.split()[0].lstrip(">")
        recs.append((name, header, "".join(parts)))
    return recs

bundled_recs = read_fasta(bundled)
local_files = sorted(
    p for p in local_dir.iterdir()
    if p.is_file() and (p.suffix in (".fa", ".fasta") or p.name.endswith((".fa.gz", ".fasta.gz")))
)
local_recs, local_names = [], set()
for lf in local_files:
    for name, header, seq in read_fasta(lf):
        if name in local_names:
            raise SystemExit(f"duplicate local sequence '{name}'")
        local_names.add(name)
        local_recs.append((lf.name, name, header, seq))

winners = {}
for name, header, seq in bundled_recs:
    if name in local_names:
        fn, _, lh, ls = next(x for x in local_recs if x[1] == name)
        winners[name] = (lh, ls)
    else:
        winners[name] = (header, seq)
for fn, name, header, seq in local_recs:
    if name not in winners:
        winners[name] = (header, seq)

lines = []
bundled_names = {n for n, _, _ in bundled_recs}
for name, header, seq in bundled_recs:
    h, s = winners[name]
    lines.append(">" + h.split()[0])
    lines.extend(textwrap.wrap(s, 60))
for fn, name, header, seq in local_recs:
    if name not in bundled_names:
        lines.append(">" + header.split()[0])
        lines.extend(textwrap.wrap(seq, 60))

merged.parent.mkdir(parents=True, exist_ok=True)
merged.write_text("\n".join(lines) + "\n")
PY
}

container_runner() {
  if [[ "$USE_CONTAINER" -eq 0 ]]; then
    need_cmd STAR
    need_cmd samtools
    need_cmd gawk
    return 0
  fi
  if command -v apptainer >/dev/null 2>&1; then printf '%s' apptainer
  elif command -v singularity >/dev/null 2>&1; then printf '%s' singularity
  else die "apptainer/singularity not found (try --no-container)"
  fi
}

run_star_genome_generate() {
  local fasta="$1" gtf="$2" out_dir="$3"
  local ram_bytes work fasta_bn gtf_bn engine star_script
  if [[ "$FORCE" -eq 0 && -f "${out_dir}/star/Genome" ]]; then
    echo "hpc_build_vi_star_indices: STAR index cached at ${out_dir}"
    return 0
  fi
  ram_bytes=$((MEM_GB * 1024 * 1024 * 1024 - 100000000))
  work="$(mktemp -d "${TMPDIR:-/tmp}/vi-star.XXXXXX")"
  fasta_bn="$(basename "$fasta")"
  gtf_bn="$(basename "$gtf")"
  cp -f "$fasta" "$work/$fasta_bn"
  cp -f "$gtf" "$work/$gtf_bn"
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

echo "hpc_build_vi_star_indices: root=${ROOT} species=${SPECIES}"

download_if_needed "$FASTA_URL" "$FASTA_GZ" "$FASTA_MD5" "host FASTA"
download_if_needed "$GTF_URL" "$GTF_GZ" "$GTF_MD5" "host GTF"
decompress_if_needed "$FASTA_GZ" "$FASTA" "$FASTA_MD5"
decompress_if_needed "$GTF_GZ" "$GTF" "$GTF_MD5"
fetch_virus_bundled
merge_virus_fasta

mkdir -p "$OUT_ROOT"
if [[ "$FORCE" -eq 1 || ! -f "$PLUS_FASTA" ]]; then
  echo "hpc_build_vi_star_indices: building ${PLUS_FASTA}..."
  cat "$FASTA" "$MERGED_VIRUS" >"$PLUS_FASTA"
fi

[[ "$USE_CONTAINER" -eq 1 ]] && container_runner >/dev/null

echo "hpc_build_vi_star_indices: STAR host index -> ${HOST_OUT} (${THREADS} threads, ${MEM_GB} GiB)..."
run_star_genome_generate "$FASTA" "$GTF" "$HOST_OUT"

echo "hpc_build_vi_star_indices: STAR plus index -> ${PLUS_OUT}..."
run_star_genome_generate "$PLUS_FASTA" "$GTF" "$PLUS_OUT"

{
  echo -e "artifact\tpath\tbytes"
  echo -e "species\t${SPECIES}\t"
  echo -e "host_fasta\t${FASTA}\t$(stat -c '%s' "$FASTA" 2>/dev/null || stat -f '%z' "$FASTA")"
  echo -e "gtf\t${GTF}\t$(stat -c '%s' "$GTF" 2>/dev/null || stat -f '%z' "$GTF")"
  echo -e "viral_merged\t${MERGED_VIRUS}\t$(stat -c '%s' "$MERGED_VIRUS" 2>/dev/null || stat -f '%z' "$MERGED_VIRUS")"
  echo -e "plus_fasta\t${PLUS_FASTA}\t$(stat -c '%s' "$PLUS_FASTA" 2>/dev/null || stat -f '%z' "$PLUS_FASTA")"
  echo -e "host_star_index\t${HOST_OUT}\t$(du -sb "$HOST_OUT" 2>/dev/null | awk '{print $1}' || du -sk "$HOST_OUT" | awk '{print $1*1024}')"
  echo -e "plus_star_index\t${PLUS_OUT}\t$(du -sb "$PLUS_OUT" 2>/dev/null | awk '{print $1}' || du -sk "$PLUS_OUT" | awk '{print $1*1024}')"
} >"$MANIFEST"

echo "hpc_build_vi_star_indices: ok"
echo "  host STAR: ${HOST_OUT}/star"
echo "  plus STAR: ${PLUS_OUT}/star"
echo "  manifest:  ${MANIFEST}"
echo ""
echo "Outputs match AllCall layout under ref/ (same URLs/MD5s as config/pin.yaml)."
echo "nf-core/viralintegration still runs STAR_GENOMEGENERATE in-pipeline unless you run VI on this node too."
