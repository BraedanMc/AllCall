#!/usr/bin/env bash
# pin.yaml reference MD5 pins must stay valid hex and match smoke fixture stamps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="${ROOT}/config/pin.yaml"
SMOKE="${ROOT}/tests/smoke.sh"

md5_re='^[0-9a-f]{32}$'

for species in human mouse; do
  for field in fasta_md5 gtf_md5; do
    val="$(yq -r ".species.${species}.references.${field}" "$PIN")"
    [[ "$val" =~ $md5_re ]] || {
      echo "test_pin_reference_md5: ${species}.${field} invalid or missing (${val})" >&2
      exit 1
    }
  done
done

pin_human_gtf="$(yq -r '.species.human.references.gtf_md5' "$PIN")"
pin_mouse_gtf="$(yq -r '.species.mouse.references.gtf_md5' "$PIN")"

smoke_human_gtf="$(grep '^gtf_md5=' "$SMOKE" | head -1 | sed -n 's/^gtf_md5="\(.*\)".*/\1/p')"
smoke_mouse_gtf="$(grep '^  gtf_md5=' "$SMOKE" | head -1 | sed -n 's/^  gtf_md5="\(.*\)".*/\1/p')"

[[ "$smoke_human_gtf" == "$pin_human_gtf" ]] || {
  echo "test_pin_reference_md5: smoke human gtf_md5 out of sync with pin" >&2
  exit 1
}
[[ "$smoke_mouse_gtf" == "$pin_mouse_gtf" ]] || {
  echo "test_pin_reference_md5: smoke mouse gtf_md5 out of sync with pin" >&2
  exit 1
}

echo "test_pin_reference_md5: ok"
