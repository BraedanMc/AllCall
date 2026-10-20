#!/usr/bin/env bash
# Shared helpers for AllCall bash orchestration.
set -euo pipefail

ALLCALL_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ALLCALL_BIN

die() {
  echo "$*" >&2
  exit 2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

load_config() {
  CONFIG="${1:?config path required}"
  [[ -f "$CONFIG" ]] || die "config not found: $CONFIG"
  PROJECT_ROOT="$(cd "$(dirname "$CONFIG")" && pwd)"
  export CONFIG PROJECT_ROOT
  need_cmd yq
}

cfg() {
  yq -r "$1" "$CONFIG"
}

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "${PROJECT_ROOT}/${p}"
  fi
}

work_dir() {
  local name="$1"
  local scratch sub
  scratch="$(cfg '.scratch_root')"
  sub="$(yq -r ".work_dirs.${name}" "$CONFIG")"
  [[ -n "$sub" && "$sub" != "null" ]] || die "work_dirs: unknown name: $name"
  if [[ "$scratch" = /* ]]; then
    echo "${scratch}/${sub}"
  else
    echo "${PROJECT_ROOT}/${scratch}/${sub}"
  fi
}

md5_file() {
  md5sum "$1" | awk '{print $1}'
}

download_url() {
  local url="$1" dest="$2"
  local partial="${dest}.partial"
  mkdir -p "$(dirname "$dest")"
  rm -f "$partial"
  curl -fsSL --max-time 60 -o "$partial" "$url" || {
    rm -f "$partial"
    die "download failed: $url"
  }
  mv "$partial" "$dest"
}

decompress_gz() {
  local gz="$1" out="$2" stamp="$3" md5="$4"
  local tmp="${out}.partial"
  rm -f "$tmp"
  gzip -dc "$gz" >"$tmp" || {
    rm -f "$tmp"
    die "decompress failed: $gz"
  }
  mv "$tmp" "$out"
  echo "$md5" >"${out}.stamp"
}

ref_asset() {
  local label="$1" url="$2" gz="$3" out="$4" md5="$5" fetch="$6"
  gz="$(abs_path "$gz")"
  out="$(abs_path "$out")"
  local stamp="${out}.stamp"
  if [[ -f "$gz" ]] && [[ "$(md5_file "$gz")" != "$md5" ]]; then
    if [[ "$fetch" == "1" ]]; then
      rm -f "$gz"
    else
      die "references: ${label} gzip MD5 mismatch"
    fi
  fi
  if [[ "$fetch" == "1" ]] && { [[ ! -f "$gz" ]] || [[ "$(md5_file "$gz")" != "$md5" ]]; }; then
    download_url "$url" "$gz"
    [[ "$(md5_file "$gz")" == "$md5" ]] || {
      rm -f "$gz"
      die "references: ${label} download MD5 mismatch"
    }
  fi
  if [[ ! -f "$out" ]] || [[ ! -f "$stamp" ]] || [[ "$(cat "$stamp")" != "$md5" ]]; then
    if [[ "$fetch" != "1" ]] && [[ -f "$out" ]]; then
      die "references: ${label} stamp mismatch at ${stamp}"
    fi
    [[ -f "$gz" ]] || die "references: cannot decompress ${label}; missing gzip"
    decompress_gz "$gz" "$out" "$stamp" "$md5"
  fi
}

references_download() {
  ref_asset fasta \
    "$(cfg '.references.fasta_url')" \
    "$(cfg '.references.fasta_gz')" \
    "$(cfg '.references.fasta')" \
    "$(cfg '.references.fasta_md5')" 1
  ref_asset gtf \
    "$(cfg '.references.gtf_url')" \
    "$(cfg '.references.gtf_gz')" \
    "$(cfg '.references.gtf')" \
    "$(cfg '.references.gtf_md5')" 1
}

references_check() {
  ref_asset fasta \
    "$(cfg '.references.fasta_url')" \
    "$(cfg '.references.fasta_gz')" \
    "$(cfg '.references.fasta')" \
    "$(cfg '.references.fasta_md5')" 0
  ref_asset gtf \
    "$(cfg '.references.gtf_url')" \
    "$(cfg '.references.gtf_gz')" \
    "$(cfg '.references.gtf')" \
    "$(cfg '.references.gtf_md5')" 0
}

java_major() {
  java -version 2>&1 | sed -n 's/.* version "\([0-9]*\)\..*/\1/p;s/.* version "1\.\([0-9]*\).*/\1/p' | head -1
}

require_java() {
  need_cmd java
  local maj
  maj="$(java_major || true)"
  [[ -n "$maj" && "$maj" -ge 17 ]] || die "Java 17+ is required and is not installed by this package"
}

nextflow_env() {
  export NXF_HOME="$(abs_path "$(cfg '.nextflow.home')")"
  export NXF_DISABLE_CHECK_LATEST=true
}

nf_version_ok() {
  local bin ver out
  bin="$(abs_path "$(cfg '.nextflow.bin')")"
  ver="$(cfg '.nextflow.version')"
  [[ -x "$bin" ]] || return 1
  out="$("$bin" -version 2>&1)" || return 1
  [[ "$out" == *"$ver"* ]]
}

nextflow_install() {
  local bin ver
  bin="$(abs_path "$(cfg '.nextflow.bin')")"
  ver="$(cfg '.nextflow.version')"
  mkdir -p "$(dirname "$bin")" "$(abs_path "$(cfg '.nextflow.home')")"
  if nf_version_ok; then
    return 0
  fi
  download_url "https://github.com/nextflow-io/nextflow/releases/download/v${ver}/nextflow" "$bin"
  chmod +x "$bin"
  nf_version_ok || die "nextflow: installed binary does not report version ${ver}"
}

nf_revision_present() {
  local home="$1" name="$2" rev="$3"
  local slug="${name//\//-}"
  [[ -d "${home}/assets/${slug}-${rev}" ]]
}

nextflow_pull() {
  require_java
  nextflow_install
  nextflow_env
  local nf bin home
  nf="$(abs_path "$(cfg '.nextflow.bin')")"
  home="$NXF_HOME"
  local name rev
  if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
    name="$(cfg '.pipelines.viralintegration.name')"
    rev="$(cfg '.pipelines.viralintegration.revision')"
    "$nf" pull "$name" -r "$rev" || die "nextflow: pull failed for ${name} revision ${rev}"
  fi
  if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
    name="$(cfg '.pipelines.sarek.name')"
    rev="$(cfg '.pipelines.sarek.revision')"
    "$nf" pull "$name" -r "$rev" || die "nextflow: pull failed for ${name} revision ${rev}"
  fi
  if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
    name="$(cfg '.pipelines.viralmetagenome.name')"
    rev="$(cfg '.pipelines.viralmetagenome.revision')"
    "$nf" pull "$name" -r "$rev" || die "nextflow: pull failed for ${name} revision ${rev}"
  fi
}

nextflow_check() {
  require_java
  local bin ver home
  bin="$(abs_path "$(cfg '.nextflow.bin')")"
  ver="$(cfg '.nextflow.version')"
  home="$(abs_path "$(cfg '.nextflow.home')")"
  [[ -x "$bin" ]] || die "nextflow: missing executable at ${bin}"
  nf_version_ok || die "nextflow: binary at ${bin} does not report version ${ver}"
  local name rev
  if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
    name="$(cfg '.pipelines.viralintegration.name')"
    rev="$(cfg '.pipelines.viralintegration.revision')"
    nf_revision_present "$home" "$name" "$rev" || die "nextflow: pipeline ${name} revision ${rev} not found under ${home}"
  fi
  if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
    name="$(cfg '.pipelines.sarek.name')"
    rev="$(cfg '.pipelines.sarek.revision')"
    nf_revision_present "$home" "$name" "$rev" || die "nextflow: pipeline ${name} revision ${rev} not found under ${home}"
  fi
  if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
    name="$(cfg '.pipelines.viralmetagenome.name')"
    rev="$(cfg '.pipelines.viralmetagenome.revision')"
    nf_revision_present "$home" "$name" "$rev" || die "nextflow: pipeline ${name} revision ${rev} not found under ${home}"
  fi
}

kraken_ready() {
  local db="$1"
  [[ -f "${db}/hash.k2d" && -f "${db}/opts.k2d" ]]
}

kraken_build() {
  local db fasta
  db="$(abs_path "$(cfg '.kraken2_db')")"
  fasta="$(abs_path "$(cfg '.references.fasta')")"
  [[ -f "$fasta" ]] || die "kraken2: host FASTA missing at ${fasta}"
  if kraken_ready "$db"; then
    return 0
  fi
  need_cmd kraken2-build
  mkdir -p "$db"
  kraken2-build --download-taxonomy --db "$db" || die "kraken2: download-taxonomy failed"
  kraken2-build --add-to-library "$fasta" --db "$db" || die "kraken2: add-to-library failed"
  kraken2-build --build --db "$db" || die "kraken2: build failed"
}

kraken_check() {
  local db
  db="$(abs_path "$(cfg '.kraken2_db')")"
  kraken_ready "$db" || die "kraken2: database not ready at ${db}"
}

check_container() {
  local profile
  profile="$(cfg '.container_profile')"
  case "$profile" in
    docker)
      need_cmd docker
      docker info >/dev/null 2>&1 || die "setup: docker is not usable (docker info failed)"
      ;;
    apptainer)
      command -v apptainer >/dev/null 2>&1 || command -v singularity >/dev/null 2>&1 ||
        die "setup: apptainer/singularity not found on PATH"
      ;;
    *) die "setup: unknown container_profile '${profile}'" ;;
  esac
}

check_scratch() {
  local scratch
  scratch="$(cfg '.scratch_root')"
  if [[ "$scratch" != /* ]]; then
    scratch="${PROJECT_ROOT}/${scratch}"
  fi
  [[ -d "$scratch" ]] || die "setup: scratch_root does not exist: ${scratch}"
  local test="${scratch}/.allcall_write_test"
  echo ok >"$test" && rm -f "$test" || die "setup: scratch_root is not writable: ${scratch}"
}
