import { createHash } from "crypto";
import { LiveNewsAuthor, LiveNewsEvent, LiveNewsMedia } from "./liveNewsCore";

/** Reviewed domain handles, pinned to immutable identities to resist handle reuse. */
export const NEWS_ACCOUNTS = [
  ["news.abc.net.au", "7v6ep3lckb5f2uaw62b4khev", "Australia"],
  ["reuters.com", "jbvnehrrdqoulco4rf5gxg5r", "Global"],
  ["apnews.com", "a67zdrt4nl2tv2qojpngogbq", "Global"],
  ["france24.com", "wkreszch2k4mumsrlkeaflgn", "France"],
  ["theguardian.com", "vovinwhtulbsx4mwfw26r5ni", "United Kingdom"],
  ["aljazeera.com", "2lofqead276vtc5647ye7sl2", "Qatar / Global"],
  ["lemonde.fr", "qqxqxgdu5z3he2piqfbfaku4", "France"],
  ["elpais.com", "u6mkbcgviwlbhuwqirmhcgu3", "Spain / Latin America"],
  ["restofworld.org", "hbdc3q6k5lforao5vyuarvsp", "Global"],
].map(([handle, id, region]) => ({ handle, id: `did:plc:${id}`, region }));
type Account = typeof NEWS_ACCOUNTS[number];
function object(value: unknown): Record<string, any> { // Provider JSON is validated field by field below.
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, any> : {};
}
function text(value: unknown, limit = 1000): string {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}
function cdn(value: unknown): string | undefined {
  try {
    const url = new URL(String(value));
    if (url.protocol === "https:" && ["cdn.bsky.app", "video.bsky.app"].includes(url.hostname) && !url.username && !url.password) return url.toString();
  } catch { /* omit unsupported assets */ }
  return undefined;
}
export function parseSocialFeed(value: unknown, account: Account, nowMs = Date.now(), profileValue?: unknown): LiveNewsEvent[] {
  const feed = object(value).feed;
  if (!Array.isArray(feed)) return [];
  const events = new Map<string, LiveNewsEvent>();
  for (const row of feed.slice(0, 50)) {
    const post = object(object(row).post), record = object(post.record), author = object(post.author);
    if (author.did !== account.id || author.handle !== account.handle || object(row).reason || record.reply) continue;
    if ([...(Array.isArray(post.labels) ? post.labels : []), ...(Array.isArray(author.labels) ? author.labels : [])].some(label => !object(label).neg)) continue;
    const body = text(record.text), time = Date.parse(record.createdAt);
    const key = text(post.uri).split('/').pop() ?? '';
    if (!body || !/^[a-z0-9]+$/.test(key) || post.uri !== `at://${account.id}/app.bsky.feed.post/${key}` || !Number.isFinite(time) || nowMs-time > 48*3600_000 || time-nowMs > 3600_000) continue;
    const sourceUrl = `https://bsky.app/profile/${account.id}/post/${key}`;
    const profile = object(profileValue);
    const identity: LiveNewsAuthor = {
      id: account.id, name: text(author.displayName,100) || account.handle,
      handle: account.handle, profileUrl: `https://bsky.app/profile/${account.id}`,
      platform: "Bluesky", region: account.region,
      ...(cdn(author.avatar) ? { avatar: cdn(author.avatar) } : {}),
      ...(profile.did === account.id && text(profile.description,400) ? { bio: text(profile.description,400) } : {}),
    };
    const embed = object(post.embed), media: LiveNewsMedia[] = [];
    if (embed.$type === "app.bsky.embed.video#view" && cdn(embed.thumbnail)) {
      media.push({ kind: "video", src: cdn(embed.thumbnail)!, poster: cdn(embed.thumbnail),
        embedUrl: `https://embed.bsky.app/embed/${account.id}/app.bsky.feed.post/${key}`,
        credit: identity.name, sourceUrl, rights: "official-embed" });
    } else {
      const images = embed.$type === "app.bsky.embed.images#view" ? embed.images : [];
      for (const image of (Array.isArray(images) ? images : []).slice(0,4)) {
        const src = cdn(object(image).thumb);
        if (src) media.push({ kind: "photo", src, credit: identity.name, sourceUrl, rights: "provider-thumbnail" });
      }
      const thumbnail = cdn(object(embed.external).thumb);
      if (!media.length && thumbnail) media.push({ kind: "photo", src: thumbnail, credit: identity.name, sourceUrl, rights: "provider-thumbnail" });
    }
    const hashtags = new Set<string>();
    for (const facet of Array.isArray(record.facets) ? record.facets : []) {
      for (const feature of Array.isArray(object(facet).features) ? facet.features : []) {
        const tag = text(object(feature).tag,64);
        if (feature.$type === 'app.bsky.richtext.facet#tag' && /^[\p{L}\p{N}_]+$/u.test(tag)) hashtags.add(tag);
      }
    }
    const publishedAt = new Date(time).toISOString();
    events.set(sourceUrl, {
      id: `social-${createHash('sha256').update(post.uri).digest('hex').slice(0,24)}`,
      title: text(object(embed.external).title,220) || body.slice(0,220), summary: body,
      author: identity, hashtags: [...hashtags].slice(0,12),
      status: 'top', place: 'World news', coords: null, scope: 'global', category: 'world',
      publishedAt, updatedAt: publishedAt, confidence: .5,
      sources: [{ publisher: identity.name, url: sourceUrl, publishedAt }], media,
    });
  }
  return [...events.values()];
}
async function request(path: string): Promise<unknown> {
  const response = await fetch(`https://public.api.bsky.app/xrpc/${path}`, { signal: AbortSignal.timeout(12000), redirect: 'error', headers: { Accept: 'application/json' } });
  if (!response.ok || !response.body) throw new Error(`social_news_http_${response.status}`);
  const reader = response.body.getReader(), chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 2*1024*1024) throw new Error('social_news_response_too_large');
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
export async function fetchSocialNews(): Promise<LiveNewsEvent[]> {
  const profiles = object(await request(`app.bsky.actor.getProfiles?${NEWS_ACCOUNTS.map(a => `actors=${encodeURIComponent(a.id)}`).join('&')}`).catch(() => ({}))).profiles;
  const result: LiveNewsEvent[] = [];
  for (let i=0; i<NEWS_ACCOUNTS.length; i+=3) {
    const rows = await Promise.allSettled(NEWS_ACCOUNTS.slice(i,i+3).map(async account => {
      const feed = await request(`app.bsky.feed.getAuthorFeed?actor=${encodeURIComponent(account.id)}&filter=posts_no_replies&limit=30`);
      const parsed = parseSocialFeed(feed,account,Date.now(),Array.isArray(profiles) ? profiles.find(p => p.did === account.id) : null);
      // Preserve a few recent videos without allowing one prolific source to dominate.
      const videos = parsed.filter(p => p.media.some(m => m.kind === 'video')).slice(0,3);
      return [...videos,...parsed.filter(p => !videos.includes(p)).slice(0,8-videos.length)];
    }));
    for (const row of rows) if (row.status === 'fulfilled') result.push(...row.value);
  }
  return result;
}
