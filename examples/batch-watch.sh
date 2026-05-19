#!/usr/bin/env bash
# examples/batch-watch.sh
# Read URLs from a file, watch each, write a JSONL artifact log to an
# output directory. Demonstrates `watch --pipe` slotting into a shell
# pipeline.
#
# Usage:
#   examples/batch-watch.sh urls.txt [out-dir]
#
# Output:
#   <out-dir>/results.jsonl — one JSON object per input URL (success
#                              or error, both keep version:1 so a
#                              consumer can branch on exit_code).
#
# Per-URL failures don't abort the loop; the pipeline keeps going and
# the failing object lands in results.jsonl with `exit_code` ≠ 0 and
# an `error` tag. See docs/output-schema.md for the pipe-mode shape.

set -uo pipefail

urls_file="${1:-}"
out_dir="${2:-./watched}"

if [[ -z "$urls_file" || ! -f "$urls_file" ]]; then
  echo "usage: batch-watch.sh <urls-file> [out-dir]" >&2
  exit 64
fi

mkdir -p "$out_dir"
cat "$urls_file" | watch --pipe | jq -c '.' > "$out_dir/results.jsonl"

echo "watched $(wc -l < "$out_dir/results.jsonl" | tr -d ' ') URLs → $out_dir/results.jsonl"
