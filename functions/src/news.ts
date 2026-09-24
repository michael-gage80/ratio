// The legal awareness centre's feed (PRD: "Legal awareness centre"). Headlines, sources,
// dates and links only — never article text — pulled from RSS and Atom, filtered to UK
// law, deduplicated across sources, and tagged by module.
//
// Each source's terms must be checked before launch (PRD); a source whose terms forbid
// this use is dropped from SOURCES.

import { XMLParser } from "fast-xml-parser";

export interface Source {
  id: string;
  name: string;
  url: string;
  /** Every item is legal news; otherwise only items matching LEGAL are kept. */
  allLegal: boolean;
  /** Links under these paths are dropped (e.g. non-UK sections). */
  excludePaths?: string[];
}

export const SOURCES: Source[] = [
  { id: "uksc", name: "UK Supreme Court", url: "https://caselaw.nationalarchives.gov.uk/uksc/atom.xml", allLegal: true },
  { id: "gazette-top", name: "Law Society Gazette", url: "https://www.lawgazette.co.uk/13505.rss", allLegal: true },
  { id: "gazette", name: "Law Society Gazette", url: "https://www.lawgazette.co.uk/13506.rss", allLegal: true },
  { id: "legalcheek", name: "Legal Cheek", url: "https://www.legalcheek.com/feed/", allLegal: true },
  {
    id: "guardian", name: "The Guardian", url: "https://www.theguardian.com/law/rss", allLegal: true,
    excludePaths: ["/us-news/", "/australia-news/", "/world/", "/global-development/"],
  },
  { id: "bbc", name: "BBC News", url: "https://feeds.bbci.co.uk/news/uk/rss.xml", allLegal: false },
];

export interface NewsItem {
  sourceId: string;
  source: string;
  title: string;
  url: string;
  publishedAt: Date;
}

const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@", textNodeName: "#text" });

const text = (value: unknown): string => {
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  if (value && typeof value === "object" && "#text" in value) return text((value as Record<string, unknown>)["#text"]);
  return "";
};

const decode = (s: string) =>
  s.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&").replace(/&#8217;|&rsquo;/g, "’").replace(/&#8216;|&lsquo;/g, "‘")
    .replace(/&#8220;|&ldquo;/g, "“").replace(/&#8221;|&rdquo;/g, "”").replace(/&#8211;|&ndash;/g, "–").replace(/&#8212;|&mdash;/g, "—")
    .replace(/&quot;/g, "\"").replace(/&#039;|&#39;|&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/\s+/g, " ").trim();

const list = <T>(value: T | T[] | undefined): T[] => (value === undefined ? [] : Array.isArray(value) ? value : [value]);

/** Items from an RSS 2.0 or Atom document. Anything without a title, link or date is skipped. */
export function parseFeed(xml: string, source: Source): NewsItem[] {
  const doc = parser.parse(xml);
  const raw: { title: string; url: string; date: string }[] = doc.rss
    ? list(doc.rss.channel?.item).map((item: Record<string, unknown>) => ({
      title: text(item.title), url: text(item.link), date: text(item.pubDate) || text(item["dc:date"]),
    }))
    : list(doc.feed?.entry).map((entry: Record<string, unknown>) => {
      const links = list(entry.link as Record<string, string> | Record<string, string>[]);
      const link = links.find((l) => !l["@type"] && (l["@rel"] ?? "alternate") === "alternate") ?? links[0];
      return { title: text(entry.title), url: link?.["@href"] ?? "", date: text(entry.published) || text(entry.updated) };
    });
  return raw
    .map((r) => ({ sourceId: source.id, source: source.name, title: decode(r.title), url: r.url.trim(), publishedAt: new Date(r.date) }))
    .filter((i) => i.title && /^https:\/\//.test(i.url) && !Number.isNaN(i.publishedAt.getTime()))
    .filter((i) => !source.excludePaths?.some((path) => i.url.includes(path)))
    .filter((i) => source.allLegal || isLegal(i.title));
}

/** For general news feeds: headlines about courts, law and the legal system. */
const LEGAL = /\b(court|courts|judge|judges|judicial|jury|trial|tribunal|inquest|inquiry|sentenc\w*|convict\w*|acquit\w*|jailed|guilty|charged|prosecut\w*|appeal|lawsuit|sued|suing|legal|lawyer\w*|barrister\w*|solicitor\w*|law|laws|bill|act|legislation|supreme court|high court|crown court|human rights|injunction|ruling|ruled|verdict)\b/i;

export function isLegal(title: string): boolean {
  return LEGAL.test(title);
}

/** Module keywords (PRD: "filtered to UK law with keyword and section rules", tagged by module). */
const MODULE_KEYWORDS: Record<string, RegExp> = {
  crime: /\b(murder\w*|manslaughter|killing|stabb\w*|assault\w*|rape|sexual offence\w*|theft|robbery|burglary|fraud\w*|jailed|sentenc\w*|convict\w*|guilty|jury|crown court|prosecut\w*|cps|police|criminal|offence\w*|bail|prison\w*|acquit\w*)\b/i,
  contract: /\b(contract\w*|breach of contract|consumer|commercial court|arbitration|supplier|terms and conditions|misrepresentation|frustration|damages for breach)\b/i,
  tort: /\b(negligen\w*|personal injury|clinical negligence|defamation|libel|slander|nuisance|compensation claim|duty of care|occupiers|vicarious|privacy claim|misuse of private information)\b/i,
  public: /\b(judicial review|on the application of|secretary of state|government|minister\w*|home office|home secretary|parliament\w*|human rights|echr|article \d+|immigration|asylum|deport\w*|public inquiry|devolution|prerogative|constitution\w*|unlawful policy|protest\w*|public order)\b/i,
  land: /\b(landlord\w*|tenan\w*|lease\w*|leasehold|freehold|property|planning|housing|eviction\w*|mortgage\w*|land registry|renters?)\b/i,
  companylaw: /\b(compan(y|ies)|directors?|shareholders?|insolven\w*|liquidat\w*|administrators?|companies house|corporate|takeover\w*)\b/i,
  eulaw: /\b(eu|european union|brexit|windsor framework|cjeu|european court of justice|retained eu law|assimilated law|trade and cooperation agreement)\b/i,
  humanrights: /\b(human rights|echr|european court of human rights|strasbourg|article (2|3|5|6|8|9|10|11|14)\b|convention rights|freedom of expression|right to (life|privacy|a fair trial))\b/i,
  equity: /\b(trust|trusts|trustee\w*|charit\w*|fiduciar\w*|probate|inheritance|wills|testator\w*|estate of|beneficiar\w*)\b/i,
};

/** The modules a headline is about, most matches first. */
export function modulesFor(title: string): string[] {
  return Object.entries(MODULE_KEYWORDS)
    .map(([module, pattern]) => [module, (title.match(new RegExp(pattern.source, "gi")) ?? []).length] as const)
    .filter(([, count]) => count > 0)
    .sort((a, b) => b[1] - a[1])
    .map(([module]) => module);
}

function words(title: string): Set<string> {
  return new Set(title.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, " ").split(/\s+/).filter((w) => w.length > 3));
}

/** Two headlines about the same story: most of their significant words shared. */
export function sameStory(a: string, b: string): boolean {
  const [x, y] = [words(a), words(b)];
  if (x.size === 0 || y.size === 0) return false;
  const shared = [...x].filter((w) => y.has(w)).length;
  return shared / Math.min(x.size, y.size) >= 0.6;
}

/** Drops repeats: the same link, or the same story from a later-listed source. */
export function dedupe(items: NewsItem[], existing: { url: string; title: string }[] = []): NewsItem[] {
  const kept: NewsItem[] = [];
  for (const item of items) {
    const seen = [...existing, ...kept];
    if (seen.some((s) => s.url === item.url || sameStory(s.title, item.title))) continue;
    kept.push(item);
  }
  return kept;
}
