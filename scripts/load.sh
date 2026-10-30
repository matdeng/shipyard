#!/usr/bin/env bash
# Generate traffic so you can watch Grafana and the HPA react.
# Usage: scripts/load.sh http://YOUR_IP 3000 20     (URL, total requests, parallel)
set -euo pipefail
URL="${1:-http://localhost:8080}"; TOTAL="${2:-2000}"; PAR="${3:-20}"
echo "Sending $TOTAL requests to $URL with $PAR in parallel..."
seq "$TOTAL" | xargs -P "$PAR" -I{} curl -s -o /dev/null "$URL/api/info"
echo "Done. Check: kubectl -n shipyard get hpa,pods"
