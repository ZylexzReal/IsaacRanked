import type { MatchConfig, MatchResultType, PlayerProfile, ProgressEvent } from "../../shared/protocol.js";

export interface DbPlayer extends PlayerProfile {
  createdAt: number;
  updatedAt: number;
}

export interface DbMatch {
  matchId: string;
  playerAId: string;
  playerBId: string;
  seed: number;
  seedString: string;
  playerType: number;
  characterName: string;
  difficulty: number;
  rulesetVersion: number;
  state: "matched" | "in_progress" | "finished" | "forfeited" | "invalid";
  winnerId: string | null;
  createdAt: number;
  startedAt: number | null;
  finishedAt: number | null;
}

export interface DbMatchPlayerResult {
  matchId: string;
  playerId: string;
  result: MatchResultType;
  elapsedMs: number;
  floor: number;
  ratingBefore: number;
  ratingAfter: number;
  ratingDelta: number;
  integrityValid: boolean;
  reason?: string;
}

export interface DbMatchEvent {
  id: string;
  matchId: string;
  playerId: string;
  type: string;
  payload: unknown;
  createdAt: number;
}

export class InMemoryDb {
  players = new Map<string, DbPlayer>();
  matches = new Map<string, DbMatch>();
  matchResults = new Map<string, DbMatchPlayerResult[]>();
  events: DbMatchEvent[] = [];

  getOrCreatePlayer(playerId: string, displayName: string): DbPlayer {
    const existing = this.players.get(playerId);
    if (existing) {
      existing.displayName = displayName;
      existing.updatedAt = Date.now();
      return existing;
    }

    const player: DbPlayer = {
      playerId,
      displayName,
      rating: 1000,
      placementMatchesRemaining: 5,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    this.players.set(playerId, player);
    return player;
  }

  getPlayer(playerId: string): DbPlayer | undefined {
    return this.players.get(playerId);
  }

  saveMatch(match: DbMatch): void {
    this.matches.set(match.matchId, match);
  }

  getMatch(matchId: string): DbMatch | undefined {
    return this.matches.get(matchId);
  }

  saveMatchResults(matchId: string, results: DbMatchPlayerResult[]): void {
    this.matchResults.set(matchId, results);
  }

  getMatchResults(matchId: string): DbMatchPlayerResult[] | undefined {
    return this.matchResults.get(matchId);
  }

  logEvent(matchId: string, playerId: string, type: string, payload: unknown): void {
    this.events.push({
      id: `${matchId}-${this.events.length}`,
      matchId,
      playerId,
      type,
      payload,
      createdAt: Date.now(),
    });
  }

  updatePlayerRating(playerId: string, rating: number, placementMatchesRemaining: number): void {
    const player = this.players.get(playerId);
    if (!player) return;
    player.rating = rating;
    player.placementMatchesRemaining = placementMatchesRemaining;
    player.updatedAt = Date.now();
  }
}

export const db = new InMemoryDb();

export type { MatchConfig, ProgressEvent };
