#!/usr/bin/env bash
set -euo pipefail

TRACE_ID=$(openssl rand -hex 16)
SPAN_ID=$(openssl rand -hex 8)
START_NS=$(date +%s)000000000
END_NS=$(($(date +%s) + 1))000000000

curl -s -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "resourceSpans": [{
    "resource": { "attributes": [{"key": "service.name", "value": {"stringValue": "laravel-demo"}}] },
    "scopeSpans": [{
      "spans": [{
        "traceId": "$TRACE_ID",
        "spanId": "$SPAN_ID",
        "name": "GET /demo/slow",
        "kind": 2,
        "startTimeUnixNano": "$START_NS",
        "endTimeUnixNano": "$END_NS",
        "attributes": [{"key": "http.route", "value": {"stringValue": "/demo/slow"}}]
      }]
    }]
  }]
}
EOF

echo
echo "Sent trace $TRACE_ID — search for it in Grafana > Explore > Tempo"
