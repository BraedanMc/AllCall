#!/usr/bin/env bash
# nf_version_ok: cohort Nextflow pin must match the installed binary (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/opt" "${tmp}/scratch"

cat >"${tmp}/pin.yaml" <<YAML
species:
  human:
    references:
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ${tmp}/ref/hg38.fa.gz
      fasta: ${tmp}/ref/hg38.fa
      fasta_md5: deadbeef
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ${tmp}/ref/hg38.gtf.gz
      gtf: ${tmp}/ref/hg38.gtf
      gtf_md5: deadbeef
    kraken2_db: ${tmp}/ref/kraken2
nextflow:
  version: "24.10.5"
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
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

cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
echo "N E X T F L O W  ~  version 24.10.5"
EOF
chmod +x "${tmp}/opt/nextflow"

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
nf_version_ok || {
  echo "nf_version_ok: matching mock binary should pass" >&2
  exit 1
}

cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
echo "N E X T F L O W  ~  version 26.10.3"
EOF
chmod +x "${tmp}/opt/nextflow"

if nf_version_ok; then
  echo "nf_version_ok: wrong version should fail" >&2
  exit 1
fi

echo "test_nf_version_ok: ok"
