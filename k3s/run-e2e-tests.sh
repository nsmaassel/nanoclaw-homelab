#!/usr/bin/env bash
# run-e2e-tests.sh — Run the Nanoclaw agent e2e test Job and stream results
set -euo pipefail

NAMESPACE=nanoclaw
JOB_NAME=nanoclaw-e2e-test
MANIFEST="$(dirname "$0")/e2e-test-job.yaml"

# Delete any previous run
kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true
# Wait for full deletion
kubectl wait --for=delete job/"$JOB_NAME" -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

echo "Starting e2e test job..."
kubectl apply -f "$MANIFEST"

# Wait for pod to appear
echo "Waiting for pod..."
until kubectl get pods -n "$NAMESPACE" -l "job-name=$JOB_NAME" --no-headers 2>/dev/null | grep -q .; do
  sleep 1
done

POD=$(kubectl get pods -n "$NAMESPACE" -l "job-name=$JOB_NAME" -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"
echo ""

# Wait for init container then stream logs
kubectl wait pod "$POD" -n "$NAMESPACE" --for=condition=Initialized --timeout=60s 2>/dev/null || true
kubectl logs -n "$NAMESPACE" "$POD" -c e2e-test -f 2>/dev/null || \
  kubectl logs -n "$NAMESPACE" "$POD" -f

# Get final job status
echo ""
if kubectl wait job/"$JOB_NAME" -n "$NAMESPACE" --for=condition=complete --timeout=120s 2>/dev/null; then
  echo "✅ E2E tests PASSED"
  exit 0
else
  echo "❌ E2E tests FAILED"
  kubectl describe job "$JOB_NAME" -n "$NAMESPACE" | tail -20
  exit 1
fi
