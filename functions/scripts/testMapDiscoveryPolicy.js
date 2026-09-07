const assert = require('node:assert/strict');
const { performance } = require('node:perf_hooks');
const p = require('../lib/mapDiscoveryPolicy');
const now = Date.UTC(2026, 8, 7);
const cell = p.competitionCell(43.65, -79.38);
assert.deepEqual(p.parseCell(cell.id), cell);
assert.equal(p.competitionCell(43.65, 280.62).id, cell.id);
assert.throws(() => p.competitionCell(91, 0));
for (const lat of [-89.9, -80, -40, 0, 40, 80, 89.9]) {
  const c = p.competitionCell(lat, 179.999);
  const height = (c.bounds.north - c.bounds.south) * Math.PI / 180 * 6371;
  const width = (c.bounds.east - c.bounds.west) * Math.PI / 180 * 6371 * Math.cos(c.center[1] * Math.PI / 180);
  assert.ok(Math.abs(height - 5) < .01);
  assert.ok(Math.abs(width - 5) < .25, `${lat}: ${width}`);
}
const world = { west: -180, east: 180, south: -90, north: 90 };
assert.equal(p.visibleCells(world), null);
assert.equal(p.visibleRegions(world, 0).length, 64);
for (let zoom = 0; zoom < 23; zoom += .25) {
  assert.ok(p.visibleRegions(world, zoom).length <= 64);
  assert.ok(p.visibleRegions({west:170,east:-170,south:-15,north:15},zoom).length <=64);
}
assert.ok(p.inBounds(0, 179, {west:170,east:-170,south:-10,north:10}));
assert.ok(!p.inBounds(0, 0, {west:170,east:-170,south:-10,north:10}));
const small = {west:-79.4,east:-79.38,south:43.64,north:43.66};
assert.ok(p.visibleCells(small).length < 24);
const base = {postId:'a',ownerId:'a',cellId:cell.id,cohort:'real',latitude:43.65,longitude:-79.38,createdAtMillis:now,rankKey:0,exposure:10,rankAt:now,expiresAtMillis:now+86400000};
const a = {...base, rankKey: 10}, b={...base,postId:'b',rankKey:11};
assert.equal(p.chooseChampion([a,b],{winner:a},now).winner.postId,'a');
assert.equal(p.chooseChampion([a,b],{winner:a,challengerId:'b',challengerSince:now},now+120001).winner.postId,'b');
assert.equal(p.chooseChampion([b],{winner:a},now).winner.postId,'b');
assert.equal(p.chooseChampion([{...a,expiresAtMillis:now-1}],{},now).winner,null);
assert.equal(p.chooseChampion([{...a,exposure:0,createdAtMillis:now-100},{...b,exposure:0}],{},now).winner.postId,'b');
assert.ok(p.candidateScore(a,now+6*3600000) / p.candidateScore(a,now) > .499);
assert.ok(p.candidateScore(a,now+6*3600000) / p.candidateScore(a,now) < .501);
let rank = p.advanceRank({},now,'view',0);
rank = p.advanceRank(rank,now+6*3600000,'like',1000);
assert.equal(rank.views,.5);
assert.equal(rank.positive,3);
const publicPost={userID:'a',caption:'hi',radiusMeters:5000,latitude:43,longitude:-79,locationVisibility:'approximate'};
assert.ok(p.eligibleMapPost(publicPost,{}));
for (const override of [{privateAccount:true},{ghostMode:true},{locationVisibility:'hidden'},{audience:'private'},{status:'draft'},{latitude:NaN},{radiusMeters:0}]) assert.ok(!p.eligibleMapPost({...publicPost,...override},{}));
assert.ok(!p.eligibleMapPost(publicPost,{privateAccount:true}));
assert.throws(()=>p.parseMapQuery({bounds:world,zoom:NaN}));
assert.throws(()=>p.parseMapQuery({bounds:{...world,north:91},zoom:4}));
// One million generated records, streaming cell elections. This measures the
// pure algorithm's CPU/memory, not Cloud Firestore or Cloud Run capacity.
const started=performance.now(), winners=new Map();
for(let i=0;i<1_000_000;i++) {
  const lat=40+(i%997)/997, lng=-80+(Math.floor(i/997)%991)/991;
  const c=p.competitionCell(lat,lng).id;
  const candidate={...base,postId:String(i),cellId:c,rankKey:(i*48271%2147483647)/2147483647};
  const winner=winners.get(c);
  if(!winner || candidate.rankKey>winner.rankKey) winners.set(c,candidate);
}
assert.ok(winners.size<1000);
const report={records:1000000,cells:winners.size,milliseconds:Math.round(performance.now()-started),heapMiB:Math.round(process.memoryUsage().heapUsed/1024/1024),maxWorldTiles:p.visibleRegions(world,0).length,maxFeatures:p.MAX_MAP_FEATURES,page:p.MAP_PAGE_SIZE};
console.log(JSON.stringify(report,null,2));
console.log('Map policy tests passed');
