#!/usr/bin/env bash
# nf_version_ok must accept only the pinned Nextflow version string.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
site="$(mktemp "${tmp}/site.XXXX.yaml")"
nf_bin="${tmp}/nextflow"
trap 'rm -rf "$tmp"' EXIT

ver="$(yq -r '.nextflow.version' "${ROOT}/config/pin.yaml")"

cat >"$nf_bin" <<'SH'
#!/usr/bin/env bash
echo "nextflow version PLACEHOLDER build 123"
SH
sed -i "s/PLACEHOLDER/${ver}/" "$nf_bin"
chmod +x "$nf_bin"

cat >"$site" <<YAML
species: human
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: samplesheets/cohort.local.example
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

yq ".nextflow.bin = \"${nf_bin}\" | .nextflow.home = \"${tmp}/nxf-home\"" \
  "${ROOT}/config/pin.yaml" >"${tmp}/pin.yaml"
export ALLCALL_PIN="${tmp}/pin.yaml"
load_config "$site"

nf_version_ok || {
  echo "test_nf_version_ok: expected match for pinned version ${ver}" >&2
  exit 1
}

cat >"$nf_bin" <<'SH'
#!/usr/bin/env bash
echo "nextflow version 99.99.9 build 1"
SH
chmod +x "$nf_bin"

nf_version_ok && {
  echo "test_nf_version_ok: must reject wrong nextflow -version output" >&2
  exit 1
}

echo "test_nf_version_ok: ok"
