#!/usr/bin/env bash
# Merge bundled + local virus FASTA; write merged FASTA and dedup TSV.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

MODE=build
CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) MODE=check; shift ;;
    *) CONFIG="$1"; shift ;;
  esac
done
[[ -n "$CONFIG" ]] || die "usage: merge_virus_fasta.sh [--check-only] <config.yaml>"

load_config "$CONFIG"

_run_merge() {
  local out_merged="$1" out_report="$2"
  local bundled local_dir url
  bundled="$(abs_path "$(cfg '.virus.bundled_fasta')")"
  local_dir="$(abs_path "$(cfg '.virus.local_dir')")"
  url="$(cfg '.virus.bundled_url')"

  if [[ "$MODE" == build ]]; then
    [[ -f "$bundled" ]] || download_url "$url" "$bundled"
  else
    [[ -f "$bundled" ]] || die "virus: missing bundled FASTA at ${bundled}"
  fi
  [[ -d "$local_dir" ]] || die "virus: local_dir not found: ${local_dir}"

  export BUNDLED="$bundled" LOCAL_DIR="$local_dir" MERGED="$out_merged" REPORT="$out_report"
  python3 <<'PY'
import gzip
import os
import textwrap
from pathlib import Path

bundled = Path(os.environ["BUNDLED"])
local_dir = Path(os.environ["LOCAL_DIR"])
merged = Path(os.environ["MERGED"])
report = Path(os.environ["REPORT"])

def read_fasta(path: Path):
    open_fn = gzip.open if path.name.endswith(".gz") else open
    mode = "rt" if path.name.endswith(".gz") else "r"
    recs = []
    seen = set()
    header = None
    parts = []
    source = str(path)
    with open_fn(path, mode) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    name = header.split()[0].lstrip(">")
                    if name in seen:
                        raise SystemExit(f"virus: duplicate sequence name '{name}' in {source}")
                    seen.add(name)
                    recs.append((name, header, "".join(parts)))
                header, parts = line[1:], []
            else:
                parts.append(line.upper())
    if header is not None:
        name = header.split()[0].lstrip(">")
        if name in seen:
            raise SystemExit(f"virus: duplicate sequence name '{name}' in {source}")
        recs.append((name, header, "".join(parts)))
    return recs

bundled_recs = read_fasta(bundled)
local_files = sorted(
    p
    for p in local_dir.iterdir()
    if p.is_file()
    and (p.suffix in (".fa", ".fasta") or p.name.endswith((".fa.gz", ".fasta.gz")))
)
local_recs = []
local_names = set()
for lf in local_files:
    for name, header, seq in read_fasta(lf):
        if name in local_names:
            raise SystemExit(f"virus: duplicate sequence name '{name}' across local files")
        local_names.add(name)
        local_recs.append((lf.name, name, header, seq))

report_rows = {}
winners = {}
for name, header, seq in bundled_recs:
    if name in local_names:
        fn, _, lh, ls = next(x for x in local_recs if x[1] == name)
        winners[name] = (lh, ls)
        report_rows[name] = (fn, "replaced")
    else:
        winners[name] = (header, seq)
        report_rows[name] = ("bundled", "kept")
for fn, name, header, seq in local_recs:
    if name not in winners:
        winners[name] = (header, seq)
        report_rows[name] = (fn, "added")

lines = []
for name, header, seq in bundled_recs:
    h, s = winners[name]
    lines.append(">" + h.split()[0])
    lines.extend(textwrap.wrap(s, 60))
bundled_names = {n for n, _, _ in bundled_recs}
for fn, name, header, seq in local_recs:
    if name not in bundled_names:
        lines.append(">" + header.split()[0])
        lines.extend(textwrap.wrap(seq, 60))

merged.parent.mkdir(parents=True, exist_ok=True)
merged.write_text("\n".join(lines) + "\n")
report.parent.mkdir(parents=True, exist_ok=True)
with report.open("w") as fh:
    fh.write("name\tsource\tstatus\n")
    for name in sorted(report_rows):
        src, st = report_rows[name]
        fh.write(f"{name}\t{src}\t{st}\n")
PY
}

merged="$(abs_path "$(cfg '.virus.merged_fasta')")"
report="$(abs_path "$(cfg '.virus.dedup_report')")"

if [[ "$MODE" == check ]]; then
  [[ -f "$merged" ]] || die "virus: missing merged FASTA at ${merged}"
  [[ -f "$report" ]] || die "virus: missing dedup report at ${report}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  _run_merge "$tmp/viral.fasta" "$tmp/dedup.tsv"
  cmp -s "$merged" "$tmp/viral.fasta" || die "virus: merged FASTA is stale; run setup"
  cmp -s "$report" "$tmp/dedup.tsv" || die "virus: dedup report is stale; run setup"
  exit 0
fi

_run_merge "$merged" "$report"
