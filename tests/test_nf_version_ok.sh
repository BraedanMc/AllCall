#!/usr/bin/env bash
# nf_version_ok: cohort only runs when the pinned Nextflow binary reports pin.yaml version.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
mkdir -p "${tmp}/scratch"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

mkdir -p "${tmp}/opt"
cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
echo "nextflow version 24.10.5 build 123"
EOF
chmod +x "${tmp}/opt/nextflow"

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
nf_version_ok || {
  echo "test_nf_version_ok: expected match for pinned 24.10.5" >&2
  exit 1
}

cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
echo "nextflow version 26.10.3 build 999"
EOF
chmod +x "${tmp}/opt/nextflow"

if nf_version_ok; then
  echo "test_nf_version_ok: must reject wrong Nextflow version" >&2
  exit 1
fi

echo "test_nf_version_ok: ok"
