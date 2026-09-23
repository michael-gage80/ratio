// Avatar moderation (PRD: "Avatars — checked with Cloud Vision SafeSearch before they
// are shown ... Falls back to the initial-letter avatar").

export type Likelihood = "UNKNOWN" | "VERY_UNLIKELY" | "UNLIKELY" | "POSSIBLE" | "LIKELY" | "VERY_LIKELY";

export interface SafeSearch {
  adult?: Likelihood | null;
  violence?: Likelihood | null;
  racy?: Likelihood | null;
  medical?: Likelihood | null;
  spoof?: Likelihood | null;
}

const RANK: Record<Likelihood, number> = { UNKNOWN: 0, VERY_UNLIKELY: 1, UNLIKELY: 2, POSSIBLE: 3, LIKELY: 4, VERY_LIKELY: 5 };
const atLeast = (value: Likelihood | null | undefined, threshold: Likelihood) => RANK[value ?? "UNKNOWN"] >= RANK[threshold];

/**
 * Whether a profile photo can be shown to other students. Adult or violent content is
 * refused when likely; racy only when very likely, so swimwear or a gym photo isn't
 * caught. Medical and spoof (memes) are allowed.
 */
export function isAcceptable(safeSearch: SafeSearch | null | undefined): boolean {
  if (!safeSearch) return false; // Vision couldn't read it — don't guess.
  return !atLeast(safeSearch.adult, "LIKELY") && !atLeast(safeSearch.violence, "LIKELY") && !atLeast(safeSearch.racy, "VERY_LIKELY");
}
