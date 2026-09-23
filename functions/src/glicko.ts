// Glicko-2 duel ratings (PRD: "Glicko-2 for each student and module, starting at
// 1,200"). Glickman, "Example of the Glicko-2 system" (2013), one game per period.

export interface Rating {
  rating: number;
  /** Rating deviation: how unsure the rating is. */
  rd: number;
  /** Volatility: how erratic the player's results are. */
  vol: number;
}

export const INITIAL: Rating = { rating: 1200, rd: 350, vol: 0.06 };
/** Constrains volatility change; 0.5 is Glickman's usual choice. */
const TAU = 0.5;
const SCALE = 173.7178;
const EPSILON = 0.000001;
/** An RD above this reads as "Provisional" rather than "Settled". */
export const SETTLED_RD = 110;

/** The new rating after one game; `score` is 1 for a win, 0.5 a draw, 0 a loss. */
export function rate(player: Rating, opponent: Pick<Rating, "rating" | "rd">, score: 0 | 0.5 | 1): Rating {
  const mu = (player.rating - 1500) / SCALE;
  const phi = player.rd / SCALE;
  const muJ = (opponent.rating - 1500) / SCALE;
  const phiJ = opponent.rd / SCALE;

  const g = 1 / Math.sqrt(1 + (3 * phiJ * phiJ) / (Math.PI * Math.PI));
  const expected = 1 / (1 + Math.exp(-g * (mu - muJ)));
  const v = 1 / (g * g * expected * (1 - expected));
  const delta = v * g * (score - expected);

  // New volatility by the Illinois algorithm (step 5).
  const a = Math.log(player.vol * player.vol);
  const f = (x: number) => {
    const ex = Math.exp(x);
    return (ex * (delta * delta - phi * phi - v - ex)) / (2 * (phi * phi + v + ex) ** 2) - (x - a) / (TAU * TAU);
  };
  let A = a;
  let B: number;
  if (delta * delta > phi * phi + v) {
    B = Math.log(delta * delta - phi * phi - v);
  } else {
    let k = 1;
    while (f(a - k * TAU) < 0) k += 1;
    B = a - k * TAU;
  }
  let fA = f(A);
  let fB = f(B);
  while (Math.abs(B - A) > EPSILON) {
    const C = A + ((A - B) * fA) / (fB - fA);
    const fC = f(C);
    if (fC * fB <= 0) {
      A = B;
      fA = fB;
    } else {
      fA /= 2;
    }
    B = C;
    fB = fC;
  }
  const vol = Math.exp(A / 2);

  const phiStar = Math.sqrt(phi * phi + vol * vol);
  const phiNew = 1 / Math.sqrt(1 / (phiStar * phiStar) + 1 / v);
  const muNew = mu + phiNew * phiNew * g * (score - expected);
  return { rating: muNew * SCALE + 1500, rd: phiNew * SCALE, vol };
}
