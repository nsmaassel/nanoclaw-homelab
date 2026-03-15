---
name: homelab-k8s
description: Inspect and operate the homelab K3s cluster — get pod status, logs, node resources, describe workloads, and safely restart deployments. Always diagnose before suggesting fixes. Use read-only kubeconfig by default; switch to operator only when restarting.
allowed-tools: Bash(kubectl:*)
---

# Homelab K3s Operations

## Kubeconfigs

Always set KUBECONFIG before running kubectl:

```bash
# Read-only (default — use for all inspection)
export KUBECONFIG=/workspace/group/kubeconfig-readonly.yaml

# Operator (only for restarts/applies)
export KUBECONFIG=/workspace/group/kubeconfig-operator.yaml
```

## Quick cluster health check

```bash
export KUBECONFIG=/workspace/group/kubeconfig-readonly.yaml
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
```

## Key namespaces

| Namespace | What's there |
|-----------|-------------|
| `monitoring` | Prometheus (:30090), Grafana (:30050), Alertmanager (:30093), Blackbox |
| `n8n` | n8n workflow automation (:5678) |
| `nanoclaw` | YOU — orchestrator + DinD sidecar |
| `kube-system` | CoreDNS, Traefik, NFS provisioner |

## Common diagnostics

### Pod not running
```bash
export KUBECONFIG=/workspace/group/kubeconfig-readonly.yaml
kubectl describe pod -n <namespace> <pod>
kubectl logs -n <namespace> <pod> --previous   # crashed container
kubectl logs -n <namespace> <pod> --tail=50
```

### Node resources
```bash
kubectl top nodes    # CPU/mem usage
kubectl top pods -A  # per-pod usage
```

### Events (recent cluster activity)
```bash
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

### Deployment rollout status
```bash
kubectl rollout status deployment/<name> -n <namespace>
kubectl rollout history deployment/<name> -n <namespace>
```

## Safe restarts (operator kubeconfig)

```bash
export KUBECONFIG=/workspace/group/kubeconfig-operator.yaml
kubectl rollout restart deployment/<name> -n <namespace>
```

## Nodes

| Node | Role | Notable |
|------|------|---------|
| `beelink` | control-plane | YOU run here |
| `tower` | agent | Prometheus, Grafana, NFS provisioner |
| `nick-blade-ubuntu` | agent | GPU (nvidia), Home Assistant |

## Workflow: diagnose a failing pod

1. `kubectl get pods -A` — identify the pod and its state
2. `kubectl describe pod -n <ns> <pod>` — check Events section for root cause
3. `kubectl logs -n <ns> <pod> --previous` — if CrashLoopBackOff
4. Check resource limits: OOMKilled = memory limit too low
5. Check PVC status if volume-related: `kubectl get pvc -n <ns>`
6. Report findings to Nick, ask before restarting
