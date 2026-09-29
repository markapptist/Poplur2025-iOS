if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) throw new Error('Emulator only');
const assert = require('node:assert/strict'), admin = require('firebase-admin');
admin.initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db=admin.firestore(), {Timestamp}=admin.firestore;
(async()=>{
 const now=Date.now(), past=now-100*86400000;
 await db.doc('users/expiry-owner').set({username:'expiry-owner',claimRadiusMeters:20});
 await db.doc('testControl/radiusDecayTrial').set({enabled:true,multiplier:5,effectiveAtMillis:past});
 const ref=db.doc('posts/expiry-post');
 await ref.set({userID:'expiry-owner',organicRadiusMeters:20,seedRadiusMeters:20,radiusMeters:40,decayedAt:Timestamp.fromMillis(past),visibilityStatus:'published'});
 const q=require('../lib/radiusDecayQueue');await q.reconcileDecayPost(ref.id);
 await q.runDecayShard(q.decayShard(ref.id),now);
 assert.equal((await db.doc('users/expiry-owner').get()).data().claimRadiusMeters,0);
 const post=(await ref.get()).data();assert.equal(post.radiusMeters,0);assert.equal(post.visibilityStatus,'expired');
 await assert.rejects(()=>require('../lib/postEngagement').applyPostEngagement('viewer',{postId:ref.id,eventId:'expired_event_12345',kind:'like'}),e=>e.code==='failed-precondition');
 const history=await ref.collection('radiusHistory').get();assert.equal(history.size,1);assert.equal(history.docs[0].data().delta,-40);
 const notify=require('../lib/radiusLossNotifications').notifyOnRadiusLoss;
 const event={data:history.docs[0],params:{postId:ref.id,historyId:history.docs[0].id}};
 await notify.run(event);
 const inbox=await db.collection('users/expiry-owner/notifications').get();assert.equal(inbox.size,1);assert.equal(inbox.docs[0].data().kind,'decrease');
 await inbox.docs[0].ref.update({isUnread:false});await notify.run(event);
 assert.equal((await inbox.docs[0].ref.get()).data().isUnread,false);
 await q.runDecayShard(q.decayShard(ref.id),now);assert.equal((await ref.collection('radiusHistory').get()).size,1);
 // A loss tap can replay its own expired post, without restoring it to discovery.
 await ref.update({latitude:43.65,longitude:-79.38,locationVisibility:'approximate'});
 await db.doc('mapDiscovery/config').set({enabled:true});
 const map=require('../lib/mapDiscovery');
 const query={bounds:{west:-79.4,east:-79.3,south:43.6,north:43.7},zoom:14,notificationId:inbox.docs[0].id};
 const focus=(await map.runMapDiscoveryQuery('expiry-owner',query)).notificationFocus;
 assert.equal(focus.beforeKm,.04);assert.equal(focus.afterKm,0);assert.equal(focus.currentKm,0);
 assert.equal(focus.notificationId,inbox.docs[0].id);
 assert.ok(!(await map.runMapDiscoveryQuery('expiry-owner',query)).posts.some(p=>p.id===ref.id));
 await db.doc(`users/stranger/notifications/${inbox.docs[0].id}`).set(inbox.docs[0].data());
 assert.equal((await map.runMapDiscoveryQuery('stranger',query)).notificationFocus,undefined);
 // Legacy official reach must be indexed, decayed once, and removed at zero.
 await db.doc('testControl/radiusDecayTrial').update({boostedEffectiveAtMillis:past});
 const legacy=db.doc('posts/legacy-seeded-reach');
 await legacy.set({userID:'expiry-owner',organicRadiusMeters:0,boostedRadiusMeters:1000,radiusMeters:1000,decayedAt:Timestamp.fromMillis(past),visibilityStatus:'published'});
 await q.reconcileDecayPost(legacy.id);
 assert.equal((await db.doc(`radiusDecayQueue/${legacy.id}`).get()).exists,true);
 await q.runDecayShard(q.decayShard(legacy.id),now);
 assert.equal((await legacy.get()).data().radiusMeters,0);
 assert.equal((await legacy.get()).data().boostedRadiusMeters,0);
 assert.equal((await legacy.get()).data().visibilityStatus,'expired');
 await q.reconcileDecayPost(legacy.id);
 assert.equal((await db.doc(`radiusDecayQueue/${legacy.id}`).get()).exists,false);
 // Real decay publishes display policy; concurrent post losses share one push.
 const active=db.doc('posts/live-projection');
 await active.set({userID:'expiry-owner',organicRadiusMeters:100000,seedRadiusMeters:5000,radiusMeters:105000,decayedAt:Timestamp.fromMillis(now-3600000),visibilityStatus:'published'});
 await q.reconcileDecayPost(active.id);await q.runDecayShard(q.decayShard(active.id),now);
 const projection=(await active.get()).data();
 assert.equal(projection.radiusDecayAnchorMillis,now);
 assert.ok(projection.radiusDecayOrganicPerDay>0 && projection.radiusDecayOrganicPerDay<1);
 assert.ok(projection.radiusDecaySeedPerDay>0);
 const messaging=admin.messaging();let pushes=0;
 messaging.sendEachForMulticast=async payload=>{assert.deepEqual(payload.tokens,['emulator-only']);pushes++;return {responses:[{success:true}]};};
 await db.doc('users/expiry-owner').update({fcmTokens:{'emulator-only':true}});
 const lossA=ref.collection('radiusHistory').doc('daily-a'),lossB=active.collection('radiusHistory').doc('daily-b');
 await Promise.all([lossA.set({cause:'decay',delta:-10,radiusMeters:0}),lossB.set({cause:'decay',delta:-20,radiusMeters:10})]);
 const events=await Promise.all([lossA,lossB].map(async r=>({data:await r.get(),params:{postId:r.parent.parent.id,historyId:r.id}})));
 await Promise.all(events.map(e=>notify.run(e)));assert.equal(pushes,1);
 await Promise.all(events.map(e=>notify.run(e)));assert.equal(pushes,1);
 assert.ok((await db.doc('users/expiry-owner').get()).data().radiusReminderAtMillis>0);
 // Two workers racing after a 48-hour gap must expire the post and debit
 // its account exactly once under the six-hour policy.
 await db.doc('testControl/radiusDecayTrial').set({enabled:true,multiplier:10,effectiveAtMillis:now-2*86400000,
   halfLifeHours:6,halfLifeEffectiveAtMillis:now-2*86400000});
 const rapid=db.doc('posts/rapid-expiry');
 await db.doc('users/rapid-owner').set({claimRadiusMeters:100000});
 await rapid.set({userID:'rapid-owner',organicRadiusMeters:100000,seedRadiusMeters:5000,radiusMeters:105000,
   decayedAt:Timestamp.fromMillis(now-2*86400000),visibilityStatus:'published'});
 await q.reconcileDecayPost(rapid.id);
 const run=require('../lib/radiusDecay').runRadiusDecay;
 await Promise.all([run(now,[rapid]),run(now,[rapid])]);
 const rapidAfter=(await rapid.get()).data();
 assert.equal(rapidAfter.radiusMeters,0);assert.equal(rapidAfter.visibilityStatus,'expired');
 assert.equal(rapidAfter.radiusDecayOrganicPerDay,.9375);
 assert.equal((await db.doc('users/rapid-owner').get()).data().claimRadiusMeters,0);
 assert.equal((await rapid.collection('radiusHistory').get()).size,1);
 console.log('Rapid decay: concurrent overdue workers expire reach, history and entitlement once');
 const capped=db.doc('posts/world-inactive');
 await db.doc('users/world-owner').set({claimRadiusMeters:6371000});
 await capped.set({userID:'world-owner',organicRadiusMeters:6371000,seedRadiusMeters:0,radiusMeters:6371000,
   decayedAt:Timestamp.now(),visibilityStatus:'published',createdAtMillis:now+100*86400000});
 const born=(await capped.get()).createTime.toMillis();
 const policy={enabled:true,multiplier:10,effectiveAtMillis:born,halfLifeHours:3,halfLifeEffectiveAtMillis:born,
   inactivityExpiryHours:24,inactivityEffectiveAtMillis:born};
 await db.doc('testControl/radiusDecayTrial').set(policy);
 await q.reconcileDecayPost(capped.id);
 const nearDeadline=born+23.75*3600000,deadline=born+24*3600000;
 await run(nearDeadline,[capped]);
 const scheduled=(await db.doc('radiusDecayQueue/'+capped.id).get()).data().dueAt.toMillis();
 assert.ok(Math.abs(scheduled-deadline)<1);
 await q.reconcileDecayPost(capped.id);
 assert.equal((await db.doc('radiusDecayQueue/'+capped.id).get()).data().dueAt.toMillis(),scheduled);
 assert.ok((await capped.get()).data().radiusMeters>0);
 await run(deadline,[capped]);
 assert.equal((await capped.get()).data().radiusMeters,0);
 assert.equal((await capped.get()).data().visibilityStatus,'expired');
 assert.equal((await db.doc('users/world-owner').get()).data().claimRadiusMeters,0);
 console.log('24-hour cutoff: world reach expires; editable dates cannot renew it; early queue deadline survives reconciliation');
 console.log('Expiry, authenticated loss replay, legacy seeded decay, and deduplicated inbox passed');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>admin.app().delete());
