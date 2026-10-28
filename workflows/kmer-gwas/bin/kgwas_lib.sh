#!/usr/bin/env bash
# Load workflows/kmer-gwas/config/kmer_gwas.params.yaml
set -euo pipefail

KGWAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KGWAS_ROOT

kgwas_die() {
  echo "kmer-gwas: $*" >&2
  exit 2
}

kgwas_need_yq() {
  if [[ -n "${YQ:-}" ]] && [[ -x "${YQ}" ]]; then
    return 0
  fi
  local allcall_root
  allcall_root="$(cd "${KGWAS_ROOT}/../.." && pwd)"
  if [[ -x "${allcall_root}/opt/tools/bin/yq" ]]; then
    export YQ="${allcall_root}/opt/tools/bin/yq"
    return 0
  fi
  command -v yq >/dev/null 2>&1 || kgwas_die "yq not found (run AllCall ./bin/setup.sh --tools-only or install yq)"
  export YQ="$(command -v yq)"
}

kgwas_expand_user_path() {
  local p="$1"
  if [[ "$p" == "~" ]]; then
    printf '%s' "$HOME"
  elif [[ "$p" == "~/"* ]]; then
    printf '%s' "${HOME}/${p:2}"
  else
    printf '%s' "$p"
  fi
}

kgwas_load_params() {
  local params="${1:-${KGWAS_PARAMS:-${KGWAS_ROOT}/config/kmer_gwas.params.yaml}}"
  [[ -f "$params" ]] || kgwas_die "params not found: ${params}"
  export KGWAS_PARAMS="$params"
  kgwas_need_yq

  local pr
  pr="$("$YQ" -r '.project_root' "$KGWAS_PARAMS")"
  if [[ "$pr" == PLACEHOLDER_* ]] || [[ -z "$pr" ]] || [[ "$pr" == "null" ]]; then
    PROJECT_ROOT="$(cd "${KGWAS_ROOT}/../.." && pwd)"
  else
    PROJECT_ROOT="$(kgwas_expand_user_path "$pr")"
    [[ "$PROJECT_ROOT" = /* ]] || PROJECT_ROOT="${KGWAS_ROOT}/${PROJECT_ROOT}"
  fi
  export PROJECT_ROOT

  RUN_NAME="$("$YQ" -r '.run_name' "$KGWAS_PARAMS")"
  if [[ "$RUN_NAME" == PLACEHOLDER_* ]] || [[ "$RUN_NAME" == "null" ]]; then
    RUN_NAME="run01"
  fi
  export RUN_NAME
}

kparam() {
  "$YQ" -r "$1" "$KGWAS_PARAMS"
}

kgwas_resolve_path() {
  local p="$1"
  p="$(kgwas_expand_user_path "$p")"
  if [[ "$p" == PLACEHOLDER_* ]]; then
    kgwas_die "unset placeholder in params: ${p}"
  fi
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "${PROJECT_ROOT}/${p}"
  fi
}

kgwas_subst_run_name() {
  local s="$1"
  s="${s//PLACEHOLDER_RUN_NAME/${RUN_NAME}}"
  s="${s//PLACEHOLDER_PROJECT_ROOT/${PROJECT_ROOT}}"
  s="${s//PLACEHOLDER_SCRATCH/${KGWAS_SCRATCH:-${PROJECT_ROOT}/workflows/kmer-gwas/scratch}}"
  printf '%s' "$s"
}

kgwas_path_from_params() {
  local key="$1"
  local raw
  raw="$(kparam "$key")"
  raw="$(kgwas_subst_run_name "$raw")"
  kgwas_resolve_path "$raw"
}

kgwas_run_in_container() {
  local engine image enabled
  enabled="$(kparam '.container.enabled')"
  [[ "$enabled" == "true" ]] || return 1
  engine="$(kparam '.container.engine')"
  image="$(kparam '.container.image')"
  if [[ "$image" == PLACEHOLDER_* ]]; then
    kgwas_die "set container.image in params or set container.enabled: false on bare-metal Linux"
  fi
  case "$engine" in
    apptainer | singularity)
      command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 ||
        kgwas_die "apptainer/singularity not on PATH"
      local run_cmd=apptainer
      command -v apptainer >/dev/null 2>&1 || run_cmd=singularity
      # shellcheck disable=SC2068
      "$run_cmd" exec --bind "${PROJECT_ROOT}" --bind "$(dirname "${WORK_DIR}")" \
        "${image}" "$@"
      ;;
    docker)
      command -v docker >/dev/null 2>&1 || kgwas_die "docker not on PATH"
      docker run --rm -u "$(id -u):$(id -g)" \
        -v "${PROJECT_ROOT}:${PROJECT_ROOT}" \
        -v "$(dirname "${WORK_DIR}"):$(dirname "${WORK_DIR}")" \
        -w "$(pwd)" \
        "${image}" "$@"
      ;;
    *) kgwas_die "unknown container.engine: ${engine}" ;;
  esac
}

kgwas_exec() {
  if kgwas_run_in_container "$@"; then
    :
  else
    # shellcheck disable=SC2068
    "$@"
  fi
}
