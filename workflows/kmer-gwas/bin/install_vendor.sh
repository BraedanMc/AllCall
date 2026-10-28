#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/vendor/K-mer-GWAS-pipeline"
if [[ -d "${DEST}/.git" ]]; then
  echo "vendor pipeline already present: ${DEST}"
  exit 0
fi
git clone --depth 1 https://github.com/viannam/K-mer-GWAS-pipeline.git "${DEST}"
echo "Cloned viannam/K-mer-GWAS-pipeline into ${DEST}"
echo "Next: unpack voichek/kmersGWAS v0.3-beta into ${ROOT}/vendor/kmersGWAS (see vendor/README.md)"
