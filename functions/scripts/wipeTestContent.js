/*
 * One-purpose production test reset for Firebase project poplur2025.
 *
 * It deliberately retains operational configuration, credit ledgers, verified
 * store purchases, and bundled asset packs. Everything else is treated as
 * disposable test/user content, including nested Firestore collections and
 * Firebase Authentication accounts.
 *
 * Usage:
 *   node scripts/wipeTestContent.js --confirm-poplur-test-content-wipe --keep-auth
 */

const admin = require('firebase-admin')

const PROJECT_ID = 'poplur2025'
const STORAGE_BUCKET = 'poplur2025.firebasestorage.app'
const CONFIRMATION = '--confirm-poplur-test-content-wipe'
const KEEP_AUTH = '--keep-auth'

const RETAINED_COLLECTIONS = new Set([
  'poplurConfig',
  'creatorCreditBalances',
  'creatorCreditTransactions',
  'verifiedStorePurchases',
])

const RETAINED_STORAGE_PREFIXES = new Set(['asset-packs'])

if (!process.argv.includes(CONFIRMATION)) {
  throw new Error(`Refusing to delete data without ${CONFIRMATION}.`)
}

admin.initializeApp({ projectId: PROJECT_ID, storageBucket: STORAGE_BUCKET })

const db = admin.firestore()
const bucket = admin.storage().bucket()

async function deleteAuthUsers() {
  let pageToken
  let removed = 0
  do {
    const page = await admin.auth().listUsers(1000, pageToken)
    const ids = page.users.map(user => user.uid)
    if (ids.length) {
      const result = await admin.auth().deleteUsers(ids)
      if (result.failureCount) {
        throw new Error(`Auth wipe failed for ${result.failureCount} account(s).`)
      }
      removed += result.successCount
    }
    pageToken = page.pageToken
  } while (pageToken)
  return removed
}

async function deleteUserStorage() {
  const [files] = await bucket.getFiles({ autoPaginate: true })
  const targets = files.filter(file => !RETAINED_STORAGE_PREFIXES.has(file.name.split('/')[0] || ''))
  await Promise.all(targets.map(file => file.delete()))
  return targets.length
}

async function main() {
  const collections = await db.listCollections()
  const removable = collections.filter(collection => !RETAINED_COLLECTIONS.has(collection.id))
  const deletedCollections = []
  for (const collection of removable) {
    await db.recursiveDelete(collection)
    deletedCollections.push(collection.id)
  }

  const storageObjects = await deleteUserStorage()
  const authUsers = process.argv.includes(KEEP_AUTH) ? 0 : await deleteAuthUsers()

  console.log(JSON.stringify({
    project: PROJECT_ID,
    deletedCollections: deletedCollections.sort(),
    deletedStorageObjects: storageObjects,
    deletedAuthUsers: authUsers,
    authRetained: process.argv.includes(KEEP_AUTH),
    retainedCollections: [...RETAINED_COLLECTIONS].sort(),
    retainedStoragePrefixes: [...RETAINED_STORAGE_PREFIXES],
  }, null, 2))
}

main().catch(error => {
  console.error(error.stack || error)
  process.exitCode = 1
})
