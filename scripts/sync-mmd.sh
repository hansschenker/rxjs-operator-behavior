#!/usr/bin/env bash
# Extract the ```mermaid block of diagrams/<operator>.md into diagrams/<operator>.mmd.
# usage: scripts/sync-mmd.sh [--check] [operator ...]
#   no operator  : every diagrams/*.md
#   --check      : verify instead of write; exit 1 if any .mmd differs or is missing
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
check=0
if [ "${1:-}" = "--check" ]; then
  check=1
  shift
fi
if [ $# -eq 0 ]; then
  set -- $(cd "$root/diagrams" && ls -- *.md | sed 's/\.md$//')
fi

extract_block() {
  # the single ```mermaid block, CR stripped
  tr -d '\r' < "$1" | awk '/^```mermaid$/{f=1;next} /^```$/{f=0} f'
}

status=0
for op in "$@"; do
  md="$root/diagrams/$op.md"
  mmd="$root/diagrams/$op.mmd"
  if [ ! -f "$md" ]; then
    echo "$op: missing diagrams/$op.md" >&2
    status=1
    continue
  fi
  block="$(extract_block "$md")"
  if [ -z "$block" ]; then
    echo "$op: no mermaid block in diagrams/$op.md" >&2
    status=1
    continue
  fi
  if [ "$check" -eq 1 ]; then
    if [ -f "$mmd" ] && [ "$block" = "$(tr -d '\r' < "$mmd")" ]; then
      echo "$op: in sync"
    else
      echo "$op: OUT OF SYNC, run scripts/sync-mmd.sh $op" >&2
      status=1
    fi
  else
    printf '%s\n' "$block" > "$mmd"
    echo "$op: wrote diagrams/$op.mmd"
  fi
done
exit "$status"
