#!/usr/bin/env bash
# nf_revision_present: match pulled pipeline clones by git tag (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

need_cmd git
home="${tmp}/nxf-home"
name="nf-core/viralintegration"
clone_root="${home}/assets/.repos/${name}/clones"
mkdir -p "$clone_root/repo"
git -C "${clone_root}/repo" init -q
git -C "${clone_root}/repo" config user.email test@test
git -C "${clone_root}/repo" config user.name test
echo x >"${clone_root}/repo/f"
git -C "${clone_root}/repo" add f
git -C "${clone_root}/repo" commit -qm init
git -C "${clone_root}/repo" tag 0.1.1

nf_revision_present "$home" "$name" "0.1.1" || {
  echo "test_nf_revision_present: expected tag 0.1.1" >&2
  exit 1
}
nf_revision_present "$home" "$name" "9.9.9" && {
  echo "test_nf_revision_present: wrong revision should not match" >&2
  exit 1
}

git -C "${clone_root}/repo" tag -d 0.1.1
git -C "${clone_root}/repo" tag v0.1.1
nf_revision_present "$home" "$name" "0.1.1" || {
  echo "test_nf_revision_present: expected v-prefixed tag" >&2
  exit 1
}

echo "test_nf_revision_present: ok"
