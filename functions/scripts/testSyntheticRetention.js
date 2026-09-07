const assert=require('node:assert/strict');
const {calculateSyntheticRetentionDecay:decay}=require('../lib/syntheticRetentionPolicy');
const {DAILY_SOURCE,simulationSlot,simulationEngagementKinds}=require('../lib/syntheticDailyPolicy');
const {Timestamp}=require('firebase-admin/firestore');
const fixture=(now)=>({userID:'sim-actor',syntheticBeta:true,syntheticSource:DAILY_SOURCE,simulationRetentionVersion:1,seedRadiusMeters:5000,organicRadiusMeters:7000,radiusMeters:12000,decayedAt:Timestamp.fromMillis(now)});
const start=Date.parse('2026-09-07T00:00:00Z');
assert.equal(decay({...fixture(start),userID:'real-user'},start+14400000),null);
assert.equal(decay({...fixture(start),simulationRetentionVersion:undefined},start+14400000),null);
assert.equal(decay(fixture(start),start+14400000).radiusMeters,6000);
assert.equal(decay(fixture(start),start+30000),null);
assert.equal(simulationSlot(start),simulationSlot(start+3500000));
assert.notEqual(simulationSlot(start),simulationSlot(start+3600000));
const kinds=Array.from({length:1000},(_,i)=>simulationEngagementKinds('tester',String(i),true));
const negative=kinds.filter(k=>k[0]==='dislike').length;assert(negative>440&&negative<560);
let posts=[],gains=0,losses=0,atPause=0,afterPause=0;
for(let hour=0;hour<96;hour++){
 const now=start+hour*3600000;
 posts=posts.map(p=>{const n=decay(p,now);if(!n)return p;if(hour>=48&&hour<72)losses+=p.radiusMeters-n.radiusMeters;return {...p,...n,decayedAt:Timestamp.fromMillis(now)};});
 if(hour===72)atPause=posts.reduce((n,p)=>n+p.radiusMeters,0);
 if(hour===80)afterPause=posts.reduce((n,p)=>n+p.radiusMeters,0);
 if(hour<72||hour>=80){posts.push(fixture(now));if(hour>=48&&hour<72)gains+=12000;}
}
assert(losses/gains>.95&&losses/gains<1.05,`balanced steady-state decline/growth: ${losses/gains}`);
assert(afterPause<atPause*.27,'eight-hour pause loses about three quarters');
assert(posts.reduce((n,p)=>n+p.radiusMeters,0)>afterPause*2,'posting recovers radius');
console.log(JSON.stringify({pass:true,stressHours:96,posts:posts.length,steadyStateGainMeters:gains,steadyStateLossMeters:losses,lossGainRatio:losses/gains,pauseStartRadius:atPause,pauseEndRadius:afterPause}));
