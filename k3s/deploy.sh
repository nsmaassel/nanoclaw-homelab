#!/usr/bin/env bash
# deploy.sh — Deploy Nanoclaw to K3s
# Prerequisites:
#   1. Run k3s/create-db-user.sh to create nanoclaw_reader postgres user
#   2. Run k3s/create-secrets.sh to create K8s secrets
#   3. Image pushed to ACR: maasselacr.azurecr.io/nanoclaw:latest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying Nanoclaw to K3s..."

# Apply manifests in order
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/rbac.yaml"
kubectl apply -f "$SCRIPT_DIR/pvc.yaml"
kubectl apply -f "$SCRIPT_DIR/deployment.yaml"

echo ""
echo "Waiting for rollout..."
kubectl rollout status deployment/nanoclaw -n nanoclaw --timeout=120s

echo ""
echo "✅ Nanoclaw deployed"
echo ""
echo "Verification:"
echo "  kubectl get pods -n nanoclaw"
echo "  kubectl logs -n nanoclaw -l app=nanoclaw -c nanoclaw --tail=30"
echo ""
echo "Send a Telegram message to test connectivity."
