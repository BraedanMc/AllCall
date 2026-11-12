#!/usr/bin/env bash
# vi_star_indices_ready layout and small_host check when indices are present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
fixture="${tmp}/site.yaml"
trap 'rm -rf "$tmp"' EXIT

vi_root="${tmp}/ref/vi_star"
mkdir -p "${vi_root}/host_star/star" "${vi_root}/plus_star/star"

vi_star_indices_ready "$vi_root" && {
  echo "test_vi_star_indices_ready: missing Genome files should not be ready" >&2
  exit 1
}

: >"${vi_root}/host_star/star/Genome"
vi_star_indices_ready "$vi_root" && {
  echo "test_vi_star_indices_ready: only host Genome should not be ready" >&2
  exit 1
}

: >"${vi_root}/plus_star/star/Genome"
vi_star_indices_ready "$vi_root" || {
  echo "test_vi_star_indices_ready: both Genome files should be ready" >&2
  exit 1
}

# small_host check passes when VI enabled and indices exist (override vi index root via ref path).
scratch="${tmp}/scratch"
mkdir -p "$scratch"
cat >"$fixture" <<YAML
species: human
scratch_root: ${scratch}
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: samplesheets/cohort.local.example
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: false
  viralmetagenome:
    enabled: false
container_profile: docker
small_host: true
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

export ALLCALL_PIN="${ROOT}/config/pin.yaml"
load_config "$fixture"
root="$(vi_star_index_root)"
[[ "$root" == "${tmp}/ref/vi_star" ]] || {
  echo "test_vi_star_indices_ready: vi_star_index_root want ${tmp}/ref/vi_star got ${root}" >&2
  exit 1
}
vi_star_indices_ready "$root" || {
  echo "test_vi_star_indices_ready: small_host fixture indices should be ready" >&2
  exit 1
}
small_host_check

echo "test_vi_star_indices_ready: ok"
