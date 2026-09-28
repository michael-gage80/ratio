// The legal awareness centre's feed (PRD: "Legal awareness centre"). Headlines, sources,
// dates and links, pulled from RSS and Atom, filtered to UK law, deduplicated across
// sources, and tagged by module. Article text is kept only for sources whose full-text
// switch is on (article.ts, reader.ts): official sources under open licences, and a
// publisher only once they've given permission (config/news, set with admin.mjs).
//
// Each source's terms must be checked before launch (PRD); a source whose terms forbid
// this use is dropped from SOURCES.

import { XMLParser } from "fast-xml-parser";

/** How a source's text is read in the app (reader.ts). */
export type Extractor =
  /** Find Case Law's Akoma Ntoso: the court's press summary, then the judgment. */
  | "uksc"
  /** legislation.gov.uk: the Act's explanatory notes (overview), once published. */
  | "legislation"
  /** The Bills API: long title, stage and summary. */
  | "bills"
  /** The feed item's own HTML (content:encoded). */
  | "feed"
  /** The publisher's page, through Readability. */
  | "page";

export interface Source {
  id: string;
  name: string;
  url: string;
  /** Every item is legal news; otherwise only items matching LEGAL are kept. */
  allLegal: boolean;
  /** Links under these paths are dropped (e.g. non-UK sections). */
  excludePaths?: string[];
  extractor: Extractor;
  /**
   * Whether article text may be stored and shown in Ratio before config/news says
   * otherwise: only for open licences. Publishers stay off until they've agreed.
   */
  fullText: boolean;
  /** The attribution the licence asks for, shown under the article. */
  licence?: string;
  /** "always": every article is subscriber-only; "check": look at each page for paywall markup. */
  paywall: "always" | "check" | "never";
  /** At most this many new items a day (high-volume feeds), most module matches first. */
  perDay?: number;
  /** Only items that tag a module (every bill's title says "Bill", so the legal filter can't tell). */
  requireModule?: boolean;
  /** A Google News search feed: titles end " - Publisher", links go via Google. */
  googleNews?: boolean;
  /** A WordPress REST API listing (JSON) rather than RSS or Atom. */
  wordpress?: boolean;
}

const OGL = "Contains public sector information licensed under the Open Government Licence v3.0.";
const OPL = "Contains Parliamentary information licensed under the Open Parliament Licence v3.0.";
const OJL = "Contains public sector information licensed under the Open Justice Licence v1.0. © Crown copyright.";
const lawcom = (type: string) => `https://lawcom.gov.uk/wp-json/wp/v2/${type}?per_page=20&_fields=date_gmt,link,title,content`;
const googleNews = (query: string) => `https://news.google.com/rss/search?q=${encodeURIComponent(query)}&hl=en-GB&gl=GB&ceid=GB:en`;

export const SOURCES: Source[] = [
  { id: "uksc", name: "UK Supreme Court", url: "https://caselaw.nationalarchives.gov.uk/uksc/atom.xml", allLegal: true, extractor: "uksc", fullText: true, licence: OJL, paywall: "never" },
  // The Law Commission's site has no working feed; its WordPress API lists news and publications with their text.
  { id: "lawcom", name: "Law Commission", url: lawcom("news"), allLegal: true, extractor: "feed", fullText: true, licence: OGL, paywall: "never", wordpress: true },
  { id: "lawcom-publications", name: "Law Commission", url: lawcom("publication"), allLegal: true, extractor: "feed", fullText: true, licence: OGL, paywall: "never", wordpress: true },
  { id: "acts", name: "New Acts", url: "https://www.legislation.gov.uk/ukpga/data.feed", allLegal: true, extractor: "legislation", fullText: true, licence: OGL, paywall: "never" },
  { id: "commonslibrary", name: "Commons Library", url: "https://commonslibrary.parliament.uk/feed/", allLegal: false, extractor: "feed", fullText: true, licence: OPL, paywall: "never" },
  { id: "lordslibrary", name: "Lords Library", url: "https://lordslibrary.parliament.uk/feed/", allLegal: false, extractor: "feed", fullText: true, licence: OPL, paywall: "never" },
  { id: "bills", name: "UK Parliament", url: "https://bills.parliament.uk/rss/allbills.rss", allLegal: false, extractor: "bills", fullText: true, licence: OPL, paywall: "never", perDay: 3, requireModule: true },
  { id: "gazette-top", name: "Law Society Gazette", url: "https://www.lawgazette.co.uk/13505.rss", allLegal: true, extractor: "page", fullText: false, paywall: "check" },
  { id: "gazette", name: "Law Society Gazette", url: "https://www.lawgazette.co.uk/13506.rss", allLegal: true, extractor: "page", fullText: false, paywall: "check" },
  { id: "legalcheek", name: "Legal Cheek", url: "https://www.legalcheek.com/feed/", allLegal: true, extractor: "page", fullText: false, paywall: "check" },
  { id: "legalfutures", name: "Legal Futures", url: "https://www.legalfutures.co.uk/feed", allLegal: true, extractor: "page", fullText: false, paywall: "check" },
  {
    id: "guardian", name: "The Guardian", url: "https://www.theguardian.com/law/rss", allLegal: true, extractor: "page", fullText: false, paywall: "never",
    excludePaths: ["/us-news/", "/australia-news/", "/world/", "/global-development/"],
  },
  { id: "bbc", name: "BBC News", url: "https://feeds.bbci.co.uk/news/uk/rss.xml", allLegal: false, extractor: "page", fullText: false, paywall: "never" },
  // No public feeds: Google News searches of each site, headlines only.
  { id: "times", name: "The Times", url: googleNews("site:thetimes.com/uk/law when:7d"), allLegal: false, extractor: "page", fullText: false, paywall: "always", perDay: 4, googleNews: true },
  { id: "ft", name: "Financial Times", url: googleNews("site:ft.com legal when:7d"), allLegal: false, extractor: "page", fullText: false, paywall: "always", perDay: 4, googleNews: true },
  { id: "law360", name: "Law360 UK", url: googleNews("site:law360.co.uk when:7d"), allLegal: true, extractor: "page", fullText: false, paywall: "always", perDay: 4, googleNews: true },
  { id: "solicitorsjournal", name: "Solicitors Journal", url: googleNews("site:solicitorsjournal.com when:7d"), allLegal: true, extractor: "page", fullText: false, paywall: "never", perDay: 4, googleNews: true },
];

export interface NewsItem {
  sourceId: string;
  source: string;
  title: string;
  url: string;
  publishedAt: Date;
  /** The item's own HTML, kept only for "feed" sources (the Commons and Lords Libraries). */
  html?: string;
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

/** Items from an RSS 2.0 or Atom document (or a WordPress REST listing). Anything without a title, link or date is skipped. */
export function parseFeed(xml: string, source: Source): NewsItem[] {
  if (source.wordpress) return clean(parseWordPress(xml), source);
  const doc = parser.parse(xml);
  const raw: { title: string; url: string; date: string; html?: string }[] = doc.rss
    ? list(doc.rss.channel?.item).map((item: Record<string, unknown>) => {
      // Parliament's bills feed dates items with <a10:updated> and gives the stage as an attribute.
      const stage = text(item["@p4:stage"]);
      return {
        title: stage ? `${text(item.title)} · ${stage}` : text(item.title),
        url: text(item.link),
        date: text(item.pubDate) || text(item["dc:date"]) || text(item["a10:updated"]),
        ...(source.extractor === "feed" ? { html: text(item["content:encoded"]) } : {}),
      };
    })
    : list(doc.feed?.entry).map((entry: Record<string, unknown>) => {
      const links = list(entry.link as Record<string, string> | Record<string, string>[]);
      const link = links.find((l) => !l["@type"] && (l["@rel"] ?? "alternate") === "alternate") ?? links[0];
      return { title: text(entry.title), url: link?.["@href"] ?? "", date: text(entry.published) || text(entry.updated) };
    });
  return clean(raw, source);
}

function parseWordPress(json: string): { title: string; url: string; date: string; html?: string }[] {
  try {
    const posts = JSON.parse(json) as { date_gmt?: string; link?: string; title?: { rendered?: string }; content?: { rendered?: string } }[];
    return posts.map((p) => ({ title: p.title?.rendered ?? "", url: p.link ?? "", date: p.date_gmt ? `${p.date_gmt}Z` : "", html: p.content?.rendered }));
  } catch {
    return [];
  }
}

function clean(raw: { title: string; url: string; date: string; html?: string }[], source: Source): NewsItem[] {
  return raw
    .map((r) => ({
      sourceId: source.id,
      source: source.name,
      title: source.googleNews ? decode(r.title).replace(/\s+[-–]\s+[^-–]+$/, "") : decode(r.title),
      url: r.url.trim().replace(/^http:\/\/(www\.)?legislation\.gov\.uk/, "https://www.legislation.gov.uk"),
      publishedAt: new Date(r.date),
      ...(r.html ? { html: r.html } : {}),
    }))
    .filter((i) => i.title && /^https:\/\//.test(i.url) && !Number.isNaN(i.publishedAt.getTime()))
    // Section fronts in site searches ("Latest Legal News"), not stories.
    .filter((i) => !source.googleNews || i.title.split(/\s+/).length >= 4)
    .filter((i) => !source.excludePaths?.some((path) => i.url.includes(path)))
    .filter((i) => source.allLegal || isLegal(i.title))
    .filter((i) => !source.requireModule || modulesFor(i.title).length > 0);
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
  employmentlaw: /\b(employment tribunal|unfair dismissal|dismiss\w*|redundanc\w*|whistleblow\w*|minimum wage|equal pay|workers?' rights|employment rights|gig economy|zero-hours|trade unions?|strike action)\b/i,
  familylaw: /\b(divorce|family court|custody|child arrangements|care proceedings|adoption|domestic abuse|cohabit\w*|marriage|civil partnership|financial remedies|prenup\w*)\b/i,
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
