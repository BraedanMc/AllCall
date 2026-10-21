#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_ONLY=0
CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools-only) TOOLS_ONLY=1; shift ;;
    *) CONFIG="$1"; shift ;;
  esac
done
install_host_tools
if [[ "$TOOLS_ONLY" -eq 1 ]]; then
  tools_check
  echo "setup: tools ok"
  exit 0
fi
CONFIG="${CONFIG:-${ROOT}/site.config.yaml}"
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
load_config "$CONFIG"

mkdir -p "$(abs_path "$(cfg '.virus.local_dir')")"
references_download
"${ALLCALL_BIN}/merge_virus_fasta.sh" "$CONFIG"
require_java
nextflow_install
nextflow_pull
kraken_build
echo "setup: ok"
