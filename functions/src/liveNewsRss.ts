import { createHash } from "crypto";
import { XMLParser } from "fast-xml-parser";
import { LiveNewsEvent } from "./liveNewsCore";

export const NEWS_FEEDS = ["world", "business", "science_and_environment", "technology"].map(category => ({
  url: `https://feeds.bbci.co.uk/news/${category}/rss.xml`, category,
}));
const MAX_BYTES = 2 * 1024 * 1024;
const parser = new XMLParser({ ignoreAttributes: true, processEntities: true });
function text(value: unknown, limit: number): string {
  return typeof value === "string" ? value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim().slice(0, limit) : "";
}

/** Use publisher headlines and short descriptions, never full articles or invented locations. */
export function parseNewsRss(xml: string, category: string, nowMs = Date.now()): LiveNewsEvent[] {
  if (Buffer.byteLength(xml) > MAX_BYTES || /<!DOCTYPE|<!ENTITY/i.test(xml)) return [];
  const items = parser.parse(xml)?.rss?.channel?.item;
  const rows = Array.isArray(items) ? items : items ? [items] : [];
  const events = new Map<string, LiveNewsEvent>();
  for (const item of rows.slice(0, 100)) {
    const title = text(item.title, 220);
    const description = text(item.description, 520);
    const timestamp = Date.parse(item.pubDate);
    if (!title || !Number.isFinite(timestamp) || nowMs - timestamp > 48 * 3600_000 || timestamp - nowMs > 3600_000) continue;
    let url: URL;
    try { url = new URL(item.link); } catch { continue; }
    if (url.protocol !== "https:" || url.username || url.password || !["www.bbc.co.uk", "www.bbc.com", "bbc.co.uk", "bbc.com"].includes(url.hostname)) continue;
    url.hash = "";
    url.search = "";
    const id = `rss-${createHash("sha256").update(url.toString()).digest("hex").slice(0, 24)}`;
    const publishedAt = new Date(timestamp).toISOString();
    events.set(id, {
      id, title, summary: description || "Read the original report from BBC News.",
      status: "top", place: "World news", coords: null, scope: "global", category,
      publishedAt, updatedAt: publishedAt, confidence: 0.5,
      sources: [{ publisher: "BBC News", url: url.toString(), publishedAt }], media: [],
    });
  }
  return [...events.values()];
}

export async function fetchRssNews(): Promise<LiveNewsEvent[]> {
  const results = await Promise.allSettled(NEWS_FEEDS.map(async feed => {
    const response = await fetch(feed.url, {
      signal: AbortSignal.timeout(15_000), redirect: "error",
      headers: { Accept: "application/rss+xml, application/xml", "User-Agent": "Poplur-News/1.0 (+https://poplur.com)" },
    });
    if (!response.ok || !response.body) throw new Error(`news_rss_http_${response.status}`);
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let bytes = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        bytes += value.byteLength;
        if (bytes > MAX_BYTES) throw new Error("news_rss_too_large");
        chunks.push(value);
      }
    } finally { await reader.cancel(); }
    return parseNewsRss(Buffer.concat(chunks).toString("utf8"), feed.category);
  }));
  const unique = new Map<string, LiveNewsEvent>();
  for (const result of results) {
    if (result.status === "fulfilled") for (const event of result.value) unique.set(event.id, event);
  }
  return [...unique.values()].sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt)).slice(0, 40);
}
