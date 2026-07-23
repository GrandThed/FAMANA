// Guild persistence: create/join/kick/leave, all transactional. Roster reads
// join players for usernames (guild_members has no username of its own).
//
// A player belongs to at most one guild — enforced at the DB level by
// guild_members.player_id being a PRIMARY KEY (see schema.sql), not just
// application logic, so a race between two concurrent "create"/"join" calls
// for the same player can't slip through.

import { pool, withTransaction } from "./db.js";

const NAME_RE = /^[\p{L}0-9 '_-]{3,24}$/u;
const TAG_RE = /^[\p{L}0-9]{2,5}$/u;

export function isValidName(name) {
  return typeof name === "string" && NAME_RE.test(name.trim());
}

export function isValidTag(tag) {
  return typeof tag === "string" && TAG_RE.test(tag.trim());
}

function guildError(code) {
  return Object.assign(new Error(code), { code });
}

async function fetchMembers(db, guildId) {
  const { rows } = await db.query(
    `SELECT m.player_id, p.username, m.joined_at, m.role
       FROM guild_members m
       JOIN players p ON p.id = m.player_id
      WHERE m.guild_id = $1
      ORDER BY m.joined_at ASC`,
    [guildId]
  );
  return rows.map((r) => ({
    playerId: String(r.player_id),
    username: r.username,
    joinedAt: r.joined_at,
    role: r.role,
  }));
}

function rowToGuild(row, members) {
  return {
    id: String(row.id),
    name: row.name,
    tag: row.tag,
    leaderId: String(row.leader_id),
    createdAt: row.created_at,
    members,
  };
}

async function fetchGuildRow(db, guildId) {
  const { rows } = await db.query(`SELECT * FROM guilds WHERE id = $1`, [guildId]);
  return rows[0] || null;
}

// Full guild (with roster) by id, or null.
export async function getGuildById(guildId) {
  const row = await fetchGuildRow(pool, guildId);
  if (!row) return null;
  return rowToGuild(row, await fetchMembers(pool, guildId));
}

// Full guild (with roster) for whichever guild `playerId` belongs to, or
// null if they're not in one. Called on every player load, so this is the
// hot path — kept to a single join.
export async function getGuildForPlayer(playerId) {
  const { rows } = await pool.query(
    `SELECT g.* FROM guilds g
       JOIN guild_members m ON m.guild_id = g.id
      WHERE m.player_id = $1`,
    [playerId]
  );
  if (rows.length === 0) return null;
  return rowToGuild(rows[0], await fetchMembers(pool, rows[0].id));
}

// Creates a guild led by `leaderId`, who becomes its first member.
// Throws { code: "already_in_guild" | "name_taken" }.
export async function createGuild(leaderId, name, tag) {
  return withTransaction(async (client) => {
    const existing = await client.query(`SELECT 1 FROM guild_members WHERE player_id = $1`, [leaderId]);
    if (existing.rows.length > 0) {
      throw guildError("already_in_guild");
    }

    let inserted;
    try {
      inserted = await client.query(
        `INSERT INTO guilds (name, tag, leader_id) VALUES ($1, $2, $3) RETURNING *`,
        [name.trim(), tag.trim().toUpperCase(), leaderId]
      );
    } catch (err) {
      if (err.code === "23505") throw guildError("name_taken"); // unique_violation
      throw err;
    }
    const guild = inserted.rows[0];
    await client.query(`INSERT INTO guild_members (guild_id, player_id) VALUES ($1, $2)`, [guild.id, leaderId]);
    return rowToGuild(guild, await fetchMembers(client, guild.id));
  });
}

// Adds `playerId` to `guildId`.
// Throws { code: "already_in_guild" | "not_found" }.
export async function joinGuild(guildId, playerId) {
  return withTransaction(async (client) => {
    const existing = await client.query(`SELECT 1 FROM guild_members WHERE player_id = $1`, [playerId]);
    if (existing.rows.length > 0) {
      throw guildError("already_in_guild");
    }
    const guild = await fetchGuildRow(client, guildId);
    if (!guild) {
      throw guildError("not_found");
    }
    await client.query(`INSERT INTO guild_members (guild_id, player_id) VALUES ($1, $2)`, [guildId, playerId]);
    return rowToGuild(guild, await fetchMembers(client, guildId));
  });
}

// Removes `targetId` from `guildId`. The leader can kick anyone but
// themselves. An officer can kick a plain member but not the leader or
// another officer — promoting someone is a leader-only trust decision, so
// letting an officer strip a peer officer would undermine it.
// Throws { code: "not_found" | "not_authorized" | "cannot_kick_self" | "target_not_member" }.
export async function kickMember(guildId, requesterId, targetId) {
  return withTransaction(async (client) => {
    const guild = await fetchGuildRow(client, guildId);
    if (!guild) throw guildError("not_found");
    if (String(targetId) === String(requesterId)) throw guildError("cannot_kick_self");

    const isLeader = String(guild.leader_id) === String(requesterId);
    if (!isLeader) {
      const { rows: requesterRows } = await client.query(
        `SELECT role FROM guild_members WHERE guild_id = $1 AND player_id = $2`,
        [guildId, requesterId]
      );
      if (!requesterRows[0] || requesterRows[0].role !== "officer") {
        throw guildError("not_authorized");
      }
      if (String(guild.leader_id) === String(targetId)) {
        throw guildError("not_authorized");
      }
      const { rows: targetRows } = await client.query(
        `SELECT role FROM guild_members WHERE guild_id = $1 AND player_id = $2`,
        [guildId, targetId]
      );
      if (targetRows.length === 0) throw guildError("target_not_member");
      if (targetRows[0].role === "officer") throw guildError("not_authorized");
    }

    const del = await client.query(
      `DELETE FROM guild_members WHERE guild_id = $1 AND player_id = $2`,
      [guildId, targetId]
    );
    if (del.rowCount === 0) throw guildError("target_not_member");

    return rowToGuild(guild, await fetchMembers(client, guildId));
  });
}

// Leader-only. Sets `targetId`'s rank to 'officer' or 'member'. Can't be
// used on the leader themselves (there's nothing to promote them to, and
// demoting "out of" leadership is a different operation — leaving/kicking —
// not a role change).
// Throws { code: "not_found" | "not_authorized" | "invalid_role" | "target_not_member" | "cannot_role_leader" }.
export async function setMemberRole(guildId, requesterId, targetId, role) {
  if (role !== "officer" && role !== "member") {
    throw guildError("invalid_role");
  }
  return withTransaction(async (client) => {
    const guild = await fetchGuildRow(client, guildId);
    if (!guild) throw guildError("not_found");
    if (String(guild.leader_id) !== String(requesterId)) throw guildError("not_authorized");
    if (String(guild.leader_id) === String(targetId)) throw guildError("cannot_role_leader");

    const result = await client.query(
      `UPDATE guild_members SET role = $1 WHERE guild_id = $2 AND player_id = $3`,
      [role, guildId, targetId]
    );
    if (result.rowCount === 0) throw guildError("target_not_member");

    return rowToGuild(guild, await fetchMembers(client, guildId));
  });
}

// Removes `playerId` from their current guild. If they were the leader and
// members remain, leadership passes to whoever joined earliest. If they
// were the last member, the guild is deleted outright.
// Returns { disbanded: true } or { disbanded: false, guild }.
// Throws { code: "not_in_guild" }.
export async function leaveGuild(playerId) {
  return withTransaction(async (client) => {
    const membership = await client.query(
      `SELECT guild_id FROM guild_members WHERE player_id = $1`,
      [playerId]
    );
    if (membership.rows.length === 0) throw guildError("not_in_guild");
    const guildId = membership.rows[0].guild_id;

    const guild = await fetchGuildRow(client, guildId);
    await client.query(`DELETE FROM guild_members WHERE guild_id = $1 AND player_id = $2`, [guildId, playerId]);

    const remaining = await fetchMembers(client, guildId);
    if (remaining.length === 0) {
      await client.query(`DELETE FROM guilds WHERE id = $1`, [guildId]);
      return { disbanded: true };
    }

    if (String(guild.leader_id) === String(playerId)) {
      const newLeaderId = remaining[0].playerId; // earliest joined_at among survivors
      await client.query(`UPDATE guilds SET leader_id = $2 WHERE id = $1`, [guildId, newLeaderId]);
      guild.leader_id = newLeaderId;
    }

    return { disbanded: false, guild: rowToGuild(guild, remaining) };
  });
}
