// Friend-lobby chat filter (PRD: "Free-text chat, filtered before sending"). Blocks
// contact details — phone numbers, emails, links and social handles — and abuse from a
// wordlist, seeing through common disguises (leetspeak, spacing, repeated letters).
// Blocked messages aren't delivered; the sender sees "Message not sent".
//
// The PRD also names Google's Perspective API for toxicity scoring; that needs an API
// key and access approval, and slots in after these checks once it's available.

export type BlockReason = "contact" | "abuse";

export const MAX_MESSAGE_LENGTH = 200;

const CONTACT: RegExp[] = [
  /[\p{L}\p{N}._%+-]+\s*(@|\(at\)|\[at\])\s*[\p{L}\p{N}.-]+\s*(\.|\(dot\)|\[dot\])\s*\p{L}{2,}/iu, // email
  /\b(https?:\/\/|www\.)\S+/i, // link
  /\b[\p{L}\p{N}-]{2,}\.(com|co\.uk|uk|net|org|io|me|app|gg|ly|tv|link)\b/iu, // bare domain
  /(\+?\d[\s().-]*){9,}/, // phone number: nine or more digits however they're spaced
  /(^|\s)@[\p{L}\p{N}_.]{2,}/u, // @handle
  /\b(insta(gram)?|snap(chat)?|tiktok|whats\s*app|telegram|discord|twitter|ig)\s*[:\-–]?\s*@?[\p{L}\p{N}_.]{3,}/iu, // "snap: name"
];

/**
 * Abuse terms, matched as whole words after normalising. A starting list: extend it
 * from a maintained source before launch. Slurs are stored obfuscated (ROT13) so the
 * source doesn't read as a list of insults.
 */
const ABUSE_ROT13 = [
  "shpx", "shpxre", "shpxvat", "fuvg", "phag", "gjng", "jnaxre", "onfgneq", "ovgpu", "qvpx", "cevpx",
  "fyhg", "juber", "nffubyr", "qvpxurnq", "xvyy lbhefrys", "xlf", "ergneq", "snttbg",
  "avttre", "avttn", "cnxv", "fcnfgvp", "pbba", "puvax", "xvxr", "genaal", "qlxr", "jbt", "fcvp",
].map(rot13);

function rot13(s: string): string {
  return s.replace(/[a-z]/g, (c) => String.fromCharCode(((c.charCodeAt(0) - 97 + 13) % 26) + 97));
}

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s" };

/** Lower case, leetspeak undone, runs of three or more letters squeezed, punctuation dropped. */
export function normalise(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .replace(/[013457@$]/g, (c) => LEET[c] ?? c)
    .replace(/(\p{L})\1{2,}/gu, "$1")
    .replace(/[^\p{L}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function containsAbuse(text: string): boolean {
  const normal = normalise(text);
  const words = ` ${normal} `;
  // Also catch "f u c k": single letters run together.
  const joined = ` ${normal.replace(/\b(\p{L}) (?=\p{L}\b)/gu, "$1")} `;
  return ABUSE_ROT13.some((term) => words.includes(` ${term} `) || joined.includes(` ${term} `));
}

/** Null if the message can be sent, otherwise why not. */
export function blockReason(text: string): BlockReason | null {
  if (CONTACT.some((pattern) => pattern.test(text))) return "contact";
  if (containsAbuse(text)) return "abuse";
  return null;
}
