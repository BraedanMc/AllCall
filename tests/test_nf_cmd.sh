#!/usr/bin/env bash
# Nextflow CLI assembly: cohort params via -c and site nextflow_configs overlays.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/config" "${tmp}/scratch" "${tmp}/nf-overlays"

cat >"${tmp}/config/pin.yaml" <<YAML
species:
  human:
    references:
      fasta_url: https://example.invalid/hg38.fa.gz
      fasta_gz: ${tmp}/ref.fa.gz
      fasta: ${tmp}/ref.fa
      fasta_md5: ""
      gtf_url: https://example.invalid/hg38.gtf.gz
      gtf_gz: ${tmp}/ref.gtf.gz
      gtf: ${tmp}/ref.gtf
      gtf_md5: ""
    kraken2_db: ${tmp}/kraken
nextflow:
  version: "24.10.5"
  bin: ${tmp}/opt/nextflow
  home: ${tmp}/opt/nxf-home
pipelines:
  viralintegration:
    name: nf-core/viralintegration
    revision: 0.1.1
YAML

cat >"${tmp}/overlay.config" <<'EOF'
process {
  cpus = 1
}
EOF

cat >"${tmp}/site.config.yaml" <<YAML
scratch_root: ${tmp}/scratch
work_dirs:
  viralintegration: nfVI
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: true
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs:
  - ${tmp}/overlay.config
YAML

mkdir -p "${tmp}/opt"
printf '#!/usr/bin/env bash\necho "nextflow version 24.10.5"\n' >"${tmp}/opt/nextflow"
chmod +x "${tmp}/opt/nextflow"

ALLCALL_PIN="${tmp}/config/pin.yaml" load_config "${tmp}/site.config.yaml"

nf_profile() {
  if [[ "$(cfg '.container_profile')" == "docker" ]]; then echo docker; else echo singularity; fi
}

nf_cmd() {
  local pipeline="$1" revision="$2" work="$3" params="$4"
  local bin extra=() c
  bin="$(abs_path "$(cfg '.nextflow.bin')")"
  while IFS= read -r c; do
    [[ -n "$c" && "$c" != "null" ]] && extra+=(-c "$(abs_path "$c")")
  done < <(yq -r '.nextflow_configs[]?' "$CONFIG_MERGED")
  printf '%q ' "$bin" run "$pipeline" -r "$revision" -resume -work-dir "$work" -c "$params" -profile "$(nf_profile)" "${extra[@]}"
}

params="${tmp}/params/viralintegration.config"
mkdir -p "$(dirname "$params")"
cat >"$params" <<EOF
params { input = "sheet.csv" }
EOF

cmd="$(nf_cmd "$(pipeline_name viralintegration)" "$(pipeline_revision viralintegration)" "$(work_dir viralintegration)" "$params")"
[[ "$cmd" == *" -c ${params} "* || "$cmd" == *" -c '${params}'"* ]] || {
  echo "test_nf_cmd: expected cohort params file passed with -c (got: ${cmd})" >&2
  exit 1
}
[[ "$cmd" != *"-params-file"* ]] || {
  echo "test_nf_cmd: must not use deprecated -params-file" >&2
  exit 1
}
overlay_abs="$(abs_path "${tmp}/overlay.config")"
[[ "$cmd" == *" -c ${overlay_abs} "* ]] || {
  echo "test_nf_cmd: expected site overlay in -c flags (got: ${cmd})" >&2
  exit 1
}
[[ "$cmd" == *" -profile docker "* ]] || {
  echo "test_nf_cmd: expected docker profile" >&2
  exit 1
}

echo "test_nf_cmd: ok"
