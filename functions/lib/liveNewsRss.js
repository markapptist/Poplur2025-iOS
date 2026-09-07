"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NEWS_FEEDS = void 0;
exports.parseNewsRss = parseNewsRss;
exports.fetchRssNews = fetchRssNews;
const crypto_1 = require("crypto");
const fast_xml_parser_1 = require("fast-xml-parser");
exports.NEWS_FEEDS = ["world", "business", "science_and_environment", "technology"].map(category => ({
    url: `https://feeds.bbci.co.uk/news/${category}/rss.xml`, category,
}));
const MAX_BYTES = 2 * 1024 * 1024;
const parser = new fast_xml_parser_1.XMLParser({ ignoreAttributes: true, processEntities: true });
function text(value, limit) {
    return typeof value === "string" ? value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim().slice(0, limit) : "";
}
/** Use publisher headlines and short descriptions, never full articles or invented locations. */
function parseNewsRss(xml, category, nowMs = Date.now()) {
    if (Buffer.byteLength(xml) > MAX_BYTES || /<!DOCTYPE|<!ENTITY/i.test(xml))
        return [];
    const items = parser.parse(xml)?.rss?.channel?.item;
    const rows = Array.isArray(items) ? items : items ? [items] : [];
    const events = new Map();
    for (const item of rows.slice(0, 100)) {
        const title = text(item.title, 220);
        const description = text(item.description, 520);
        const timestamp = Date.parse(item.pubDate);
        if (!title || !Number.isFinite(timestamp) || nowMs - timestamp > 48 * 3600_000 || timestamp - nowMs > 3600_000)
            continue;
        let url;
        try {
            url = new URL(item.link);
        }
        catch {
            continue;
        }
        if (url.protocol !== "https:" || url.username || url.password || !["www.bbc.co.uk", "www.bbc.com", "bbc.co.uk", "bbc.com"].includes(url.hostname))
            continue;
        url.hash = "";
        url.search = "";
        const id = `rss-${(0, crypto_1.createHash)("sha256").update(url.toString()).digest("hex").slice(0, 24)}`;
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
async function fetchRssNews() {
    const results = await Promise.allSettled(exports.NEWS_FEEDS.map(async (feed) => {
        const response = await fetch(feed.url, {
            signal: AbortSignal.timeout(15_000), redirect: "error",
            headers: { Accept: "application/rss+xml, application/xml", "User-Agent": "Poplur-News/1.0 (+https://poplur.com)" },
        });
        if (!response.ok || !response.body)
            throw new Error(`news_rss_http_${response.status}`);
        const reader = response.body.getReader();
        const chunks = [];
        let bytes = 0;
        try {
            while (true) {
                const { done, value } = await reader.read();
                if (done)
                    break;
                bytes += value.byteLength;
                if (bytes > MAX_BYTES)
                    throw new Error("news_rss_too_large");
                chunks.push(value);
            }
        }
        finally {
            await reader.cancel();
        }
        return parseNewsRss(Buffer.concat(chunks).toString("utf8"), feed.category);
    }));
    const unique = new Map();
    for (const result of results) {
        if (result.status === "fulfilled")
            for (const event of result.value)
                unique.set(event.id, event);
    }
    return [...unique.values()].sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt)).slice(0, 40);
}
