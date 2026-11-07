#!/usr/bin/env bash
# local.apptainer.config: Singularity enabled overlay for apptainer sites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/tmp:${PATH}"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

overlay="${ROOT}/config/nextflow/local.apptainer.config"
[[ -f "$overlay" ]] || {
  echo "test_nextflow_apptainer_overlay: missing ${overlay}" >&2
  exit 1
}

grep -q 'enabled = true' "$overlay" || {
  echo "test_nextflow_apptainer_overlay: apptainer overlay must enable singularity" >&2
  exit 1
}
grep -q 'autoMounts = false' "$overlay" || {
  echo "test_nextflow_apptainer_overlay: expected autoMounts = false" >&2
  exit 1
}
grep -q "runOptions = '-u --containall --no-home'" "$overlay" || {
  echo "test_nextflow_apptainer_overlay: expected contained runOptions" >&2
  exit 1
}

base="${ROOT}/config/nextflow/local.config"
grep -A6 '^singularity {' "$base" | grep -q 'enabled = false' || {
  echo "test_nextflow_apptainer_overlay: local.config must keep singularity disabled for docker profile" >&2
  exit 1
}

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
scratch_root: from_pin
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
container_profile: apptainer
sex_xy_min_ratio: 0.1
nextflow_configs:
  - config/nextflow/local.config
  - config/nextflow/local.apptainer.config
YAML
touch "${tmp}/cohort.csv"
mkdir -p "${tmp}/scratch"

# Site under repo config/ still resolves repo-relative overlays.
cp "${tmp}/site.config.yaml" "${ROOT}/config/.allcall-test-apptainer-site.yaml"
trap 'rm -rf "$tmp"; rm -f "${ROOT}/config/.allcall-test-apptainer-site.yaml"' EXIT

ALLCALL_PIN="${tmp}/pin.yaml" load_config "${ROOT}/config/.allcall-test-apptainer-site.yaml"
mapfile -t overlays < <(yq -r '.nextflow_configs[]?' "$CONFIG_MERGED")
[[ "${#overlays[@]}" -eq 2 ]] || {
  echo "test_nextflow_apptainer_overlay: expected two nextflow_configs entries" >&2
  exit 1
}
for rel in "${overlays[@]}"; do
  [[ -f "$(abs_path "$rel")" ]] || {
    echo "test_nextflow_apptainer_overlay: missing overlay ${rel}" >&2
    exit 1
  }
done

echo "test_nextflow_apptainer_overlay: ok"
