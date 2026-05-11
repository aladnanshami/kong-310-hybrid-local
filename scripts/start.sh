#!/usr/bin/env bash
set -euo pipefail

if [ ! -f certs/cluster.crt ] || [ ! -f certs/cluster.key ]; then
  ./scripts/generate-certs.sh
fi

docker compose up -d

echo
echo "Kong containers:"
docker compose ps

echo
echo "Admin API:"
curl -s http://localhost:8001/status | jq . || curl -s http://localhost:8001/status

echo
echo "Hybrid cluster status:"
curl -s http://localhost:8001/clustering/status | jq . || curl -s http://localhost:8001/clustering/status

echo
echo "Kong Manager: http://localhost:8002"
echo "Local LB HTTPS: https://apigw.placsoft.local:8443"
echo "Direct DP1 HTTPS: https://localhost:8143"
echo "Direct DP2 HTTPS: https://localhost:8243"
