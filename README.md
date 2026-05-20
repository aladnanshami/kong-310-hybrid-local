# Kong Gateway 3.10 — Hybrid Mode Local Setup

> A fully working **Kong Gateway 3.10 Enterprise hybrid deployment** running locally on Mac using Docker Compose — the same architecture used in real banks and enterprises.
>
> Originally based on [pritishpattanaik/kong-310-hybrid-local](https://github.com/pritishpattanaik/kong-310-hybrid-local) — fixed and extended with working TLS certificates, decK config management, and ngrok internet exposure.

---

## What is Hybrid Mode?

In hybrid mode, Kong is split into two parts:

- **Control Plane (CP)** — manages all configuration, exposes the Admin API and Kong Manager UI. No customer traffic goes through it.
- **Data Plane (DP)** — serves all actual API traffic. Gets its config from the CP. Can keep running even if CP goes down.

This is how real banks and enterprises run Kong in production — for high availability and security.

---

## Architecture

```
Internet
    ↓
ngrok (optional — exposes local Kong to internet)
    ↓
Nginx Load Balancer  :8080 (HTTP) / :8443 (HTTPS)
    ↓                      ↓
Kong Data Plane 1       Kong Data Plane 2
  :8100 (HTTP)             :8200 (HTTP)
  :8143 (HTTPS)            :8243 (HTTPS)
         ↓                      ↓
         Kong Control Plane (CP)
           :8001 Admin API
           :8002 Kong Manager UI
           :8005 Cluster endpoint
           :8006 Telemetry endpoint
                    ↓
              PostgreSQL DB
                  :5432
```

---

## Services & Ports

| Container | Description | Ports |
|---|---|---|
| `kong-cp` | Control Plane | `8001` (Admin API), `8002` (Manager UI), `8005` (Cluster), `8006` (Telemetry) |
| `kong-dp1` | Data Plane 1 | `8100` (HTTP proxy), `8143` (HTTPS proxy) |
| `kong-dp2` | Data Plane 2 | `8200` (HTTP proxy), `8243` (HTTPS proxy) |
| `kong-dp-lb` | Nginx Load Balancer | `8080` (HTTP), `8443` (HTTPS) |
| `kong-db` | PostgreSQL 16 | `5432` |
| `kong-migrations` | DB migration job | — |

---

## Prerequisites

- Mac with Apple Silicon (M1/M2/M3) or Intel
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Homebrew](https://brew.sh/)

---

## Setup

### 1. Clone this repo

```bash
git clone https://github.com/YOUR_USERNAME/kong-310-hybrid-local
cd kong-310-hybrid-local
```

### 2. Generate cluster certificates

> ⚠️ **Critical:** You MUST use Kong's own cert generator — not plain `openssl`.
> Kong Enterprise 3.10 requires `CN=kong_clustering` internally. Using any other CN will cause `ssl handshake failed: certificate host mismatch` and the Data Planes will never connect.

```bash
mkdir -p certs

# Generate Kong cluster cert (CP <-> DP mTLS)
docker run --rm -v $(pwd)/certs:/app kong/kong-gateway:3.10 \
  sh -c "cd /app && kong hybrid gen_cert"

# Generate Nginx TLS cert (for the load balancer)
openssl req -new -x509 -nodes \
  -newkey rsa:2048 \
  -keyout certs/apigw.placsoft.local.key \
  -out certs/apigw.placsoft.local.crt \
  -days 3650 \
  -subj "/CN=apigw.placsoft.local"
```

### 3. Verify docker-compose.yml

Make sure both `kong-dp1` and `kong-dp2` have these three environment variables:

```yaml
KONG_CLUSTER_MTLS: shared
KONG_CLUSTER_SERVER_NAME: kong_clustering
KONG_CLUSTER_TELEMETRY_SERVER_NAME: kong_clustering
```

These must match the `CN=kong_clustering` in the generated cert.

### 4. Start everything

```bash
docker compose up -d
```

### 5. Wait 30 seconds then verify Data Planes are connected

```bash
sleep 30 && curl -s http://localhost:8001/clustering/data-planes | jq '[.data[] | {hostname, sync_status}]'
```

Expected output — both DPs should show `sync_status: normal`:

```json
[
  { "hostname": "abc123", "sync_status": "normal" },
  { "hostname": "def456", "sync_status": "normal" }
]
```

### 6. Open Kong Manager UI

```
http://localhost:8002
```

> Note: You will see a "No valid Kong Enterprise license" banner. This is expected — hybrid mode works in free mode.

---

## Managing Config with decK

decK is Kong's official CLI tool for managing Kong config as YAML files. This is how real teams manage Kong in production — no manual clicking, everything in Git.

### Install decK

```bash
# Use Kong's own tap — not brew install deck (that installs a different tool!)
brew tap kong/deck && brew install kong/deck/deck
```

### Connect to Kong

```bash
deck gateway ping --kong-addr http://localhost:8001
```

### Export current config to YAML

```bash
deck gateway dump --kong-addr http://localhost:8001 -o kong-state.yaml
```

### Preview changes before applying

```bash
deck gateway diff --kong-addr http://localhost:8001 kong-state.yaml
```

### Apply config

```bash
deck gateway sync --kong-addr http://localhost:8001 kong-state.yaml
```

> 💡 **Tip:** Always run `diff` before `sync` to see exactly what will change. Store `kong-state.yaml` in Git — if anything breaks, one `sync` command restores everything in under 1 minute.

---

## Expose to Internet with ngrok

```bash
# Install
brew install ngrok

# Add your authtoken (get it from ngrok.com after free signup)
ngrok config add-authtoken YOUR_TOKEN_HERE

# Expose Kong's load balancer to the internet
ngrok http 8080
```

Add `ngrok-skip-browser-warning: true` header to bypass ngrok's browser warning:

```bash
curl -s -H "ngrok-skip-browser-warning: true" https://YOUR-NGROK-URL/your-route
```

---

## Example: Banking API Security Setup

Here is a complete example of setting up a protected banking API through Kong:

### Create a service and route

```bash
# Create service
curl -s -X POST http://localhost:8001/services \
  --data name=banking-api \
  --data url=https://jsonplaceholder.typicode.com | jq .name

# Create route
curl -s -X POST http://localhost:8001/services/banking-api/routes \
  --data "paths[]=/banking" \
  --data "name=banking-route" | jq .id
```

### Add API Key Authentication

```bash
curl -s -X POST http://localhost:8001/services/banking-api/plugins \
  --data "name=key-auth" | jq .name
```

### Create a consumer and generate API key

```bash
# Create consumer
curl -s -X POST http://localhost:8001/consumers \
  --data username=mobile-banking-app \
  --data custom_id=app-001 | jq .username

# Generate API key
curl -s -X POST http://localhost:8001/consumers/mobile-banking-app/key-auth | jq .key
```

### Add Rate Limiting

```bash
curl -s -X POST http://localhost:8001/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=5" \
  --data "config.policy=local" | jq .name
```

### Test the API

```bash
# Without key — blocked
curl -s http://localhost:8100/banking/users | jq .message

# With key — works
curl -s "http://localhost:8100/banking/users?apikey=YOUR_KEY" | jq '.[0].name'
```

---

## Common Problems & Solutions

### Problem: `ssl handshake failed: certificate host mismatch`

**Root cause:** Wrong certificate CN. Kong Enterprise 3.10 expects `CN=kong_clustering`.

**Fix:** Delete existing certs and regenerate using Kong's own tool:
```bash
rm certs/cluster.crt certs/cluster.key
docker run --rm -v $(pwd)/certs:/app kong/kong-gateway:3.10 sh -c "cd /app && kong hybrid gen_cert"
docker compose down -v && docker compose up -d
```

---

### Problem: `Port 8001 already allocated`

**Root cause:** Another container is using port 8001.

**Fix:**
```bash
sudo lsof -nP -iTCP:8001 -sTCP:LISTEN
docker compose down && docker compose up -d
```

---

### Problem: `temporary failure in name resolution`

**Root cause:** Docker network corrupted from a previous failed start.

**Fix:**
```bash
docker compose down && docker network prune -f && docker compose up -d
```

---

### Problem: Data Planes show empty `[]` after startup

**Fix:** Wait 30–40 seconds after startup for DPs to connect, then check again:
```bash
sleep 40 && curl -s http://localhost:8001/clustering/data-planes | jq .
```

---

## Useful Commands

```bash
# Check all container status
docker compose ps

# Check DP connection to CP
curl -s http://localhost:8001/clustering/data-planes | jq '[.data[] | {hostname, sync_status}]'

# View CP logs
docker logs kong-cp --tail 20

# View DP1 logs
docker logs kong-dp1 --tail 20

# Check Kong version
docker exec kong-cp kong version

# Stop everything
docker compose down

# Stop and wipe all data (fresh start)
docker compose down -v
```

---

## What I Fixed From the Original Repo

The original repo by [pritishpattanaik](https://github.com/pritishpattanaik/kong-310-hybrid-local) had a certificate issue that prevented Data Planes from connecting to the Control Plane.

| Issue | Root Cause | Fix Applied |
|---|---|---|
| `ssl handshake failed: certificate host mismatch` | `generate-certs.sh` was generating certs with `CN=kong-cp` using plain openssl | Replaced with `kong hybrid gen_cert` which generates `CN=kong_clustering` — the CN Kong Enterprise expects internally |
| Missing cluster env vars | `KONG_CLUSTER_SERVER_NAME` pointed to wrong hostname | Updated to `kong_clustering` to match the cert CN |
| `KONG_CLUSTER_TELEMETRY_SERVER_NAME` missing | Not set in original compose file | Added to both dp1 and dp2 |

---

## Author

**Al Adnan Shami**
- Learned and fixed this setup while working on Kong Enterprise hybrid deployments
- Connect on [LinkedIn](https://linkedin.com)
- Questions? Open an issue!

---

## References

- [Kong Hybrid Mode Docs](https://docs.konghq.com/gateway/latest/production/deployment-topologies/hybrid-mode/)
- [decK Documentation](https://docs.konghq.com/deck/latest/)
- [Kong Docker Hub](https://hub.docker.com/r/kong/kong-gateway)
- Original repo: [pritishpattanaik/kong-310-hybrid-local](https://github.com/pritishpattanaik/kong-310-hybrid-local)
