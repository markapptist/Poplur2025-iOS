/** Pure contracts for spatial discovery. Coordinates are PUBLIC approximate origins. */
export const MAP_SCHEMA = 1;
export const CELL_KM = 5;
export const CELL_ROWS = Math.ceil(Math.PI * 6371 / CELL_KM);
export const REGION_DEPTH = 10;
export const MAX_MAP_FEATURES = 200;
export const MAX_REGION_TILES = 64;
export const MAP_PAGE_SIZE = 50;
export const MAX_LOCAL_CELLS = 24;
export const RANK_HALF_LIFE_MS = 6 * 3600_000;
export const RANK_WINDOW_MS = 6 * 3600_000;
export const RANK_MAX_AGE_MS = 72 * 3600_000;
export const CHALLENGER_HOLD_MS = 120_000;
const EPOCH = Date.UTC(2026, 0, 1);
const TAU = RANK_HALF_LIFE_MS / Math.LN2;
export type Cohort = 'real' | 'test';
export type Bounds = { west: number; south: number; east: number; north: number };
export type Cell = { id: string; center: [number, number]; bounds: Bounds };
export type Region = { z: number; x: number; y: number };
export type Rank = { at: number; views: number; positive: number; negative: number; growth: number };
export type Candidate = {
  postId: string; ownerId: string; cellId: string; cohort: Cohort;
  latitude: number; longitude: number; createdAtMillis: number;
  rankKey: number; exposure: number; rankAt: number; expiresAtMillis: number;
  rankBucket?: number; rankEligible?: boolean;
};
export const wrapLongitude = (lng: number) => ((lng + 180) % 360 + 360) % 360 - 180;
const clamp = (n: number, a: number, b: number) => Math.max(a, Math.min(b, n));
export function millis(value: unknown): number {
  if (value && typeof (value as { toMillis?: unknown }).toMillis === 'function') return (value as { toMillis: () => number }).toMillis();
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}
export function cellColumns(row: number): number {
  const lat = -90 + (row + .5) * 180 / CELL_ROWS;
  return Math.max(1, Math.round(2 * Math.PI * 6371 * Math.cos(lat * Math.PI / 180) / CELL_KM));
}
export function cellFromIndices(row: number, col: number): Cell {
  if (!Number.isInteger(row) || row < 0 || row >= CELL_ROWS) throw new Error('Invalid cell row');
  const columns = cellColumns(row);
  if (!Number.isInteger(col) || col < 0 || col >= columns) throw new Error('Invalid cell column');
  const south = -90 + row * 180 / CELL_ROWS, west = -180 + col * 360 / columns;
  const north = south + 180 / CELL_ROWS, east = west + 360 / columns;
  return { id: `c${row}.${col}`, center: [(west + east) / 2, (south + north) / 2], bounds: { west, south, east, north } };
}
export function parseCell(id: string): Cell {
  const m = /^c(\d{1,4})\.(\d{1,4})$/.exec(id);
  if (!m) throw new Error('Invalid cell ID');
  return cellFromIndices(Number(m[1]), Number(m[2]));
}
export function competitionCell(lat: number, lng: number): Cell {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90) throw new Error('Invalid coordinates');
  const row = clamp(Math.floor((lat + 90) / 180 * CELL_ROWS), 0, CELL_ROWS - 1);
  return cellFromIndices(row, Math.floor((wrapLongitude(lng) + 180) / 360 * cellColumns(row)));
}
export function longitudeRanges(bounds: Bounds): Array<[number, number]> {
  if (Math.abs(bounds.east - bounds.west) >= 359.999) return [[-180, 180]];
  const w = wrapLongitude(bounds.west), e = wrapLongitude(bounds.east);
  return w <= e ? [[w, e]] : [[w, 180], [-180, e]];
}
export function inBounds(lat: number, lng: number, b: Bounds): boolean {
  return lat >= b.south && lat <= b.north && longitudeRanges(b).some(([w, e]) => wrapLongitude(lng) >= w && wrapLongitude(lng) <= e);
}
/** Stop enumerating immediately at budget; a world request never allocates all cells. */
export function visibleCells(bounds: Bounds, maximum = MAX_MAP_FEATURES): Cell[] | null {
  const first = competitionCell(bounds.south, 0).id.split('.')[0].slice(1);
  const last = competitionCell(bounds.north, 0).id.split('.')[0].slice(1);
  const cells = new Map<string, Cell>();
  for (let row = Number(first); row <= Number(last); row++) {
    const columns = cellColumns(row);
    for (const [w, e] of longitudeRanges(bounds)) {
      const from = clamp(Math.floor((w + 180) / 360 * columns), 0, columns - 1);
      const to = clamp(Math.floor((e + 180) / 360 * columns), 0, columns - 1);
      if (to - from + 1 > maximum) return null;
      for (let col = from; col <= to; col++) {
        const cell = cellFromIndices(row, col); cells.set(cell.id, cell);
        if (cells.size > maximum) return null;
      }
    }
  }
  return [...cells.values()];
}
export function regionAt(lat: number, lng: number, z = REGION_DEPTH): Region {
  const n = 2 ** z;
  return { z, x: clamp(Math.floor((wrapLongitude(lng) + 180) / 360 * n), 0, n - 1), y: clamp(Math.floor((lat + 90) / 180 * n), 0, n - 1) };
}
export const regionId = (r: Region) => `r${r.z}.${r.x}.${r.y}`;
export function parseRegion(id: string): Region {
  const m = /^r(\d{1,2})\.(\d{1,4})\.(\d{1,4})$/.exec(id);
  if (!m) throw new Error('Invalid region');
  const [z, x, y] = m.slice(1).map(Number);
  if (z > REGION_DEPTH || x >= 2 ** z || y >= 2 ** z) throw new Error('Invalid region');
  return { z, x, y };
}
export function regionBounds(r: Region): Bounds {
  const n = 2 ** r.z;
  return { west: -180 + r.x * 360 / n, east: -180 + (r.x + 1) * 360 / n, south: -90 + r.y * 180 / n, north: -90 + (r.y + 1) * 180 / n };
}
export const parentRegion = (r: Region): Region | null => r.z ? { z: r.z - 1, x: Math.floor(r.x / 2), y: Math.floor(r.y / 2) } : null;
export const regionChildren = (r: Region): Region[] => [0, 1, 2, 3].map(i => ({ z: r.z + 1, x: r.x * 2 + i % 2, y: r.y * 2 + Math.floor(i / 2) }));
export function visibleRegions(bounds: Bounds, zoom: number): Region[] {
  for (let z = clamp(Math.max(3, Math.floor(zoom)), 0, REGION_DEPTH); z >= 0; z--) {
    const n = 2 ** z, result = new Map<string, Region>();
    const y0 = clamp(Math.floor((bounds.south + 90) / 180 * n) - 1, 0, n - 1);
    const y1 = clamp(Math.floor((bounds.north + 90) / 180 * n) + 1, 0, n - 1);
    let overflow = false;
    for (const [west, east] of longitudeRanges(bounds)) {
      const x0 = Math.floor((west + 180) / 360 * n) - 1, x1 = Math.min(n - 1, Math.floor((east + 180) / 360 * n)) + 1;
      if ((Math.min(n, x1 - x0 + 1)) * (y1 - y0 + 1) > MAX_REGION_TILES) { overflow = true; break; }
      for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) {
        const r = { z, x: (x + n) % n, y }; result.set(regionId(r), r);
      }
    }
    if (!overflow && result.size <= MAX_REGION_TILES) return [...result.values()];
  }
  return [{ z: 0, x: 0, y: 0 }];
}
export function postCohort(post: Record<string, unknown>, owner: Record<string, unknown>): Cohort {
  return post.syntheticBeta === true || post.syntheticCohort === true || owner.syntheticBeta === true ? 'test' : 'real';
}
export function eligibleMapPost(post: Record<string, unknown>, owner: Record<string, unknown>): boolean {
  const status = post.visibilityStatus ?? post.status;
  return (!post.audience || post.audience === 'public') && (!status || status === 'published' || status === 'live')
    && post.locationVisibility === 'approximate' && post.privateAccount !== true && post.ghostMode !== true
    && owner.privateAccount !== true && owner.ghostMode !== true && owner.disabled !== true
    && !['removed', 'blocked', 'rejected'].includes(String(post.moderationStatus))
    && typeof post.latitude === 'number' && Number.isFinite(post.latitude) && Math.abs(post.latitude) <= 90
    && typeof post.longitude === 'number' && Number.isFinite(post.longitude) && Math.abs(post.longitude) <= 180
    && (Number(post.radiusMeters ?? post.radius) > 0)
    && Boolean(post.mediaURL || post.playbackURL || post.caption);
}
export function advanceRank(old: Partial<Rank>, now: number, kind: string, gain: number): Rank {
  const factor = Math.exp(-Math.max(0, now - (old.at || now)) / TAU);
  const next: Rank = { at: now, views: (old.views || 0) * factor, positive: (old.positive || 0) * factor, negative: (old.negative || 0) * factor, growth: (old.growth || 0) * factor };
  if (kind === 'view') next.views++;
  if (kind === 'like') next.positive += 3;
  if (kind === 'comment') next.positive += 4;
  if (kind === 'dislike') next.negative += 3;
  next.growth += clamp(gain / 1000, -2, 2);
  return next;
}
export function rankKey(rank: Partial<Rank>, createdAt: number): number {
  const views = Math.max(0, rank.views || 0), positive = Math.max(0, rank.positive || 0);
  const confidence = views / (views + 10);
  const quality = Math.max(.001, (positive - (rank.negative || 0) + .2 * (rank.growth || 0)) / (views + 10));
  const score = Math.max(.00001, confidence * quality * Math.log2(views + 2));
  return Math.log(score) + ((rank.at || createdAt) - EPOCH) / TAU;
}
export const candidateScore = (c: Candidate, now: number) => Math.exp(clamp(c.rankKey - (now - EPOCH) / TAU, -700, 50));
export const qualifiedWinner = (c: Candidate, now: number) => c.expiresAtMillis > now && c.exposure * Math.exp(-Math.max(0, now - c.rankAt) / TAU) >= 5;
export function chooseChampion(candidates: Candidate[], previous: { winner?: Candidate | null; challengerId?: string | null; challengerSince?: number }, now: number, hold = true) {
  const live = candidates.filter(c => c.expiresAtMillis > now);
  const qualified = live.filter(c => qualifiedWinner(c, now));
  const sorted = (qualified.length ? qualified : live).sort((a, b) => qualified.length
    ? b.rankKey - a.rankKey || a.postId.localeCompare(b.postId) : b.createdAtMillis - a.createdAtMillis || a.postId.localeCompare(b.postId));
  const best = sorted[0] ?? null;
  const incumbent = sorted.find(c => c.postId === previous.winner?.postId);
  if (hold && best && incumbent && incumbent.postId !== best.postId && qualified.length) {
    if (candidateScore(best, now) < candidateScore(incumbent, now) * 1.1) return { winner: incumbent, challengerId: null, challengerSince: 0 };
    const since = previous.challengerId === best.postId ? previous.challengerSince || now : now;
    if (now - since < CHALLENGER_HOLD_MS) return { winner: incumbent, challengerId: best.postId, challengerSince: since };
  }
  return { winner: best, challengerId: null, challengerSince: 0 };
}
export function parseMapQuery(data: unknown): { bounds: Bounds; zoom: number; cursor: string | null; includeTest: boolean; selectedPostId: string | null } {
  const d = data as Record<string, unknown> | null, b = d?.bounds as Record<string, unknown> | null;
  if (!b || !['west', 'east', 'south', 'north'].every(k => typeof b[k] === 'number' && Number.isFinite(b[k]))) throw new Error('Invalid map bounds');
  const bounds = b as Bounds;
  if (Math.abs(bounds.west) > 1080 || Math.abs(bounds.east) > 1080 || bounds.south < -90 || bounds.north > 90 || bounds.south > bounds.north) throw new Error('Invalid map bounds');
  if (typeof d?.zoom !== 'number' || !Number.isFinite(d.zoom) || d.zoom < 0 || d.zoom > 24) throw new Error('Invalid map zoom');
  if (d.cursor != null && (typeof d.cursor !== 'string' || d.cursor.length > 1500)) throw new Error('Invalid cursor');
  const selectedPostId = typeof d.selectedPostId === 'string' && /^[\w-]{1,180}$/.test(d.selectedPostId) ? d.selectedPostId : null;
  return { bounds, zoom: d.zoom, cursor: typeof d.cursor === 'string' ? d.cursor : null, includeTest: d.includeTest === true, selectedPostId };
}
