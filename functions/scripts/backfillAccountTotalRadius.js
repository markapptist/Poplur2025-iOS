const admin = require('firebase-admin');
const { reconcileAccountPostRadius, ACCOUNT_TOTAL_CONTRIBUTIONS } = require('../lib/accountTotalRadius');
const db = admin.firestore();
(async () => {
  // Include receipts so a deletion concurrent with a previous run is reconciled.
  const [posts, receipts] = await Promise.all([
    db.collection('posts').select().get(), db.collection(ACCOUNT_TOTAL_CONTRIBUTIONS).select().get(),
  ]);
  const ids = [...new Set([...posts.docs, ...receipts.docs].map(d => d.id))];
  for (let i = 0; i < ids.length; i += 8) {
    await Promise.all(ids.slice(i, i + 8).map(id => reconcileAccountPostRadius(db, id, { countPostRate: false })));
  }
  console.log(`Reconciled total, earned and committed radius for ${ids.length} posts/receipts (post-rate windows untouched).`);
})().catch(error => { console.error(error); process.exitCode = 1; });
