---
name: homelab-monitoring
description: Query Prometheus metrics and Alertmanager alerts for the homelab. Use for trend analysis, alert history, resource usage over time, and diagnosing what led up to an incident.
allowed-tools: Bash(curl:*)
---

# Homelab Monitoring Stack

## Endpoints (reachable from inside the cluster)

| Service | NodePort | Cluster DNS |
|---------|----------|-------------|
| Prometheus | `http://100.125.77.112:30090` | `http://prometheus.monitoring.svc.cluster.local:9090` |
| Alertmanager | `http://100.125.77.112:30093` | `http://alertmanager.monitoring.svc.cluster.local:9093` |
| Grafana | `http://100.125.77.112:30050` | `http://grafana.monitoring.svc.cluster.local:3000` |

Use the NodePort URLs (100.125.77.112 = beelink) — cluster DNS may not resolve from DinD.

## Prometheus: instant query

```bash
curl -sG 'http://100.125.77.112:30090/api/v1/query' \
  --data-urlencode 'query=up' | python3 -m json.tool
```

## Prometheus: range query (trends over time)

```bash
# Last 1 hour, 5-minute step
curl -sG 'http://100.125.77.112:30090/api/v1/query_range' \
  --data-urlencode 'query=node_memory_MemAvailable_bytes' \
  --data-urlencode 'start=1h' \
  --data-urlencode 'end=now' \
  --data-urlencode 'step=5m' | python3 -m json.tool
```

## Useful queries

### Node health
```
up{job="node_exporter"}                    # which nodes are up
node_load1                                  # 1-min load average
node_memory_MemAvailable_bytes              # available RAM
(node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100  # disk % free
```

### K3s pods
```
kube_pod_status_phase{phase!="Running",phase!="Succeeded"}  # unhealthy pods
kube_deployment_status_replicas_unavailable > 0              # unavailable deployments
```

### Temperature / home comfort sensors
```
dht22_temperature_celsius                   # room temps by instance
dht22_humidity_percent                      # humidity
```

### n8n workflows
```
up{job="n8n"}                              # n8n availability
```

## Alertmanager: current active alerts

```bash
curl -s 'http://100.125.77.112:30093/api/v2/alerts?active=true' \
  | python3 -c "import json,sys; alerts=json.load(sys.stdin); [print(a['labels']['alertname'], a['labels'].get('instance',''), a['startsAt']) for a in alerts]"
```

## Alertmanager: alert history (recent resolved)

```bash
curl -s 'http://100.125.77.112:30093/api/v2/alerts?active=false&silenced=false' \
  | python3 -m json.tool | head -100
```

## Workflow: diagnose what led up to an alert

1. Check active alerts: `curl .../alertmanager/api/v2/alerts?active=true`
2. Note the `alertname` and `instance`
3. Query the relevant metric over the last 2h range in Prometheus
4. Look for the inflection point — when did it cross the threshold?
5. Correlate with other metrics (memory pressure → OOM → pod crash)
6. Report timeline summary to Nick

## Alert groups (from alerting rules)

| Group | What fires |
|-------|-----------|
| `instance` | Node/exporter down |
| `disk` | >85% or >95% disk usage |
| `cpu` | Sustained high CPU |
| `memory` | Low available memory |
| `home-comfort` | Temp/humidity out of range |
| `synthetic` | HTTP probe failures (external sites, internal services) |
| `kubernetes` | Unavailable pods/deployments |
