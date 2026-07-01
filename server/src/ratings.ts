const K_FACTOR = 32;
const PLACEMENT_K = 48;

export interface EloOutcome {
  ratingBefore: number;
  ratingAfter: number;
  ratingDelta: number;
  placementMatchesRemaining: number;
}

export function expectedScore(ratingA: number, ratingB: number): number {
  return 1 / (1 + Math.pow(10, (ratingB - ratingA) / 400));
}

export function applyElo(
  rating: number,
  opponentRating: number,
  score: number,
  placementMatchesRemaining: number
): EloOutcome {
  const k = placementMatchesRemaining > 0 ? PLACEMENT_K : K_FACTOR;
  const expected = expectedScore(rating, opponentRating);
  const delta = Math.round(k * (score - expected));
  const ratingAfter = Math.max(0, rating + delta);

  return {
    ratingBefore: rating,
    ratingAfter,
    ratingDelta: delta,
    placementMatchesRemaining: Math.max(0, placementMatchesRemaining - 1),
  };
}

export function scoreFromResult(result: "win" | "loss" | "draw"): number {
  if (result === "win") return 1;
  if (result === "loss") return 0;
  return 0.5;
}
