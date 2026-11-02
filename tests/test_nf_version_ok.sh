#!/usr/bin/env bash
# nf_version_ok: pinned Nextflow binary must report the configured version (no network).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/opt" "${tmp}/scratch"

cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "nextflow version 24.10.5 build 123"
  exit 0
fi
exit 1
EOF
chmod +x "${tmp}/opt/nextflow"

cat >"${tmp}/pin.yaml" <<YAML
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
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
work_dirs:
  viralintegration: nfVI
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
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${tmp}/site.config.yaml"
nf_version_ok || {
  echo "test_nf_version_ok: matching mock binary should pass" >&2
  exit 1
}

cat >"${tmp}/opt/nextflow" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "nextflow version 26.10.3 build 999"
  exit 0
fi
exit 1
EOF

if nf_version_ok; then
  echo "test_nf_version_ok: wrong version should fail nf_version_ok" >&2
  exit 1
fi

echo "test_nf_version_ok: ok"
