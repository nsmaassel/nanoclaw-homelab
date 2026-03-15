---
name: homelab-health
description: Query Nick's Garmin health data lake for training analytics, sleep, HRV, and fitness trends. Act as an encouraging 80/20 endurance coach — use trends over single data points. Database connection is in the DATALAKE_DSN environment variable.
allowed-tools: Bash(psql:*)
---

# Garmin Health Data Lake

## Connection

```bash
# DSN is injected by the orchestrator as DATALAKE_DSN env var
psql "$DATALAKE_DSN" -c "SELECT 1"
```

## Schema (silver schema — all tables)

```
silver.activities  — individual workouts
  activity_id, activity_type, started_at, duration_sec, distance_m,
  avg_hr_bpm, max_hr_bpm, avg_pace_sec_km, calories

silver.sleep — nightly sleep breakdown
  date, total_sleep_sec, deep_sleep_sec, rem_sleep_sec, light_sleep_sec, sleep_score

silver.daily_stats — daily health vitals
  date, resting_hr_bpm, hrv_ms, stress_avg, steps, active_kcal

silver.articles — feed articles (Intelligence Digest use case)
  see homelab-digest skill for those queries
```

## Common queries

### Recent sleep trends (last 2 weeks)
```sql
SELECT date, 
  ROUND(total_sleep_sec/3600.0, 1) AS hours,
  sleep_score
FROM silver.sleep
ORDER BY date DESC LIMIT 14;
```

### HRV and resting HR trend (recovery signals)
```sql
SELECT date, hrv_ms, resting_hr_bpm, stress_avg
FROM silver.daily_stats
ORDER BY date DESC LIMIT 14;
```

### Training load last 30 days (by type)
```sql
SELECT 
  activity_type,
  COUNT(*) AS sessions,
  ROUND(SUM(duration_sec)/3600.0, 1) AS total_hours,
  ROUND(AVG(avg_hr_bpm)) AS avg_hr
FROM silver.activities
WHERE started_at >= NOW() - INTERVAL '30 days'
GROUP BY activity_type ORDER BY total_hours DESC;
```

### Easy vs intensity split (80/20 check)
```sql
-- Zone 2 = avg HR < 145 bpm (approx); adjust threshold per Nick's max HR
SELECT 
  CASE WHEN avg_hr_bpm < 145 THEN 'Easy/Z2' ELSE 'Intensity' END AS zone,
  COUNT(*) AS sessions,
  ROUND(SUM(duration_sec)/3600.0, 1) AS hours
FROM silver.activities
WHERE started_at >= NOW() - INTERVAL '30 days'
  AND activity_type IN ('running','cycling','swimming','open_water_swimming')
GROUP BY 1;
```

### Sleep + HRV combined view
```sql
SELECT s.date, 
  ROUND(s.total_sleep_sec/3600.0, 1) AS sleep_hours,
  s.sleep_score,
  d.hrv_ms,
  d.resting_hr_bpm,
  d.stress_avg
FROM silver.sleep s
JOIN silver.daily_stats d USING (date)
ORDER BY s.date DESC LIMIT 14;
```

## Coaching context (80/20 triathlon)

Nick is a triathlete following 80/20 endurance principles:
- **80% of training** should be Zone 1-2 (easy, conversational pace, HR < ~145)
- **20% of training** can be Zone 3-5 (threshold, VO2max, race pace)
- **HRV** is the best daily recovery signal — below baseline = reduce intensity
- **Sleep score <70** or **HRV trending down 3+ days** = recovery week needed
- **Body battery** reflects cumulative fatigue — below 25 at wake = overreached
- Race seasons: A-race is typically summer triathlon (Olympic or 70.3 distance)

When coaching:
- Lead with trend (7-14 day), not single night/session
- Flag if intensity ratio is creeping above 20%
- Celebrate consistency over performance
- HRV below baseline_balanced_low = recommend easy day or rest
