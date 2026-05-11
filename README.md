# Kong Gateway 3.10 Hybrid Local Lab - Docker Compose

Topology:

- Control Plane + PostgreSQL
- Two Data Planes
- Local Nginx LB in front of both Data Planes
- Admin API exposed to Mac host on `8001` and `8444`
- Kong Manager exposed to Mac host on `8002` and `8445`
- Local LB hostname: `apigw.placsoft.local`

## Important image note

For strict Kong OSS image, Docker Official Image `kong` may not provide 3.10 tags in all registries. This compose uses:

```bash
kong/kong-gateway:3.10
```

This is Kong's Gateway image and is the practical option for a 3.10 local Docker lab. If you specifically need OSS-only source-built image, build Kong OSS 3.10 yourself and set:

```bash
export KONG_IMAGE=your-local-kong-oss:3.10
```

Then run the same compose.

## 1. Add local hostname on Mac

```bash
sudo sh -c 'echo "127.0.0.1 apigw.placsoft.local" >> /etc/hosts'
```

## 2. Generate certs

```bash
chmod +x scripts/*.sh
./scripts/generate-certs.sh
```

Generated files:

```text
certs/cluster.crt
certs/cluster.key
certs/apigw.placsoft.local.crt
certs/apigw.placsoft.local.key
```

The same `cluster.crt` and `cluster.key` are mounted into CP, DP1, and DP2. This follows Kong hybrid shared certificate mode for local lab use.

## 3. Start Kong

```bash
docker compose up -d
```

or:

```bash
./scripts/start.sh
```

## 4. Validate

```bash
docker compose ps

curl -s http://localhost:8001/status | jq .
curl -s http://localhost:8001/clustering/status | jq .
```

Expected: both DP nodes should appear in clustering status after a short time.

## 5. Access Kong Manager

```text
http://localhost:8002
https://localhost:8445
```

## 6. Access Data Planes

Direct:

```bash
curl -k https://localhost:8143
curl -k https://localhost:8243
```

Via local LB:

```bash
curl -k https://apigw.placsoft.local:8443
curl http://apigw.placsoft.local:8080
```

## 7. decK from Mac host

Install decK if not installed:

```bash
brew install deck
```

Check gateway:

```bash
deck gateway ping --kong-addr http://localhost:8001
```

Apply sample config:

```bash
deck gateway sync deck/kong.yaml --kong-addr http://localhost:8001
```

Test route through LB:

```bash
curl -k https://apigw.placsoft.local:8443/mock/get
```

## 8. Useful commands

```bash
docker logs -f kong-cp
docker logs -f kong-dp1
docker logs -f kong-dp2

docker exec -it kong-cp kong config db_export /tmp/kong.yaml
docker cp kong-cp:/tmp/kong.yaml ./deck/exported-kong.yaml
```

## 9. Clean up

```bash
docker compose down
```

Remove DB data also:

```bash
docker compose down -v
```
