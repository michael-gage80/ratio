import assert from "node:assert/strict";
import { test } from "node:test";
import { aknToBlocks, articleDoc, htmlToBlocks, isPaywalledPage, paywalledDomain, tidy, tooShort } from "./article.js";
import { capped } from "./newsIngest.js";
import { NewsItem, parseFeed, SOURCES } from "./news.js";

const source = (id: string) => SOURCES.find((s) => s.id === id)!;

test("HTML becomes headings, paragraphs with links and emphasis, quotes, lists and tables", () => {
  const { blocks } = htmlToBlocks(`
    <nav>Menu</nav><h2>What happened</h2>
    <p>The <em>Court of Appeal</em> said <a href="/judgments/1">the judge</a> erred.</p>
    <blockquote><p>It was not open to him.</p></blockquote>
    <ul><li>First</li><li>Second</li></ul>
    <table><tr><th>Year</th><th>Cases</th></tr><tr><td>2025</td><td>12</td></tr></table>
    <script>track()</script>`, "https://example.org/news/story");
  assert.deepEqual(blocks.map((b) => b.k), ["h", "p", "q", "list", "table"]);
  const p = blocks[1];
  assert.ok(p.k === "p");
  assert.deepEqual(p.runs, [
    { t: "The " }, { t: "Court of Appeal", i: true }, { t: " said " },
    { t: "the judge", href: "https://example.org/judgments/1" }, { t: " erred." },
  ]);
  assert.deepEqual(blocks[4].k === "table" && blocks[4].rows, [["Year", "Cases"], ["2025", "12"]]);
});

test("images are taken only when allowed", () => {
  const html = `<p>Text</p><img src="https://example.org/lead.jpg" alt="The court">`;
  assert.equal(htmlToBlocks(html, "https://example.org/").image, undefined);
  assert.deepEqual(htmlToBlocks(html, "https://example.org/", true).image, { src: "https://example.org/lead.jpg", alt: "The court" });
});

test("judgment paragraphs keep their numbers; heading styles become headings", () => {
  const xml = `<akomaNtoso xmlns="http://docs.oasis-open.org/legaldocml/ns/akn/3.0"><judgment><header><p>Counsel list</p></header>
    <judgmentBody><decision>
      <paragraph eId="para_1"><num>1.</num><content><p class="Paraheading2">Introduction</p></content></paragraph>
      <paragraph eId="lvl_1"><num>1.</num><content><p>The issue is <span style="font-style:italic">mens rea</span>, see <ref href="http://www.legislation.gov.uk/id/ukpga/1998/42">the 1998 Act</ref>.</p></content></paragraph>
      <paragraph eId="lvl_2"><num>2.</num><content><p>Second.</p><embeddedStructure><p>A quoted passage.</p></embeddedStructure></content></paragraph>
    </decision></judgmentBody></judgment></akomaNtoso>`;
  const blocks = aknToBlocks(xml, "https://caselaw.nationalarchives.gov.uk/uksc/2026/34");
  assert.deepEqual(blocks.map((b) => [b.k, "n" in b ? b.n : undefined]), [["h", undefined], ["p", "1"], ["p", "2"], ["q", undefined]]);
  const first = blocks[1];
  assert.ok(first.k === "p");
  assert.deepEqual(first.runs.map((r) => [r.t, r.i ?? false, r.href ?? ""]), [
    ["The issue is ", false, ""], ["mens rea", true, ""], [", see ", false, ""], ["the 1998 Act", false, "http://www.legislation.gov.uk/id/ukpga/1998/42"], [".", false, ""],
  ]);
});

test("whitespace is tidied and empty runs dropped", () => {
  assert.deepEqual(tidy([{ t: "  Hello\n  " }, { t: "world " }, { t: "" }]), [{ t: "Hello world" }]);
});

test("word counts and the too-short guard", () => {
  const doc = articleDoc({ title: "", source: "", url: "", licence: "", blocks: [{ k: "p", runs: [{ t: "one two three" }] }] });
  assert.equal(doc.words, 3);
  assert.ok(tooShort(doc.blocks));
});

test("paywalls: schema.org markup and known domains", () => {
  assert.ok(isPaywalledPage(`<script type="application/ld+json">{"@type":"NewsArticle","isAccessibleForFree": false}</script>`));
  assert.ok(isPaywalledPage(`{"isAccessibleForFree":"False"}`));
  assert.ok(!isPaywalledPage(`{"isAccessibleForFree": true}`));
  assert.ok(paywalledDomain("https://www.thetimes.com/uk/law/article/x"));
  assert.ok(paywalledDomain("https://www.ft.com/content/abc"));
  assert.ok(!paywalledDomain("https://www.theguardian.com/law/2026/sep/22/x"));
});

test("Google News titles lose the publisher suffix; section fronts are dropped", () => {
  const rss = `<rss><channel>
    <item><title>Judge should not have heard case from bed, Court of Appeal says - The Times</title><link>https://news.google.com/rss/articles/abc</link><pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate></item>
    <item><title>Latest Legal News - Solicitors Journal</title><link>https://news.google.com/rss/articles/def</link><pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate></item>
  </channel></rss>`;
  assert.deepEqual(parseFeed(rss, source("times")).map((i) => i.title), ["Judge should not have heard case from bed, Court of Appeal says"]);
  assert.deepEqual(parseFeed(rss, source("solicitorsjournal")).map((i) => i.title), ["Judge should not have heard case from bed, Court of Appeal says"]);
});

test("feed HTML is kept only for sources read from their feed", () => {
  const rss = `<rss><channel><item><title>Court reform briefing on judicial review</title><link>https://commonslibrary.parliament.uk/research-briefings/cbp-1/</link>
    <pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate><content:encoded><![CDATA[<p>Summary text.</p>]]></content:encoded></item></channel></rss>`;
  assert.equal(parseFeed(rss, source("commonslibrary"))[0].html, "<p>Summary text.</p>");
  assert.equal(parseFeed(rss.replace("commonslibrary.parliament.uk", "www.theguardian.com/law"), source("guardian"))[0].html, undefined);
});

test("bills must tag a module, and legislation links become https", () => {
  const rss = `<rss><channel>
    <item><title>Sovereign Grant Bill</title><link>https://bills.parliament.uk/bills/4280</link><pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate></item>
    <item><title>Renters' Rights Bill</title><link>https://bills.parliament.uk/bills/4281</link><pubDate>Mon, 28 Sep 2026 10:00:00 GMT</pubDate></item>
  </channel></rss>`;
  assert.deepEqual(parseFeed(rss, source("bills")).map((i) => i.title), ["Renters' Rights Bill"]);
  const atom = `<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Steel Industry Act 2026</title><link href="http://www.legislation.gov.uk/ukpga/2026/27/2026-07-15"/><published>2026-09-28T00:00:00Z</published></entry></feed>`;
  assert.equal(parseFeed(atom, source("acts"))[0].url, "https://www.legislation.gov.uk/ukpga/2026/27/2026-07-15");
});

test("high-volume sources are capped per day, best matches first", () => {
  const item = (sourceId: string, title: string, hour: number): NewsItem => ({ sourceId, source: sourceId, title, url: `https://x/${title}`, publishedAt: new Date(Date.UTC(2026, 8, 28, hour)) });
  const items = [
    item("bills", "Tenancy Bill", 9), item("bills", "Divorce and custody Bill", 8), item("bills", "Company directors Bill", 7),
    item("bills", "Murder sentencing Bill", 6), item("guardian", "Anything", 5),
  ];
  const kept = capped(items, { bills: 1 });
  assert.deepEqual(kept.map((i) => i.title), ["Tenancy Bill", "Divorce and custody Bill", "Anything"]);
});
