#!/usr/bin/env bash
# Apptainer site configs must get local.apptainer.config after local.config (Singularity re-enabled).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

scratch="$(mktemp -d)"
site="$(mktemp "${ROOT}/config/apptainer-overlay-test.XXXX.yaml")"
trap 'rm -rf "$scratch" "$site"' EXIT

cat >"$site" <<YAML
species: human
scratch_root: ${scratch}
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: samplesheets/cohort.local.example
results_dir: results
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: apptainer
sex_xy_min_ratio: 0.1
nextflow_configs:
  - config/nextflow/local.config
YAML

load_config "$site"

args=()
while IFS= read -r -d '' c; do
  args+=("$c")
done < <(nf_nextflow_config_args)

[[ "${#args[@]}" -eq 4 ]] || {
  echo "test_nf_apptainer_overlay: expected 4 -c args, got ${#args[@]}" >&2
  exit 1
}
[[ "${args[1]}" == *"local.config" && "${args[1]}" != *"apptainer"* ]] || {
  echo "test_nf_apptainer_overlay: second arg should be local.config (got ${args[1]})" >&2
  exit 1
}
[[ "${args[3]}" == *"local.apptainer.config" ]] || {
  echo "test_nf_apptainer_overlay: fourth arg should be local.apptainer.config (got ${args[3]})" >&2
  exit 1
}

echo "test_nf_apptainer_overlay: ok"
