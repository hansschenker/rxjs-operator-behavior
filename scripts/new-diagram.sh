#!/usr/bin/env bash
# Scaffold diagrams/<operator>.md from docs/diagram-template.md.
# usage: scripts/new-diagram.sh <operator>
set -euo pipefail

op="${1:-}"
if [ -z "$op" ]; then
  echo "usage: scripts/new-diagram.sh <operator>" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/docs/diagram-template.md"
dst="$root/diagrams/$op.md"

if [ ! -f "$root/operators/$op.md" ]; then
  echo "no analysis at operators/$op.md; write the Mealy analysis first" >&2
  exit 1
fi
if [ -e "$dst" ]; then
  echo "diagrams/$op.md exists; not overwriting" >&2
  exit 1
fi

tr -d '\r' < "$src" | sed "s/\[operator\]/$op/g" > "$dst"
echo "created diagrams/$op.md"
echo "next: replace every [bracketed] field (see docs/diagram-method.md),"
echo "      then run scripts/sync-mmd.sh $op"
