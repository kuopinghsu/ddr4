#!/usr/bin/env bash
# gen_wavedrom.sh — Convert every docs/wavedrom/*.json to docs/img/*.svg
#
# Usage:  bash scripts/gen_wavedrom.sh
# Requires: wavedrom-cli  (npm install -g wavedrom-cli)

set -euo pipefail

SRCDIR="docs/wavedrom"
OUTDIR="docs/img"

mkdir -p "$OUTDIR"

shopt -s nullglob
json_files=("$SRCDIR"/*.json)

if [[ ${#json_files[@]} -eq 0 ]]; then
  echo "No JSON files found in $SRCDIR — nothing to do."
  exit 0
fi

echo "Rendering ${#json_files[@]} diagram(s): $SRCDIR → $OUTDIR/"

ok=0
fail=0
for json_file in "${json_files[@]}"; do
  name=$(basename "$json_file" .json)
  svg_file="$OUTDIR/${name}.svg"
  if wavedrom-cli -i "$json_file" -s "$svg_file"; then
    echo "  ✓  $svg_file"
    (( ok++ )) || true
  else
    echo "  ✗  FAILED: $json_file" >&2
    (( fail++ )) || true
  fi
done

echo ""
echo "Done: $ok rendered, $fail failed."
[[ $fail -eq 0 ]]   # exit non-zero if any diagram failed
