import WebSocket from "ws";
import { PROTOCOL_VERSION } from "../../shared/protocol.js";

const WS_URL = `ws://localhost:${process.env.ISAAC_RANKED_WS_PORT ?? 8765}`;

function createClient(name: string) {
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

  const send = (msg: unknown): void => {
    ws.send(JSON.stringify(msg));
  };

  const close = (): void => ws.close();

  return { name, ws, open, send, nextMessage, close };
}

async function main(): Promise<void> {
  const a = createClient("RunnerA");
  const b = createClient("RunnerB");

  await Promise.all([a.open(), b.open()]);

  a.send({
    type: "hello",
    protocolVersion: PROTOCOL_VERSION,
    playerId: "test-player-a",
    displayName: "RunnerA",
    clientVersion: "0.1.0",
  });
  b.send({
    type: "hello",
    protocolVersion: PROTOCOL_VERSION,
    playerId: "test-player-b",
    displayName: "RunnerB",
    clientVersion: "0.1.0",
  });

  const ackA = (await a.nextMessage()) as { type: string };
  const ackB = (await b.nextMessage()) as { type: string };
  if (ackA.type !== "hello_ack" || ackB.type !== "hello_ack") {
    throw new Error("Expected hello_ack");
  }

  a.send({ type: "queue_join", playerId: "test-player-a" });
  b.send({ type: "queue_join", playerId: "test-player-b" });

  const aMessages = [await a.nextMessage(), await a.nextMessage()];
  const bMessages = [await b.nextMessage(), await b.nextMessage()];

  const matchA = aMessages.find((m) => (m as { type: string }).type === "match_found") as
    | { config?: { seed: number; playerType: number } }
    | undefined;
  const matchB = bMessages.find((m) => (m as { type: string }).type === "match_found") as
    | { config?: { seed: number; playerType: number } }
    | undefined;

  if (!matchA?.config || !matchB?.config) {
    throw new Error(`Expected match_found for both players: ${JSON.stringify({ aMessages, bMessages })}`);
  }

  if (matchA.config.seed !== matchB.config.seed || matchA.config.playerType !== matchB.config.playerType) {
    throw new Error("Players did not receive identical match config");
  }

  console.log("matchmaking test passed", {
    seed: matchA.config.seed,
    playerType: matchA.config.playerType,
  });

  a.close();
  b.close();
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
