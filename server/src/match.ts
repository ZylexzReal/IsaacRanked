import { DEFAULT_CHARACTER_POOL } from "../../shared/protocol.js";
import type { RankedCharacter } from "../../shared/protocol.js";

/** Convert numeric seed to Isaac-style display string (8 chars, space after 4). */
export function seedToString(seed: number): string {
  const chars = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  let value = seed >>> 0;
  let out = "";
  for (let i = 0; i < 8; i++) {
    out += chars[value % chars.length];
    value = Math.floor(value / chars.length);
  }
  return `${out.slice(0, 4)} ${out.slice(4)}`;
}

export function generateSeed(): number {
  return Math.floor(Math.random() * 0xffffffff) + 1;
}

export function pickRandomCharacter(allowedTypes?: number[]): RankedCharacter {
  const pool = allowedTypes?.length
    ? DEFAULT_CHARACTER_POOL.filter((c) => allowedTypes.includes(c.playerType))
    : DEFAULT_CHARACTER_POOL;

  if (pool.length === 0) {
    return DEFAULT_CHARACTER_POOL[0];
  }

  return pool[Math.floor(Math.random() * pool.length)];
}

export function intersectCharacterPools(poolA: number[] | undefined, poolB: number[] | undefined): number[] {
  if (!poolA?.length && !poolB?.length) {
    return DEFAULT_CHARACTER_POOL.map((c) => c.playerType);
  }
  if (!poolA?.length) return poolB ?? [];
  if (!poolB?.length) return poolA;
  return poolA.filter((t) => poolB.includes(t));
}
