// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0
//
// strava-connect.ar-runner.app
//
// Cloudflare Worker that proxies Strava OAuth calls so the watchOS / iOS
// clients never have to ship the STRAVA_CLIENT_SECRET. The secret lives only
// in the Worker environment (set via `wrangler secret put STRAVA_CLIENT_SECRET`).
//
// Endpoints:
//   POST /token        — authorization_code exchange
//   POST /refresh      — refresh_token exchange
//   POST /deauthorize  — revoke an access_token (removes app from athlete settings)

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";
const STRAVA_DEAUTH_URL = "https://www.strava.com/oauth/deauthorize";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
      ...extraHeaders,
    },
  });
}

function errorResponse(error, message, status) {
  return jsonResponse({ error, message }, status);
}

async function readJsonBody(request) {
  try {
    return await request.json();
  } catch (_e) {
    return null;
  }
}

async function forwardStravaResponse(stravaResp) {
  const text = await stravaResp.text();
  let parsed;
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch (_e) {
    parsed = { error: "upstream_invalid_json", raw: text };
  }
  return jsonResponse(parsed, stravaResp.status);
}

async function handleToken(request, env) {
  const body = await readJsonBody(request);
  if (!body) {
    return errorResponse("invalid_request", "request body must be JSON", 400);
  }
  const { code, client_id } = body;
  if (!client_id) {
    return errorResponse("invalid_request", "client_id is required", 400);
  }
  if (!code) {
    return errorResponse("invalid_request", "code is required", 400);
  }

  const form = new URLSearchParams({
    client_id: String(client_id),
    client_secret: env.STRAVA_CLIENT_SECRET,
    code: String(code),
    grant_type: "authorization_code",
  });

  const resp = await fetch(STRAVA_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  return forwardStravaResponse(resp);
}

async function handleRefresh(request, env) {
  const body = await readJsonBody(request);
  if (!body) {
    return errorResponse("invalid_request", "request body must be JSON", 400);
  }
  const { refresh_token, client_id } = body;
  if (!client_id) {
    return errorResponse("invalid_request", "client_id is required", 400);
  }
  if (!refresh_token) {
    return errorResponse("invalid_request", "refresh_token is required", 400);
  }

  const form = new URLSearchParams({
    client_id: String(client_id),
    client_secret: env.STRAVA_CLIENT_SECRET,
    refresh_token: String(refresh_token),
    grant_type: "refresh_token",
  });

  const resp = await fetch(STRAVA_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  return forwardStravaResponse(resp);
}

async function handleDeauthorize(request, _env) {
  const body = await readJsonBody(request);
  if (!body) {
    return errorResponse("invalid_request", "request body must be JSON", 400);
  }
  const { access_token } = body;
  if (!access_token) {
    return errorResponse("invalid_request", "access_token is required", 400);
  }

  const resp = await fetch(STRAVA_DEAUTH_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${access_token}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
  });
  return forwardStravaResponse(resp);
}

const ROUTES = {
  "/token": { POST: handleToken },
  "/refresh": { POST: handleRefresh },
  "/deauthorize": { POST: handleDeauthorize },
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/$/, "") || "/";

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const route = ROUTES[path];
    if (!route) {
      return errorResponse("not_found", `no route for ${path}`, 404);
    }

    const handler = route[request.method];
    if (!handler) {
      return errorResponse(
        "method_not_allowed",
        `${request.method} not allowed on ${path}`,
        405,
      );
    }

    try {
      return await handler(request, env);
    } catch (err) {
      return errorResponse(
        "internal_error",
        err && err.message ? err.message : "unexpected error",
        500,
      );
    }
  },
};
