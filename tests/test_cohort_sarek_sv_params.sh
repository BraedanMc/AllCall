#!/usr/bin/env bash
# run_cohort.sh wires Sarek SV params.tools through sarek_sv_tools (SV + CNV).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
script="${ROOT}/bin/run_cohort.sh"

grep -q 'tools = "$(sarek_sv_tools)"' "$script" || {
  echo "test_cohort_sarek_sv_params: run_cohort.sh must set tools via sarek_sv_tools" >&2
  exit 1
}

echo "test_cohort_sarek_sv_params: ok"
