import { randomUUID } from "node:crypto";
import type { MatchConfig, MatchResultType, ProgressEvent } from "../../shared/protocol.js";
import { db } from "./db.js";
import { applyElo } from "./ratings.js";
import { generateSeed, intersectCharacterPools, pickRandomCharacter, seedToString } from "./match.js";
import { RULESET_VERSION, RANKED_DIFFICULTY } from "../../shared/protocol.js";

export interface QueuedPlayer {
  playerId: string;
  displayName: string;
  rating: number;
  joinedAt: number;
  unlockedCharacters?: number[];
  send: (msg: unknown) => void;
}

const QUEUE_RATING_WINDOW_INITIAL = 100;
const QUEUE_RATING_WINDOW_GROWTH_PER_SEC = 10;
const HEARTBEAT_TIMEOUT_MS = 30_000;

export class MatchmakingService {
  private queue: QueuedPlayer[] = [];
  private activeConnections = new Map<string, QueuedPlayer>();
  private playerMatches = new Map<string, string>();
  private heartbeats = new Map<string, number>();
  private opponentProgress = new Map<string, ProgressEvent>();
  private pendingResults = new Map<
    string,
    Map<string, { result: MatchResultType; elapsedMs: number; floor: number; integrityValid: boolean }>
  >();

  registerConnection(player: QueuedPlayer): void {
    this.activeConnections.set(player.playerId, player);
    this.heartbeats.set(player.playerId, Date.now());
  }

  unregisterConnection(playerId: string): void {
    this.activeConnections.delete(playerId);
    this.heartbeats.delete(playerId);
    this.leaveQueue(playerId);
  }

  heartbeat(playerId: string): void {
    this.heartbeats.set(playerId, Date.now());
  }

  getStalePlayerIds(): string[] {
    const now = Date.now();
    const stale: string[] = [];
    for (const [playerId, lastBeat] of this.heartbeats) {
      if (now - lastBeat > HEARTBEAT_TIMEOUT_MS) {
        stale.push(playerId);
      }
    }
    return stale;
  }

  joinQueue(player: QueuedPlayer): { position: number; estimatedWaitSec: number } {
    if (this.queue.some((q) => q.playerId === player.playerId)) {
      return this.getQueueStatus(player.playerId);
    }

    this.queue.push(player);
    this.queue.sort((a, b) => a.joinedAt - b.joinedAt);
    this.tryPair();
    return this.getQueueStatus(player.playerId);
  }

  leaveQueue(playerId: string): void {
    this.queue = this.queue.filter((q) => q.playerId !== playerId);
  }

  tick(): void {
    this.tryPair();
  }

  getQueueStatus(playerId: string): { position: number; estimatedWaitSec: number } {
    const index = this.queue.findIndex((q) => q.playerId === playerId);
    return {
      position: index === -1 ? 0 : index + 1,
      estimatedWaitSec: index === -1 ? 0 : Math.max(5, (index + 1) * 8),
    };
  }

  private ratingWindowFor(waitSec: number): number {
    return QUEUE_RATING_WINDOW_INITIAL + waitSec * QUEUE_RATING_WINDOW_GROWTH_PER_SEC;
  }

  private tryPair(): void {
    if (this.queue.length < 2) return;

    for (let i = 0; i < this.queue.length; i++) {
      const a = this.queue[i];
      const waitSecA = (Date.now() - a.joinedAt) / 1000;
      const windowA = this.ratingWindowFor(waitSecA);

      for (let j = i + 1; j < this.queue.length; j++) {
        const b = this.queue[j];
        const waitSecB = (Date.now() - b.joinedAt) / 1000;
        const windowB = this.ratingWindowFor(waitSecB);
        const window = Math.max(windowA, windowB);

        if (Math.abs(a.rating - b.rating) <= window) {
          this.createMatch(a, b);
          return;
        }
      }
    }
  }

  private createMatch(a: QueuedPlayer, b: QueuedPlayer): void {
    this.queue = this.queue.filter((q) => q.playerId !== a.playerId && q.playerId !== b.playerId);

    const allowed = intersectCharacterPools(a.unlockedCharacters, b.unlockedCharacters);
    const character = pickRandomCharacter(allowed);
    const seed = generateSeed();
    const matchId = randomUUID();

    const dbMatch = {
      matchId,
      playerAId: a.playerId,
      playerBId: b.playerId,
      seed,
      seedString: seedToString(seed),
      playerType: character.playerType,
      characterName: character.name,
      difficulty: RANKED_DIFFICULTY,
      rulesetVersion: RULESET_VERSION,
      state: "matched" as const,
      winnerId: null,
      createdAt: Date.now(),
      startedAt: null,
      finishedAt: null,
    };

    db.saveMatch(dbMatch);
    this.playerMatches.set(a.playerId, matchId);
    this.playerMatches.set(b.playerId, matchId);

    const configFor = (self: QueuedPlayer, opponent: QueuedPlayer): MatchConfig => ({
      matchId,
      seed,
      seedString: seedToString(seed),
      playerType: character.playerType,
      characterName: character.name,
      difficulty: RANKED_DIFFICULTY,
      rulesetVersion: RULESET_VERSION,
      opponent: {
        playerId: opponent.playerId,
        displayName: opponent.displayName,
        rating: opponent.rating,
      },
    });

    a.send({ type: "match_found", config: configFor(a, b) });
    b.send({ type: "match_found", config: configFor(b, a) });
  }

  getActiveMatchId(playerId: string): string | undefined {
    return this.playerMatches.get(playerId);
  }

  markMatchStarted(matchId: string, playerId: string, actualSeed: number, actualPlayerType: number): void {
    const match = db.getMatch(matchId);
    if (!match) return;

    db.logEvent(matchId, playerId, "match_started", { actualSeed, actualPlayerType });

    if (!match.startedAt) {
      match.startedAt = Date.now();
      match.state = "in_progress";
      db.saveMatch(match);
    }
  }

  reportProgress(playerId: string, event: ProgressEvent): void {
    const matchId = this.playerMatches.get(playerId);
    if (!matchId) return;

    db.logEvent(matchId, playerId, "progress", event);
    this.opponentProgress.set(`${matchId}:${playerId}`, event);

    const match = db.getMatch(matchId);
    if (!match) return;

    const opponentId = match.playerAId === playerId ? match.playerBId : match.playerAId;
    const opponent = this.activeConnections.get(opponentId);
    if (opponent) {
      opponent.send({ type: "opponent_progress", matchId, event });
    }
  }

  reportIntegrityViolation(playerId: string, matchId: string, reason: string): void {
    const match = db.getMatch(matchId);
    if (!match) return;
    const opponentId = match.playerAId === playerId ? match.playerBId : match.playerAId;
    this.resolveMatch(matchId, opponentId, "win", 0, 0, reason ?? "opponent_integrity_violation");
  }

  reportResult(
    playerId: string,
    matchId: string,
    result: MatchResultType,
    elapsedMs: number,
    floor: number,
    reason?: string,
    integrityValid = true
  ): void {
    const match = db.getMatch(matchId);
    if (!match || match.state === "finished" || match.state === "invalid") return;

    db.logEvent(matchId, playerId, "match_result", { result, elapsedMs, floor, reason, integrityValid });

    let store = this.pendingResults.get(matchId);
    if (!store) {
      store = new Map();
      this.pendingResults.set(matchId, store);
    }

    store.set(playerId, { result, elapsedMs, floor, integrityValid });

    if (store.size < 2) return;

    const [aId, bId] = [match.playerAId, match.playerBId];
    const aResult = store.get(aId);
    const bResult = store.get(bId);
    if (!aResult || !bResult) return;

    if (!aResult.integrityValid || !bResult.integrityValid || result === "invalid") {
      this.resolveMatch(matchId, null, "invalid", aResult.elapsedMs, bResult.elapsedMs, reason ?? "integrity_violation");
      return;
    }

    if (aResult.result === "forfeit") {
      this.resolveMatch(matchId, bId, "win", bResult.elapsedMs, aResult.elapsedMs, "opponent_forfeit");
      return;
    }
    if (bResult.result === "forfeit") {
      this.resolveMatch(matchId, aId, "win", aResult.elapsedMs, bResult.elapsedMs, "opponent_forfeit");
      return;
    }

    if (aResult.result === "win" && bResult.result !== "win") {
      this.resolveMatch(matchId, aId, "win", aResult.elapsedMs, bResult.elapsedMs);
      return;
    }
    if (bResult.result === "win" && aResult.result !== "win") {
      this.resolveMatch(matchId, bId, "win", bResult.elapsedMs, aResult.elapsedMs);
      return;
    }

    if (aResult.result === "win" && bResult.result === "win") {
      const winnerId = aResult.elapsedMs <= bResult.elapsedMs ? aId : bId;
      this.resolveMatch(
        matchId,
        winnerId,
        "win",
        aResult.elapsedMs,
        bResult.elapsedMs,
        "time_tiebreak"
      );
      return;
    }

    this.resolveMatch(matchId, null, "dnf", aResult.elapsedMs, bResult.elapsedMs, "both_dnf");
  }

  forfeit(playerId: string, matchId: string, reason?: string): void {
    this.reportResult(playerId, matchId, "forfeit", 0, 0, reason, true);
  }

  private resolveMatch(
    matchId: string,
    winnerId: string | null,
    result: MatchResultType,
    elapsedA: number,
    elapsedB: number,
    reason?: string
  ): void {
    const match = db.getMatch(matchId);
    if (!match || match.state === "finished" || match.state === "invalid") return;

    match.state = result === "invalid" ? "invalid" : "finished";
    match.winnerId = winnerId;
    match.finishedAt = Date.now();
    db.saveMatch(match);

    const playerA = db.getPlayer(match.playerAId);
    const playerB = db.getPlayer(match.playerBId);
    if (!playerA || !playerB) return;

    const results: Array<{
      playerId: string;
      outcome: ReturnType<typeof applyElo>;
      result: MatchResultType;
      elapsedMs: number;
    }> = [];

    if (result === "invalid") {
      for (const pid of [match.playerAId, match.playerBId]) {
        const p = db.getPlayer(pid)!;
        results.push({
          playerId: pid,
          outcome: {
            ratingBefore: p.rating,
            ratingAfter: p.rating,
            ratingDelta: 0,
            placementMatchesRemaining: p.placementMatchesRemaining,
          },
          result: "invalid",
          elapsedMs: pid === match.playerAId ? elapsedA : elapsedB,
        });
      }
    } else if (winnerId) {
      const loserId = winnerId === match.playerAId ? match.playerBId : match.playerAId;
      const winner = db.getPlayer(winnerId)!;
      const loser = db.getPlayer(loserId)!;

      const winOutcome = applyElo(winner.rating, loser.rating, 1, winner.placementMatchesRemaining);
      const lossOutcome = applyElo(loser.rating, winner.rating, 0, loser.placementMatchesRemaining);

      db.updatePlayerRating(winnerId, winOutcome.ratingAfter, winOutcome.placementMatchesRemaining);
      db.updatePlayerRating(loserId, lossOutcome.ratingAfter, lossOutcome.placementMatchesRemaining);

      results.push(
        {
          playerId: winnerId,
          outcome: winOutcome,
          result: "win",
          elapsedMs: winnerId === match.playerAId ? elapsedA : elapsedB,
        },
        {
          playerId: loserId,
          outcome: lossOutcome,
          result: "loss",
          elapsedMs: loserId === match.playerAId ? elapsedA : elapsedB,
        }
      );
    }

    db.saveMatchResults(
      matchId,
      results.map((r) => ({
        matchId,
        playerId: r.playerId,
        result: r.result,
        elapsedMs: r.elapsedMs,
        floor: 0,
        ratingBefore: r.outcome.ratingBefore,
        ratingAfter: r.outcome.ratingAfter,
        ratingDelta: r.outcome.ratingDelta,
        integrityValid: result !== "invalid",
        reason,
      }))
    );

    this.pendingResults.delete(matchId);

    for (const r of results) {
      const conn = this.activeConnections.get(r.playerId);
      if (conn) {
        conn.send({
          type: "match_resolved",
          matchId,
          winnerId,
          result: r.result,
          ratingDelta: r.outcome.ratingDelta,
          newRating: r.outcome.ratingAfter,
          reason,
        });
      }
      this.playerMatches.delete(r.playerId);
    }
  }
}

export const matchmaking = new MatchmakingService();
