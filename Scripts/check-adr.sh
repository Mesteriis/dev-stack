#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
adr_dir="$repo_root/docs/adr"
index_file="$adr_dir/0000-index.md"

if [[ ! -f "$index_file" ]]; then
  echo "Missing ADR index: $index_file" >&2
  exit 1
fi

numbered_files=()
while IFS= read -r path; do
  numbered_files+=("$path")
done < <(find "$adr_dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' | sort)

if [[ "${#numbered_files[@]}" -eq 0 ]]; then
  echo "No numbered ADR files found in $adr_dir" >&2
  exit 1
fi

expected_number=0
for path in "${numbered_files[@]}"; do
  file_name="$(basename "$path")"
  number="${file_name%%-*}"
  actual_number=$((10#$number))

  if [[ "$expected_number" -eq 0 && "$file_name" != "0000-index.md" ]]; then
    echo "First numbered ADR must be 0000-index.md" >&2
    exit 1
  fi

  if [[ "$actual_number" -ne "$expected_number" ]]; then
    printf 'ADR numbering gap: expected %04d but found %s\n' "$expected_number" "$file_name" >&2
    exit 1
  fi

  if [[ "$file_name" != "0000-index.md" ]] && ! grep -Fq "$file_name" "$index_file"; then
    echo "ADR index is missing $file_name" >&2
    exit 1
  fi

  expected_number=$((expected_number + 1))
done

echo "ADR checks passed."
