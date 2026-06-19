# 2026-06-19 — Infrastructure + Feature Releases (v0.6.3 + DNS Hotfix)

## Shipped in This Session Window

### v0.6.3 — History Date-Range Filter

**PR:** #127 / **Tag:** v0.6.3-1

- Phone History tab now shows date-range picker (all runs, last 7 days, last 30 days, last 90 days)
- Filters WCMessage run list + HealthKit queries for faster load on large libraries
- Watch persists run history via side-store; phone mirrors via WCSession
- Performance validated on 200+ run library

Shipped to TestFlight 2026-06-19.

### v0.6.2 (earlier in session window)

See `.squad/log/2026-06-18-v0.6.2-strava-scheduling.md`

## Infrastructure Fixes

### Cloudflare Worker Custom Domain Binding (PR #126)

**Issue:** DNS outage on `strava-connect.ar-runner.app` worker domain; Strava OAuth token-exchange requests failing.

**Fix:** Added custom domain binding in Wrangler config + DNS A records at registrar. Worker now routable via custom domain instead of auto-assigned `*.workers.dev`. Resolved intermittent 502/504 errors.

**Impact:** OAuth flow (v0.5.3+) now resilient to Cloudflare DNS churn.

## Related

- `.squad/log/2026-06-19-custom-hud-planning.md` — HUD planning session (v0.6.1 planning)
- Decision: `.squad/decisions.md` § "Recent Decisions (2026-06-18)" for v0.6.2 details
