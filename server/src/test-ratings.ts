import { applyElo } from "./ratings.js";

const winner = applyElo(1200, 1000, 1, 0);
const loser = applyElo(1000, 1200, 0, 0);

if (winner.ratingDelta <= 0) {
  throw new Error("Winner should gain rating against lower opponent");
}
if (loser.ratingDelta >= 0) {
  throw new Error("Loser should lose rating against higher opponent");
}

console.log("ratings test passed", { winner, loser });
