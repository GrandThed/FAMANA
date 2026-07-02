// Admin-panel authentication. Deliberately dependency-free: sessions are
// HMAC-signed cookies built with Node's built-in `crypto`, so the panel ships
// with the API and needs no extra npm packages to deploy on Railway.
//
// This is NOT the game's X-Api-Key auth (that secret is shared with Roblox
// servers). Admin access is gated by ADMIN_PASSWORD; see config.js.

import crypto from "node:crypto";
import { config } from "./config.js";

const COOKIE_NAME = "admin_session";
const SESSION_TTL_MS = 8 * 60 * 60 * 1000; // 8 hours

// --- session token: base64url(payload).hmac ---------------------------------

function sign(data) {
  return crypto
    .createHmac("sha256", config.adminSessionSecret)
    .update(data)
    .digest("base64url");
}

export function issueSession() {
  const payload = Buffer.from(JSON.stringify({ exp: Date.now() + SESSION_TTL_MS })).toString(
    "base64url"
  );
  return `${payload}.${sign(payload)}`;
}

function verifySession(token) {
  if (!token || typeof token !== "string") return null;
  const dot = token.indexOf(".");
  if (dot === -1) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);

  const expected = sign(payload);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  try {
    const { exp } = JSON.parse(Buffer.from(payload, "base64url").toString());
    if (typeof exp !== "number" || Date.now() > exp) return null;
    return { exp };
  } catch {
    return null;
  }
}

// --- password check ---------------------------------------------------------

// Constant-time comparison that also tolerates differing lengths.
export function passwordMatches(provided) {
  if (!config.adminPassword) return false; // panel disabled when unset
  if (typeof provided !== "string") return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(config.adminPassword);
  if (a.length !== b.length) {
    // Still burn a comparison to avoid leaking length via timing.
    crypto.timingSafeEqual(b, b);
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

export function adminEnabled() {
  return Boolean(config.adminPassword);
}

// --- cookies ----------------------------------------------------------------

function parseCookies(header) {
  const out = {};
  if (!header) return out;
  for (const part of header.split(";")) {
    const idx = part.indexOf("=");
    if (idx === -1) continue;
    out[part.slice(0, idx).trim()] = decodeURIComponent(part.slice(idx + 1).trim());
  }
  return out;
}

function cookieAttrs(maxAgeSeconds) {
  const parts = ["HttpOnly", "SameSite=Lax", "Path=/", `Max-Age=${maxAgeSeconds}`];
  // Railway terminates TLS in front of us; mark Secure outside local dev.
  if (config.nodeEnv === "production") parts.push("Secure");
  return parts;
}

export function setSessionCookie(reply, token) {
  reply.header(
    "set-cookie",
    [`${COOKIE_NAME}=${token}`, ...cookieAttrs(Math.floor(SESSION_TTL_MS / 1000))].join("; ")
  );
}

export function clearSessionCookie(reply) {
  reply.header("set-cookie", [`${COOKIE_NAME}=`, ...cookieAttrs(0)].join("; "));
}

// --- Fastify guard ----------------------------------------------------------

// preHandler for guarded /admin routes. Rejects requests without a valid,
// unexpired session cookie.
export function requireAdmin(request, reply, done) {
  const cookies = parseCookies(request.headers.cookie);
  const session = verifySession(cookies[COOKIE_NAME]);
  if (!session) {
    reply.code(401).send({ error: "unauthorized" });
    return;
  }
  request.adminSession = session;
  done();
}

// --- login rate limiting (in-memory, per-IP) --------------------------------

const attempts = new Map(); // ip -> { count, resetAt }
const RATE_WINDOW_MS = 15 * 60 * 1000;
const RATE_MAX = 10;

// Records an attempt and returns true if the caller is still under the limit.
export function allowLoginAttempt(ip) {
  const now = Date.now();
  let entry = attempts.get(ip);
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_WINDOW_MS };
    attempts.set(ip, entry);
  }
  entry.count += 1;
  return entry.count <= RATE_MAX;
}

// Clears the counter on a successful login so a good password isn't punished
// for earlier typos.
export function resetLoginAttempts(ip) {
  attempts.delete(ip);
}
