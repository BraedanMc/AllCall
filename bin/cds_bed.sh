#!/usr/bin/env bash
# CDS intervals from GTF (plus flank bp), merged per chromosome.
set -euo pipefail
GTF="${1:?gtf path}"
OUT="${2:?bed path}"
FLANK="${3:-10}"

awk -v flank="$FLANK" '
  $0 ~ /^#/ || NF < 9 { next }
  $3 != "CDS" { next }
  {
    s = $4 - 1 - flank
    if (s < 0) s = 0
    e = $5 + flank
    print $1, s, e
  }
' "$GTF" | sort -k1,1 -k2,2n | awk '
  {
    if (NR == 1) { c = $1; s = $2; e = $3; next }
    if ($1 == c && $2 <= e) { if ($3 > e) e = $3 }
    else { print c "\t" s "\t" e; c = $1; s = $2; e = $3 }
  }
  END { if (NR) print c "\t" s "\t" e }
' >"$OUT"
