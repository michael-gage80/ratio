// Boards (PRD: "Boards, streaks and notifications"): daily, weekly and monthly, ranked by
// wins in human duels. Each period is its own collection, boards/{key}/entries/{uid},
// keyed by UK date — so boards reset at 00:00 UK, Monday 00:00 and the 1st of the month
// without any job clearing them.

export type Period = "daily" | "weekly" | "monthly";

function ukParts(now: Date): { year: number; month: number; day: number; weekday: number } {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", year: "numeric", month: "2-digit", day: "2-digit", weekday: "short" })
    .formatToParts(now);
  const get = (type: string) => parts.find((p) => p.type === type)!.value;
  const weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(get("weekday"));
  return { year: Number(get("year")), month: Number(get("month")), day: Number(get("day")), weekday };
}

const pad = (n: number) => String(n).padStart(2, "0");

/** The board each period is currently on: "day-2026-09-23", "week-2026-09-21" (its Monday), "month-2026-09". */
export function periodKeys(now: Date): Record<Period, string> {
  const { year, month, day, weekday } = ukParts(now);
  const monday = new Date(Date.UTC(year, month - 1, day - weekday));
  return {
    daily: `day-${year}-${pad(month)}-${pad(day)}`,
    weekly: `week-${monday.getUTCFullYear()}-${pad(monday.getUTCMonth() + 1)}-${pad(monday.getUTCDate())}`,
    monthly: `month-${year}-${pad(month)}`,
  };
}
