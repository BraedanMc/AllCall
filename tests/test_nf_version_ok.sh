#!/usr/bin/env bash
# nf_version_ok gates nextflow_install on pinned version (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pin="${tmp}/pin.yaml"
nf_bin="${tmp}/opt/nextflow"
mkdir -p "${tmp}/opt" "${tmp}/scratch"

write_nf() {
  local ver_line="$1"
  cat >"$nf_bin" <<EOF
#!/usr/bin/env bash
echo "${ver_line}"
EOF
  chmod +x "$nf_bin"
}

cat >"$pin" <<YAML
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
  bin: ${nf_bin}
  home: ${tmp}/opt/nxf-home
scratch_root: ${tmp}/scratch
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
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"

ALLCALL_PIN="$pin" load_config "${tmp}/site.config.yaml"

write_nf "nextflow version 24.10.5 build 5935"
nf_version_ok || {
  echo "test_nf_version_ok: expected match for pinned 24.10.5" >&2
  exit 1
}

write_nf "nextflow version 26.10.3 build 9999"
if nf_version_ok; then
  echo "test_nf_version_ok: should reject wrong nextflow version" >&2
  exit 1
fi

rm -f "$nf_bin"
if nf_version_ok; then
  echo "test_nf_version_ok: missing binary should fail" >&2
  exit 1
fi

echo "test_nf_version_ok: ok"
