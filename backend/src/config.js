// Centralised environment config with light validation.

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  databaseUrl: required("DATABASE_URL"),
  apiKey: required("API_KEY"),
  port: Number(process.env.PORT || 3000),
  // Railway/Postgres plugins require SSL; local dev usually does not.
  // Toggle with PGSSL=true if your host needs it.
  pgSsl: process.env.PGSSL === "true",
  nodeEnv: process.env.NODE_ENV || "development",

  // Admin dashboard. Separate credentials from the game's API_KEY (which is
  // shared with Roblox servers). The panel is disabled if ADMIN_PASSWORD is
  // unset. ADMIN_SESSION_SECRET signs session cookies; it falls back to the
  // API_KEY so the panel still works with a single secret in a pinch, but set
  // a dedicated value in production.
  adminPassword: process.env.ADMIN_PASSWORD || "",
  adminSessionSecret:
    process.env.ADMIN_SESSION_SECRET || process.env.API_KEY || "insecure-dev-secret",
};
