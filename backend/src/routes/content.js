import { content } from "../content.js";

// Game-content defs (items, starter kit, grid dims, equipment slots).
// Registered behind X-Api-Key: only Roblox servers consume it.
export default async function contentRoutes(fastify) {
  fastify.get("/content", async () => content);
}
