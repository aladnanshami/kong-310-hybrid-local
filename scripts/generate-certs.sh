#!/usr/bin/env bash
set -euo pipefail

mkdir -p certs

echo "Generating Kong CP/DP shared cluster certificate..."
openssl req -new -x509 -nodes \
  -newkey rsa:4096 \
  -keyout certs/cluster.key \
  -out certs/cluster.crt \
  -days 3650 \
  -subj "/CN=kong-cp"

echo "Generating local LB certificate for apigw.placsoft.local..."
cat > certs/apigw.placsoft.local.cnf <<'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = apigw.placsoft.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = apigw.placsoft.local
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl req -new -x509 -nodes \
  -newkey rsa:2048 \
  -keyout certs/apigw.placsoft.local.key \
  -out certs/apigw.placsoft.local.crt \
  -days 3650 \
  -config certs/apigw.placsoft.local.cnf

chmod 600 certs/*.key
chmod 644 certs/*.crt

echo "Done."
ls -l certs/*.crt certs/*.key
