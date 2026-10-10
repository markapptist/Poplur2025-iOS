#!/usr/bin/env node
// Recount the live installs number the landing page shows (public/betaInstalls)
// from production, once — the users/{uid} triggers keep it current after that.
// Auth: application-default credentials (gcloud auth application-default login)
// or GOOGLE_APPLICATION_CREDENTIALS. Build first: npm run build.
const admin = require("firebase-admin");
const { publishBetaInstalls } = require("../lib/betaInstalls");
if (admin.apps.length === 0) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "poplur2025" });
publishBetaInstalls(admin.firestore()).then(count => { console.log(JSON.stringify(count)); process.exit(0); }).catch(error => { console.error(error); process.exit(1); });
