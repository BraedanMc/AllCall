#!/usr/bin/env bash
# Pinned reference MD5s (regression guard for UCSC re-download / Mac setup fixes).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pin="${ROOT}/config/pin.yaml"

human_gtf_md5="$(yq -r '.species.human.references.gtf_md5' "$pin")"
[[ "$human_gtf_md5" == "6a585655a3e67150264b792b758372a2" ]] || {
  echo "test_pin_reference_md5: unexpected human gtf_md5 (got ${human_gtf_md5})" >&2
  exit 1
}

grep -q 'install_mikefarah_yq' "${ROOT}/bin/lib.sh" || {
  echo "test_pin_reference_md5: Darwin yq installer missing from lib.sh" >&2
  exit 1
}
grep -qE 'Darwin.*install_mikefarah_yq|install_mikefarah_yq.*Darwin' "${ROOT}/bin/lib.sh" || {
  if ! awk '/uname -s.*Darwin/{d=1} d&&/install_mikefarah_yq/{found=1} END{exit !found}' "${ROOT}/bin/lib.sh"; then
    echo "test_pin_reference_md5: install_host_tools should install mikefarah yq on Darwin" >&2
    exit 1
  fi
}

echo "test_pin_reference_md5: ok"
