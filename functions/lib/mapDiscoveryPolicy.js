"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.qualifiedWinner = exports.candidateScore = exports.regionChildren = exports.parentRegion = exports.regionId = exports.wrapLongitude = exports.CHALLENGER_HOLD_MS = exports.RANK_MAX_AGE_MS = exports.RANK_WINDOW_MS = exports.RANK_HALF_LIFE_MS = exports.MAX_LOCAL_CELLS = exports.MAP_PAGE_SIZE = exports.MAX_REGION_TILES = exports.MAX_MAP_FEATURES = exports.REGION_DEPTH = exports.CELL_ROWS = exports.CELL_KM = exports.MAP_SCHEMA = void 0;
exports.millis = millis;
exports.cellColumns = cellColumns;
exports.cellFromIndices = cellFromIndices;
exports.parseCell = parseCell;
exports.competitionCell = competitionCell;
exports.longitudeRanges = longitudeRanges;
exports.inBounds = inBounds;
exports.visibleCells = visibleCells;
exports.regionAt = regionAt;
exports.parseRegion = parseRegion;
exports.regionBounds = regionBounds;
exports.visibleRegions = visibleRegions;
exports.postCohort = postCohort;
exports.eligibleMapPost = eligibleMapPost;
exports.advanceRank = advanceRank;
exports.rankKey = rankKey;
exports.chooseChampion = chooseChampion;
exports.parseMapQuery = parseMapQuery;
/** Pure contracts for spatial discovery. Coordinates are PUBLIC approximate origins. */
exports.MAP_SCHEMA = 1;
exports.CELL_KM = 5;
exports.CELL_ROWS = Math.ceil(Math.PI * 6371 / exports.CELL_KM);
exports.REGION_DEPTH = 10;
exports.MAX_MAP_FEATURES = 200;
exports.MAX_REGION_TILES = 64;
exports.MAP_PAGE_SIZE = 50;
exports.MAX_LOCAL_CELLS = 24;
exports.RANK_HALF_LIFE_MS = 6 * 3600_000;
exports.RANK_WINDOW_MS = 6 * 3600_000;
exports.RANK_MAX_AGE_MS = 72 * 3600_000;
exports.CHALLENGER_HOLD_MS = 120_000;
const EPOCH = Date.UTC(2026, 0, 1);
const TAU = exports.RANK_HALF_LIFE_MS / Math.LN2;
const wrapLongitude = (lng) => ((lng + 180) % 360 + 360) % 360 - 180;
exports.wrapLongitude = wrapLongitude;
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
function millis(value) {
    if (value && typeof value.toMillis === 'function')
        return value.toMillis();
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}
function cellColumns(row) {
    const lat = -90 + (row + .5) * 180 / exports.CELL_ROWS;
    return Math.max(1, Math.round(2 * Math.PI * 6371 * Math.cos(lat * Math.PI / 180) / exports.CELL_KM));
}
function cellFromIndices(row, col) {
    if (!Number.isInteger(row) || row < 0 || row >= exports.CELL_ROWS)
        throw new Error('Invalid cell row');
    const columns = cellColumns(row);
    if (!Number.isInteger(col) || col < 0 || col >= columns)
        throw new Error('Invalid cell column');
    const south = -90 + row * 180 / exports.CELL_ROWS, west = -180 + col * 360 / columns;
    const north = south + 180 / exports.CELL_ROWS, east = west + 360 / columns;
    return { id: `c${row}.${col}`, center: [(west + east) / 2, (south + north) / 2], bounds: { west, south, east, north } };
}
function parseCell(id) {
    const m = /^c(\d{1,4})\.(\d{1,4})$/.exec(id);
    if (!m)
        throw new Error('Invalid cell ID');
    return cellFromIndices(Number(m[1]), Number(m[2]));
}
function competitionCell(lat, lng) {
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90)
        throw new Error('Invalid coordinates');
    const row = clamp(Math.floor((lat + 90) / 180 * exports.CELL_ROWS), 0, exports.CELL_ROWS - 1);
    return cellFromIndices(row, Math.floor(((0, exports.wrapLongitude)(lng) + 180) / 360 * cellColumns(row)));
}
function longitudeRanges(bounds) {
    if (Math.abs(bounds.east - bounds.west) >= 359.999)
        return [[-180, 180]];
    const w = (0, exports.wrapLongitude)(bounds.west), e = (0, exports.wrapLongitude)(bounds.east);
    return w <= e ? [[w, e]] : [[w, 180], [-180, e]];
}
function inBounds(lat, lng, b) {
    return lat >= b.south && lat <= b.north && longitudeRanges(b).some(([w, e]) => (0, exports.wrapLongitude)(lng) >= w && (0, exports.wrapLongitude)(lng) <= e);
}
/** Stop enumerating immediately at budget; a world request never allocates all cells. */
function visibleCells(bounds, maximum = exports.MAX_MAP_FEATURES) {
    const first = competitionCell(bounds.south, 0).id.split('.')[0].slice(1);
    const last = competitionCell(bounds.north, 0).id.split('.')[0].slice(1);
    const cells = new Map();
    for (let row = Number(first); row <= Number(last); row++) {
        const columns = cellColumns(row);
        for (const [w, e] of longitudeRanges(bounds)) {
            const from = clamp(Math.floor((w + 180) / 360 * columns), 0, columns - 1);
            const to = clamp(Math.floor((e + 180) / 360 * columns), 0, columns - 1);
            if (to - from + 1 > maximum)
                return null;
            for (let col = from; col <= to; col++) {
                const cell = cellFromIndices(row, col);
                cells.set(cell.id, cell);
                if (cells.size > maximum)
                    return null;
            }
        }
    }
    return [...cells.values()];
}
function regionAt(lat, lng, z = exports.REGION_DEPTH) {
    const n = 2 ** z;
    return { z, x: clamp(Math.floor(((0, exports.wrapLongitude)(lng) + 180) / 360 * n), 0, n - 1), y: clamp(Math.floor((lat + 90) / 180 * n), 0, n - 1) };
}
const regionId = (r) => `r${r.z}.${r.x}.${r.y}`;
exports.regionId = regionId;
function parseRegion(id) {
    const m = /^r(\d{1,2})\.(\d{1,4})\.(\d{1,4})$/.exec(id);
    if (!m)
        throw new Error('Invalid region');
    const [z, x, y] = m.slice(1).map(Number);
    if (z > exports.REGION_DEPTH || x >= 2 ** z || y >= 2 ** z)
        throw new Error('Invalid region');
    return { z, x, y };
}
function regionBounds(r) {
    const n = 2 ** r.z;
    return { west: -180 + r.x * 360 / n, east: -180 + (r.x + 1) * 360 / n, south: -90 + r.y * 180 / n, north: -90 + (r.y + 1) * 180 / n };
}
const parentRegion = (r) => r.z ? { z: r.z - 1, x: Math.floor(r.x / 2), y: Math.floor(r.y / 2) } : null;
exports.parentRegion = parentRegion;
const regionChildren = (r) => [0, 1, 2, 3].map(i => ({ z: r.z + 1, x: r.x * 2 + i % 2, y: r.y * 2 + Math.floor(i / 2) }));
exports.regionChildren = regionChildren;
function visibleRegions(bounds, zoom) {
    for (let z = clamp(Math.max(3, Math.floor(zoom)), 0, exports.REGION_DEPTH); z >= 0; z--) {
        const n = 2 ** z, result = new Map();
        const y0 = clamp(Math.floor((bounds.south + 90) / 180 * n) - 1, 0, n - 1);
        const y1 = clamp(Math.floor((bounds.north + 90) / 180 * n) + 1, 0, n - 1);
        let overflow = false;
        for (const [west, east] of longitudeRanges(bounds)) {
            const x0 = Math.floor((west + 180) / 360 * n) - 1, x1 = Math.min(n - 1, Math.floor((east + 180) / 360 * n)) + 1;
            if ((Math.min(n, x1 - x0 + 1)) * (y1 - y0 + 1) > exports.MAX_REGION_TILES) {
                overflow = true;
                break;
            }
            for (let x = x0; x <= x1; x++)
                for (let y = y0; y <= y1; y++) {
                    const r = { z, x: (x + n) % n, y };
                    result.set((0, exports.regionId)(r), r);
                }
        }
        if (!overflow && result.size <= exports.MAX_REGION_TILES)
            return [...result.values()];
    }
    return [{ z: 0, x: 0, y: 0 }];
}
function postCohort(post, owner) {
    return post.syntheticBeta === true || post.syntheticCohort === true || owner.syntheticBeta === true ? 'test' : 'real';
}
function eligibleMapPost(post, owner) {
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
function advanceRank(old, now, kind, gain) {
    const factor = Math.exp(-Math.max(0, now - (old.at || now)) / TAU);
    const next = { at: now, views: (old.views || 0) * factor, positive: (old.positive || 0) * factor, negative: (old.negative || 0) * factor, growth: (old.growth || 0) * factor };
    if (kind === 'view')
        next.views++;
    if (kind === 'like')
        next.positive += 3;
    if (kind === 'comment')
        next.positive += 4;
    if (kind === 'dislike')
        next.negative += 3;
    next.growth += clamp(gain / 1000, -2, 2);
    return next;
}
function rankKey(rank, createdAt) {
    const views = Math.max(0, rank.views || 0), positive = Math.max(0, rank.positive || 0);
    const confidence = views / (views + 10);
    const quality = Math.max(.001, (positive - (rank.negative || 0) + .2 * (rank.growth || 0)) / (views + 10));
    const score = Math.max(.00001, confidence * quality * Math.log2(views + 2));
    return Math.log(score) + ((rank.at || createdAt) - EPOCH) / TAU;
}
const candidateScore = (c, now) => Math.exp(clamp(c.rankKey - (now - EPOCH) / TAU, -700, 50));
exports.candidateScore = candidateScore;
const qualifiedWinner = (c, now) => c.expiresAtMillis > now && c.exposure * Math.exp(-Math.max(0, now - c.rankAt) / TAU) >= 5;
exports.qualifiedWinner = qualifiedWinner;
function chooseChampion(candidates, previous, now, hold = true) {
    const live = candidates.filter(c => c.expiresAtMillis > now);
    const qualified = live.filter(c => (0, exports.qualifiedWinner)(c, now));
    const sorted = (qualified.length ? qualified : live).sort((a, b) => qualified.length
        ? b.rankKey - a.rankKey || a.postId.localeCompare(b.postId) : b.createdAtMillis - a.createdAtMillis || a.postId.localeCompare(b.postId));
    const best = sorted[0] ?? null;
    const incumbent = sorted.find(c => c.postId === previous.winner?.postId);
    if (hold && best && incumbent && incumbent.postId !== best.postId && qualified.length) {
        if ((0, exports.candidateScore)(best, now) < (0, exports.candidateScore)(incumbent, now) * 1.1)
            return { winner: incumbent, challengerId: null, challengerSince: 0 };
        const since = previous.challengerId === best.postId ? previous.challengerSince || now : now;
        if (now - since < exports.CHALLENGER_HOLD_MS)
            return { winner: incumbent, challengerId: best.postId, challengerSince: since };
    }
    return { winner: best, challengerId: null, challengerSince: 0 };
}
function parseMapQuery(data) {
    const d = data, b = d?.bounds;
    if (!b || !['west', 'east', 'south', 'north'].every(k => typeof b[k] === 'number' && Number.isFinite(b[k])))
        throw new Error('Invalid map bounds');
    const bounds = b;
    if (Math.abs(bounds.west) > 1080 || Math.abs(bounds.east) > 1080 || bounds.south < -90 || bounds.north > 90 || bounds.south > bounds.north)
        throw new Error('Invalid map bounds');
    if (typeof d?.zoom !== 'number' || !Number.isFinite(d.zoom) || d.zoom < 0 || d.zoom > 24)
        throw new Error('Invalid map zoom');
    if (d.cursor != null && (typeof d.cursor !== 'string' || d.cursor.length > 1500))
        throw new Error('Invalid cursor');
    const selectedPostId = typeof d.selectedPostId === 'string' && /^[\w-]{1,180}$/.test(d.selectedPostId) ? d.selectedPostId : null;
    return { bounds, zoom: d.zoom, cursor: typeof d.cursor === 'string' ? d.cursor : null, includeTest: d.includeTest === true, selectedPostId };
}
