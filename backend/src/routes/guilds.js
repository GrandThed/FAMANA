import {
  getGuildById,
  getGuildForPlayer,
  createGuild,
  joinGuild,
  kickMember,
  leaveGuild,
  isValidName,
  isValidTag,
} from "../guilds.js";

// Maps a thrown guildError code to an HTTP status. Unknown codes (a bug, not
// a client mistake) fall through to 500 via the caller's try/catch.
const ERROR_STATUS = {
  already_in_guild: 409,
  name_taken: 409,
  not_found: 404,
  not_leader: 403,
  cannot_kick_self: 400,
  target_not_member: 400,
  not_in_guild: 404,
};

function parseId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

// Runs `fn`, translating a thrown guildError into the right HTTP response.
// Returns the resolved value on success so the route can still shape it.
async function handled(reply, fn) {
  try {
    return await fn();
  } catch (err) {
    const status = ERROR_STATUS[err.code];
    if (status) {
      reply.code(status);
      return { __error: err.code };
    }
    throw err;
  }
}

export default async function guildRoutes(fastify) {
  // Guild for a given player, or { guild: null } if they're not in one.
  // Always 200 (no guild is a normal state, not a 404) — the Roblox side
  // calls this on every join and shouldn't have to special-case it.
  fastify.get("/guild/player/:id", async (request, reply) => {
    const id = parseId(request.params.id);
    if (id === null) {
      reply.code(400);
      return { error: "invalid player id" };
    }
    const guild = await getGuildForPlayer(id);
    return { guild };
  });

  fastify.get("/guild/:id", async (request, reply) => {
    const id = parseId(request.params.id);
    if (id === null) {
      reply.code(400);
      return { error: "invalid guild id" };
    }
    const guild = await getGuildById(id);
    if (!guild) {
      reply.code(404);
      return { error: "not_found" };
    }
    return { guild };
  });

  fastify.post("/guild", async (request, reply) => {
    const { leaderId, name, tag } = request.body || {};
    const id = parseId(leaderId);
    if (id === null) {
      reply.code(400);
      return { error: "invalid leader id" };
    }
    if (!isValidName(name)) {
      reply.code(400);
      return { error: "invalid_name" };
    }
    if (!isValidTag(tag)) {
      reply.code(400);
      return { error: "invalid_tag" };
    }

    const result = await handled(reply, () => createGuild(id, name, tag));
    if (result.__error) return { error: result.__error };
    reply.code(201);
    return { guild: result };
  });

  fastify.post("/guild/:id/join", async (request, reply) => {
    const guildId = parseId(request.params.id);
    const playerId = parseId((request.body || {}).playerId);
    if (guildId === null || playerId === null) {
      reply.code(400);
      return { error: "invalid id" };
    }
    const result = await handled(reply, () => joinGuild(guildId, playerId));
    if (result.__error) return { error: result.__error };
    return { guild: result };
  });

  fastify.post("/guild/:id/kick", async (request, reply) => {
    const guildId = parseId(request.params.id);
    const { requesterId, targetId } = request.body || {};
    const reqId = parseId(requesterId);
    const tgtId = parseId(targetId);
    if (guildId === null || reqId === null || tgtId === null) {
      reply.code(400);
      return { error: "invalid id" };
    }
    const result = await handled(reply, () => kickMember(guildId, reqId, tgtId));
    if (result.__error) return { error: result.__error };
    return { guild: result };
  });

  // Guild id in the path is informational/for REST symmetry; the player's
  // actual membership (looked up server-side) is what leaveGuild acts on.
  fastify.post("/guild/:id/leave", async (request, reply) => {
    const playerId = parseId((request.body || {}).playerId);
    if (playerId === null) {
      reply.code(400);
      return { error: "invalid player id" };
    }
    const result = await handled(reply, () => leaveGuild(playerId));
    if (result.__error) return { error: result.__error };
    return result; // { disbanded: true } | { disbanded: false, guild }
  });
}
