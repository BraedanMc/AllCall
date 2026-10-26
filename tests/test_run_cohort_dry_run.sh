#!/usr/bin/env bash
# run_cohort.sh dry-run: Nextflow -c params, viralintegration caps, viral_fasta param name.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
run_cohort="${ROOT}/bin/run_cohort.sh"

grep -q 'viral_fasta' "$run_cohort" || {
  echo "test_run_cohort_dry_run: viralintegration params must use viral_fasta (nf-core 0.1.1)" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$run_cohort" || {
  echo "test_run_cohort_dry_run: viralintegration max_cpus cap missing" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$run_cohort" || {
  echo "test_run_cohort_dry_run: viralintegration max_memory cap missing" >&2
  exit 1
}
grep -qE '\-c "\$params"' "$run_cohort" || {
  echo "test_run_cohort_dry_run: nf_cmd must pass cohort params with -c (not -params-file)" >&2
  exit 1
}
if grep -q '\-params-file' "$run_cohort"; then
  echo "test_run_cohort_dry_run: nf_cmd must not use -params-file (Nextflow 24.x cohort configs)" >&2
  exit 1
fi

YQ_BIN="${YQ_BIN:-}"
if [[ -z "$YQ_BIN" ]]; then
  if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q mikefarah; then
    YQ_BIN="$(command -v yq)"
  elif [[ -x /usr/local/bin/yq ]] && /usr/local/bin/yq --version 2>&1 | grep -q mikefarah; then
    YQ_BIN=/usr/local/bin/yq
  else
    echo "test_run_cohort_dry_run: skip functional dry-run (mikefarah yq not on PATH)" >&2
    echo "test_run_cohort_dry_run: ok (static)"
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="${tmp}/repo"
scratch="${tmp}/scratch"
tools="${repo}/opt/tools"
mkdir -p "${repo}/bin" "${tools}/bin" "$scratch" "${tmp}/ref/virus/local" "${tmp}/data" "${tmp}/config"

cp -a "${ROOT}/bin"/*.sh "${repo}/bin/"
chmod +x "${repo}/bin"/*.sh

pin="${tmp}/config/pin.yaml"
cp "${ROOT}/config/pin.yaml" "$pin"
"$YQ_BIN" "
  .species.human.references.fasta_gz = \"${tmp}/ref/hg38.fa.gz\" |
  .species.human.references.fasta = \"${tmp}/ref/hg38.fa\" |
  .species.human.references.gtf_gz = \"${tmp}/ref/hg38.gtf.gz\" |
  .species.human.references.gtf = \"${tmp}/ref/hg38.gtf\" |
  .species.human.kraken2_db = \"${tmp}/ref/kraken2/hg38\" |
  .virus.bundled_fasta = \"${tmp}/ref/virus/ctat.fasta\" |
  .virus.local_dir = \"${tmp}/ref/virus/local\" |
  .virus.merged_fasta = \"${tmp}/ref/virus/viral.fasta\" |
  .virus.dedup_report = \"${tmp}/ref/virus/dedup.tsv\" |
  .nextflow.bin = \"opt/nextflow\" |
  .nextflow.home = \"opt/nxf-home\"
" "$pin" >"${pin}.patched"
mv "${pin}.patched" "$pin"

# MD5s of printf 'ACGT\n' | gzip -c and printf 'gene\n' | gzip -c (isolated fixtures).
FASTA_MD5="8f969ecf131e837c6b1bb7f936cf009b"
GTF_MD5="3c4cd47cd66df7b8a7ce821fca45e769"
"$YQ_BIN" "
  .species.human.references.fasta_md5 = \"${FASTA_MD5}\" |
  .species.human.references.gtf_md5 = \"${GTF_MD5}\"
" "$pin" >"${pin}.md5"
mv "${pin}.md5" "$pin"
mkdir -p "${repo}/config"
cp "$pin" "${repo}/config/pin.yaml"
printf 'ACGT\n' | gzip -c >"${tmp}/ref/hg38.fa.gz"
printf 'ACGT\n' >"${tmp}/ref/hg38.fa"
echo "$FASTA_MD5" >"${tmp}/ref/hg38.fa.stamp"
printf 'gene\n' | gzip -c >"${tmp}/ref/hg38.gtf.gz"
printf 'gene\n' >"${tmp}/ref/hg38.gtf"
echo "$GTF_MD5" >"${tmp}/ref/hg38.gtf.stamp"
cat >"${tmp}/ref/virus/ctat.fasta" <<'FA'
>V1
ACGT
FA
cp "${tmp}/ref/virus/ctat.fasta" "${tmp}/ref/virus/viral.fasta"
echo -e "name\taction" >"${tmp}/ref/virus/dedup.tsv"

touch "${tmp}/data/S1_R1.fastq.gz" "${tmp}/data/S1_R2.fastq.gz"
echo "sample,fastq_1,fastq_2" >"${tmp}/cohort.csv"
echo "S1,${tmp}/data/S1_R1.fastq.gz,${tmp}/data/S1_R2.fastq.gz" >>"${tmp}/cohort.csv"

cat >"${tmp}/site.config.yaml" <<YAML
species: human
scratch_root: ${scratch}
work_dirs:
  viralintegration: nfVI
  sarek_sv: nfSarekSV
  sarek_snp: nfSarekSNP
  viralmetagenome: nfVirMeta
samplesheet: ${tmp}/cohort.csv
results_dir: ${tmp}/results
pipelines:
  viralintegration:
    enabled: true
  sarek:
    enabled: false
    tools_sv: manta
    tools_snp: haplotypecaller
  viralmetagenome:
    enabled: false
container_profile: docker
sex_xy_min_ratio: 0.1
nextflow_configs: []
YAML

cat >"${tools}/bin/bash" <<'STUB'
#!/bin/bash
exec /bin/bash "$@"
STUB
cat >"${tools}/bin/java" <<'STUB'
#!/bin/bash
if [[ "$1" == "-version" ]]; then
  echo 'openjdk version "17.0.18"' >&2
  exit 0
fi
exec /usr/bin/java "$@"
STUB
cat >"${tools}/bin/samtools" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "samtools 1.24"
  exit 0
fi
exit 0
STUB
cat >"${tools}/bin/kraken2-build" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cp "$YQ_BIN" "${tools}/bin/yq"
chmod +x "${tools}/bin"/*

mkdir -p "${tools}/lib/jvm/bin"
ln -sf "${tools}/bin/java" "${tools}/lib/jvm/bin/java"

# shellcheck source=/dev/null
source "${repo}/bin/lib.sh"
tools_spec_stamp "$pin" >"${tools}/.allcall-stamp"
mkdir -p "${repo}/opt"
cat >"${repo}/opt/env.sh" <<EOF
export JAVA_HOME="${tools}/lib/jvm"
export PATH="${tools}/bin:\${PATH}"
EOF

mkdir -p "${tmp}/opt"
nxf_home="${tmp}/opt/nxf-home"
cat >"${tmp}/opt/nextflow" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "-version" ]]; then
  echo "nextflow version 24.10.5 build 123"
  exit 0
fi
exit 0
STUB
chmod +x "${tmp}/opt/nextflow"

clone_dir="${nxf_home}/assets/.repos/nf-core/viralintegration/clones/dryrun"
mkdir -p "$clone_dir"
git -C "$clone_dir" init -q
git -C "$clone_dir" config user.email "test@example.com"
git -C "$clone_dir" config user.name "test"
echo test >"${clone_dir}/README"
git -C "$clone_dir" add README
git -C "$clone_dir" commit -q -m init
git -C "$clone_dir" tag 0.1.1

stub_bin="${tmp}/stub-bin"
mkdir -p "$stub_bin"
cat >"${stub_bin}/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then exit 0; fi
exit 0
STUB
chmod +x "${stub_bin}/docker"

export PATH="${stub_bin}:${tools}/bin:${PATH}"
ALLCALL_PIN="$pin" "${repo}/bin/merge_virus_fasta.sh" "${tmp}/site.config.yaml"
if ! ALLCALL_PIN="$pin" "${repo}/bin/run_cohort.sh" --config "${tmp}/site.config.yaml" --run-name dryrun01 --dry-run \
  >"${tmp}/dry_run.out" 2>"${tmp}/dry_run.err"; then
  echo "test_run_cohort_dry_run: run_cohort --dry-run failed" >&2
  cat "${tmp}/dry_run.err" >&2
  exit 1
fi

vi_params="${tmp}/results/dryrun01/params/viralintegration.config"
[[ -f "$vi_params" ]] || {
  echo "test_run_cohort_dry_run: missing ${vi_params}" >&2
  cat "${tmp}/dry_run.err" >&2
  exit 1
}
grep -q 'viral_fasta' "$vi_params" || {
  echo "test_run_cohort_dry_run: viralintegration.config missing viral_fasta" >&2
  exit 1
}
grep -q 'virus_fasta' "$vi_params" && {
  echo "test_run_cohort_dry_run: viralintegration.config must not use virus_fasta" >&2
  exit 1
}
grep -q 'max_cpus = 8' "$vi_params" || {
  echo "test_run_cohort_dry_run: viralintegration.config missing max_cpus" >&2
  exit 1
}
grep -q 'max_memory = "20.GB"' "$vi_params" || {
  echo "test_run_cohort_dry_run: viralintegration.config missing max_memory" >&2
  exit 1
}

grep -q -- ' -c ' "${tmp}/dry_run.out" || {
  echo "test_run_cohort_dry_run: dry-run nextflow line missing -c" >&2
  cat "${tmp}/dry_run.out" >&2
  exit 1
}
grep -q 'params-file' "${tmp}/dry_run.out" && {
  echo "test_run_cohort_dry_run: dry-run must not use -params-file" >&2
  exit 1
}

echo "test_run_cohort_dry_run: ok"
