#!/usr/bin/env bash
# tools_spec_stamp: host tool pin fingerprint (invalidates prefix when yq pin changes).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../bin/lib.sh
source "${ROOT}/bin/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "${ROOT}/config/pin.yaml" "${tmp}/pin.yaml"
stamp_a="$(tools_spec_stamp "${tmp}/pin.yaml")"
[[ "$stamp_a" == *"yq="* ]] || {
  echo "test_tools_spec_stamp: stamp missing yq field" >&2
  exit 1
}
yq_ver="$(pin_field tool_yq "${tmp}/pin.yaml")"
[[ "$stamp_a" == *"yq=${yq_ver}"* ]] || {
  echo "test_tools_spec_stamp: stamp yq version mismatch" >&2
  exit 1
}

sed -i 's/^tool_yq:.*/tool_yq: "9.99.9"/' "${tmp}/pin.yaml"
stamp_b="$(tools_spec_stamp "${tmp}/pin.yaml")"
[[ "$stamp_a" != "$stamp_b" ]] || {
  echo "test_tools_spec_stamp: stamp should change when tool_yq pin changes" >&2
  exit 1
}

plat="$(conda_platform)"
[[ "$plat" == linux-64 || "$plat" == linux-aarch64 ]] || {
  echo "test_tools_spec_stamp: unexpected conda_platform on CI: ${plat}" >&2
  exit 1
}

echo "test_tools_spec_stamp: ok"
