#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-${ROOT}/site.config.yaml}"
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
load_config "$CONFIG"

tools_check
references_check
"${ALLCALL_BIN}/merge_virus_fasta.sh" --check-only "$CONFIG"
nextflow_check
# kraken_check is paused. The build remains in setup.sh (kraken_build).
check_container
check_scratch
"${ALLCALL_BIN}/write_sheets.sh" "$CONFIG" "${PROJECT_ROOT}/.allcall_setup_sheets_check" 1
for name in viralintegration sarek_sv sarek_snp viralmetagenome; do
  work_dir "$name" >/dev/null
done
echo "check: ok"
