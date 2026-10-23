#!/usr/bin/env bash
# Cohort driver: VI + Sarek SV + viralmetagenome in parallel; CDS filter + SNP when ready.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

CONFIG=""
RUN_NAME="default"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --run-name) RUN_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) die "usage: run_cohort.sh --config <yaml> [--run-name NAME] [--dry-run]" ;;
  esac
done
[[ -n "$CONFIG" ]] || die "usage: run_cohort.sh --config <yaml> [--run-name NAME] [--dry-run]"
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
load_config "$CONFIG"

results="$(abs_path "$(cfg '.results_dir')")"
run_root="${results}/${RUN_NAME}"
mkdir -p "${run_root}/sheets" "${run_root}/params"
progress="${run_root}/progress.tsv"
[[ -f "$progress" ]] || printf 'timestamp\tstep\tstatus\n' >"$progress"
progress_event() {
  printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$2" >>"$progress"
}

progress_event check launched
if ! "${ALLCALL_BIN}/check.sh" "$CONFIG"; then
  progress_event check failed
  exit 2
fi
progress_event check completed

mapfile -t sheet_paths < <("${ALLCALL_BIN}/write_sheets.sh" "$CONFIG" "${run_root}/sheets" 1)
declare -A sheets
for p in "${sheet_paths[@]}"; do
  case "$(basename "$p")" in
    viralintegration_*) sheets[viralintegration]="$p" ;;
    sarek_sv_*) sheets[sarek_sv]="$p" ;;
    viralmetagenome_*) sheets[viralmetagenome]="$p" ;;
  esac
done

mapfile -t samples < <(tail -n +2 "$(abs_path "$(cfg '.samplesheet')")" | cut -d, -f1 | sed 's/ //g' | awk '!seen[$0]++')

ANALYSES=(viralintegration sarek_sv cds_filter sarek_snp viralmetagenome)
matrix="${run_root}/matrix.tsv"

declare -A STATUS
declare -A snp_ready=()
matrix_write() {
  local tmp="${matrix}.tmp" s a
  {
    echo -ne "sample\t"
    printf '%s\t' "${ANALYSES[@]}" | sed 's/\t$//'
    echo
    for s in "${samples[@]}"; do
      echo -ne "${s}\t"
      for a in "${ANALYSES[@]}"; do
        echo -ne "${STATUS["${s}|${a}"]:-not_started}\t"
      done
      echo
    done
  } | sed 's/\t$//' >"$tmp"
  mv "$tmp" "$matrix"
}

for s in "${samples[@]}"; do
  for a in "${ANALYSES[@]}"; do STATUS["${s}|${a}"]=not_started; done
done

bed_path="${run_root}/cds_intervals.bed"
if [[ ! -f "$bed_path" ]]; then
  "${ALLCALL_BIN}/cds_bed.sh" "$(abs_path "$(cfg '.references.gtf')")" "$bed_path" 10
fi

write_params() {
  local key="$1" path="$2"
  mkdir -p "$(dirname "$path")"
  case "$key" in
    viralintegration)
      cat >"$path" <<EOF
params {
  input = "${sheets[viralintegration]}"
  outdir = "${run_root}/viralintegration"
  fasta = "$(abs_path "$(cfg '.references.fasta')")"
  gtf = "$(abs_path "$(cfg '.references.gtf')")"
  viral_fasta = "$(abs_path "$(cfg '.virus.merged_fasta')")"
  max_cpus = 8
  max_memory = "20.GB"
}
EOF
      ;;
    sarek_sv)
      cat >"$path" <<EOF
params {
  input = "${sheets[sarek_sv]}"
  outdir = "${run_root}/sarek_sv"
  genome = "null"
  igenomes_ignore = true
  fasta = "$(abs_path "$(cfg '.references.fasta')")"
  gtf = "$(abs_path "$(cfg '.references.gtf')")"
  tools = "$(cfg '.pipelines.sarek.tools_sv')"
}
EOF
      ;;
    viralmetagenome)
      cat >"$path" <<EOF
params {
  input = "${sheets[viralmetagenome]}"
  outdir = "${run_root}/viralmetagenome"
  host_genome = "$(abs_path "$(cfg '.references.fasta')")"
  kraken2_db = "$(abs_path "$(cfg '.kraken2_db')")"
}
EOF
      ;;
    sarek_snp)
      cat >"$path" <<EOF
params {
  input = "${run_root}/sheets/sarek_snp_samplesheet.csv"
  outdir = "${run_root}/sarek_snp"
  genome = "null"
  igenomes_ignore = true
  fasta = "$(abs_path "$(cfg '.references.fasta')")"
  gtf = "$(abs_path "$(cfg '.references.gtf')")"
  tools = "$(cfg '.pipelines.sarek.tools_snp')"
  wes = true
  intervals = "${bed_path}"
}
EOF
      ;;
  esac
}

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

cmds=() cmd_names=()
if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
  p="${run_root}/params/viralintegration.config"
  write_params viralintegration "$p"
  cmds+=("$(nf_cmd "$(pipeline_name viralintegration)" "$(pipeline_revision viralintegration)" "$(work_dir viralintegration)" "$p")")
  cmd_names+=(viralintegration)
fi
if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
  p="${run_root}/params/sarek_sv.config"
  write_params sarek_sv "$p"
  cmds+=("$(nf_cmd "$(pipeline_name sarek)" "$(pipeline_revision sarek)" "$(work_dir sarek_sv)" "$p")")
  cmd_names+=(sarek_sv)
fi
if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
  p="${run_root}/params/viralmetagenome.config"
  write_params viralmetagenome "$p"
  cmds+=("$(nf_cmd "$(pipeline_name viralmetagenome)" "$(pipeline_revision viralmetagenome)" "$(work_dir viralmetagenome)" "$p")")
  cmd_names+=(viralmetagenome)
fi
p="${run_root}/params/sarek_snp.config"
write_params sarek_snp "$p"
snp_cmd="$(nf_cmd "$(pipeline_name sarek)" "$(pipeline_revision sarek)" "$(work_dir sarek_snp)" "$p")"

for c in "${cmds[@]}"; do echo "$c"; done
echo "$snp_cmd"

if [[ "$DRY_RUN" == 1 ]]; then
  for s in "${samples[@]}"; do
    for n in viralintegration sarek_sv viralmetagenome; do
      STATUS["${s}|${n}"]=running
    done
  done
  matrix_write
  for n in "${cmd_names[@]}"; do
    progress_event "$n" launched
  done
  exit 0
fi

need_cmd samtools
nextflow_env
out_vi="${run_root}/viralintegration"
out_sv="${run_root}/sarek_sv"
filt_dir="${run_root}/filtered_bams"
sex_path="${run_root}/sex.tsv"
mkdir -p "$filt_dir"
[[ -f "$sex_path" ]] || echo -e "sample\tsex" >"$sex_path"

declare -A sex_map
infer_sex() {
  local bam="$1" ratio x=0 y=0 chrom count
  ratio="$(cfg '.sex_xy_min_ratio')"
  [[ -f "$bam" ]] || { echo NA; return; }
  while IFS=$'\t' read -r chrom _ _ count _; do
    case "$chrom" in chrX|X) x=$count ;; chrY|Y) y=$count ;; esac
  done < <(samtools idxstats "$bam")
  if [[ "$x" == 0 && "$y" == 0 ]]; then echo NA; return; fi
  if [[ "$y" == 0 ]]; then echo XX; return; fi
  awk -v y="$y" -v x="$x" -v r="$ratio" 'BEGIN{ if (y/(x+0.0) >= r) print "XY"; else print "XX" }'
}

declare -A pid_name
for i in "${!cmds[@]}"; do
  name="${cmd_names[$i]}"
  for s in "${samples[@]}"; do STATUS["${s}|${name}"]=running; done
  matrix_write
  progress_event "$name" launched
  eval "${cmds[$i]}" & pid_name[$!]="$name"
done

snp_started=0 snp_pid=""
cds_logged=0
idle_pass=0
sarek_sv_finished=0

mark_done() {
  local pid="$1"
  local rc="$2"
  local name="${pid_name[$pid]}"
  local st=failed; [[ "$rc" == 0 ]] && st=succeeded
  for s in "${samples[@]}"; do STATUS["${s}|${name}"]=$st; done
  matrix_write
  if [[ "$st" == succeeded ]]; then
    progress_event "$name" completed
  else
    progress_event "$name" failed
  fi
  [[ "$name" == sarek_sv ]] && sarek_sv_finished=1
  unset "pid_name[$pid]"
}

cds_filter_settled() {
  cohort_cds_filter_settled "$sarek_sv_finished" "$out_sv" samples STATUS
}

while :; do
  for pid in "${!pid_name[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      rc=0
      wait "$pid" || rc=$?
      mark_done "$pid" "$rc"
    fi
  done

  for sample in "${samples[@]}"; do
    sv_bam="${out_sv}/preprocessing/markduplicates/${sample}/${sample}.md.cram"
    if [[ -f "$sv_bam" && ! -f "${filt_dir}/${sample}.cds.bam" ]]; then
      [[ "$cds_logged" == 1 ]] || { progress_event cds_filter launched; cds_logged=1; }
      if samtools view -b -L "$bed_path" "$sv_bam" -o "${filt_dir}/${sample}.cds.bam"; then
        STATUS["${sample}|cds_filter"]=succeeded
        progress_event cds_filter completed
      else
        STATUS["${sample}|cds_filter"]=failed
        progress_event cds_filter failed
      fi
      matrix_write
    fi
    vi_bam="${out_vi}/star_align/${sample}/${sample}.Aligned.sortedByCoord.out.bam"
    if [[ -f "$vi_bam" && -z "${sex_map[$sample]:-}" ]]; then
      sex_map[$sample]="$(infer_sex "$vi_bam")"
      echo -e "${sample}\t${sex_map[$sample]}" >>"$sex_path"
    fi
    [[ -f "${filt_dir}/${sample}.cds.bam" ]] && snp_ready[$sample]=1
  done

  if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" && "$snp_started" == 0 && ${#snp_ready[@]} -gt 0 ]] && cds_filter_settled; then
    mapfile -t ready < <(printf '%s\n' "${!snp_ready[@]}" | sort)
    {
      echo "patient,sex,status,sample,bam"
      for s in "${ready[@]}"; do
        echo "${s},${sex_map[$s]:-NA},0,${s},${filt_dir}/${s}.cds.bam"
      done
    } >"${run_root}/sheets/sarek_snp_samplesheet.csv"
    for s in "${ready[@]}"; do STATUS["${s}|sarek_snp"]=running; done
    matrix_write
    progress_event sarek_snp launched
    eval "$snp_cmd" & snp_pid=$!
    snp_started=1
  fi

  if [[ -n "$snp_pid" ]] && ! kill -0 "$snp_pid" 2>/dev/null; then
    rc=0
    wait "$snp_pid" || rc=$?
    st=failed; [[ "$rc" == 0 ]] && st=succeeded
    for s in "${!snp_ready[@]}"; do STATUS["${s}|sarek_snp"]=$st; done
    matrix_write
    if [[ "$st" == succeeded ]]; then
      progress_event sarek_snp completed
    else
      progress_event sarek_snp failed
    fi
    snp_pid=""
  fi

  [[ ${#pid_name[@]} -eq 0 && "$snp_started" == 1 && -z "$snp_pid" ]] && break
  if [[ ${#pid_name[@]} -eq 0 && "$snp_started" == 0 ]]; then
    idle_pass=$((idle_pass + 1))
    [[ "$idle_pass" -ge 2 ]] && break
  else
    idle_pass=0
  fi
  sleep 2
done
