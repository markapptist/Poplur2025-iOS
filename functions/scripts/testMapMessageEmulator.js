if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) throw new Error('Emulator-only test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
admin.initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db = admin.firestore();
const map = require('../lib/mapDiscovery');
(async () => {
  await db.doc('mapDiscovery/config').set({enabled:true});
  await Promise.all(['viewer','writer'].map(id => db.doc(`users/${id}`).set({username:id})));
  const caption = 'Meet at the library\n\nBring notes 📚\n' + 'Read every word. '.repeat(20);
  const shared = {userID:'writer',latitude:43.65,longitude:-79.38,locationVisibility:'approximate',radiusMeters:5000,createdAt:admin.firestore.Timestamp.now(),caption,contentType:'message',privateDraft:'not public'};
  await db.doc('posts/message').set({...shared,messageCard:true,mediaType:'photo',mediaURL:'https://example.com/share-card.jpg'});
  await db.doc('posts/attachment').set({...shared,messageCard:false,mediaType:'photo',mediaURL:'https://example.com/photo.jpg'});
  const {contentType, ...legacy} = shared;
  await db.doc('posts/legacy').set(legacy);
  for (const id of ['message','attachment','legacy']) await map.reconcileMapPost(id);
  const query = {bounds:{west:-79.4,east:-79.37,south:43.64,north:43.67},zoom:14};
  const page = await map.runMapDiscoveryQuery('viewer',query);
  assert.equal(page.posts.length,3);
  for (const post of page.posts) {
    assert.equal(post.row.caption,caption);
    assert.equal(post.row.privateDraft,undefined);
  }
  assert.equal(page.posts.find(p => p.id==='message').row.contentType,'message');
  assert.equal(page.posts.find(p => p.id==='message').row.messageCard,true);
  assert.equal(page.posts.find(p => p.id==='attachment').row.messageCard,false);
  assert.equal(page.posts.find(p => p.id==='attachment').row.mediaURL,'https://example.com/photo.jpg');
  await db.doc('users/writer/blocked/viewer').set({});
  assert.equal((await map.runMapDiscoveryQuery('viewer',query)).posts.length,0);
  console.log('PASS: full message text, line breaks, share-card metadata, real attachment and mutual-block privacy survive map discovery.');
})().catch(error => {console.error(error);process.exitCode=1}).finally(() => admin.app().delete());
