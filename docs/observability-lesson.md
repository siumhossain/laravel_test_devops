# Observability lesson: Prometheus, Grafana, Loki, Tempo, Alertmanager

Teaching stack for showing metrics, logs, traces, and alerts flowing out of a
real Laravel app. Run the app on your host machine; everything else
(Prometheus, Grafana, Loki, Promtail, Tempo, Alertmanager, Redis) runs in
Docker.

## Why this shape

Laravel (PHP-FPM or `artisan serve`) kills its process after every request —
nothing survives in memory between requests. So the metrics counters can't
live in a PHP variable; they live in Redis, and every request reads/increments
the shared value there. This is the one non-obvious fact the whole lesson
hangs off of.

## Run it

```bash
# 1. observability stack
docker compose up -d

# 2. the app itself (stays on the host, not in Docker)
php artisan serve --host=0.0.0.0 --port=8000

# 3. generate continuous traffic so the dashboard isn't flat
./docker/generate-traffic.sh
```

Open Grafana: http://localhost:3000 (no login — anonymous admin, dev only).
The "Laravel Overview" dashboard is already there under the Laravel folder.

### Triggering the alerts

Default traffic from `generate-traffic.sh` is healthy on purpose — mostly
`/demo/fast`, some `/demo/variable`, no errors — so both alert rules sit at
`inactive`. To see the full `inactive → pending → firing → resolved`
lifecycle:

```bash
./docker/generate-traffic.sh --break   # mostly errors + slow requests
```

Watch it live at Prometheus's alert page (http://localhost:9090/alerts) or
query it directly:

```bash
curl -s localhost:9090/api/v1/rules | grep -o '"state":"[a-z]*"'
```

Both rules require the condition to hold for `1m` (the `for:` clause) before
they flip from `pending` to `firing` — that delay exists so one noisy request
doesn't page anyone. Firing alerts show up at http://localhost:9093
(Alertmanager). Stop `--break` traffic and the alerts resolve on their own
once the rate window clears.

First boot: Loki and Tempo need ~15-20s after starting before they report
ready (`curl localhost:3100/ready`, `curl localhost:3200/ready`). Panels will
show "no data" until then.

**Port conflict**: if you already run Redis locally on 6379 (Homebrew, another
project), stop it first (`brew services stop redis`) or `docker compose up`
will fail to bind the port.

## What's wired up and what's a stand-in

| Signal | Real | How |
|---|---|---|
| Metrics | Yes | `RecordMetrics` middleware on every request, Redis-backed counters/histograms, scraped by Prometheus every 5s |
| Logs | Yes | Laravel writes to `storage/logs/laravel.log`, Promtail tails it, ships to Loki |
| Traces | Demo only | Tempo is running and wired as a Grafana datasource, but there's no tracing instrumentation in the app — a stock Laravel app doesn't emit OpenTelemetry spans without adding the OTel PHP SDK, which is a separate, heavier lesson. `docker/send-demo-trace.sh` pushes one fake span so students can see the Tempo UI and understand what a trace *would* look like. |
| Alerts | Yes, evaluation only | Two real Prometheus alert rules evaluate against live metrics and genuinely transition `inactive → pending → firing`. Alertmanager routes them to a `null-receiver` — no Slack/email/PagerDuty webhook, since that would mean putting real credentials in a shared teaching repo. Firing state is visible in the Alertmanager UI; wiring a real notification channel is the natural next step, shown but not built. |

## The pieces, file by file

### `app/Http/Middleware/RecordMetrics.php`
Runs on every request. Records two Prometheus metric types:
- **Counter** (`app_http_requests_total`) — only goes up, labeled by method/route/status. Grafana turns it into a rate with `rate(...[1m])`.
- **Histogram** (`app_http_request_duration_seconds`) — buckets request duration so Grafana can compute percentiles (p95) after the fact, not just an average.

Route label uses the route *pattern* (`demo/{id}`), not the resolved URL, so
`/users/1` and `/users/2` collapse into one time series instead of exploding
into thousands ("cardinality explosion" — the #1 way people break Prometheus).

Skips `/metrics` itself via `$request->is('metrics')`, checked on path rather
than route name because this is global middleware and runs before Laravel
has matched the route.

### `app/Providers/AppServiceProvider.php`
Binds `Prometheus\CollectorRegistry` as a singleton backed by Redis
(`promphp/prometheus_client_php` + `predis/predis`, pure-PHP client, no PECL
extension needed). One registry per request, shared storage across requests.

### `bootstrap/app.php`
`/metrics` is registered via the `then:` callback in `withRouting`, which
runs *outside* the `web` middleware group — no session, no CSRF, no cookies.
Prometheus is a dumb scraper; it shouldn't be creating a session row in the
database every 5 seconds forever.

### `routes/web.php`
Four demo routes under `/demo`, each shaped to teach a different panel:
- `/demo/fast` — near-zero latency, all samples in the lowest histogram bucket.
- `/demo/slow` — sleeps 300-800ms, clusters mid-range so it visibly reads "slow" in Grafana.
- `/demo/variable` — sleeps 10ms-1.2s, spans almost every bucket so avg and p95 diverge (p95 is what shows tail latency an average hides).
- `/demo/error` — always 500s and logs an error, so both the error-rate panel and the logs panel light up together.

### `docker-compose.yml` + `docker/*/`
- **prometheus.yml** — scrapes `host.docker.internal:8000/metrics` every 5s. `host.docker.internal` is Docker's DNS name for "the machine running Docker" — `localhost` from inside a container means the container itself. Also loads `alert-rules.yml` and points at Alertmanager.
- **prometheus/alert-rules.yml** — two rules: `HighErrorRate` (5xx ratio > 5%) and `SlowP95Latency` (p95 > 500ms), each with `for: 1m` so a single blip doesn't fire an alert — the condition has to hold continuously first.
- **alertmanager.yml** — receives firing alerts from Prometheus (a push, unlike Prometheus's own pull-based scraping) and routes them. Receiver is a no-op (`null-receiver`) on purpose — see the Alerts row above.
- **loki.yml** — single-node config, filesystem storage, no clustering. Loki stores and indexes log lines; it doesn't read files itself.
- **promtail.yml** — the log shipper. Tails `storage/logs/*.log` (mounted read-only from the repo) and pushes to Loki.
- **tempo.yml** — trace storage + OTLP receiver, explicitly bound to `0.0.0.0` (Tempo's default binds to `localhost` inside the container, which Docker's port publishing can't reach).
- **grafana/provisioning/** — datasources and the dashboard are auto-loaded on boot from these files; nobody has to click through "Add data source" by hand. Datasource `uid:` values are pinned (`prometheus`, `loki`, `tempo`) so the dashboard JSON's panel references resolve.

## PromQL used in the dashboard

```promql
# requests per second, by route — a counter can't be charted raw, only its rate
sum(rate(app_http_requests_total[1m])) by (route)

# average response time — sum/count is the standard Prometheus average pattern
sum(rate(app_http_request_duration_seconds_sum[1m])) by (route)
  / sum(rate(app_http_request_duration_seconds_count[1m])) by (route)

# p95 — reads the histogram buckets and interpolates; this is *why* you use a
# histogram instead of just tracking sum/count
histogram_quantile(0.95,
  sum(rate(app_http_request_duration_seconds_bucket[1m])) by (le, route))

# error ratio
sum(rate(app_http_requests_total{status=~"5.."}[1m]))
  / sum(rate(app_http_requests_total[1m]))
```

## Alert rules

```yaml
# fires when the aggregate 5xx ratio holds above 5% for a full minute
- alert: HighErrorRate
  expr: sum(rate(app_http_requests_total{status=~"5.."}[2m]))
      / sum(rate(app_http_requests_total[2m])) > 0.05
  for: 1m

# fires when p95 latency holds above 500ms for a full minute
- alert: SlowP95Latency
  expr: histogram_quantile(0.95,
      sum(rate(app_http_request_duration_seconds_bucket[2m])) by (le)) > 0.5
  for: 1m
```

Same `histogram_quantile` and `rate` patterns as the dashboard panels — an
alert rule is just a PromQL query Prometheus re-checks on its own schedule
and remembers the state of.

## Teardown

```bash
docker compose down       # stop, keep data (grafana dashboards/state)
docker compose down -v    # stop, wipe everything (fresh start next time)
```
