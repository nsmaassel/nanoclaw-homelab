#!/usr/bin/env bash
# create-secrets.sh — Create K8s secrets for Nanoclaw
# Run this once after creating the namespace. Values come from environment or prompts.
set -euo pipefail

NAMESPACE=nanoclaw

echo "Creating nanoclaw secrets in namespace: $NAMESPACE"

# ── Source homelab .env for shared secrets ──────────────────────────────────
HOMELAB_ENV="$HOME/homelab/.env"
if [[ -f "$HOMELAB_ENV" ]]; then
  export $(grep -v '^#' "$HOMELAB_ENV" | xargs)
fi

# ── Telegram (reuse existing n8n-telegram values) ────────────────────────────
TELEGRAM_BOT_TOKEN_B64=$(kubectl get secret n8n-telegram -n n8n \
  -o jsonpath='{.data.TELEGRAM_BOT_TOKEN}')
TELEGRAM_CHAT_ID_B64=$(kubectl get secret n8n-telegram -n n8n \
  -o jsonpath='{.data.TELEGRAM_CHAT_ID}')

# ── Anthropic API key ────────────────────────────────────────────────────────
ANTHROPIC_B64=$(kubectl get secret n8n-secrets -n n8n \
  -o jsonpath='{.data.ANTHROPIC_API_KEY}' 2>/dev/null || \
  echo -n "${ANTHROPIC_API_KEY:-}" | base64 -w0)

# ── Discord webhook (same alerts channel as n8n) ─────────────────────────────
DISCORD_B64=$(kubectl get secret n8n-secrets -n n8n \
  -o jsonpath='{.data.DISCORD_WEBHOOK_ALERTS}')

# ── nanoclaw-secrets ─────────────────────────────────────────────────────────
kubectl create secret generic nanoclaw-secrets \
  --namespace="$NAMESPACE" \
  --from-literal=TELEGRAM_BOT_TOKEN="$(echo "$TELEGRAM_BOT_TOKEN_B64" | base64 -d)" \
  --from-literal=TELEGRAM_CHAT_ID="$(echo "$TELEGRAM_CHAT_ID_B64" | base64 -d)" \
  --from-literal=ANTHROPIC_API_KEY="$(echo "$ANTHROPIC_B64" | base64 -d)" \
  --from-literal=DISCORD_WEBHOOK_URL="$(echo "$DISCORD_B64" | base64 -d)" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ nanoclaw-secrets created"

# ── nanoclaw-db (Postgres read-only DSN) ─────────────────────────────────────
# Requires nanoclaw_reader user to exist in data_lake DB (run create-db-user.sh first)
POSTGRES_IP=$(kubectl get svc postgres -n data-lake \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.43.0.1")

DB_PASSWORD="${NANOCLAW_DB_PASSWORD:-}"
if [[ -z "$DB_PASSWORD" ]]; then
  echo "Enter nanoclaw_reader postgres password (set in create-db-user.sh):"
  read -s DB_PASSWORD
fi

kubectl create secret generic nanoclaw-db \
  --namespace="$NAMESPACE" \
  --from-literal=DATALAKE_READONLY_DSN="postgresql://nanoclaw_reader:${DB_PASSWORD}@${POSTGRES_IP}:5432/data_lake" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ nanoclaw-db created"

# ── ACR pull secret (copy from helldivers namespace) ─────────────────────────
kubectl get secret acr-pull-secret -n helldivers -o json \
  | python3 -c "
import json, sys
s = json.load(sys.stdin)
s['metadata']['namespace'] = 'nanoclaw'
del s['metadata']['resourceVersion']
del s['metadata']['uid']
del s['metadata']['creationTimestamp']
print(json.dumps(s))
" | kubectl apply -f -

echo "✅ acr-pull-secret copied to nanoclaw namespace"
echo ""
echo "All secrets created. Deploy with: kubectl apply -f k3s/"
