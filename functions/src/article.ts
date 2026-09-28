// The in-app reader's text (PRD: "Legal awareness centre"). Only for sources whose
// full-text switch is on (config/news, see news.ts): official sources published under
// open licences, and publishers only once they've given permission. Everything is turned
// into a small set of blocks the app typesets itself: headings, numbered paragraphs,
// quotes, lists, tables and one lead image.

import { DOMParser, parseHTML } from "linkedom";
import { Readability } from "@mozilla/readability";

/** A run of inline text: italic, bold, or a link. */
export interface Run {
  t: string;
  i?: true;
  b?: true;
  href?: string;
}

export type Block =
  | { k: "h"; runs: Run[] }
  | { k: "p"; runs: Run[]; n?: string }
  | { k: "q"; runs: Run[] }
  | { k: "list"; ordered: boolean; items: Run[][] }
  | { k: "table"; rows: string[][] }
  | { k: "img"; src: string; alt?: string };

export interface ArticleDoc {
  title: string;
  source: string;
  url: string;
  /** "Contains public sector information licensed under the Open Government Licence v3.0." */
  licence: string;
  byline?: string;
  words: number;
  blocks: Block[];
}

type Node = { nodeType: number; nodeName: string; textContent: string | null; childNodes: ArrayLike<Node> } & Partial<ElementLike>;
interface ElementLike {
  localName: string;
  getAttribute(name: string): string | null;
}

const ELEMENT = 1;
const TEXT = 3;
const tag = (node: Node) => (node.localName ?? node.nodeName).toLowerCase().replace(/^.*:/, "");
const children = (node: Node) => Array.from(node.childNodes);
const attr = (node: Node, name: string) => node.getAttribute?.(name) ?? null;

const SKIP = new Set(["script", "style", "nav", "aside", "form", "button", "noscript", "svg", "iframe", "figcaption", "footer", "header", "meta", "input", "select"]);
const BLOCKS = new Set(["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "table", "figure", "img", "div", "section", "article", "main", "li", "dl", "pre"]);

/** Collapses whitespace inside runs and merges neighbours with the same style. */
export function tidy(runs: Run[]): Run[] {
  const out: Run[] = [];
  for (const run of runs) {
    const t = run.t.replace(/\s+/g, " ");
    if (!t) continue;
    const last = out.at(-1);
    if (last && last.i === run.i && last.b === run.b && last.href === run.href) last.t += t;
    else out.push({ ...run, t });
  }
  if (out.length) {
    out[0].t = out[0].t.trimStart();
    out[out.length - 1].t = out[out.length - 1].t.trimEnd();
  }
  return out.filter((r) => r.t.length > 0);
}

const plain = (runs: Run[]) => runs.map((r) => r.t).join("");

function absolute(href: string | null, base: string): string | undefined {
  if (!href || href.startsWith("#") || href.startsWith("javascript:") || href.startsWith("mailto:")) return undefined;
  try {
    const url = new URL(href, base);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : undefined;
  } catch {
    return undefined;
  }
}

function styleOf(node: Node): { i?: true; b?: true } {
  const style = (attr(node, "style") ?? "").toLowerCase();
  return {
    ...(/font-style:\s*italic/.test(style) ? { i: true as const } : {}),
    ...(/font-weight:\s*(bold|[6-9]00)/.test(style) ? { b: true as const } : {}),
  };
}

/** Inline content: text, emphasis and links. */
function inline(node: Node, base: string, style: { i?: true; b?: true; href?: string } = {}): Run[] {
  if (node.nodeType === TEXT) return [{ t: node.textContent ?? "", ...style }];
  if (node.nodeType !== ELEMENT) return [];
  const name = tag(node);
  if (SKIP.has(name) || name === "num" || name === "img") return [];
  if (name === "br") return [{ t: " ", ...style }];
  let next = { ...style, ...styleOf(node) };
  if (name === "i" || name === "em" || name === "cite") next = { ...next, i: true };
  if (name === "b" || name === "strong") next = { ...next, b: true };
  if (name === "a" || name === "ref") {
    const href = absolute(attr(node, "href"), base);
    if (href) next = { ...next, href };
  }
  return children(node).flatMap((child) => inline(child, base, next));
}

function hasBlockChild(node: Node): boolean {
  return children(node).some((c) => c.nodeType === ELEMENT && BLOCKS.has(tag(c)));
}

interface Walk {
  base: string;
  blocks: Block[];
  /** The first image's URL, when the source's images may be used. */
  image?: { src: string; alt?: string };
  images: boolean;
}

/** Walks HTML (or Akoma Ntoso) block structure into blocks. */
function walk(node: Node, w: Walk, number?: string): void {
  if (node.nodeType !== ELEMENT) return;
  const name = tag(node);
  if (SKIP.has(name)) return;
  const cls = (attr(node, "class") ?? "").toLowerCase();

  switch (name) {
    case "h1": case "h2": case "h3": case "h4": case "h5": case "h6": case "heading": {
      const runs = tidy(inline(node, w.base));
      if (runs.length) w.blocks.push({ k: "h", runs });
      return;
    }
    case "blockquote": case "embeddedstructure": {
      const inner: Walk = { ...w, blocks: [] };
      children(node).forEach((c) => walk(c, inner));
      const runs = inner.blocks.flatMap((b) => ("runs" in b ? [...b.runs, { t: " " }] : []));
      const tidied = tidy(runs.length ? runs : inline(node, w.base));
      if (tidied.length) w.blocks.push({ k: "q", runs: tidied });
      return;
    }
    case "ul": case "ol": case "blocklist": {
      const items = children(node)
        .filter((c) => c.nodeType === ELEMENT && (tag(c) === "li" || tag(c) === "item"))
        .map((li) => tidy(inline(li, w.base)))
        .filter((runs) => runs.length);
      if (items.length) w.blocks.push({ k: "list", ordered: name === "ol", items });
      return;
    }
    case "table": {
      const rows = collect(node, "tr").map((tr) =>
        children(tr).filter((c) => c.nodeType === ELEMENT && (tag(c) === "td" || tag(c) === "th"))
          .map((cell) => plain(tidy(inline(cell, w.base)))));
      const kept = rows.filter((r) => r.some((c) => c));
      if (kept.length) w.blocks.push({ k: "table", rows: kept });
      return;
    }
    case "img": {
      const src = absolute(attr(node, "src"), w.base);
      if (w.images && !w.image && src && !/\.(svg|gif)(\?|$)/i.test(src)) w.image = { src, alt: attr(node, "alt") ?? undefined };
      return;
    }
    case "paragraph": case "subparagraph": {
      // Akoma Ntoso: <num> then the content; the number goes on the first paragraph.
      const num = children(node).find((c) => c.nodeType === ELEMENT && tag(c) === "num");
      const label = num ? (num.textContent ?? "").trim().replace(/\.$/, "") : undefined;
      let pending = label;
      for (const child of children(node)) {
        if (child === num) continue;
        const before = w.blocks.length;
        walk(child, w, pending);
        if (w.blocks.length > before) pending = undefined;
      }
      return;
    }
    case "p": {
      if (/heading/.test(cls)) {
        const runs = tidy(inline(node, w.base));
        if (runs.length) w.blocks.push({ k: "h", runs });
        return;
      }
      if (hasBlockChild(node)) break;
      const runs = tidy(inline(node, w.base));
      if (runs.length) w.blocks.push({ k: "p", runs, ...(number ? { n: number } : {}) });
      for (const child of children(node)) {
        if (child.nodeType === ELEMENT && tag(child) === "img") walk(child, w);
      }
      return;
    }
    default:
      break;
  }

  // Containers: a div of plain text is a paragraph; otherwise look inside.
  if (!hasBlockChild(node) && name !== "content" && name !== "level" && name !== "li") {
    const runs = tidy(inline(node, w.base));
    if (runs.length && (name === "div" || name === "section" || name === "span" || name === "intro" || name === "wrapup")) {
      w.blocks.push({ k: "p", runs, ...(number ? { n: number } : {}) });
      return;
    }
  }
  let pending = number;
  for (const child of children(node)) {
    const before = w.blocks.length;
    walk(child, w, pending);
    if (w.blocks.length > before) pending = undefined;
  }
}

function collect(node: Node, name: string): Node[] {
  const out: Node[] = [];
  for (const child of children(node)) {
    if (child.nodeType !== ELEMENT) continue;
    if (tag(child) === name) out.push(child);
    else out.push(...collect(child, name));
  }
  return out;
}

function words(blocks: Block[]): number {
  const text = blocks.map((b) => (b.k === "list" ? b.items.flat().map((r) => r.t).join(" ") : b.k === "table" ? b.rows.flat().join(" ") : "runs" in b ? plain(b.runs) : "")).join(" ");
  return text.split(/\s+/).filter(Boolean).length;
}

/** Blocks from an HTML fragment or page element. */
export function htmlToBlocks(html: string, base: string, images = false): { blocks: Block[]; image?: { src: string; alt?: string } } {
  const { document } = parseHTML(`<!doctype html><html><body>${html}</body></html>`);
  const w: Walk = { base, blocks: [], images };
  walk(document.body as unknown as Node, w);
  return { blocks: w.blocks, image: w.image };
}

/**
 * Blocks from an Akoma Ntoso document (Find Case Law's judgments and press summaries):
 * the judgment body, or a press summary's main body with its header lines.
 */
export function aknToBlocks(xml: string, base: string): Block[] {
  const doc = new DOMParser().parseFromString(xml, "text/xml") as unknown as Node;
  const body = collect(doc, "judgmentbody")[0] ?? collect(doc, "mainbody")[0];
  if (!body) return [];
  const w: Walk = { base, blocks: [], images: false };
  if (tag(body) === "mainbody") {
    // A press summary's preface, less what the reader's header already shows ("Press
    // Summary", the date, the parties): the citation, the appeal and the justices.
    const preface = collect(doc, "preface")[0];
    if (preface) {
      walk(preface, w);
      w.blocks = w.blocks
        .filter((b) => !("runs" in b) || !/^(press summary|\d{1,2} \w+ \d{4})$|\((appellant|respondent)s?\)/i.test(plain(b.runs).trim()))
        .map((b) => (b.k === "h" ? { k: "p", runs: b.runs } : b));
    }
  }
  walk(body, w);
  return w.blocks;
}

/** Readability's main text from a whole page, for publishers who've given permission. */
export function readablePage(html: string, url: string, images = false): { title?: string; byline?: string; blocks: Block[]; image?: { src: string; alt?: string } } | null {
  const { document } = parseHTML(html);
  const article = new Readability(document as never).parse();
  if (!article?.content) return null;
  const { blocks, image } = htmlToBlocks(article.content, url, images);
  return { title: article.title ?? undefined, byline: article.byline ?? undefined, blocks, image };
}

export function articleDoc(parts: Omit<ArticleDoc, "words">): ArticleDoc {
  return { ...parts, words: words(parts.blocks) };
}

/** Too little text to be the article (a cookie wall, a stub, a parse gone wrong). */
export function tooShort(blocks: Block[], minimum = 60): boolean {
  return words(blocks) < minimum;
}

/**
 * Whether a publisher marks the page as paywalled. News sites tell search engines with
 * schema.org markup (isAccessibleForFree: false) on subscriber-only articles.
 */
export function isPaywalledPage(html: string): boolean {
  return /"isAccessibleForFree"\s*:\s*"?(false|False)"?/.test(html)
    || /<meta[^>]+(name|property)="(article:content_tier|content_tier)"[^>]+content="(locked|metered|premium)"/i.test(html);
}

/** Domains whose articles are behind a paywall. */
export const PAYWALLED_DOMAINS = ["thetimes.com", "thetimes.co.uk", "ft.com", "law360.com", "telegraph.co.uk", "economist.com", "thelawyer.com"];

export function paywalledDomain(url: string): boolean {
  try {
    const host = new URL(url).hostname.replace(/^www\./, "");
    return PAYWALLED_DOMAINS.some((d) => host === d || host.endsWith(`.${d}`));
  } catch {
    return false;
  }
}
