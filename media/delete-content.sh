#!/bin/bash
set -e
cd "$(dirname "$0")/media"

echo "=== Delete Downloaded Content ==="
echo ""

if [[ ! -d ./media ]]; then
  echo "No media folder found."
  exit 0
fi

echo "Content in ./media:"
echo ""

entries=()
while IFS= read -r line; do
  entries+=("$line")
done < <(find ./media -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "No content found."
  exit 0
fi

select entry in "Exit" "${entries[@]}"; do
  case $entry in
    "Exit")
      echo "Aborted."
      exit 0
      ;;
    "")
      echo "Invalid option."
      ;;
    *)
      read -p "Delete '$entry'? This cannot be undone. (y/N): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$entry"
        echo ""
        echo "Deleted! Remember to refresh Radarr/Sonarr to mark as missing."
      else
        echo "Cancelled."
      fi
      exit 0
      ;;
  esac
done
