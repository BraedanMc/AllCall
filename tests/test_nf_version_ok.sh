#!/usr/bin/env bash
# nf_version_ok must match pinned nextflow.version (NF 24.10.5 gate).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

pick_yq() {
  if command -v /usr/local/bin/yq >/dev/null 2>&1 &&
    /usr/local/bin/yq --version 2>&1 | grep -q 'mikefarah'; then
    echo /usr/local/bin/yq
  elif [[ -x /tmp/yq_mikefarah ]]; then
    echo /tmp/yq_mikefarah
  elif command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q 'v4\.'; then
    command -v yq
  else
    echo "test_nf_version_ok: mikefarah yq required (see .github/workflows/test.yml)" >&2
    exit 2
  fi
}
export PATH="$(dirname "$(pick_yq)"):${PATH}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
nf_bin="${tmp}/nextflow"

write_mock_nf() {
  local ver="$1" executable="${2:-1}"
  cat >"$nf_bin" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-version" ]]; then
  echo "nextflow version ${ver} build 5927"
  exit 0
fi
exit 1
EOF
  if [[ "$executable" == 1 ]]; then chmod +x "$nf_bin"; else chmod -x "$nf_bin"; fi
}

mkdir -p "${tmp}/scratch"
printf 'sample\n' >"${tmp}/cohort.csv"

cat >"${tmp}/site.yaml" <<YAML
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
nextflow:
  bin: ${nf_bin}
YAML

ALLCALL_PIN="${ROOT}/config/pin.yaml" load_config "${tmp}/site.yaml"

[[ "$(cfg '.nextflow.version')" == "24.10.5" ]] || {
  echo "test_nf_version_ok: expected pinned 24.10.5" >&2
  exit 1
}

write_mock_nf "24.10.5"
nf_version_ok || {
  echo "test_nf_version_ok: matching mock binary should pass" >&2
  exit 1
}

write_mock_nf "26.10.3"
nf_version_ok && {
  echo "test_nf_version_ok: wrong Nextflow version should fail" >&2
  exit 1
}

write_mock_nf "24.10.5" 0
nf_version_ok && {
  echo "test_nf_version_ok: non-executable bin should fail" >&2
  exit 1
}

echo "test_nf_version_ok: ok"
