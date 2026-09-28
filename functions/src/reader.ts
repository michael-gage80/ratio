// Fetches a story's text for the in-app reader and stores it in Cloud Storage at
// news/{id}/{part}.json (a judgment can outgrow a Firestore document). Each source has
// its own route to clean text (news.ts `extractor`); publishers' pages go through
// Readability, but only once their full-text switch is on (config/news).

import { getStorage } from "firebase-admin/storage";
import { parseHTML } from "linkedom";
import { aknToBlocks, ArticleDoc, articleDoc, Block, htmlToBlocks, isPaywalledPage, paywalledDomain, readablePage, tooShort } from "./article.js";
import { Source } from "./news.js";

const USER_AGENT = "Ratio legal news (educational app for UK law students)";
const WORDS_PER_MINUTE = 230;

export type ReaderPart = "article" | "summary" | "judgment";

/** What the app needs on the story to offer the reader. */
export interface ReaderInfo {
  parts: ReaderPart[];
  minutes: number;
}

export type ReaderResult =
  | { status: "done"; reader: ReaderInfo }
  /** Not ready yet (an Act's explanatory notes come out after the Act); try again later. */
  | { status: "pending" }
  /** No clean text: the app opens the page in Safari's Reader view instead. */
  | { status: "failed" };

export class NotYet extends Error {}

async function get(url: string, accept = "text/html"): Promise<Response> {
  const response = await fetch(url, { headers: { "User-Agent": USER_AGENT, Accept: accept }, redirect: "follow", signal: AbortSignal.timeout(15_000) });
  return response;
}

async function text(url: string, accept?: string): Promise<string> {
  const response = await get(url, accept);
  if (response.status === 404) throw new NotYet(`404 ${url}`);
  if (!response.ok) throw new Error(`HTTP ${response.status} ${url}`);
  return response.text();
}

export interface StoryInput {
  id: string;
  title: string;
  url: string;
  html?: string;
}

interface Extracted {
  parts: { part: ReaderPart; blocks: Block[]; byline?: string }[];
  image?: { src: string; alt?: string };
  /** Fewer words than this means the parse went wrong. */
  minimum: number;
}

const para = (t: string, i = false): Block => ({ k: "p", runs: [{ t, ...(i ? { i: true as const } : {}) }] });

async function extract(story: StoryInput, source: Source, images: boolean): Promise<Extracted> {
  switch (source.extractor) {
    case "uksc": {
      const [summary, judgment] = await Promise.all([
        text(`${story.url}/press-summary/data.xml`, "application/xml").then((xml) => aknToBlocks(xml, story.url)).catch(() => []),
        text(`${story.url}/data.xml`, "application/xml").then((xml) => aknToBlocks(xml, story.url)),
      ]);
      return {
        parts: [...(summary.length ? [{ part: "summary" as const, blocks: summary }] : []), { part: "judgment", blocks: judgment }],
        minimum: 200,
      };
    }
    case "legislation": {
      const act = story.url.match(/^https:\/\/www\.legislation\.gov\.uk\/ukpga\/\d{4}\/\d+/)?.[0];
      if (!act) throw new Error("Not an Act");
      // Explanatory notes are published after the Act; until then, NotYet.
      const contents = parseHTML(await text(`${act}/notes/contents`)).document;
      const links = [...contents.querySelectorAll("#toc a")].map((a) => ({ text: a.textContent ?? "", href: a.getAttribute("href") ?? "" }));
      const overview = links.find((l) => /overview|summary/i.test(l.text)) ?? links[0];
      const division = overview?.href.match(/(\d+)\/index\.htm/)?.[1];
      if (!division) throw new NotYet("No notes yet");
      const url = `${act}/notes/division/${division}/index.htm`;
      const page = parseHTML(await text(url)).document;
      const article = page.querySelector("#full-pane article") ?? page.querySelector("article");
      return { parts: [{ part: "article", blocks: article ? htmlToBlocks(article.innerHTML, url).blocks : [] }], minimum: 40 };
    }
    case "bills": {
      const id = story.url.match(/\/bills\/(\d+)/)?.[1];
      if (!id) throw new Error("Not a bill");
      const bill = JSON.parse(await text(`https://bills-api.parliament.uk/api/v1/Bills/${id}`, "application/json")) as {
        longTitle?: string;
        summary?: string | null;
        currentStage?: { description?: string; house?: string };
        sponsors?: { member?: { name?: string; party?: string } }[];
        isAct?: boolean;
      };
      const sponsor = bill.sponsors?.[0]?.member;
      const blocks: Block[] = [
        ...(bill.longTitle ? [para(bill.longTitle, true)] : []),
        ...(bill.currentStage?.description ? [{ k: "h", runs: [{ t: "Where it is" }] } as Block, para(`${bill.isAct ? "Now an Act" : `${bill.currentStage.house ?? "Parliament"} · ${bill.currentStage.description}`}`)] : []),
        ...(sponsor?.name ? [para(`Sponsored by ${sponsor.name}${sponsor.party ? ` (${sponsor.party})` : ""}.`)] : []),
        ...(bill.summary ? [{ k: "h", runs: [{ t: "Summary" }] } as Block, ...htmlToBlocks(bill.summary, story.url).blocks] : []),
        { k: "p", runs: [{ t: "Read the bill and its explanatory notes", href: `https://bills.parliament.uk/bills/${id}/publications` }] },
      ];
      return { parts: [{ part: "article", blocks }], minimum: 15 };
    }
    case "feed": {
      const { blocks, image } = htmlToBlocks(story.html ?? "", story.url, images);
      return { parts: [{ part: "article", blocks }], image, minimum: 20 };
    }
    case "page": {
      const html = await text(story.url);
      if (isPaywalledPage(html)) return { parts: [], minimum: Infinity };
      const page = readablePage(html, story.url, images);
      return { parts: [{ part: "article", blocks: page?.blocks ?? [], byline: page?.byline }], image: page?.image, minimum: 120 };
    }
  }
}

/** Copies the lead image into Storage (open-licence sources only, see config/news). */
async function storeImage(id: string, image: { src: string; alt?: string }): Promise<Block | null> {
  try {
    const response = await get(image.src, "image/*");
    const type = response.headers.get("content-type") ?? "";
    if (!response.ok || !/^image\/(jpeg|png|webp)/.test(type)) return null;
    const data = Buffer.from(await response.arrayBuffer());
    if (data.length > 3_000_000) return null;
    const path = `news/${id}/lead.${type.split("/")[1].replace("jpeg", "jpg")}`;
    await getStorage().bucket().file(path).save(data, { contentType: type, metadata: { cacheControl: "public, max-age=604800" } });
    return { k: "img", src: path, ...(image.alt ? { alt: image.alt } : {}) };
  } catch {
    return null;
  }
}

/** Extracts and stores a story's text, returning what to put on the story. */
export async function buildReader(story: StoryInput, source: Source, images: boolean): Promise<ReaderResult> {
  let extracted: Extracted;
  try {
    extracted = await extract(story, source, images);
  } catch (error) {
    return error instanceof NotYet ? { status: "pending" } : { status: "failed" };
  }
  const parts = extracted.parts.filter((p) => !tooShort(p.blocks, extracted.minimum));
  if (parts.length === 0) return { status: "failed" };
  const lead = extracted.image ? await storeImage(story.id, extracted.image) : null;
  const bucket = getStorage().bucket();
  let words = 0;
  for (const [index, part] of parts.entries()) {
    const doc: ArticleDoc = articleDoc({
      title: story.title,
      source: source.name,
      url: story.url,
      licence: source.licence ?? `© ${source.name}. Shown with permission.`,
      ...(part.byline ? { byline: part.byline } : {}),
      blocks: index === 0 && lead ? [lead, ...part.blocks] : part.blocks,
    });
    // The first part is what the reader opens with; a judgment's length would overstate it.
    if (index === 0) words = doc.words;
    await bucket.file(`news/${story.id}/${part.part}.json`).save(JSON.stringify(doc), {
      contentType: "application/json",
      metadata: { cacheControl: "public, max-age=3600" },
    });
  }
  return { status: "done", reader: { parts: parts.map((p) => p.part), minutes: Math.max(1, Math.round(words / WORDS_PER_MINUTE)) } };
}

/** Whether a story is subscriber-only: by source, by domain, or by the page's own markup. */
export async function checkPaywall(url: string, source: Source): Promise<boolean> {
  if (source.paywall === "always" || paywalledDomain(url)) return true;
  if (source.paywall === "never") return false;
  try {
    const response = await get(url);
    return response.ok ? isPaywalledPage(await response.text()) : false;
  } catch {
    return false;
  }
}
