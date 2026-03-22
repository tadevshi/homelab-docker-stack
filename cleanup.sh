#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Homelab Cleanup ==="
echo ""

# List available services
services=()
for dir in */; do
  if [[ -f "$dir/docker-compose.yml" ]]; then
    services+=("${dir%/}")
  fi
done

if [[ ${#services[@]} -eq 0 ]]; then
  echo "No services found."
  exit 0
fi

echo "Available services:"
select service in "Exit" "${services[@]}"; do
  case $service in
    "Exit")
      echo "Aborted."
      exit 0
      ;;
    "")
      echo "Invalid option."
      ;;
    *)
      echo ""
      echo "Removing $service..."
      
      if [[ -f "$service/docker-compose.yml" ]]; then
        echo "  -> Stopping and removing containers..."
        docker compose -f "$service/docker-compose.yml" down 2>/dev/null || true
        
        echo "  -> Removing volumes (config data)..."
        docker compose -f "$service/docker-compose.yml" down -v 2>/dev/null || true
      fi
      
      echo "  -> Deleting directory..."
      rm -rf "$service"
      
      echo ""
      echo "Done! Run 'git add -A && git status' to see changes."
      exit 0
      ;;
  esac
done
