// Admin dashboard: serves the single-page panel and its JSON API.
//
// Route layout (see docs/ADMIN_DASHBOARD.md):
//   GET  /admin            -> SPA shell (public; the app shows a login screen
//                             until /admin/login sets a session cookie)
//   POST /admin/login      -> password -> session cookie (public, rate-limited)
//   POST /admin/logout     -> clear session
//   everything else under /admin/* requires a valid session.

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  adminEnabled,
  passwordMatches,
  issueSession,
  setSessionCookie,
  clearSessionCookie,
  requireAdmin,
  allowLoginAttempt,
  resetLoginAttempts,
} from "../adminAuth.js";
import {
  getStats,
  listPlayers,
  getPlayerDetail,
  getItemCatalog,
  updatePlayer,
  updateProgress,
  adminAddItem,
  adminRemoveItem,
  clearInventory,
  deletePlayer,
} from "../adminService.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const INDEX_HTML_PATH = join(__dirname, "..", "..", "admin-web", "index.html");

// Load the SPA shell once at boot; keep a cached copy.
let indexHtml = null;
async function getIndexHtml(request) {
  if (indexHtml === null) {
    try {
      indexHtml = await readFile(INDEX_HTML_PATH, "utf8");
    } catch (err) {
      request.log.error(err, "admin: failed to read admin-web/index.html");
      indexHtml = "<h1>Admin panel assets missing</h1>";
    }
  }
  return indexHtml;
}

function parsePlayerId(request, reply) {
  const id = Number(request.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    reply.code(400).send({ error: "invalid player id" });
    return null;
  }
  return id;
}

export default async function adminRoutes(fastify) {
  // --- SPA shell (public) ---------------------------------------------------
  fastify.get("/admin", async (request, reply) => {
    reply.type("text/html; charset=utf-8");
    return getIndexHtml(request);
  });

  // --- auth (public, rate-limited) ------------------------------------------
  fastify.post("/admin/login", async (request, reply) => {
    if (!adminEnabled()) {
      reply.code(503);
      return { error: "admin_disabled" };
    }
    if (!allowLoginAttempt(request.ip)) {
      reply.code(429);
      return { error: "too_many_attempts" };
    }
    const { password } = request.body || {};
    if (!passwordMatches(password)) {
      reply.code(401);
      return { error: "invalid_credentials" };
    }
    resetLoginAttempts(request.ip);
    setSessionCookie(reply, issueSession());
    return { ok: true };
  });

  fastify.post("/admin/logout", async (request, reply) => {
    clearSessionCookie(reply);
    return { ok: true };
  });

  // --- guarded API ----------------------------------------------------------
  await fastify.register(async (instance) => {
    instance.addHook("preHandler", requireAdmin);

    // Lets the SPA confirm the session on load.
    instance.get("/admin/me", async () => ({ ok: true }));

    instance.get("/admin/stats", async () => getStats());

    instance.get("/admin/items", async () => ({ items: getItemCatalog() }));

    instance.get("/admin/players", async (request) => {
      const { query, cell, limit, offset, sort } = request.query || {};
      return listPlayers({ query, cell, limit, offset, sort });
    });

    instance.get("/admin/players/:id", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      const player = await getPlayerDetail(id);
      if (!player) {
        reply.code(404);
        return { error: "not_found" };
      }
      return player;
    });

    instance.patch("/admin/players/:id", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      try {
        const ok = await updatePlayer(id, request.body || {}, request.ip);
        if (!ok) {
          reply.code(404);
          return { error: "not_found" };
        }
        return getPlayerDetail(id);
      } catch (err) {
        if (err.code === "bad_field" || err.code === "no_fields") {
          reply.code(400);
          return { error: err.code, field: err.field };
        }
        throw err;
      }
    });

    // Gold / level / xp / class — pushed live to online players via the
    // player_events queue (kind "stats").
    instance.patch("/admin/players/:id/progress", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      try {
        const result = await updateProgress(id, request.body || {}, request.ip);
        if (!result) {
          reply.code(404);
          return { error: "not_found" };
        }
        return result;
      } catch (err) {
        if (err.code === "bad_field" || err.code === "no_fields") {
          reply.code(400);
          return { error: err.code, field: err.field };
        }
        throw err;
      }
    });

    instance.post("/admin/players/:id/items", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      const { itemId, quantity } = request.body || {};
      try {
        const result = await adminAddItem(id, itemId, Number(quantity), request.ip);
        if (!result) {
          reply.code(404);
          return { error: "not_found" };
        }
        return result;
      } catch (err) {
        if (err.code === "no_room") {
          reply.code(409);
          return { error: "no_room", added: err.added };
        }
        if (err.code === "unknown_item" || err.code === "bad_quantity") {
          reply.code(400);
          return { error: err.code };
        }
        throw err;
      }
    });

    instance.delete("/admin/players/:id/items", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      const { itemId, quantity } = request.body || {};
      try {
        const result = await adminRemoveItem(id, itemId, Number(quantity), request.ip);
        if (!result) {
          reply.code(404);
          return { error: "not_found" };
        }
        return result;
      } catch (err) {
        if (err.code === "insufficient") {
          reply.code(409);
          return { error: "insufficient" };
        }
        if (err.code === "bad_quantity") {
          reply.code(400);
          return { error: err.code };
        }
        throw err;
      }
    });

    instance.delete("/admin/players/:id/inventory", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      const result = await clearInventory(id, request.ip);
      if (!result) {
        reply.code(404);
        return { error: "not_found" };
      }
      return result;
    });

    instance.delete("/admin/players/:id", async (request, reply) => {
      const id = parsePlayerId(request, reply);
      if (id === null) return;
      const ok = await deletePlayer(id, request.ip);
      if (!ok) {
        reply.code(404);
        return { error: "not_found" };
      }
      return { deleted: true };
    });
  });
}
