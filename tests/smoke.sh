#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f "${ROOT}/opt/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/opt/env.sh"
fi

SMOKE_SPECIES="${SMOKE_SPECIES:-human}"
case "$SMOKE_SPECIES" in
  human|mouse) ;;
  *)
    echo "smoke: SMOKE_SPECIES must be human or mouse (got '${SMOKE_SPECIES}')" >&2
    exit 1
    ;;
esac

for key in tool_micromamba tool_bash tool_openjdk tool_yq tool_samtools tool_kraken2 tool_prefix; do
  grep -q "^${key}:" config/pin.yaml || {
    echo "smoke: pin missing ${key}" >&2
    exit 1
  }
done

if command -v shellcheck >/dev/null; then
  shellcheck -S warning bin/*.sh
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
scratch="${tmp}/scratch"
mkdir -p "$scratch" "${tmp}/ref/virus/local" "${tmp}/data" "${tmp}/config"

ref_tag="hg38"
fasta_md5="1c9dcaddfa41027f17cd8f7a82c7293b"
gtf_md5="15e6cab3a16e87f2564839f7500700e2"
if [[ "$SMOKE_SPECIES" == mouse ]]; then
  ref_tag="mm39"
  fasta_md5="41ace1b7157b98b393746aef5d1287a8"
  gtf_md5="25e15ef5bdd7afc6d3447a757e5fa487"
fi

# Fixture pin: local paths under tmp (URLs unused in smoke).
yq "
  .species.${SMOKE_SPECIES}.references.fasta_gz = \"${tmp}/ref/${ref_tag}.fa.gz\" |
  .species.${SMOKE_SPECIES}.references.fasta = \"${tmp}/ref/${ref_tag}.fa\" |
  .species.${SMOKE_SPECIES}.references.gtf_gz = \"${tmp}/ref/${ref_tag}.gtf.gz\" |
  .species.${SMOKE_SPECIES}.references.gtf = \"${tmp}/ref/${ref_tag}.gtf\" |
  .species.${SMOKE_SPECIES}.kraken2_db = \"${tmp}/ref/kraken2/${ref_tag}\" |
  .virus.bundled_fasta = \"${tmp}/ref/virus/ctat.fasta\" |
  .virus.local_dir = \"${tmp}/ref/virus/local\" |
  .virus.merged_fasta = \"${tmp}/ref/virus/viral.fasta\" |
  .virus.dedup_report = \"${tmp}/ref/virus/dedup.tsv\" |
  .nextflow.bin = \"${tmp}/opt/nextflow\" |
  .nextflow.home = \"${tmp}/opt/nxf-home\"
" "${ROOT}/config/pin.yaml" >"${tmp}/config/pin.yaml"

cat >"${tmp}/bundled.fa" <<'FA'
>KeepMe
ACGT
>OverrideMe
AAAA
FA
cat >"${tmp}/ref/virus/local/NewVirus.fa" <<'FA'
>NewVirus
CCCC
FA
cat >"${tmp}/ref/virus/local/OverrideMe.fa" <<'FA'
>OverrideMe
TTTT
FA

cat >"${tmp}/site.config.yaml" <<YAML
species: ${SMOKE_SPECIES}
scratch_root: ${scratch}
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: true
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: true
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

cp "${tmp}/bundled.fa" "${tmp}/ref/virus/ctat.fasta"
echo "gzip test" | gzip -c >"${tmp}/ref/${ref_tag}.fa.gz"
printf 'ACGT\n' >"${tmp}/ref/${ref_tag}.fa"
echo "$fasta_md5" >"${tmp}/ref/${ref_tag}.fa.stamp"
cat >"${tmp}/ref/${ref_tag}.gtf" <<'GTF'
chr1	source	gene	1	100	.	+	.	.
chr1	source	CDS	10	20	.	+	0	.
GTF
echo "$gtf_md5" >"${tmp}/ref/${ref_tag}.gtf.stamp"

touch "${tmp}/data/S1_R1.fastq.gz" "${tmp}/data/S1_R2.fastq.gz"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/data/S1_R1.fastq.gz,${tmp}/data/S1_R2.fastq.gz" >>"${tmp}/cohort.csv"

ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/merge_virus_fasta.sh" "${tmp}/site.config.yaml"
grep -q replaced "${tmp}/ref/virus/dedup.tsv"
grep -q TTTT "${tmp}/ref/virus/viral.fasta"

ALLCALL_PIN="${tmp}/config/pin.yaml" "${ROOT}/bin/write_sheets.sh" "${tmp}/site.config.yaml" "${tmp}/sheets" 0
test -f "${tmp}/sheets/viralintegration_samplesheet.csv"

"${ROOT}/bin/cds_bed.sh" "${tmp}/ref/${ref_tag}.gtf" "${tmp}/cds.bed" 10
test -s "${tmp}/cds.bed"
grep -q $'chr1\t0\t30' "${tmp}/cds.bed" || {
  echo "smoke: cds.bed expected chr1 0-30 with 10bp flank on CDS 10-20" >&2
  exit 1
}

echo "smoke: ok (${SMOKE_SPECIES})"
