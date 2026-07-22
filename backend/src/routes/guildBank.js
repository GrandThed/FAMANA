import { getBank, getBankLog, depositItem, withdrawItem } from "../guildBank.js";

const ERROR_STATUS = {
  not_member: 403,
  not_authorized: 403,
  guild_not_found: 404,
  unknown_item: 400,
  insufficient: 409,
  no_room: 409,
  bad_quantity: 400,
};

function parseId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function parseQuantity(value) {
  const qty = Number(value);
  return Number.isInteger(qty) && qty > 0 ? qty : null;
}

async function handleTransfer(reply, fn) {
  try {
    return await fn();
  } catch (err) {
    const status = ERROR_STATUS[err.code] || 500;
    reply.code(status);
    return { error: err.code || "error" };
  }
}

export default async function guildBankRoutes(fastify) {
  fastify.get("/guild/:id/bank", async (request, reply) => {
    const guildId = parseId(request.params.id);
    if (guildId === null) {
      reply.code(400);
      return { error: "invalid_guild_id" };
    }
    const items = await getBank(guildId);
    return { items };
  });

  fastify.get("/guild/:id/bank/log", async (request, reply) => {
    const guildId = parseId(request.params.id);
    if (guildId === null) {
      reply.code(400);
      return { error: "invalid_guild_id" };
    }
    const entries = await getBankLog(guildId);
    return { entries };
  });

  fastify.post("/guild/:id/bank/deposit", async (request, reply) => {
    const guildId = parseId(request.params.id);
    const { playerId, itemId, quantity } = request.body || {};
    const pId = parseId(playerId);
    const qty = parseQuantity(quantity);
    if (guildId === null || pId === null || typeof itemId !== "string" || qty === null) {
      reply.code(400);
      return { error: "invalid_request" };
    }
    return handleTransfer(reply, () => depositItem(guildId, pId, itemId, qty));
  });

  fastify.post("/guild/:id/bank/withdraw", async (request, reply) => {
    const guildId = parseId(request.params.id);
    const { playerId, itemId, quantity } = request.body || {};
    const pId = parseId(playerId);
    const qty = parseQuantity(quantity);
    if (guildId === null || pId === null || typeof itemId !== "string" || qty === null) {
      reply.code(400);
      return { error: "invalid_request" };
    }
    return handleTransfer(reply, () => withdrawItem(guildId, pId, itemId, qty));
  });
}
