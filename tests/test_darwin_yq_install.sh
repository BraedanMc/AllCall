#!/usr/bin/env bash
# macOS host tools: mikefarah yq from GitHub, not conda python-yq (lib.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
lib="${ROOT}/bin/lib.sh"

grep -q 'install_mikefarah_yq' "$lib" || {
  echo "test_darwin_yq_install: missing install_mikefarah_yq helper" >&2
  exit 1
}
grep -q 'yq_darwin_' "$lib" || {
  echo "test_darwin_yq_install: expected darwin yq release URL" >&2
  exit 1
}
grep -q '!= Darwin ]]; then' "$lib" && grep -q 'spec+=("yq=' "$lib" || {
  echo "test_darwin_yq_install: non-Darwin should install yq via micromamba" >&2
  exit 1
}
grep -q '== Darwin ]]; then' "$lib" && grep -q 'install_mikefarah_yq' "$lib" || {
  echo "test_darwin_yq_install: Darwin should install mikefarah yq after micromamba" >&2
  exit 1
}
grep -q 'install_mikefarah_yq.*tool_yq' "$lib" || {
  echo "test_darwin_yq_install: Darwin should call install_mikefarah_yq with pin version" >&2
  exit 1
}

echo "test_darwin_yq_install: ok"
