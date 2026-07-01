import WebSocket from "ws";
import { PROTOCOL_VERSION } from "../../shared/protocol.js";

const WS_URL = `ws://localhost:${process.env.ISAAC_RANKED_WS_PORT ?? 8765}`;

function createClient(playerId: string) {
  const ws = new WebSocket(WS_URL);
  const inbox: unknown[] = [];
  let waiter: ((msg: unknown) => void) | null = null;

  ws.on("message", (data) => {
    const msg = JSON.parse(data.toString());
    if (waiter) {
      const resolve = waiter;
      waiter = null;
      resolve(msg);
      return;
    }
    inbox.push(msg);
  });

  const nextMessage = (): Promise<unknown> => {
    if (inbox.length > 0) {
      return Promise.resolve(inbox.shift());
    }
    return new Promise((resolve) => {
      waiter = resolve;
    });
  };

  const open = (): Promise<void> =>
    new Promise((resolve, reject) => {
      ws.once("open", () => resolve());
      ws.once("error", reject);
    });

  const send = (msg: unknown): void => ws.send(JSON.stringify(msg));
  const close = (): void => ws.close();

  return { playerId, open, send, nextMessage, close };
}

async function main(): Promise<void> {
  const cheater = createClient("cheater");
  const honest = createClient("honest");

  await Promise.all([cheater.open(), honest.open()]);

  for (const client of [cheater, honest]) {
    client.send({
      type: "hello",
      protocolVersion: PROTOCOL_VERSION,
      playerId: client.playerId,
      displayName: client.playerId,
      clientVersion: "0.1.0",
    });
    const ack = (await client.nextMessage()) as { type: string };
    if (ack.type !== "hello_ack") throw new Error("hello failed");
  }

  cheater.send({ type: "queue_join", playerId: cheater.playerId });
  honest.send({ type: "queue_join", playerId: honest.playerId });

  const cheaterMatch = (await cheater.nextMessage()) as { type: string; config?: { matchId: string } };
  const cheaterMatch2 = (await cheater.nextMessage()) as { type: string; config?: { matchId: string } };
  const honestMatch = (await honest.nextMessage()) as { type: string; config?: { matchId: string } };
  const honestMatch2 = (await honest.nextMessage()) as { type: string; config?: { matchId: string } };

  const cheaterConfig = [cheaterMatch, cheaterMatch2].find((m) => m.type === "match_found")?.config;
  const honestConfig = [honestMatch, honestMatch2].find((m) => m.type === "match_found")?.config;

  if (!cheaterConfig || !honestConfig) {
    throw new Error("Failed to create match for integrity test");
  }

  cheater.send({
    type: "match_started",
    matchId: cheaterConfig.matchId,
    playerId: cheater.playerId,
    actualSeed: 123,
    actualPlayerType: 0,
    integrity: {
      matchId: cheaterConfig.matchId,
      vanillaConsoleDisabled: true,
      repentogonConsoleBlocked: true,
      consoleViolation: true,
      violationReason: "console command blocked: giveitem",
      anticheatVersion: 1,
      modsWhitelisted: true,
      modWhitelistVersion: 1,
      enabledMods: ["isaac-ranked", "external item descriptions_836319872"],
    },
  });

  const [cheaterResolved, honestResolved] = await Promise.all([
    cheater.nextMessage(),
    honest.nextMessage(),
  ]) as Array<{
    type: string;
    result?: string;
    ratingDelta?: number;
    winnerId?: string;
  }>;

  if (cheaterResolved.type !== "match_resolved" || cheaterResolved.result !== "loss") {
    throw new Error(`Expected cheater loss resolution, got ${JSON.stringify(cheaterResolved)}`);
  }

  if (honestResolved.type !== "match_resolved" || honestResolved.result !== "win") {
    throw new Error(`Expected honest win resolution, got ${JSON.stringify(honestResolved)}`);
  }

  if ((honestResolved.ratingDelta ?? 0) <= 0) {
    throw new Error("Honest player should gain rating after opponent integrity violation");
  }

  if ((cheaterResolved.ratingDelta ?? 0) >= 0) {
    throw new Error("Cheater should lose rating after integrity violation");
  }

  console.log("integrity test passed");
  cheater.close();
  honest.close();
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
