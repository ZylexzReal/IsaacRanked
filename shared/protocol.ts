/**
 * Shared protocol between Isaac Ranked mod clients and the matchmaking server.
 */

export const PROTOCOL_VERSION = 1;
export const RULESET_VERSION = 1;
/** Isaac Difficulty enum: 0 = Normal, 1 = Hard */
export const RANKED_DIFFICULTY = 1;

export type MatchState =
  | "idle"
  | "queued"
  | "matched"
  | "starting"
  | "in_progress"
  | "finished"
  | "forfeited"
  | "invalid";

export type MatchResultType = "win" | "loss" | "dnf" | "forfeit" | "invalid";

export interface RankedCharacter {
  playerType: number;
  name: string;
  tainted: boolean;
}

/** Default ranked character pool (vanilla PlayerType values). */
export const DEFAULT_CHARACTER_POOL: RankedCharacter[] = [
  { playerType: 0, name: "Isaac", tainted: false },
  { playerType: 1, name: "Magdalene", tainted: false },
  { playerType: 2, name: "Cain", tainted: false },
  { playerType: 3, name: "Judas", tainted: false },
  { playerType: 4, name: "???", tainted: false },
  { playerType: 5, name: "Eve", tainted: false },
  { playerType: 6, name: "Samson", tainted: false },
  { playerType: 7, name: "Azazel", tainted: false },
  { playerType: 8, name: "Lazarus", tainted: false },
  { playerType: 9, name: "Eden", tainted: false },
  { playerType: 10, name: "The Lost", tainted: false },
  { playerType: 21, name: "Tainted Isaac", tainted: true },
  { playerType: 22, name: "Tainted Magdalene", tainted: true },
  { playerType: 23, name: "Tainted Cain", tainted: true },
];

export interface PlayerProfile {
  playerId: string;
  displayName: string;
  rating: number;
  placementMatchesRemaining: number;
}

export interface MatchConfig {
  matchId: string;
  seed: number;
  seedString: string;
  playerType: number;
  characterName: string;
  difficulty: number;
  rulesetVersion: number;
  opponent: {
    playerId: string;
    displayName: string;
    rating: number;
  };
}

export interface ProgressEvent {
  matchId: string;
  floor: number;
  stage: number;
  stageType?: number;
  roomName?: string;
  elapsedMs: number;
  alive: boolean;
}

export interface MatchResultPayload {
  matchId: string;
  result: MatchResultType;
  elapsedMs: number;
  floor: number;
  reason?: string;
  actualSeed?: number;
  actualPlayerType?: number;
}

export const ANTICHEAT_VERSION = 1;
export const MOD_WHITELIST_VERSION = 1;

export interface IntegrityReport {
  matchId: string;
  vanillaConsoleDisabled: boolean;
  repentogonConsoleBlocked: boolean;
  consoleViolation: boolean;
  violationReason?: string;
  /** Client anticheat module version (sent over WebSocket; server does not read local files). */
  anticheatVersion?: number;
  inventoryTracked?: number;
  startingCollectibleCount?: number;
  /** Enabled mod folder names scanned from the Lua environment (Repentogon Debug API). */
  enabledMods?: string[];
  /** Mod folders not on the ranked whitelist. */
  disallowedMods?: string[];
  modsWhitelisted?: boolean;
  modWhitelistVersion?: number;
}

// --- Client -> Server messages ---

export interface HelloMessage {
  type: "hello";
  protocolVersion: number;
  playerId: string;
  displayName: string;
  clientVersion: string;
  repentogonVersion?: string;
}

export interface QueueJoinMessage {
  type: "queue_join";
  playerId: string;
  unlockedCharacters?: number[];
}

export interface QueueLeaveMessage {
  type: "queue_leave";
  playerId: string;
}

export interface MatchStartedMessage {
  type: "match_started";
  matchId: string;
  playerId: string;
  actualSeed: number;
  actualPlayerType: number;
  integrity: IntegrityReport;
}

export interface ProgressMessage {
  type: "progress_event";
  playerId: string;
  event: ProgressEvent;
}

export interface MatchResultMessage {
  type: "match_result";
  playerId: string;
  payload: MatchResultPayload;
}

export interface ForfeitMessage {
  type: "forfeit";
  playerId: string;
  matchId: string;
  reason?: string;
}

export interface HeartbeatMessage {
  type: "heartbeat";
  playerId: string;
  matchId?: string;
  matchState: MatchState;
}

export interface IntegrityViolationMessage {
  type: "integrity_violation";
  playerId: string;
  report: IntegrityReport;
}

export type ClientMessage =
  | HelloMessage
  | QueueJoinMessage
  | QueueLeaveMessage
  | MatchStartedMessage
  | ProgressMessage
  | MatchResultMessage
  | ForfeitMessage
  | HeartbeatMessage
  | IntegrityViolationMessage;

// --- Server -> Client messages ---

export interface HelloAckMessage {
  type: "hello_ack";
  player: PlayerProfile;
}

export interface QueueUpdateMessage {
  type: "queue_update";
  position: number;
  estimatedWaitSec: number;
  rating: number;
}

export interface MatchFoundMessage {
  type: "match_found";
  config: MatchConfig;
}

export interface OpponentProgressMessage {
  type: "opponent_progress";
  matchId: string;
  event: ProgressEvent;
}

export interface MatchResolvedMessage {
  type: "match_resolved";
  matchId: string;
  winnerId: string | null;
  result: MatchResultType;
  ratingDelta: number;
  newRating: number;
  reason?: string;
}

export interface ErrorMessage {
  type: "error";
  code: string;
  message: string;
}

export type ServerMessage =
  | HelloAckMessage
  | QueueUpdateMessage
  | MatchFoundMessage
  | OpponentProgressMessage
  | MatchResolvedMessage
  | ErrorMessage;

/** File-bridge envelope used when the mod cannot speak WebSocket directly. */
export interface BridgeRequest {
  requestId: string;
  message: ClientMessage;
}

export interface BridgeResponse {
  requestId: string;
  messages: ServerMessage[];
  error?: string;
}
