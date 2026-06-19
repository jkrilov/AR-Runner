# strava-connect (Cloudflare Worker)

Proxy worker for Strava OAuth, deployed to `https://strava-connect.ar-runner.app`.

The AR-Runner watchOS / iOS clients call this worker so that the Strava
`client_secret` never has to ship inside the app bundle. The secret lives only
in the Cloudflare Worker environment.

## Endpoints

All endpoints accept `application/json` request bodies and return JSON. CORS is
open (`Access-Control-Allow-Origin: *`).

### `POST /token`
Exchange an authorization `code` for tokens.

```json
{ "code": "...", "client_id": "..." }
```

Forwards to `POST https://www.strava.com/oauth/token` with
`grant_type=authorization_code` and the stored `client_secret`. Returns
Strava's response verbatim (including `access_token`, `refresh_token`,
`expires_at`, and `athlete`).

### `POST /refresh`
Exchange a `refresh_token` for a new access token. Strava access tokens expire
every 6 hours.

```json
{ "refresh_token": "...", "client_id": "..." }
```

Forwards to `POST https://www.strava.com/oauth/token` with
`grant_type=refresh_token`.

### `POST /deauthorize`
Revoke an `access_token`. Invalidates all of the athlete's refresh/access
tokens for this app and removes AR-Runner from their Strava settings.

```json
{ "access_token": "..." }
```

Forwards to `POST https://www.strava.com/oauth/deauthorize` with the token in
the `Authorization: Bearer` header.

## Errors

`400` for missing fields, `404` for unknown paths, `405` for wrong methods on
known paths, `500` for upstream/runtime failures. Body shape:

```json
{ "error": "invalid_request", "message": "client_id is required" }
```

## Deploy

```sh
# one-time: set the Strava client secret in the Worker environment
wrangler secret put STRAVA_CLIENT_SECRET

# deploy
wrangler deploy
```

The hostname `strava-connect.ar-runner.app` is bound as a **Custom Domain**
in `wrangler.toml` (`custom_domain = true`). Cloudflare creates and manages the
proxied DNS record, so `wrangler deploy` (re)provisions DNS automatically — the
host cannot be silently orphaned the way a plain pattern route can if the
worker or its DNS record is removed.

## Local dev

```sh
echo 'STRAVA_CLIENT_SECRET = "..."' > .dev.vars
wrangler dev
```

`.dev.vars` is gitignored.
