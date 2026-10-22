#!/usr/bin/env bash
# Repo local site config: merge, paths, and nextflow overlay files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

load_config "${ROOT}/config/local.config.yaml"

[[ "$(cfg '.container_profile')" == "docker" ]] || {
  echo "local config: expected container_profile docker" >&2
  exit 1
}
[[ "$(cfg '.scratch_root')" == "~/Documents/projects/allcall/scratch" ]] || {
  echo "local config: unexpected scratch_root" >&2
  exit 1
}
[[ "$PROJECT_ROOT" == "$ROOT" ]] || {
  echo "local config: PROJECT_ROOT should be repo root (got ${PROJECT_ROOT})" >&2
  exit 1
}

mapfile -t overlays < <(yq -r '.nextflow_configs[]?' "$CONFIG_MERGED")
[[ "${#overlays[@]}" -ge 1 ]] || {
  echo "local config: nextflow_configs empty" >&2
  exit 1
}
for rel in "${overlays[@]}"; do
  [[ -f "$(abs_path "$rel")" ]] || {
    echo "local config: missing overlay ${rel}" >&2
    exit 1
  }
  grep -q "executor" "$(abs_path "$rel")" || {
    echo "local config: overlay should set executor (${rel})" >&2
    exit 1
  }
  grep -qE 'singularity|docker' "$(abs_path "$rel")" || {
    echo "local config: overlay should document container options (${rel})" >&2
    exit 1
  }
done

scratch_home="${HOME}/Documents/projects/allcall/scratch"
mkdir -p "$scratch_home"
wd="$(work_dir viralintegration)"
[[ "$wd" == "${scratch_home}/nfVI" ]] || {
  echo "local config: work_dir viralintegration wrong (got ${wd})" >&2
  exit 1
}

got="$(expand_user_path '$HOME/Documents/projects/allcall/scratch')"
[[ "$got" == "${HOME}/Documents/projects/allcall/scratch" ]] || {
  echo "local config: expand_user_path \$HOME failed (got ${got})" >&2
  exit 1
}

sheet="$(abs_path "$(cfg '.samplesheet')")"
[[ -f "$sheet" ]] || {
  echo "local config: samplesheet missing at ${sheet}" >&2
  exit 1
}

echo "test_local_config: ok"
