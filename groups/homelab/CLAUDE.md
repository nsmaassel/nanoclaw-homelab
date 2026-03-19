# Homelab Group — K3s Monitoring & Health Coaching

This group has access to the homelab K3s cluster, data lake, and monitoring stack.

## Environment Setup

`jq` is not pre-installed. Install it before running monitoring queries:
```bash
apt-get install -y jq -q 2>/dev/null
```
Or use `python3 -c "import json,sys; data=json.load(sys.stdin); ..."` as an alternative.

## Cluster Topology

| Node | Role | IP | Notes |
|------|------|----|-------|
| beelink | control-plane | 100.125.77.112 | Where nanoclaw runs |
| tower | worker | 100.73.171.55 | Monitoring stack |
| nick-blade-ubuntu | worker | — | GPU (nvidia), media services |

**NFS Storage**: Synology NAS at `192.168.1.2` (`nfs-synology` StorageClass)

## Key Services

| Service | Cluster DNS | External |
|---------|-------------|----------|
| Prometheus | `prometheus.monitoring.svc.cluster.local:9090` | `:30090` |
| Alertmanager | `alertmanager.monitoring.svc.cluster.local:9093` | `:30093` |
| Grafana | `grafana.monitoring.svc.cluster.local:3000` | `:30050` |
| n8n | `n8n.n8n.svc.cluster.local:5678` | `:5678` |

## Monitoring Queries

```bash
# Active alerts right now
curl -s http://alertmanager.monitoring.svc.cluster.local:9093/api/v1/alerts | \
  jq '.data[] | select(.status.state=="active") | {name: .labels.alertname, severity: .labels.severity, summary: .annotations.summary}'

# CPU usage by node (last 5 min)
curl -s 'http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=100-(avg+by(instance)(rate(node_cpu_seconds_total%7Bmode%3D"idle"%7D%5B5m%5D))*100)' | \
  jq '.data.result[] | {node: .metric.instance, cpu_pct: (.value[1] | tonumber | . * 100 | round / 100)}'

# Memory by pod (top 10)
curl -s 'http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=sort_desc(container_memory_working_set_bytes%7Bcontainer!%3D""%7D)&limit=10' | \
  jq '.data.result[:10][] | {pod: .metric.pod, ns: .metric.namespace, mb: (.value[1] | tonumber / 1048576 | round)}'
```

## Data Lake Schema Reference

**Connection**: `psql "$DATALAKE_READONLY_DSN"`

### Health & Fitness Tables
```sql
-- Recent activities (runs, bikes, swims)
SELECT date, activity_type, distance_km, duration_min, avg_hr, training_stress_score
FROM silver.activities
WHERE date >= NOW() - INTERVAL '30 days'
ORDER BY date DESC;

-- Daily HRV + body metrics
SELECT date, hrv_status, avg_stress, body_battery_high, resting_heart_rate, steps
FROM silver.daily_stats
WHERE date >= NOW() - INTERVAL '14 days'
ORDER BY date DESC;

-- Sleep quality
SELECT date, duration_hours, sleep_score, deep_sleep_min, rem_sleep_min, light_sleep_min, avg_stress
FROM silver.sleep
WHERE date >= NOW() - INTERVAL '14 days'
ORDER BY date DESC;
```

### Content & Digest Tables
```sql
-- Recent articles from feeds
SELECT title, source, published_at, category, url
FROM silver.articles
WHERE published_at >= NOW() - INTERVAL '7 days'
ORDER BY published_at DESC;

-- Latest weekly synthesis
SELECT created_at, executive_summary, top_themes, model_used
FROM gold.synthesis_reports
ORDER BY created_at DESC LIMIT 3;
```

## Autonomy Model

### Tier 1 — Read, Never Confirm
```bash
kubectl get pods -A
kubectl describe pod <name> -n <ns>
kubectl logs <name> -n <ns> --tail=100
kubectl top nodes
kubectl top pods -A
kubectl get events -n <ns> --sort-by='.lastTimestamp'
kubectl get cronjob -A
kubectl describe cronjob <name> -n <ns>
curl <prometheus|alertmanager-url>   # read queries only
psql "$DATALAKE_READONLY_DSN" -c "SELECT ..."
```

### Tier 2 — Propose First, Execute After "yes, go ahead"

Always explain *what* you found and *why* before proposing. Format:
> "I found [problem]. To fix it, I'd [action]. This is [recoverable/reversible] because [reason]. Want me to do it?"

```bash
# Safe restart (K8s recreates pod)
kubectl rollout restart deployment/<name> -n <ns>
# Kill stuck pod (K8s recreates via ReplicaSet)
kubectl delete pod <name> -n <ns>
# Manually trigger a CronJob run
kubectl create job --from=cronjob/<name> manual-$(date +%s) -n <ns>
```

### Never
- `kubectl delete deployment/statefulset/namespace/pvc`
- `kubectl apply -f ...` (draft YAML diffs only, user applies)
- Modify Prometheus/Alertmanager/n8n configs
- Access K8s secrets

## 80/20 Training Methodology

The owner follows Matt Fitzgerald's **80/20 Endurance** approach:
- **Zone 1-2** (low intensity, <75% max HR): target ~80% of weekly volume
- **Zone 3-5** (threshold and above): target ~20% of weekly volume
- **Training Stress Score (TSS)**: tracks cumulative load (sweet spot: 40–60 TSS/day sustainable)
- **Recovery indicators**: HRV status ("Balanced" or "High" = ready; "Low" = rest day)
- **Acute-to-Chronic Workload Ratio (ACWR)**: stays 0.8–1.3 = healthy ramp rate

### Coaching Response Template
When answering training questions:
1. State current trend (last 7 days of HRV, resting HR)
2. State recent load (TSS from last 3 activities)
3. State sleep quality correlation
4. Give specific recommendation based on 80/20 principles
5. Quantify: "I'd suggest [easy 45 min Zone 2 run] tomorrow rather than your planned tempo"

## Common Workflows

### "Why is [pod] crashing?"
1. `kubectl describe pod <name> -n <ns>` — check Events, Last State exit code
2. `kubectl logs <name> -n <ns> --previous` — crash logs
3. Check OOMKilled → memory limit too low → draft patch
4. Check CrashLoopBackOff + exit 1 → check app logs for error message
5. Check ImagePullBackOff → ACR auth issue (check `acr-pull-secret` exists in namespace)

### "How was my [sleep/training/recovery] recently?"
1. Query `silver.sleep` or `silver.daily_stats` for last 14 days
2. Calculate trends (use SQL AVG, LAG for week-over-week)
3. Apply 80/20 context to interpret
4. Give specific recommendation

### "What CronJobs failed recently?"
```bash
kubectl get jobs -A --sort-by='.metadata.creationTimestamp' | tail -20
# For a specific namespace
kubectl get jobs -n data-lake -o json | \
  jq '.items[] | select(.status.failed>0) | {name: .metadata.name, failed: .status.failed}'
```
