import assert from "node:assert/strict";
import { test } from "node:test";
import { dedupe, isLegal, modulesFor, parseFeed, sameStory, SOURCES } from "./news.js";

const source = (id: string) => SOURCES.find((s) => s.id === id)!;

const rss = `<?xml version="1.0"?><rss version="2.0"><channel><title>Law</title>
<item><title><![CDATA[Supreme Court rules on &#8216;virtual certainty&#8217; direction]]></title><link>https://www.theguardian.com/law/2026/sep/22/one</link><pubDate>Tue, 22 Sep 2026 10:00:00 GMT</pubDate><description>Full article text we must never keep</description></item>
<item><title>US judge blocks policy</title><link>https://www.theguardian.com/us-news/2026/sep/22/two</link><pubDate>Tue, 22 Sep 2026 09:00:00 GMT</pubDate></item>
<item><title>No link</title><pubDate>Tue, 22 Sep 2026 09:00:00 GMT</pubDate></item>
</channel></rss>`;

const atom = `<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Latest</title>
<entry><title>R (on the application of Quaye) v Secretary of State for Justice</title>
<link href="https://caselaw.nationalarchives.gov.uk/uksc/2026/34" rel="alternate"/>
<published>2026-09-22T00:00:00+00:00</published>
<link href="https://caselaw.nationalarchives.gov.uk/uksc/2026/34/data.xml" rel="alternate" type="application/akn+xml"/></entry></feed>`;

test("RSS items keep headline, link and date only, and skip excluded sections", () => {
  const items = parseFeed(rss, source("guardian"));
  assert.equal(items.length, 1);
  assert.equal(items[0].title, "Supreme Court rules on ‘virtual certainty’ direction");
  assert.equal(items[0].url, "https://www.theguardian.com/law/2026/sep/22/one");
  assert.equal(items[0].publishedAt.toISOString(), "2026-09-22T10:00:00.000Z");
  assert.equal(JSON.stringify(items).includes("Full article"), false);
});

test("Atom entries use the page link, not the data file", () => {
  const [item] = parseFeed(atom, source("uksc"));
  assert.equal(item.url, "https://caselaw.nationalarchives.gov.uk/uksc/2026/34");
  assert.equal(item.source, "UK Supreme Court");
});

test("general news is kept only when it's about the law", () => {
  assert.equal(isLegal("Man jailed for life for murder of teenager"), true);
  assert.equal(isLegal("Supreme Court rules on Rwanda policy"), true);
  assert.equal(isLegal("Heatwave to hit southern England"), false);
  const bbc = rss.replace(/theguardian\.com\/law/g, "bbc.co.uk/news").replace("Supreme Court rules on &#8216;virtual certainty&#8217; direction", "Weather warning issued");
  assert.deepEqual(parseFeed(bbc, source("bbc")).map((i) => i.title), ["US judge blocks policy"]);
});

test("headlines are tagged with the modules they touch", () => {
  assert.deepEqual(modulesFor("Man jailed for murder after jury trial"), ["crime"]);
  assert.equal(modulesFor("Landlord loses eviction appeal over leasehold flat")[0], "land");
  assert.equal(modulesFor("Home Office policy unlawful, judicial review finds")[0], "public");
  assert.deepEqual(modulesFor("Firm announces new trainee intake"), []);
  assert.deepEqual(modulesFor("Lawyers say secret commissions fight will continue"), []);
  assert.equal(modulesFor("R (on the application of Quaye) v Secretary of State for Justice")[0], "public");
  assert.equal(modulesFor("Court rules on trustee's duty under the will of her father")[0], "equity");
});

test("the same story from two sources is kept once", () => {
  assert.equal(sameStory("Supreme Court rules Rwanda asylum policy unlawful", "Rwanda asylum policy unlawful, Supreme Court rules"), true);
  assert.equal(sameStory("Supreme Court rules Rwanda policy unlawful", "Barrister struck off for misconduct"), false);
  const a = { sourceId: "uksc", source: "UK Supreme Court", title: "Rwanda asylum policy unlawful, Supreme Court rules", url: "https://a/1", publishedAt: new Date() };
  const b = { ...a, sourceId: "bbc", source: "BBC News", title: "Supreme Court rules Rwanda asylum policy unlawful", url: "https://b/1" };
  const c = { ...a, title: "Something else entirely happened", url: "https://c/1" };
  assert.deepEqual(dedupe([a, b, c]).map((i) => i.url), ["https://a/1", "https://c/1"]);
  assert.deepEqual(dedupe([b], [{ url: "https://a/1", title: a.title }]), []);
});
