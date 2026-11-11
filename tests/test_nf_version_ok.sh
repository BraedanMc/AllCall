#!/usr/bin/env bash
# nf_version_ok: cohort nextflow pin must match the installed binary (regression for NF 26).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
nxf_bin="${tmp}/opt/nextflow"
mkdir -p "$(dirname "$nxf_bin")"

cat >"${tmp}/pin.yaml" <<'YAML'
species:
  human:
    references:
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ref/hg38.fa.gz
      fasta: ref/hg38.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ref/hg38.gtf.gz
      gtf: ref/hg38.gtf
      gtf_md5: ""
    kraken2_db: ref/kraken2/hg38
nextflow:
  version: "24.10.5"
  bin: opt/nextflow
  home: opt/nxf-home
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
YAML

cat >"${tmp}/site.config.yaml" <<YAML
species: human
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: false
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/a.gz,${tmp}/b.gz" >>"${tmp}/cohort.csv"
touch "${tmp}/a.gz" "${tmp}/b.gz"
mkdir -p "${tmp}/scratch"

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"

cat >"$nxf_bin" <<'EOF'
#!/usr/bin/env bash
echo "      N E X T F L O W  ~  version 24.10.5"
EOF
chmod +x "$nxf_bin"

nf_version_ok || {
  echo "test_nf_version_ok: expected match for pinned 24.10.5" >&2
  exit 1
}

cat >"$nxf_bin" <<'EOF'
#!/usr/bin/env bash
echo "      N E X T F L O W  ~  version 26.10.3"
EOF
chmod +x "$nxf_bin"

if nf_version_ok; then
  echo "test_nf_version_ok: wrong-version binary must fail" >&2
  exit 1
fi

[[ ! -x "$nxf_bin" ]] || chmod -x "$nxf_bin"
if nf_version_ok; then
  echo "test_nf_version_ok: non-executable binary must fail" >&2
  exit 1
fi

echo "test_nf_version_ok: ok"
