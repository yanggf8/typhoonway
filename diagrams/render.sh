#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR="$ROOT_DIR/svg"

mkdir -p "$OUT_DIR"

render_one() {
  src=$1
  name=$(basename "$src" .mmd)
  out="$OUT_DIR/$name.svg"

  if command -v mmdc >/dev/null 2>&1; then
    mmdc -i "$src" -o "$out" -t neutral -b transparent
  else
    npx -y @mermaid-js/mermaid-cli@10.9.1 -i "$src" -o "$out" -t neutral -b transparent
  fi
}

for src in "$ROOT_DIR"/*.mmd; do
  render_one "$src"
done
