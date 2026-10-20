#!/usr/bin/env bash
# Expand simple cohort CSV into pipeline samplesheets.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

CONFIG="${1:?config}"
OUTDIR="${2:?outdir}"
CHECK="${3:-1}"

load_config "$CONFIG"
sheet="$(abs_path "$(cfg '.samplesheet')")"
mkdir -p "$OUTDIR"
[[ -f "$sheet" ]] || die "samplesheet: file not found: ${sheet}"

header="$(head -1 "$sheet" | tr -d '\r')"
[[ "$header" == sample,fastq_1,fastq_2 || "$header" == sample,fastq_1,fastq_2,lane ]] ||
  die "samplesheet: unexpected header (want sample,fastq_1,fastq_2[,lane])"
has_lane=0
[[ "$header" == *",lane" ]] && has_lane=1

vi_rows=() sv_rows=() vm_rows=()
declare -A lane_seen
rownum=1
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line//$'\r'/}"
  [[ -z "$line" ]] && continue
  ((rownum += 1))
  if [[ "$has_lane" == 1 ]]; then
    IFS=',' read -r sample fq1 fq2 lane <<<"$line"
    lane="${lane// /}"
    [[ -n "$lane" ]] || die "samplesheet: row ${rownum}: lane required"
  else
    IFS=',' read -r sample fq1 fq2 <<<"$line"
    lane=1
  fi
  sample="${sample// /}"
  fq1="${fq1// /}"
  fq2="${fq2// /}"
  [[ -n "$sample" ]] || die "samplesheet: row ${rownum}: invalid sample id"
  [[ "$sample" != *" "* ]] || die "samplesheet: row ${rownum}: invalid sample id"
  [[ -n "$fq1" && -n "$fq2" ]] || die "samplesheet: row ${rownum}: fastq_1 and fastq_2 required"
  [[ "$fq1" == *.fastq.gz || "$fq1" == *.fq.gz ]] || die "samplesheet: row ${rownum}: fastq_1 must end with .fastq.gz or .fq.gz"
  [[ "$fq2" == *.fastq.gz || "$fq2" == *.fq.gz ]] || die "samplesheet: row ${rownum}: fastq_2 must end with .fastq.gz or .fq.gz"
  afq1="$(abs_path "$fq1")"
  afq2="$(abs_path "$fq2")"
  if [[ "$CHECK" == "1" ]]; then
    [[ -f "$afq1" ]] || die "samplesheet: row ${rownum}: fastq_1 not found: ${afq1}"
    [[ -f "$afq2" ]] || die "samplesheet: row ${rownum}: fastq_2 not found: ${afq2}"
  fi
  key="${sample}:${lane}"
  [[ -z "${lane_seen[$key]:-}" ]] || die "samplesheet: sample ${sample}: duplicate lane ${lane}"
  lane_seen[$key]=1

  if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
    vi_rows+=("${sample},${afq1},${afq2}")
  fi
  if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
    sv_rows+=("${sample},NA,0,${sample},${lane},${afq1},${afq2}")
  fi
  if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
    vm_rows+=("${sample},${afq1},${afq2}")
  fi
done < <(tail -n +2 "$sheet")

count=$(( ${#vi_rows[@]} + ${#sv_rows[@]} + ${#vm_rows[@]} ))
[[ "$count" -gt 0 ]] || die "samplesheet: no data rows"

if [[ "$(cfg '.pipelines.viralintegration.enabled')" == "true" ]]; then
  p="${OUTDIR}/viralintegration_samplesheet.csv"
  { echo "sample,fastq_1,fastq_2"; printf '%s\n' "${vi_rows[@]}"; } >"$p"
  echo "$p"
fi
if [[ "$(cfg '.pipelines.sarek.enabled')" == "true" ]]; then
  p="${OUTDIR}/sarek_sv_samplesheet.csv"
  { echo "patient,sex,status,sample,lane,fastq_1,fastq_2"; printf '%s\n' "${sv_rows[@]}"; } >"$p"
  echo "$p"
fi
if [[ "$(cfg '.pipelines.viralmetagenome.enabled')" == "true" ]]; then
  p="${OUTDIR}/viralmetagenome_samplesheet.csv"
  { echo "sample,fastq_1,fastq_2"; printf '%s\n' "${vm_rows[@]}"; } >"$p"
  echo "$p"
fi
