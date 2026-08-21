#!/usr/bin/env bash
set -euo pipefail

HOST="http://localhost:8000"
BREAK=false

for arg in "$@"; do
  case "$arg" in
    --break) BREAK=true ;;
    http*) HOST="$arg" ;;
  esac
done

if [ "$BREAK" = true ]; then
  ROUTES=(demo/fast demo/slow demo/slow demo/variable demo/error demo/error)
  echo "Generating BROKEN traffic against $HOST (high error rate + slow p95) — Ctrl+C to stop"
else
  ROUTES=(demo/fast demo/fast demo/fast demo/fast demo/variable)
  echo "Generating healthy traffic against $HOST — Ctrl+C to stop. Run with --break to trigger the alerts."
fi

while true; do
  route="${ROUTES[$RANDOM % ${#ROUTES[@]}]}"
  curl -s -o /dev/null "$HOST/$route" &
  sleep 0.2
done
