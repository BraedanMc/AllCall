#!/usr/bin/env bash
# macOS setup installs mikefarah yq from GitHub; Linux keeps conda python-yq package name yq.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${ROOT}/bin/lib.sh"
PIN="${ROOT}/config/pin.yaml"

grep -q 'install_mikefarah_yq' "$LIB" || {
  echo "test_tools_yq_darwin: missing install_mikefarah_yq" >&2
  exit 1
}
grep -q 'yq_darwin_' "$LIB" || {
  echo "test_tools_yq_darwin: expected darwin yq release URL" >&2
  exit 1
}
grep -qE 'arm64\) arch=arm64' "$LIB" || {
  echo "test_tools_yq_darwin: arm64 arch mapping missing" >&2
  exit 1
}
grep -qE 'x86_64\) arch=amd64' "$LIB" || {
  echo "test_tools_yq_darwin: x86_64 arch mapping missing" >&2
  exit 1
}

tool_yq="$(yq -r '.tool_yq' "$PIN")"
[[ "$tool_yq" =~ ^4\. ]] || {
  echo "test_tools_yq_darwin: tool_yq must be mikefarah 4.x (got ${tool_yq})" >&2
  exit 1
}

# Conda spec must omit yq on Darwin (installed separately).
awk '
  /uname -s.*!= Darwin/ { skip=1 }
  skip && /spec\+=\("yq=/ { found=1 }
  END { if (!found) exit 1 }
' "$LIB" || {
  echo "test_tools_yq_darwin: Linux install path should add yq to micromamba spec" >&2
  exit 1
}

grep -q 'uname -s.*== Darwin' "$LIB" && grep -q 'install_mikefarah_yq' "$LIB" || {
  echo "test_tools_yq_darwin: Darwin branch should call install_mikefarah_yq" >&2
  exit 1
}

echo "test_tools_yq_darwin: ok"
