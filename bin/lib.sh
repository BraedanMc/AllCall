#!/usr/bin/env bash
# Shared helpers for AllCall bash orchestration.
set -euo pipefail

ALLCALL_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLCALL_ROOT="$(cd "${ALLCALL_BIN}/.." && pwd)"
export ALLCALL_BIN ALLCALL_ROOT
if [[ -f "${ALLCALL_ROOT}/opt/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${ALLCALL_ROOT}/opt/env.sh"
fi

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
  local config_dir
  config_dir="$(cd "$(dirname "$CONFIG")" && pwd)"
  # Site templates under repo config/ still use repo-root-relative paths.
  if [[ "$config_dir" == "${ALLCALL_ROOT}/config" ]]; then
    PROJECT_ROOT="$ALLCALL_ROOT"
  else
    PROJECT_ROOT="$config_dir"
  fi
  export CONFIG PROJECT_ROOT
  PIN="${ALLCALL_PIN:-${PROJECT_ROOT}/config/pin.yaml}"
  [[ -f "$PIN" ]] || die "pin manifest not found: ${PIN} (set ALLCALL_PIN to override)"
  export PIN
  need_cmd yq
  CONFIG_MERGED="$(mktemp)"
  export CONFIG_MERGED
  # pin.yaml first; site config overrides on key overlap (keep keys disjoint).
  yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$PIN" "$CONFIG" >"$CONFIG_MERGED"
  resolve_species_config
}

resolve_species_config() {
  local species tmp
  # Site species is a scalar; pin species is a map — read the toggle from the site file.
  species="$(yq -r '.species // "human"' "$CONFIG")"
  case "$species" in
    human|mouse) ;;
    *)
      die "species must be human or mouse (got '${species}')"
      ;;
  esac
  if [[ "$(yq -r ".species.${species}.references.fasta_url" "$PIN")" == "null" ]]; then
    die "pin manifest missing species.${species}.references"
  fi
  if [[ "$(yq -r ".species.${species}.kraken2_db" "$PIN")" == "null" ]]; then
    die "pin manifest missing species.${species}.kraken2_db"
  fi
  tmp="$(mktemp)"
  yq "
    .references = (load(\"${PIN}\") | .species.${species}.references) |
    .kraken2_db = (load(\"${PIN}\") | .species.${species}.kraken2_db)
  " "$CONFIG_MERGED" >"$tmp"
  mv "$tmp" "$CONFIG_MERGED"
}

cfg() {
  yq -r "$1" "$CONFIG_MERGED"
}

pipeline_name() {
  cfg ".pipelines.${1}.name"
}

pipeline_revision() {
  cfg ".pipelines.${1}.revision"
}

expand_user_path() {
  local p="$1"
  if [[ "$p" == "$(printf '\176')" ]]; then
    printf '%s' "$HOME"
  elif [[ "$p" == "$(printf '\176')/"* ]]; then
    printf '%s' "${HOME}/${p:2}"
  elif [[ "$p" == "\$HOME" ]]; then
    printf '%s' "$HOME"
  elif [[ "$p" == "\$HOME/"* ]]; then
    printf '%s' "${HOME}/${p:6}"
  elif [[ "$p" == "\$HOME"* ]]; then
    printf '%s' "${HOME}${p:5}"
  elif [[ "$p" == "\${HOME}" ]]; then
    printf '%s' "$HOME"
  elif [[ "$p" == "\${HOME}/"* ]]; then
    printf '%s' "${HOME}/${p:7}"
  elif [[ "$p" == "\${HOME}"* ]]; then
    printf '%s' "${HOME}${p:7}"
  else
    printf '%s' "$p"
  fi
}

abs_path() {
  local p="$1"
  p="$(expand_user_path "$p")"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "${PROJECT_ROOT}/${p}"
  fi
}

work_dir() {
  local name="$1"
  local scratch sub
  scratch="$(expand_user_path "$(cfg '.scratch_root')")"
  sub="$(yq -r ".work_dirs.${name}" "$CONFIG_MERGED")"
  [[ -n "$sub" && "$sub" != "null" ]] || die "work_dirs: unknown name: $name"
  if [[ "$scratch" = /* ]]; then
    echo "${scratch}/${sub}"
  else
    echo "${PROJECT_ROOT}/${scratch}/${sub}"
  fi
}

md5_file() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  else
    md5 -q "$1"
  fi
}

download_url() {
  local url="$1" dest="$2"
  local partial="${dest}.partial"
  mkdir -p "$(dirname "$dest")"
  rm -f "$partial"
  curl -fsSL --retry 3 --retry-delay 2 -o "$partial" "$url" || {
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

pin_field() {
  local key="$1" file="$2" val
  val="$(awk -F': ' -v k="$key" '$1 == k { print $2; exit }' "$file")"
  val="${val%\"}"
  val="${val#\"}"
  [[ -n "$val" && "$val" != "null" ]] || die "pin missing ${key} in ${file}"
  printf '%s' "$val"
}

conda_platform() {
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) echo osx-arm64 ;;
    Darwin-x86_64) echo osx-64 ;;
    Linux-x86_64) echo linux-64 ;;
    Linux-aarch64|Linux-arm64) echo linux-aarch64 ;;
    *) die "tools: unsupported platform $(uname -s) $(uname -m)" ;;
  esac
}

tools_pin_file() {
  echo "${ALLCALL_ROOT}/config/pin.yaml"
}

tools_spec_stamp() {
  local pin="$1"
  printf 'micromamba=%s\nbash=%s\nopenjdk=%s\nyq=%s\nsamtools=%s\nkraken2=%s\n' \
    "$(pin_field tool_micromamba "$pin")" \
    "$(pin_field tool_bash "$pin")" \
    "$(pin_field tool_openjdk "$pin")" \
    "$(pin_field tool_yq "$pin")" \
    "$(pin_field tool_samtools "$pin")" \
    "$(pin_field tool_kraken2 "$pin")"
}

java_home_for() {
  local prefix="$1"
  if [[ -x "${prefix}/lib/jvm/bin/java" ]]; then
    echo "${prefix}/lib/jvm"
  elif [[ -x "${prefix}/bin/java" ]]; then
    echo "${prefix}"
  else
    return 1
  fi
}

write_tools_env() {
  local prefix="$1" env_file="${ALLCALL_ROOT}/opt/env.sh" java_home
  java_home="$(java_home_for "$prefix")" || die "tools: java not found under ${prefix}"
  mkdir -p "${ALLCALL_ROOT}/opt"
  cat >"$env_file" <<EOF
export JAVA_HOME="${java_home}"
export PATH="${java_home}/bin:${prefix}/bin:\${PATH}"
EOF
  # shellcheck disable=SC1090
  source "$env_file"
}

tools_ready() {
  local prefix="$1" stamp="$2" pin="$3"
  java_home_for "$prefix" >/dev/null || return 1
  [[ -x "${prefix}/bin/yq" && -x "${prefix}/bin/samtools" && -x "${prefix}/bin/kraken2-build" ]] || return 1
  [[ -f "$stamp" ]] || return 1
  [[ "$(cat "$stamp")" == "$(tools_spec_stamp "$pin")" ]]
}

install_host_tools() {
  local pin prefix stamp spec mm_ver plat mm_dir mm_bin archive
  pin="$(tools_pin_file)"
  [[ -f "$pin" ]] || die "tools: pin manifest not found: ${pin}"
  prefix="${ALLCALL_ROOT}/$(pin_field tool_prefix "$pin")"
  stamp="${prefix}/.allcall-stamp"
  if tools_ready "$prefix" "$stamp" "$pin"; then
    write_tools_env "$prefix"
    echo "tools: already installed"
    return 0
  fi
  mm_ver="$(pin_field tool_micromamba "$pin")"
  plat="$(conda_platform)"
  mm_dir="${ALLCALL_ROOT}/opt/micromamba"
  mm_bin="${mm_dir}/bin/micromamba"
  if [[ ! -x "$mm_bin" ]]; then
    archive="${mm_dir}/micromamba.tar.bz2"
    mkdir -p "$mm_dir"
    curl -fsSL --max-time 180 -o "${archive}.partial" \
      "https://github.com/mamba-org/micromamba-releases/releases/download/${mm_ver}/micromamba-${plat}.tar.bz2" || {
      rm -f "${archive}.partial"
      die "tools: failed to download micromamba ${mm_ver}"
    }
    mv "${archive}.partial" "$archive"
    tar -xjf "$archive" -C "$mm_dir"
    rm -f "$archive"
  fi
  [[ -x "$mm_bin" ]] || die "tools: micromamba binary missing after extract"
  export MAMBA_ROOT_PREFIX="${ALLCALL_ROOT}/opt/mamba-root"
  mkdir -p "$MAMBA_ROOT_PREFIX"
  spec=(
    "bash=$(pin_field tool_bash "$pin")"
    "openjdk=$(pin_field tool_openjdk "$pin")"
    "yq=$(pin_field tool_yq "$pin")"
    "samtools=$(pin_field tool_samtools "$pin")"
    "kraken2=$(pin_field tool_kraken2 "$pin")"
  )
  if [[ -x "${prefix}/bin/java" ]]; then
    "$mm_bin" install -y -p "$prefix" -c conda-forge -c bioconda "${spec[@]}" \
      || die "tools: install failed"
  else
    "$mm_bin" create -y -p "$prefix" -c conda-forge -c bioconda "${spec[@]}" \
      || die "tools: create failed"
  fi
  tools_spec_stamp "$pin" >"$stamp"
  write_tools_env "$prefix"
  echo "tools: installed into ${prefix}"
}

tools_check() {
  local pin prefix stamp
  pin="$(tools_pin_file)"
  prefix="${ALLCALL_ROOT}/$(pin_field tool_prefix "$pin")"
  stamp="${prefix}/.allcall-stamp"
  [[ -f "${ALLCALL_ROOT}/opt/env.sh" ]] || die "tools: opt/env.sh missing; run ./bin/setup.sh --tools-only"
  tools_ready "$prefix" "$stamp" "$pin" || die "tools: prefix does not match pin; run ./bin/setup.sh --tools-only"
  # shellcheck disable=SC1091
  source "${ALLCALL_ROOT}/opt/env.sh"
  local maj yq_ver
  bash --version | grep -q "version $(pin_field tool_bash "$pin")" \
    || die "tools: bash version mismatch"
  maj="$(java_major || true)"
  [[ "$maj" == "17" ]] || die "tools: java is not 17 (got '${maj}')"
  yq_ver="$(yq --version 2>&1)"
  [[ "$yq_ver" == *"$(pin_field tool_yq "$pin")"* ]] || die "tools: yq version mismatch: ${yq_ver}"
  samtools --version | grep -q "$(pin_field tool_samtools "$pin")" \
    || die "tools: samtools version mismatch"
  kraken2-build --version >/dev/null 2>&1 || kraken2 --version >/dev/null 2>&1 \
    || die "tools: kraken2-build is not runnable"
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
  local nxf_home
  nxf_home="$(abs_path "$(cfg '.nextflow.home')")"
  export NXF_HOME="$nxf_home"
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
  if [[ -x "$bin" ]]; then
    rm -rf "$(abs_path "$(cfg '.nextflow.home')")"
  fi
  download_url "https://github.com/nextflow-io/nextflow/releases/download/v${ver}/nextflow" "$bin"
  chmod +x "$bin"
  nf_version_ok || die "nextflow: installed binary does not report version ${ver}"
}

nf_revision_present() {
  local home="$1" name="$2" rev="$3" clones d tag
  clones="${home}/assets/.repos/${name}/clones"
  [[ -d "$clones" ]] || return 1
  command -v git >/dev/null 2>&1 || return 0
  for d in "$clones"/*; do
    [[ -d "${d}/.git" ]] || continue
    tag="$(git -C "$d" describe --tags --exact-match HEAD 2>/dev/null || true)"
    [[ "$tag" == "$rev" || "$tag" == "v${rev}" ]] && return 0
  done
  return 1
}

_nf_pull_one() {
  local nf="$1" name="$2" rev="$3"
  "$nf" pull "$name" -r "$rev" || die "nextflow: pull failed for ${name} revision ${rev}"
}

_nf_check_one() {
  local home="$1" name="$2" rev="$3"
  nf_revision_present "$home" "$name" "$rev" ||
    die "nextflow: pipeline ${name} revision ${rev} not found under ${home}"
}

nextflow_pull() {
  require_java
  nextflow_install
  nextflow_env
  local nf
  nf="$(abs_path "$(cfg '.nextflow.bin')")"
  if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
    _nf_pull_one "$nf" "$(pipeline_name viralintegration)" "$(pipeline_revision viralintegration)"
  fi
  if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
    _nf_pull_one "$nf" "$(pipeline_name sarek)" "$(pipeline_revision sarek)"
  fi
  if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
    _nf_pull_one "$nf" "$(pipeline_name viralmetagenome)" "$(pipeline_revision viralmetagenome)"
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
  if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
    _nf_check_one "$home" "$(pipeline_name viralintegration)" "$(pipeline_revision viralintegration)"
  fi
  if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
    _nf_check_one "$home" "$(pipeline_name sarek)" "$(pipeline_revision sarek)"
  fi
  if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
    _nf_check_one "$home" "$(pipeline_name viralmetagenome)" "$(pipeline_revision viralmetagenome)"
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
  # Paused until a host Kraken2 build is run on a machine with enough disk.
  return 0
  # local db
  # db="$(abs_path "$(cfg '.kraken2_db')")"
  # kraken_ready "$db" || die "kraken2: database not ready at ${db}"
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
  scratch="$(expand_user_path "$(cfg '.scratch_root')")"
  if [[ "$scratch" != /* ]]; then
    scratch="${PROJECT_ROOT}/${scratch}"
  fi
  [[ -d "$scratch" ]] || die "setup: scratch_root does not exist: ${scratch}"
  local test="${scratch}/.allcall_write_test"
  echo ok >"$test" && rm -f "$test" || die "setup: scratch_root is not writable: ${scratch}"
}

# True when Sarek SV cohort pass finished and every sample with an SV BAM has cds_filter status set.
cohort_cds_filter_settled() {
  local sarek_sv_finished="$1" out_sv="$2"
  local -n samples_ref="$3"
  local -n status_ref="$4"
  [[ "$sarek_sv_finished" == 1 ]] || return 1
  local sample sv_bam st
  for sample in "${samples_ref[@]}"; do
    sv_bam="${out_sv}/preprocessing/markduplicates/${sample}/${sample}.md.cram"
    [[ -f "$sv_bam" ]] || continue
    st="${status_ref["${sample}|cds_filter"]:-not_started}"
    [[ "$st" != not_started ]] || return 1
  done
  return 0
}
