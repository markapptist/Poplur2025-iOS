"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.poplurAiApi = exports.cameraSceneScan = exports.premiumAiAssist = exports.generateRetroGame = exports.testSessionIngest = exports.testActivityControl = exports.refreshLiveNews = exports.liveNewsApi = exports.wardrobeGarmentApi = exports.meshyStatus = exports.meshyGenerate = exports.setAccountLocationPrivacy = exports.notifyOnDirectMessage = exports.notifyOnEngagement = exports.poplurPassOnProfileChange = exports.poplurPassWebService = exports.poplurOwnedCards = exports.poplurWalletPass = exports.verifyCardPurchase = void 0;
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const premiumAiFlows_1 = require("./ai/premiumAiFlows");
var cardPurchases_1 = require("./cardPurchases");
Object.defineProperty(exports, "verifyCardPurchase", { enumerable: true, get: function () { return cardPurchases_1.verifyCardPurchase; } });
var walletPass_1 = require("./walletPass");
Object.defineProperty(exports, "poplurWalletPass", { enumerable: true, get: function () { return walletPass_1.poplurWalletPass; } });
Object.defineProperty(exports, "poplurOwnedCards", { enumerable: true, get: function () { return walletPass_1.poplurOwnedCards; } });
var walletPassWebService_1 = require("./walletPassWebService");
Object.defineProperty(exports, "poplurPassWebService", { enumerable: true, get: function () { return walletPassWebService_1.poplurPassWebService; } });
Object.defineProperty(exports, "poplurPassOnProfileChange", { enumerable: true, get: function () { return walletPassWebService_1.poplurPassOnProfileChange; } });
var engagementNotifications_1 = require("./engagementNotifications");
Object.defineProperty(exports, "notifyOnEngagement", { enumerable: true, get: function () { return engagementNotifications_1.notifyOnEngagement; } });
var directMessageNotifications_1 = require("./directMessageNotifications");
Object.defineProperty(exports, "notifyOnDirectMessage", { enumerable: true, get: function () { return directMessageNotifications_1.notifyOnDirectMessage; } });
var accountPrivacy_1 = require("./accountPrivacy");
Object.defineProperty(exports, "setAccountLocationPrivacy", { enumerable: true, get: function () { return accountPrivacy_1.setAccountLocationPrivacy; } });
var meshyModels_1 = require("./meshyModels");
Object.defineProperty(exports, "meshyGenerate", { enumerable: true, get: function () { return meshyModels_1.meshyGenerate; } });
Object.defineProperty(exports, "meshyStatus", { enumerable: true, get: function () { return meshyModels_1.meshyStatus; } });
var wardrobeGarments_1 = require("./wardrobeGarments");
Object.defineProperty(exports, "wardrobeGarmentApi", { enumerable: true, get: function () { return wardrobeGarments_1.wardrobeGarmentApi; } });
var liveNews_1 = require("./liveNews");
Object.defineProperty(exports, "liveNewsApi", { enumerable: true, get: function () { return liveNews_1.liveNewsApi; } });
Object.defineProperty(exports, "refreshLiveNews", { enumerable: true, get: function () { return liveNews_1.refreshLiveNews; } });
var testActivity_1 = require("./testActivity");
Object.defineProperty(exports, "testActivityControl", { enumerable: true, get: function () { return testActivity_1.testActivityControl; } });
var syntheticBrowserRunner_1 = require("./syntheticBrowserRunner");
Object.defineProperty(exports, "testSessionIngest", { enumerable: true, get: function () { return syntheticBrowserRunner_1.testSessionIngest; } });
var generateRetroGame_1 = require("./retro/generateRetroGame");
Object.defineProperty(exports, "generateRetroGame", { enumerable: true, get: function () { return generateRetroGame_1.generateRetroGame; } });
if (admin.apps.length === 0)
    admin.initializeApp();
const db = admin.firestore();
const googleAiApiKey = (0, params_1.defineSecret)("GOOGLE_AI_API_KEY");
const anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
const protectedRegion = "us-central1";
exports.premiumAiAssist = (0, https_1.onCall)({
    region: protectedRegion,
    enforceAppCheck: true,
    secrets: [googleAiApiKey],
    timeoutSeconds: 120,
    memory: "512MiB",
}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in to use Poplur AI.");
    }
    const action = parseAction(request.data?.action);
    const input = parseInput(action, request.data?.input);
    const usage = await reservePremiumAIUsage(uid);
    try {
        configureGoogleAIKey();
        const result = await (0, premiumAiFlows_1.premiumAiFlow)({ action, input });
        return {
            ...result,
            usage: {
                premiumTier: usage.tier,
                monthlyLimit: usage.limit,
                usedThisMonth: usage.usedAfter,
                remaining: usage.remaining,
                month: usage.month,
            },
        };
    }
    catch (error) {
        await refundPremiumAIUsage(uid, usage.month);
        firebase_functions_1.logger.error("premium_ai_generation_failed", {
            action,
            uidSuffix: uid.slice(-6),
            code: error instanceof https_1.HttpsError ? error.code : "internal",
        });
        throw new https_1.HttpsError("internal", "AI generation failed. Please try again.");
    }
});
/** One explicit Camera Scan sends one reduced JPEG. This is intentionally not
 * a streaming endpoint: the expensive model has no permission to follow the
 * camera after the user turns Scan off. */
exports.cameraSceneScan = (0, https_1.onCall)({
    region: protectedRegion,
    enforceAppCheck: true,
    secrets: [googleAiApiKey],
    timeoutSeconds: 30,
    memory: "512MiB",
}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in to scan a scene.");
    const imageBase64 = typeof request.data?.imageBase64 === "string" ? request.data.imageBase64 : "";
    if (!imageBase64 || imageBase64.length > 1_400_000) {
        throw new https_1.HttpsError("invalid-argument", "Send one JPEG smaller than 1 MB.");
    }
    // One result every eight seconds per account is enough for a deliberate
    // scan and makes button mashing bounded at the server as well as the phone.
    const rateRef = db.collection("cameraScanRate").doc(uid);
    await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(rateRef);
        const lastAt = snapshot.data()?.lastAt;
        if (lastAt && Date.now() - lastAt.toMillis() < 8_000) {
            throw new https_1.HttpsError("resource-exhausted", "Let this scan finish before starting another.");
        }
        transaction.set(rateRef, { lastAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    });
    configureGoogleAIKey();
    const payload = await callGeminiGenerateContent({
        apiKey: googleAiApiKey.value(),
        model: process.env.POPLUR_CAMERA_SCAN_MODEL || "gemini-2.5-flash",
        contents: [{ parts: [
                    { text: [
                            "Identify the scene and the most visually evident objects in this camera image.",
                            "Do not guess brands or product models unless distinctive visible evidence supports it.",
                            "Return concise JSON only: {primary:string, confidence:number, context:string[], description:string}.",
                            "confidence is 0 to 1; context has at most 3 different concrete objects or scene facts.",
                        ].join(" ") },
                    { inlineData: { mimeType: "image/jpeg", data: imageBase64 } },
                ] }],
        generationConfig: {
            temperature: 0.1,
            maxOutputTokens: 180,
            responseMimeType: "application/json",
        },
    });
    const result = parseJson(extractGeminiText(payload));
    const primary = typeof result.primary === "string" ? result.primary.trim().slice(0, 80) : "";
    if (!primary)
        throw new https_1.HttpsError("internal", "The scene scan returned no useful answer.");
    const confidence = typeof result.confidence === "number"
        ? Math.max(0, Math.min(1, result.confidence))
        : 0.7;
    return {
        primary,
        confidence,
        context: stringArrayField(result.context).slice(0, 3),
        description: typeof result.description === "string" ? result.description.trim().slice(0, 180) : "",
    };
});
exports.poplurAiApi = (0, https_1.onRequest)({
    region: protectedRegion,
    cors: true,
    secrets: [googleAiApiKey, anthropicApiKey],
    timeoutSeconds: 300,
    memory: "1GiB",
}, async (request, response) => {
    configureGoogleAIKey();
    await routePoplurAIRequest(request, response);
});
function parseAction(rawAction) {
    const parsed = premiumAiFlows_1.PremiumAIActionSchema.safeParse(rawAction);
    if (!parsed.success) {
        throw new https_1.HttpsError("invalid-argument", "Unsupported Premium AI action.");
    }
    return parsed.data;
}
function parseInput(action, rawInput) {
    try {
        return (0, premiumAiFlows_1.validatePremiumAIInput)(action, rawInput ?? {});
    }
    catch {
        throw new https_1.HttpsError("invalid-argument", "Check the AI request fields and try again.");
    }
}
async function reservePremiumAIUsage(uid) {
    const month = currentUsageMonth();
    const userRef = db.collection("users").doc(uid);
    return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(userRef);
        if (!snapshot.exists) {
            throw new https_1.HttpsError("failed-precondition", "Poplur AI is included with Premium.");
        }
        const data = snapshot.data() ?? {};
        if (data.isPremium !== true) {
            throw new https_1.HttpsError("failed-precondition", "Poplur AI is included with Premium.");
        }
        const tier = typeof data.premiumTier === "string" && data.premiumTier.trim()
            ? data.premiumTier.trim()
            : "premium";
        const defaultLimit = tier.toLowerCase() === "business" ? 500 : 100;
        const limit = positiveInt(data.aiMonthlyLimit, defaultLimit);
        const storedMonth = typeof data.aiUsageMonth === "string" ? data.aiUsageMonth : "";
        const usedBefore = storedMonth === month ? positiveInt(data.aiUsedThisMonth, 0) : 0;
        if (usedBefore >= limit) {
            throw new https_1.HttpsError("resource-exhausted", "You have used all Poplur AI generations for this month.");
        }
        const usedAfter = usedBefore + 1;
        transaction.set(userRef, {
            premiumTier: tier,
            aiMonthlyLimit: limit,
            aiUsageMonth: month,
            aiUsedThisMonth: usedAfter,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        return {
            month,
            tier,
            limit,
            usedBefore,
            usedAfter,
            remaining: Math.max(limit - usedAfter, 0),
        };
    });
}
async function requirePremiumAIUser(uid) {
    const snapshot = await db.collection("users").doc(uid).get();
    const data = snapshot.data() ?? {};
    if (!snapshot.exists || data.isPremium !== true) {
        throw httpError(403, "ai_locked_for_plan", "Poplur AI radio host is included with Premium.");
    }
}
async function refundPremiumAIUsage(uid, month) {
    const userRef = db.collection("users").doc(uid);
    try {
        await db.runTransaction(async (transaction) => {
            const snapshot = await transaction.get(userRef);
            const data = snapshot.data() ?? {};
            const currentMonth = typeof data.aiUsageMonth === "string" ? data.aiUsageMonth : "";
            const used = positiveInt(data.aiUsedThisMonth, 0);
            if (currentMonth === month && used > 0) {
                transaction.update(userRef, {
                    aiUsedThisMonth: used - 1,
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                });
            }
        });
    }
    catch (error) {
        firebase_functions_1.logger.warn("premium_ai_usage_refund_failed", {
            uidSuffix: uid.slice(-6),
            month,
            code: error instanceof https_1.HttpsError ? error.code : "unknown",
        });
    }
}
function positiveInt(rawValue, fallback) {
    const numberValue = typeof rawValue === "number" ? rawValue : Number(rawValue);
    return Number.isFinite(numberValue) && numberValue >= 0 ? Math.floor(numberValue) : fallback;
}
function currentUsageMonth() {
    return new Date().toISOString().slice(0, 7);
}
function configureGoogleAIKey() {
    const key = googleAiApiKey.value();
    if (!key) {
        return;
    }
    process.env.GOOGLE_AI_API_KEY = key;
    process.env.GOOGLE_API_KEY = process.env.GOOGLE_API_KEY || key;
    process.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY || key;
}
async function routePoplurAIRequest(req, res) {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    try {
        const path = normalizedPath(req);
        if (req.method === "GET" && (path === "/" || path === "/health")) {
            res.status(200).json({
                ok: true,
                service: "poplurAiApi",
                project: "poplur2025",
                region: protectedRegion,
                authenticatedRoutesRequire: "Authorization: Bearer <firebase-id-token>",
            });
            return;
        }
        // Pre-login surface: the auth-screen voice guide runs before any Firebase
        // user exists, so this route authenticates nobody and is instead
        // rate-limited per client IP with a tightly bounded prompt and output.
        if (req.method === "POST" && path === "/assistant/guest-chat") {
            await handleAuthGuideChat(req, res);
            return;
        }
        const uid = await requireFirebaseUser(req);
        if (req.method === "GET" && path === "/credits/balance") {
            await handleCreditBalance(uid, res);
            return;
        }
        if (req.method === "GET" && path === "/ai/jobs") {
            await handleListJobs(uid, res);
            return;
        }
        if (req.method === "POST" && path === "/radio/host") {
            await handleRadioHost(uid, req, res);
            return;
        }
        if (req.method === "POST" && path === "/assistant/chat") {
            await handleAssistantChat(uid, req, res);
            return;
        }
        if (req.method === "POST" && path === "/tv/style") {
            await handleTvStyle(uid, req, res);
            return;
        }
        if (req.method === "POST" && path === "/bumper/script") {
            await handleBumperScript(uid, req, res);
            return;
        }
        if (req.method === "POST" && path === "/games/config") {
            await handleGameConfig(uid, req, res);
            return;
        }
        if (req.method === "POST" && path === "/video/storyboard") {
            await handleVideoStoryboard(uid, req, res);
            return;
        }
        const jobMatch = path.match(/^\/ai\/jobs\/([^/]+)$/);
        if (req.method === "GET" && jobMatch) {
            await handleGetJob(uid, jobMatch[1], res);
            return;
        }
        const cancelMatch = path.match(/^\/ai\/jobs\/([^/]+)\/cancel$/);
        if (req.method === "POST" && cancelMatch) {
            await handleCancelJob(uid, cancelMatch[1], res);
            return;
        }
        const publishMatch = path.match(/^\/ai\/jobs\/([^/]+)\/publish-to-map$/);
        if (req.method === "POST" && publishMatch) {
            await handlePublishGeneratedJob(uid, publishMatch[1], req, res);
            return;
        }
        const generateMatch = path.match(/^\/ai\/generate\/([^/]+)$/);
        if (req.method === "POST" && generateMatch) {
            await handleGenerate(uid, parseContentType(generateMatch[1]), req, res);
            return;
        }
        const radiusBoostMatch = path.match(/^\/posts\/([^/]+)\/radius-boost$/);
        if (req.method === "POST" && radiusBoostMatch) {
            await handleRadiusBoost(uid, radiusBoostMatch[1], req, res);
            return;
        }
        const campaignMatch = path.match(/^\/businesses\/([^/]+)\/ai-campaigns$/);
        if (req.method === "POST" && campaignMatch) {
            await handleBusinessCampaign(uid, campaignMatch[1], req, res);
            return;
        }
        sendError(res, 404, "not_found", "Unknown Poplur AI endpoint.");
    }
    catch (error) {
        handleRouteError(error, res);
    }
}
function normalizedPath(req) {
    const path = req.path || "/";
    return path.endsWith("/") && path.length > 1 ? path.slice(0, -1) : path;
}
async function requireFirebaseUser(req) {
    const header = req.header("authorization") || req.header("Authorization") || "";
    const match = header.match(/^Bearer\s+(.+)$/i);
    if (!match) {
        throw httpError(401, "unauthenticated", "Send a Firebase ID token as a Bearer token.");
    }
    const decoded = await admin.auth().verifyIdToken(match[1]);
    return decoded.uid;
}
function parseContentType(rawType) {
    const contentType = rawType.toLowerCase();
    if (contentType === "image" ||
        contentType === "video" ||
        contentType === "edit" ||
        contentType === "vfx" ||
        contentType === "3d" ||
        contentType === "voice" ||
        contentType === "music" ||
        contentType === "game") {
        return contentType;
    }
    throw httpError(400, "invalid_content_type", "Unsupported AI generation content type.");
}
async function handleCreditBalance(uid, res) {
    const snapshot = await db.collection("creatorCreditBalances").doc(uid).get();
    const data = snapshot.data() ?? {};
    res.status(200).json({
        availableCredits: positiveInt(data.availableCredits, 0),
        reservedCredits: positiveInt(data.reservedCredits, 0),
        lifetimeEarned: positiveInt(data.lifetimeEarned, 0),
        lifetimeSpent: positiveInt(data.lifetimeSpent, 0),
        planTier: typeof data.planTier === "string" ? data.planTier : "free",
        updatedAt: serializeValue(data.updatedAt),
    });
}
async function handleListJobs(uid, res) {
    const snapshot = await db
        .collection("aiGenerationJobs")
        .where("userId", "==", uid)
        .orderBy("createdAt", "desc")
        .limit(25)
        .get();
    res.status(200).json({
        jobs: snapshot.docs.map((doc) => serializeDocument(doc.id, doc.data())),
    });
}
async function handleGetJob(uid, jobId, res) {
    const snapshot = await db.collection("aiGenerationJobs").doc(jobId).get();
    const data = snapshot.data();
    if (!snapshot.exists || !data || data.userId !== uid) {
        throw httpError(404, "job_not_found", "AI job not found.");
    }
    res.status(200).json({ job: serializeDocument(snapshot.id, data) });
}
async function handleGenerate(uid, contentType, req, res) {
    const body = objectBody(req);
    const prompt = stringField(body.prompt, "prompt", 4000);
    const sourceAssetIds = stringArrayField(body.sourceAssetIds);
    const sourceImage = optionalSourceImage(body);
    const location = plainObjectField(body.location);
    const channelId = optionalStringField(body.channelId, 120);
    const metadata = plainObjectField(body.metadata) ?? {};
    const provider = "google_ai_studio";
    const { jobId, cost } = await reserveCreditsAndCreateJob({
        uid,
        contentType,
        prompt,
        provider,
        sourceAssetIds,
        location,
        channelId,
        metadata,
    });
    try {
        const result = await runGoogleAIProvider({
            uid,
            jobId,
            contentType,
            prompt,
            sourceAssetIds,
            sourceImage,
            metadata,
        });
        const completed = await completeGenerationJob(uid, jobId, cost, result);
        res.status(200).json({ job: completed });
    }
    catch (error) {
        await failGenerationJob(uid, jobId, cost, error);
        throw error;
    }
}
async function handleAssistantChat(uid, req, res) {
    const body = objectBody(req);
    const question = stringField(body.question, "question", 500);
    const apiKey = anthropicApiKey.value() || process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        throw httpError(500, "missing_anthropic_key", "ANTHROPIC_API_KEY is not configured server-side.");
    }
    const anthropic = new sdk_1.default({ apiKey });
    const message = await anthropic.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 120,
        system: "You are Poplur AI, a friendly voice assistant built into the Poplur social media app. " +
            "Answer concisely in 1-2 sentences max. Be upbeat and helpful.",
        messages: [{ role: "user", content: question }],
        metadata: { user_id: uid },
    });
    const reply = message.content
        .filter((block) => block.type === "text")
        .map((block) => block.text)
        .join(" ")
        .trim();
    if (!reply) {
        throw httpError(502, "assistant_empty_reply", "The assistant returned no text.");
    }
    res.status(200).json({ reply });
}
const CLAUDE_ON_DEVICE_MODEL = "claude-haiku-4-5-20251001";
function anthropicClient() {
    const apiKey = anthropicApiKey.value() || process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        throw httpError(500, "missing_anthropic_key", "ANTHROPIC_API_KEY is not configured server-side.");
    }
    return new sdk_1.default({ apiKey });
}
function extractClaudeText(message) {
    return message.content
        .filter((block) => block.type === "text")
        .map((block) => block.text)
        .join(" ")
        .trim();
}
/** Strip markdown code fences and surrounding prose, then parse the JSON object. */
function parseClaudeJson(text) {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start < 0 || end <= start) {
        throw httpError(502, "assistant_invalid_json", "The assistant returned no JSON object.");
    }
    try {
        return JSON.parse(text.slice(start, end + 1));
    }
    catch {
        throw httpError(502, "assistant_invalid_json", "The assistant returned invalid JSON.");
    }
}
/** Classifies one post image into Poplur TV broadcast metadata. */
async function handleTvStyle(uid, req, res) {
    const body = objectBody(req);
    const imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64 : "";
    // Reject rather than truncate — a sliced base64 string is a corrupt image.
    if (!imageBase64 || imageBase64.length > 1_400_000) {
        throw httpError(400, "invalid_field", "Send one JPEG smaller than 1 MB as imageBase64.");
    }
    const prompt = [
        "You are a TV broadcast classifier for Poplur TV, a social platform where every post is a TV broadcast.",
        "Analyze this image and respond ONLY with a JSON object — no extra text, no markdown:",
        "{\"channel\":\"<food|fitness|sports|beauty|fashion|music|tech|news|city|entertainment>\"," +
            "\"tvFormat\":\"<commercial|highlight_reel|cooking_show|documentary|talk_show|music_video|news_segment>\"," +
            "\"adConcept\":\"<what this would be as a TV ad or show in under 8 words>\"," +
            "\"caption\":\"<PUNCHY ALL-CAPS HEADLINE MAX 5 WORDS>\"," +
            "\"tagline\":\"<one compelling motivational sentence>\"," +
            "\"broadcastName\":\"<POPLUR CHANNEL e.g. POPLUR FITNESS>\"}",
    ].join("\n");
    const message = await anthropicClient().messages.create({
        model: CLAUDE_ON_DEVICE_MODEL,
        max_tokens: 300,
        messages: [{
                role: "user",
                content: [
                    { type: "image", source: { type: "base64", media_type: "image/jpeg", data: imageBase64 } },
                    { type: "text", text: prompt },
                ],
            }],
        metadata: { user_id: uid },
    });
    const result = parseClaudeJson(extractClaudeText(message));
    res.status(200).json({
        channel: optionalStringField(result.channel, 40) ?? "entertainment",
        tvFormat: optionalStringField(result.tvFormat, 40) ?? "commercial",
        adConcept: optionalStringField(result.adConcept, 120) ?? "",
        caption: optionalStringField(result.caption, 80) ?? "",
        tagline: optionalStringField(result.tagline, 200) ?? "",
        broadcastName: optionalStringField(result.broadcastName, 60) ?? "POPLUR TV",
    });
}
/** One spoken TV-host sentence introducing the next feed video. */
async function handleBumperScript(uid, req, res) {
    const body = objectBody(req);
    const context = stringField(body.context, "context", 700);
    const language = optionalStringField(body.language, 20) ?? "english";
    const langLine = language === "french"
        ? "Write the sentence in French (français). Sound like a natural French TV presenter."
        : language === "spanish"
            ? "Write the sentence in Spanish (español). Sound like a natural Spanish TV presenter."
            : "Write the sentence in English. Sound like a natural English-speaking TV presenter.";
    const prompt = [
        "You are a charismatic TV host for Poplur, a social video app.",
        "Using the details below, write ONE natural spoken sentence (12–22 words) that a host would say live on air to introduce the next video.",
        "Reference the channel, location, and radius reach naturally — don't just list them.",
        `Be warm, specific, and engaging. Vary your phrasing. ${langLine}`,
        "Return ONLY the spoken sentence — no quotes, no labels, no extra text.",
        "",
        context,
    ].join("\n");
    const message = await anthropicClient().messages.create({
        model: CLAUDE_ON_DEVICE_MODEL,
        max_tokens: 80,
        messages: [{ role: "user", content: prompt }],
        metadata: { user_id: uid },
    });
    const script = extractClaudeText(message);
    if (!script) {
        throw httpError(502, "assistant_empty_reply", "The assistant returned no script.");
    }
    res.status(200).json({ script });
}
const GAME_CONFIG_SHAPE = [
    "Return exactly this JSON shape:",
    "{",
    "  \"game\": \"<game_key>\",",
    "  \"character\": \"<character_id>\",",
    "  \"gameName\": \"<creative 2-4 word title>\",",
    "  \"theme\": \"<one word: Jungle|Space|Neon|Arctic|Lava|Ocean|Cyber|Ancient|Dream|Toxic>\",",
    "  \"skyColor\": \"<hex #RRGGBB>\",",
    "  \"groundColor\": \"<hex #RRGGBB>\",",
    "  \"accentColor\": \"<hex #RRGGBB>\",",
    "  \"difficulty\": \"<easy|medium|hard>\",",
    "  \"speed\": <integer 200-380>,",
    "  \"powerUps\": [\"<name>\", \"<name>\"],",
    "  \"enemyType\": \"<creative enemy name>\",",
    "  \"specialMechanic\": \"<one short phrase>\"",
    "}",
].join("\n");
const GAME_SYSTEM_PROMPTS = {
    arcade: [
        "You generate game session configs for Poplur, a mobile game app. Return ONLY valid JSON — no markdown, no code fences.",
        "",
        "Available game keys: stella_blast",
        "Available character ids: pop, zyla, blip, rex, stella, glitch",
        "",
        GAME_CONFIG_SHAPE,
        "",
        "Generate a polished arcade-shooter session that feels closer to a real console game than a toy mini-game.",
        "Use stella_blast, choose cinematic space/neon colors, and make the mechanics sound skill-based.",
    ].join("\n"),
    maker: [
        "You generate game session configs for Poplur, a mobile game app, from a user's description.",
        "Return ONLY valid JSON — no markdown, no code fences.",
        "",
        "Available game keys: pop_runner (side-scroller), stella_blast (arcade shooter), zyla_quest (action/adventure), rex_hoops (sports)",
        "Available character ids: pop, zyla, blip, rex, stella, glitch",
        "",
        GAME_CONFIG_SHAPE,
        "",
        "Choose the game key that best fits the user's description. Pick colours and mechanics that",
        "match their theme. Make it sound like a polished console game, not a toy mini-game.",
    ].join("\n"),
};
/** One generated Poplur mini-game session config. */
async function handleGameConfig(uid, req, res) {
    const body = objectBody(req);
    const mode = optionalStringField(body.mode, 20) ?? "arcade";
    const system = GAME_SYSTEM_PROMPTS[mode];
    if (!system) {
        throw httpError(400, "invalid_field", "mode must be \"arcade\" or \"maker\".");
    }
    const prompt = optionalStringField(body.prompt, 500);
    const userMessage = mode === "maker" && prompt
        ? `Create a game based on this idea: ${prompt}`
        : "Generate a fresh, surprising game config now.";
    // The client caches one session per shipped game/day, but billing protection
    // must live on the server. A signed-in caller gets enough headroom for all
    // three games plus retries while button mashing and scripted abuse stay
    // bounded even if they bypass the web bundle entirely.
    const today = new Date().toISOString().slice(0, 10);
    const rateRef = db.collection("gameConfigRate").doc(uid);
    await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(rateRef);
        const data = snapshot.data() ?? {};
        const lastAt = data.lastAt;
        const sameDay = data.day === today;
        const usedToday = sameDay && typeof data.count === "number" ? Math.max(0, Math.floor(data.count)) : 0;
        if (lastAt && Date.now() - lastAt.toMillis() < 4_000) {
            throw httpError(429, "rate_limited", "Let the game director finish before asking again.");
        }
        if (usedToday >= 12) {
            throw httpError(429, "daily_limit", "Today's game-director sessions are ready. Come back tomorrow for new ones.");
        }
        transaction.set(rateRef, {
            day: today,
            count: usedToday + 1,
            lastAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    const message = await anthropicClient().messages.create({
        model: CLAUDE_ON_DEVICE_MODEL,
        max_tokens: 280,
        system,
        messages: [{ role: "user", content: userMessage }],
        metadata: { user_id: uid },
    });
    res.status(200).json({ config: parseClaudeJson(extractClaudeText(message)) });
}
/** Three-shot AI-video storyboard for the Android AI video studio. */
async function handleVideoStoryboard(uid, req, res) {
    const body = objectBody(req);
    const prompt = stringField(body.prompt, "prompt", 500);
    const styleLabel = optionalStringField(body.styleLabel, 80) ?? "Poplur TV";
    const styleSuffix = optionalStringField(body.styleSuffix, 300) ?? "";
    const locationName = optionalStringField(body.locationName, 120);
    const system = [
        "You are a creative director for Poplur, a social video app where content is tied to real-world locations.",
        "Generate a 3-shot storyboard for a short vertical social video based on the user's prompt.",
        `Style: ${styleLabel}${styleSuffix ? ` — ${styleSuffix}` : ""}`,
        locationName ? `Location: ${locationName}.` : "",
        "",
        "Return ONLY valid JSON in this exact structure — no markdown, no explanation:",
        "{",
        "  \"title\": \"short catchy title\",",
        "  \"style\": \"brief style description\",",
        "  \"shots\": [",
        "    {\"shot\": 1, \"type\": \"opening shot type\", \"prompt\": \"detailed visual description of what happens in this 5-second clip, no text or watermarks\", \"duration\": 5},",
        "    {\"shot\": 2, \"type\": \"main action type\", \"prompt\": \"detailed visual description\", \"duration\": 5},",
        "    {\"shot\": 3, \"type\": \"closing shot type\", \"prompt\": \"detailed visual description\", \"duration\": 5}",
        "  ]",
        "}",
        "",
        "IMPORTANT: Each prompt must describe ORIGINAL characters only — no copyrighted IP, no named celebrities or brands.",
        `Make the prompts rich, cinematic, and specific to the ${styleLabel} aesthetic.`,
    ].filter((line) => line !== undefined).join("\n");
    const message = await anthropicClient().messages.create({
        model: CLAUDE_ON_DEVICE_MODEL,
        max_tokens: 600,
        system,
        messages: [{ role: "user", content: prompt }],
        metadata: { user_id: uid },
    });
    const result = parseClaudeJson(extractClaudeText(message));
    if (!Array.isArray(result.shots) || result.shots.length === 0) {
        throw httpError(502, "assistant_invalid_json", "The storyboard has no shots.");
    }
    res.status(200).json(result);
}
const AUTH_GUIDE_SYSTEM_PROMPTS = {
    welcome: "You are Poplur's onboarding guide. Poplur is a location-based social app — every post has a radius " +
        "that controls how far it reaches. Answer in 1-2 warm, friendly sentences.",
    login: "You are Poplur's sign-in helper. The user is logging in with email and password. If stuck, they can " +
        "tap FORGOT to reset. Answer in 1-2 sentences.",
    signUp: "You are Poplur's sign-up guide. Personal accounts are for individual creators; business accounts " +
        "unlock brand features. Answer in 1-2 friendly sentences.",
};
/** Pre-login auth-screen voice guide. Unauthenticated by necessity, so the
 * prompt is server-owned, the output is tiny, and each client IP is limited
 * to one request every few seconds via the same transaction pattern as
 * cameraSceneScan. */
async function handleAuthGuideChat(req, res) {
    const body = objectBody(req);
    const screen = optionalStringField(body.screen, 20) ?? "welcome";
    const system = AUTH_GUIDE_SYSTEM_PROMPTS[screen];
    if (!system) {
        throw httpError(400, "invalid_field", "screen must be welcome, login, or signUp.");
    }
    const question = stringField(body.question, "question", 300);
    const clientIp = (req.ip || req.header("x-forwarded-for") || "unknown").split(",")[0].trim();
    const rateKey = Buffer.from(clientIp).toString("base64url").slice(0, 100);
    const rateRef = db.collection("authGuideRate").doc(rateKey);
    await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(rateRef);
        const lastAt = snapshot.data()?.lastAt;
        if (lastAt && Date.now() - lastAt.toMillis() < 4_000) {
            throw httpError(429, "rate_limited", "One question at a time — give the guide a moment.");
        }
        transaction.set(rateRef, { lastAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    });
    const message = await anthropicClient().messages.create({
        model: CLAUDE_ON_DEVICE_MODEL,
        max_tokens: 80,
        system,
        messages: [{ role: "user", content: question }],
    });
    const reply = extractClaudeText(message);
    if (!reply) {
        throw httpError(502, "assistant_empty_reply", "The assistant returned no text.");
    }
    res.status(200).json({ reply });
}
async function handleRadioHost(uid, req, res) {
    await requirePremiumAIUser(uid);
    const body = objectBody(req);
    const script = stringField(body.script, "script", 1800);
    const cityName = optionalStringField(body.cityName, 120) ?? "this stop";
    const stopTitle = optionalStringField(body.stopTitle, 160) ?? cityName;
    const stationName = optionalStringField(body.stationName, 180) ?? "the local station";
    const style = optionalStringField(body.style, 220) ?? "warm local radio presenter";
    const hostedScript = await generateRadioHostScript({
        uid,
        script,
        cityName,
        stopTitle,
        stationName,
        style,
    });
    const audio = await synthesizeRadioHostAudio(hostedScript);
    res.status(200).json({
        script: hostedScript,
        audioBase64: audio.audioBase64,
        mimeType: audio.mimeType,
        sampleRateHz: audio.sampleRateHz,
        stationName,
    });
}
async function generateRadioHostScript(input) {
    const apiKey = process.env.GOOGLE_AI_API_KEY;
    if (!apiKey) {
        if (process.env.FUNCTIONS_EMULATOR === "true") {
            return fallbackRadioHostScript(input.script, input.cityName, input.stationName);
        }
        throw httpError(500, "missing_google_ai_key", "GOOGLE_AI_API_KEY is not configured server-side.");
    }
    const prompt = [
        "Rewrite this Poplur AI line into one natural radio-host segment.",
        "Make it sound like a real live radio presenter, not a robot.",
        "Keep it concise: 22 to 45 spoken words.",
        "Use contractions, light rhythm, and a clean handoff into the station.",
        "Do not add labels, markdown, quotes, sound effects, or stage directions.",
        `City: ${input.cityName}`,
        `Current stop: ${input.stopTitle}`,
        `Station bed: ${input.stationName}`,
        `Presenter style: ${input.style}`,
        `Original line: ${input.script}`,
    ].join("\n");
    const payload = await callGeminiGenerateContent({
        apiKey,
        model: process.env.POPLUR_RADIO_SCRIPT_MODEL || "gemini-3.5-flash",
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
            temperature: 0.82,
            maxOutputTokens: 140,
            responseMimeType: "text/plain",
        },
    });
    return cleanGeneratedText(extractGeminiText(payload)) || fallbackRadioHostScript(input.script, input.cityName, input.stationName);
}
async function synthesizeRadioHostAudio(script) {
    const apiKey = process.env.GOOGLE_AI_API_KEY;
    if (!apiKey) {
        throw httpError(500, "missing_google_ai_key", "GOOGLE_AI_API_KEY is not configured server-side.");
    }
    const sampleRateHz = 24_000;
    const payload = await callGeminiAudioInteraction({
        apiKey,
        model: process.env.POPLUR_RADIO_TTS_MODEL || "gemini-3.1-flash-tts-preview",
        input: [
            "Say this like a warm, natural FM radio host over a music bed.",
            "Keep the delivery human, relaxed, lightly energetic, and not synthetic.",
            "Avoid reading punctuation as literal words.",
            script,
        ].join("\n"),
        voice: process.env.POPLUR_RADIO_TTS_VOICE || "Kore",
    });
    const audio = extractGeminiInteractionAudio(payload);
    if (!audio?.data) {
        throw httpError(502, "provider_missing_audio", "Google AI Studio returned no radio audio.");
    }
    const pcm = Buffer.from(audio.data, "base64");
    const wav = wrapLinearPCMAsWav(pcm, sampleRateHz, 1, 16);
    return {
        audioBase64: wav.toString("base64"),
        mimeType: "audio/wav",
        sampleRateHz,
    };
}
async function handleCancelJob(uid, jobId, res) {
    const jobRef = db.collection("aiGenerationJobs").doc(jobId);
    const job = await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(jobRef);
        const data = snapshot.data();
        if (!snapshot.exists || !data || data.userId !== uid) {
            throw httpError(404, "job_not_found", "AI job not found.");
        }
        if (data.status === "completed" || data.status === "failed" || data.status === "cancelled") {
            return serializeDocument(snapshot.id, data);
        }
        const reserved = positiveInt(data.creditsReserved, 0);
        if (reserved > 0) {
            const balanceRef = db.collection("creatorCreditBalances").doc(uid);
            const balanceSnapshot = await transaction.get(balanceRef);
            const balance = balanceSnapshot.data() ?? {};
            transaction.set(balanceRef, {
                availableCredits: positiveInt(balance.availableCredits, 0) + reserved,
                reservedCredits: Math.max(positiveInt(balance.reservedCredits, 0) - reserved, 0),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
            transaction.create(db.collection("creatorCreditTransactions").doc(), {
                userId: uid,
                amount: reserved,
                type: "ai_generation_cancel_refund",
                relatedJobId: jobId,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        transaction.update(jobRef, {
            status: "cancelled",
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            completedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return {
            id: jobId,
            ...data,
            status: "cancelled",
        };
    });
    res.status(200).json({ job });
}
async function handlePublishGeneratedJob(uid, jobId, req, res) {
    const body = objectBody(req);
    const latitude = numberField(body.latitude, "latitude");
    const longitude = numberField(body.longitude, "longitude");
    const channelId = stringField(body.channelId, "channelId", 120);
    const radiusMeters = positiveInt(body.radiusMeters, 5000);
    const caption = optionalStringField(body.caption, 2000);
    const jobRef = db.collection("aiGenerationJobs").doc(jobId);
    const userRef = db.collection("users").doc(uid);
    const [jobSnapshot, userSnapshot] = await Promise.all([jobRef.get(), userRef.get()]);
    const job = jobSnapshot.data();
    if (!jobSnapshot.exists || !job || job.userId !== uid) {
        throw httpError(404, "job_not_found", "AI job not found.");
    }
    if (job.status !== "completed") {
        throw httpError(409, "job_not_complete", "This AI job is not ready to publish yet.");
    }
    const chosenChannelId = chooseChannel(channelId, job.prompt, job.contentType);
    const postRef = db.collection("posts").doc();
    const outputAssetIds = Array.isArray(job.outputAssetIds) ? job.outputAssetIds : [];
    const now = firestore_1.FieldValue.serverTimestamp();
    const account = userSnapshot.data();
    const hiddenOrigin = account?.privateAccount === true || account?.ghostMode === true;
    const latitudeCell = Math.round(latitude * 1_000);
    const longitudeCell = Math.round(longitude * 1_000);
    const post = {
        userId: uid,
        userID: uid,
        aiGenerated: true,
        aiGenerationJobId: jobId,
        assetIds: outputAssetIds,
        channelId: chosenChannelId,
        originalChannelId: channelId,
        channelReviewStatus: chosenChannelId === channelId ? "approved" : "rerouted",
        audience: "public",
        locationVisibility: hiddenOrigin ? "hidden" : "approximate",
        radiusMeters,
        organicRadiusMeters: radiusMeters,
        boostedRadiusMeters: 0,
        visibilityStatus: "published",
        caption: caption ?? job.outputText ?? "",
        createdAt: now,
        updatedAt: now,
    };
    if (!hiddenOrigin) {
        post.latitude = latitudeCell / 1_000;
        post.longitude = longitudeCell / 1_000;
        post.latitudeCell = latitudeCell;
        post.longitudeCell = longitudeCell;
    }
    const publishBatch = db.batch();
    publishBatch.set(postRef, post);
    publishBatch.set(userRef.collection("postLocations").doc(postRef.id), {
        latitude,
        longitude,
        createdAt: now,
        source: "ai-generated-post",
    });
    publishBatch.set(jobRef, {
        publishedPostId: postRef.id,
        publishedChannelId: chosenChannelId,
        updatedAt: now,
    }, { merge: true });
    await publishBatch.commit();
    res.status(200).json({
        postId: postRef.id,
        chosenChannelId,
        originalChannelId: channelId,
        rerouted: chosenChannelId !== channelId,
    });
}
async function handleRadiusBoost(uid, postId, req, res) {
    const body = objectBody(req);
    const radiusMetersAdded = positiveInt(body.radiusMetersAdded, 1000);
    const durationHours = positiveInt(body.durationHours, 24);
    const cost = calculateRadiusBoostCost(radiusMetersAdded, durationHours);
    const postRef = db.collection("posts").doc(postId);
    const boostRef = db.collection("radiusBoostTransactions").doc();
    const expiresAt = firestore_1.Timestamp.fromMillis(Date.now() + durationHours * 60 * 60 * 1000);
    await db.runTransaction(async (transaction) => {
        const postSnapshot = await transaction.get(postRef);
        const post = postSnapshot.data();
        if (!postSnapshot.exists || !post || (post.userId !== uid && post.userID !== uid)) {
            throw httpError(404, "post_not_found", "Post not found.");
        }
        await spendCreditsInTransaction(transaction, uid, cost, {
            type: "radius_boost_spend",
            relatedPostId: postId,
            metadata: { radiusMetersAdded, durationHours },
        });
        transaction.create(boostRef, {
            userId: uid,
            postId,
            amount: -cost,
            radiusMetersAdded,
            durationHours,
            expiresAt,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        transaction.set(postRef, {
            boostedRadiusMeters: radiusMetersAdded,
            boostExpiresAt: expiresAt,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    res.status(200).json({
        postId,
        boostTransactionId: boostRef.id,
        creditsCharged: cost,
        radiusMetersAdded,
        durationHours,
        expiresAt: expiresAt.toDate().toISOString(),
    });
}
async function handleBusinessCampaign(uid, businessId, req, res) {
    const body = objectBody(req);
    const prompt = stringField(body.prompt, "prompt", 4000);
    const businessRef = db.collection("businesses").doc(businessId);
    const businessSnapshot = await businessRef.get();
    const business = businessSnapshot.data();
    if (!businessSnapshot.exists || !business || business.ownerUserId !== uid) {
        throw httpError(404, "business_not_found", "Business profile not found.");
    }
    const contentType = "game";
    const provider = "google_ai_studio";
    const { jobId, cost } = await reserveCreditsAndCreateJob({
        uid,
        contentType,
        prompt,
        provider,
        sourceAssetIds: [],
        metadata: { businessId, campaign: true },
    });
    try {
        const result = await runGoogleAIProvider({
            uid,
            jobId,
            contentType,
            prompt: [
                "Create a Poplur business campaign bundle.",
                `Business name: ${typeof business.businessName === "string" ? business.businessName : businessId}`,
                `Prompt: ${prompt}`,
                "Return concise campaign copy, channel recommendation, coupon idea, caption, and tags.",
            ].join("\n"),
            sourceAssetIds: [],
            metadata: { businessId, campaign: true },
        });
        const completedJob = await completeGenerationJob(uid, jobId, cost, result);
        const campaignRef = db.collection("aiCampaigns").doc();
        await campaignRef.set({
            businessId,
            ownerUid: uid,
            jobId,
            prompt,
            status: "ready",
            assetIds: completedJob.outputAssetIds ?? [],
            campaignText: completedJob.outputText ?? "",
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        res.status(200).json({
            campaignId: campaignRef.id,
            job: completedJob,
        });
    }
    catch (error) {
        await failGenerationJob(uid, jobId, cost, error);
        throw error;
    }
}
async function reserveCreditsAndCreateJob(input) {
    const cost = aiCreditCost(input.contentType);
    const jobRef = db.collection("aiGenerationJobs").doc();
    await db.runTransaction(async (transaction) => {
        await reserveCreditsInTransaction(transaction, input.uid, cost, {
            type: "ai_generation_reserve",
            relatedJobId: jobRef.id,
            provider: input.provider,
            contentType: input.contentType,
            metadata: input.metadata,
        });
        transaction.create(jobRef, {
            userId: input.uid,
            provider: input.provider,
            contentType: input.contentType,
            prompt: input.prompt,
            sourceAssetIds: input.sourceAssetIds,
            status: "processing",
            creditsReserved: cost,
            creditsCharged: 0,
            outputAssetIds: [],
            location: input.location ?? null,
            channelId: input.channelId ?? null,
            metadata: input.metadata,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return { jobId: jobRef.id, cost };
}
async function reserveCreditsInTransaction(transaction, uid, cost, ledger) {
    const balanceRef = db.collection("creatorCreditBalances").doc(uid);
    const balanceSnapshot = await transaction.get(balanceRef);
    const balance = balanceSnapshot.data() ?? {};
    const availableCredits = positiveInt(balance.availableCredits, 0);
    const reservedCredits = positiveInt(balance.reservedCredits, 0);
    if (availableCredits < cost) {
        throw httpError(402, "insufficient_credits", "Not enough Poplur credits for this request.");
    }
    transaction.set(balanceRef, {
        availableCredits: availableCredits - cost,
        reservedCredits: reservedCredits + cost,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.create(db.collection("creatorCreditTransactions").doc(), {
        userId: uid,
        amount: -cost,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        ...ledger,
    });
}
async function spendCreditsInTransaction(transaction, uid, cost, ledger) {
    const balanceRef = db.collection("creatorCreditBalances").doc(uid);
    const balanceSnapshot = await transaction.get(balanceRef);
    const balance = balanceSnapshot.data() ?? {};
    const availableCredits = positiveInt(balance.availableCredits, 0);
    if (availableCredits < cost) {
        throw httpError(402, "insufficient_credits", "Not enough Poplur credits for this request.");
    }
    transaction.set(balanceRef, {
        availableCredits: availableCredits - cost,
        lifetimeSpent: positiveInt(balance.lifetimeSpent, 0) + cost,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.create(db.collection("creatorCreditTransactions").doc(), {
        userId: uid,
        amount: -cost,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        ...ledger,
    });
}
async function completeGenerationJob(uid, jobId, cost, result) {
    const jobRef = db.collection("aiGenerationJobs").doc(jobId);
    const outputAssetIds = [];
    const outputUrls = [];
    if (result.status === "provider_pending") {
        await jobRef.set({
            status: "provider_pending",
            outputText: result.outputText ?? null,
            providerJobId: result.providerJobId ?? null,
            providerMetadata: result.rawMetadata ?? {},
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        const snapshot = await jobRef.get();
        return serializeDocument(snapshot.id, snapshot.data() ?? {});
    }
    if (result.asset) {
        const assetRef = db.collection("generatedAssets").doc();
        const extension = extensionForMimeType(result.asset.mimeType);
        const storagePath = `generated/${uid}/${jobId}/${assetRef.id}.${extension}`;
        const file = admin.storage().bucket().file(storagePath);
        await file.save(result.asset.bytes, {
            metadata: {
                contentType: result.asset.mimeType,
            },
        });
        const downloadUrl = await signedGeneratedAssetUrl(file);
        await assetRef.set({
            userId: uid,
            jobId,
            provider: "google_ai_studio",
            contentType: result.asset.mimeType.startsWith("video/") ? "video" : "image",
            storagePath,
            downloadUrl,
            mimeType: result.asset.mimeType,
            moderationStatus: "pending",
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            metadata: result.rawMetadata ?? {},
        });
        outputAssetIds.push(assetRef.id);
        outputUrls.push(downloadUrl);
    }
    await db.runTransaction(async (transaction) => {
        const balanceRef = db.collection("creatorCreditBalances").doc(uid);
        const balanceSnapshot = await transaction.get(balanceRef);
        const balance = balanceSnapshot.data() ?? {};
        transaction.set(balanceRef, {
            reservedCredits: Math.max(positiveInt(balance.reservedCredits, 0) - cost, 0),
            lifetimeSpent: positiveInt(balance.lifetimeSpent, 0) + cost,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.set(jobRef, {
            status: result.status,
            creditsReserved: 0,
            creditsCharged: result.status === "completed" ? cost : 0,
            outputAssetIds,
            outputUrls,
            outputUrl: outputUrls[0] ?? null,
            outputText: result.outputText ?? null,
            providerJobId: result.providerJobId ?? null,
            providerMetadata: result.rawMetadata ?? {},
            completedAt: result.status === "completed" ? firestore_1.FieldValue.serverTimestamp() : null,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    const snapshot = await jobRef.get();
    return serializeDocument(snapshot.id, snapshot.data() ?? {});
}
async function signedGeneratedAssetUrl(file) {
    const [url] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });
    return url;
}
async function failGenerationJob(uid, jobId, cost, error) {
    const message = error instanceof Error ? error.message : "AI generation failed.";
    await db.runTransaction(async (transaction) => {
        const balanceRef = db.collection("creatorCreditBalances").doc(uid);
        const balanceSnapshot = await transaction.get(balanceRef);
        const balance = balanceSnapshot.data() ?? {};
        transaction.set(balanceRef, {
            availableCredits: positiveInt(balance.availableCredits, 0) + cost,
            reservedCredits: Math.max(positiveInt(balance.reservedCredits, 0) - cost, 0),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.create(db.collection("creatorCreditTransactions").doc(), {
            userId: uid,
            amount: cost,
            type: "ai_generation_refund",
            relatedJobId: jobId,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        transaction.set(db.collection("aiGenerationJobs").doc(jobId), {
            status: "failed",
            errorMessage: message.slice(0, 500),
            creditsReserved: 0,
            creditsCharged: 0,
            completedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
async function runGoogleAIProvider(input) {
    const apiKey = process.env.GOOGLE_AI_API_KEY;
    if (!apiKey) {
        if (process.env.FUNCTIONS_EMULATOR === "true") {
            return {
                status: "completed",
                outputText: `Emulator Poplur AI ${input.contentType} result for: ${input.prompt}`,
                rawMetadata: { emulator: true },
            };
        }
        throw httpError(500, "missing_google_ai_key", "GOOGLE_AI_API_KEY is not configured server-side.");
    }
    const model = modelForContentType(input.contentType);
    const sourceInput = input.sourceImage
        ? [
            { type: "text", text: input.prompt },
            { type: "image", mime_type: input.sourceImage.mimeType, data: input.sourceImage.data },
        ]
        : input.prompt;
    const body = {
        model,
        input: sourceInput,
        background: input.contentType === "video",
        generation_config: {
            response_modalities: responseModalitiesForContentType(input.contentType),
        },
    };
    const response = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(body),
    });
    const responseText = await response.text();
    if (!response.ok) {
        firebase_functions_1.logger.error("google_ai_provider_failed", {
            status: response.status,
            contentType: input.contentType,
            jobId: input.jobId,
            bodyPreview: responseText.slice(0, 280),
        });
        throw httpError(502, "provider_failed", "Google AI Studio generation failed.");
    }
    const payload = parseJson(responseText);
    const extracted = extractProviderOutput(payload);
    return {
        status: extracted.asset || extracted.text || !extracted.providerJobId ? "completed" : "provider_pending",
        outputText: extracted.text ?? (!extracted.providerJobId ? "Google AI Studio returned a completed response without text media." : undefined),
        asset: extracted.asset,
        providerJobId: extracted.providerJobId,
        rawMetadata: {
            model,
            providerStatus: extracted.providerStatus,
        },
    };
}
/**
 * A single bounded image travels with an edit request; it is not written to a
 * job document or logged. This keeps an unposted camera capture private while
 * letting the provider perform genuine image-to-image editing.
 */
function optionalSourceImage(body) {
    const raw = plainObjectField(body.sourceImage);
    if (!raw)
        return undefined;
    const data = optionalStringField(raw.data, 1_400_000);
    const mimeType = optionalStringField(raw.mimeType, 40);
    if (!data || !mimeType || !/^[A-Za-z0-9+/=]+$/.test(data)) {
        throw httpError(400, "invalid_source_image", "Send one encoded JPEG, PNG, or WebP image.");
    }
    if (mimeType !== "image/jpeg" && mimeType !== "image/png" && mimeType !== "image/webp") {
        throw httpError(400, "invalid_source_image", "Use a JPEG, PNG, or WebP image for AI editing.");
    }
    const bytes = Buffer.from(data, "base64");
    if (!bytes.length || bytes.length > 1_000_000) {
        throw httpError(400, "invalid_source_image", "The AI edit source image must be 1 MB or smaller.");
    }
    return { data, mimeType };
}
function responseModalitiesForContentType(contentType) {
    switch (contentType) {
        case "image":
        case "edit":
        case "vfx":
        case "3d":
            return ["image"];
        case "video":
            return ["video"];
        case "voice":
            return ["audio"];
        default:
            return ["text"];
    }
}
function modelForContentType(contentType) {
    switch (contentType) {
        case "video":
            return process.env.POPLUR_VIDEO_MODEL || "gemini-omni-flash-preview";
        case "image":
        case "edit":
        case "vfx":
        case "3d":
            return process.env.POPLUR_IMAGE_MODEL || "gemini-2.5-flash-image";
        default:
            return process.env.POPLUR_TEXT_MODEL || "gemini-3.5-flash";
    }
}
async function callGeminiGenerateContent(input) {
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(input.model)}:generateContent`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": input.apiKey,
        },
        body: JSON.stringify({
            contents: input.contents,
            generationConfig: input.generationConfig,
        }),
    });
    const responseText = await response.text();
    if (!response.ok) {
        firebase_functions_1.logger.error("google_ai_generate_content_failed", {
            status: response.status,
            model: input.model,
            bodyPreview: responseText.slice(0, 280),
        });
        throw httpError(502, "provider_failed", "Google AI Studio generation failed.");
    }
    return parseJson(responseText);
}
async function callGeminiAudioInteraction(input) {
    const response = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": input.apiKey,
        },
        body: JSON.stringify({
            model: input.model,
            input: input.input,
            response_format: { type: "audio" },
            generation_config: {
                speech_config: [
                    {
                        voice: input.voice,
                    },
                ],
            },
        }),
    });
    const responseText = await response.text();
    if (!response.ok) {
        firebase_functions_1.logger.error("google_ai_audio_interaction_failed", {
            status: response.status,
            model: input.model,
            bodyPreview: responseText.slice(0, 280),
        });
        throw httpError(502, "provider_failed", "Google AI Studio radio voice generation failed.");
    }
    return parseJson(responseText);
}
function extractGeminiText(payload) {
    const candidates = payload?.candidates;
    const first = Array.isArray(candidates) ? candidates[0] : undefined;
    const content = first?.content;
    const parts = Array.isArray(content?.parts) ? content?.parts : [];
    return parts
        .map((part) => part.text)
        .filter((text) => typeof text === "string")
        .join(" ")
        .trim();
}
function extractGeminiInteractionAudio(payload) {
    if (!payload || typeof payload !== "object") {
        return undefined;
    }
    const record = payload;
    const outputAudio = record.output_audio ?? record.outputAudio;
    if (outputAudio && typeof outputAudio === "object") {
        const audioRecord = outputAudio;
        const data = typeof audioRecord.data === "string" ? audioRecord.data : undefined;
        const mimeType = typeof audioRecord.mime_type === "string"
            ? audioRecord.mime_type
            : typeof audioRecord.mimeType === "string"
                ? audioRecord.mimeType
                : undefined;
        if (data) {
            return { data, mimeType };
        }
    }
    const outputs = record.output ?? record.outputs;
    if (Array.isArray(outputs)) {
        for (const output of outputs) {
            const audio = extractGeminiInteractionAudio(output);
            if (audio) {
                return audio;
            }
        }
    }
    return undefined;
}
function wrapLinearPCMAsWav(pcm, sampleRate, channels, bitsPerSample) {
    const byteRate = sampleRate * channels * bitsPerSample / 8;
    const blockAlign = channels * bitsPerSample / 8;
    const header = Buffer.alloc(44);
    header.write("RIFF", 0);
    header.writeUInt32LE(36 + pcm.length, 4);
    header.write("WAVE", 8);
    header.write("fmt ", 12);
    header.writeUInt32LE(16, 16);
    header.writeUInt16LE(1, 20);
    header.writeUInt16LE(channels, 22);
    header.writeUInt32LE(sampleRate, 24);
    header.writeUInt32LE(byteRate, 28);
    header.writeUInt16LE(blockAlign, 32);
    header.writeUInt16LE(bitsPerSample, 34);
    header.write("data", 36);
    header.writeUInt32LE(pcm.length, 40);
    return Buffer.concat([header, pcm]);
}
function cleanGeneratedText(text) {
    return text
        .replace(/^["'\s]+|["'\s]+$/g, "")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 420);
}
function fallbackRadioHostScript(script, cityName, stationName) {
    const cleaned = cleanGeneratedText(script);
    return cleanGeneratedText(`Poplur Radio is live in ${cityName}. ${cleaned} Settle in for a few minutes, then we will blend right back into ${stationName}.`);
}
function extractProviderOutput(payload) {
    const data = payload;
    const providerJobId = optionalRecordString(data, ["id", "name", "operation"]);
    const providerStatus = optionalRecordString(data, ["status", "state"]);
    const outputText = findString(data, ["output_text", "outputText", "text"]);
    const media = findMedia(data);
    return {
        text: outputText,
        asset: media,
        providerJobId,
        providerStatus,
    };
}
function findMedia(value) {
    if (!value || typeof value !== "object") {
        return undefined;
    }
    if (Array.isArray(value)) {
        for (const item of value) {
            const found = findMedia(item);
            if (found) {
                return found;
            }
        }
        return undefined;
    }
    const record = value;
    const data = typeof record.data === "string" ? record.data : undefined;
    const mimeType = typeof record.mime_type === "string"
        ? record.mime_type
        : typeof record.mimeType === "string"
            ? record.mimeType
            : undefined;
    if (data && mimeType && (mimeType.startsWith("image/") || mimeType.startsWith("video/"))) {
        return {
            bytes: Buffer.from(data, "base64"),
            mimeType,
        };
    }
    for (const child of Object.values(record)) {
        const found = findMedia(child);
        if (found) {
            return found;
        }
    }
    return undefined;
}
function findString(value, keys) {
    if (!value || typeof value !== "object") {
        return undefined;
    }
    if (Array.isArray(value)) {
        for (const item of value) {
            const found = findString(item, keys);
            if (found) {
                return found;
            }
        }
        return undefined;
    }
    const record = value;
    for (const key of keys) {
        if (typeof record[key] === "string" && record[key]) {
            return record[key];
        }
    }
    for (const child of Object.values(record)) {
        const found = findString(child, keys);
        if (found) {
            return found;
        }
    }
    return undefined;
}
function optionalRecordString(record, keys) {
    for (const key of keys) {
        if (typeof record[key] === "string" && record[key]) {
            return record[key];
        }
    }
    return undefined;
}
function aiCreditCost(contentType) {
    switch (contentType) {
        case "image":
            return 12;
        case "video":
            return 45;
        case "edit":
            return 18;
        case "vfx":
            return 25;
        case "3d":
            return 30;
        case "voice":
            return 8;
        case "music":
            return 10;
        case "game":
            return 35;
    }
}
function calculateRadiusBoostCost(radiusMetersAdded, durationHours) {
    const distanceUnits = Math.max(Math.ceil(radiusMetersAdded / 1000), 1);
    const dayUnits = Math.max(Math.ceil(durationHours / 24), 1);
    return distanceUnits * dayUnits;
}
function chooseChannel(channelId, prompt, contentType) {
    const text = `${channelId} ${String(prompt ?? "")} ${String(contentType ?? "")}`.toLowerCase();
    if (text.includes("food") || text.includes("restaurant") || text.includes("burger") || text.includes("coffee")) {
        return "food";
    }
    if (text.includes("music") || text.includes("concert") || text.includes("song")) {
        return "music";
    }
    if (text.includes("fashion") || text.includes("fit") || text.includes("sneaker")) {
        return "fashion";
    }
    if (text.includes("game") || text.includes("play")) {
        return "gaming";
    }
    return channelId;
}
function extensionForMimeType(mimeType) {
    if (mimeType === "image/jpeg") {
        return "jpg";
    }
    if (mimeType === "video/mp4") {
        return "mp4";
    }
    if (mimeType === "image/webp") {
        return "webp";
    }
    return "png";
}
function objectBody(req) {
    if (!req.body || typeof req.body !== "object" || Array.isArray(req.body)) {
        throw httpError(400, "invalid_body", "Send a JSON object request body.");
    }
    return req.body;
}
function stringField(value, key, maxLength) {
    if (typeof value !== "string" || !value.trim()) {
        throw httpError(400, "invalid_field", `${key} is required.`);
    }
    return value.trim().slice(0, maxLength);
}
function optionalStringField(value, maxLength) {
    return typeof value === "string" && value.trim() ? value.trim().slice(0, maxLength) : undefined;
}
function numberField(value, key) {
    const numberValue = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(numberValue)) {
        throw httpError(400, "invalid_field", `${key} must be a number.`);
    }
    return numberValue;
}
function stringArrayField(value) {
    if (!Array.isArray(value)) {
        return [];
    }
    return value.filter((item) => typeof item === "string" && item.trim().length > 0).slice(0, 20);
}
function plainObjectField(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : undefined;
}
function parseJson(value) {
    try {
        return JSON.parse(value);
    }
    catch {
        throw httpError(502, "provider_invalid_response", "Google AI Studio returned an invalid response.");
    }
}
function serializeDocument(id, data) {
    return {
        id,
        ...Object.fromEntries(Object.entries(data).map(([key, value]) => [key, serializeValue(value)])),
    };
}
function serializeValue(value) {
    if (value instanceof firestore_1.Timestamp) {
        return value.toDate().toISOString();
    }
    if (Array.isArray(value)) {
        return value.map(serializeValue);
    }
    if (value && typeof value === "object") {
        return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, serializeValue(child)]));
    }
    return value ?? null;
}
function httpError(status, code, message) {
    const error = new Error(message);
    error.status = status;
    error.code = code;
    return error;
}
function handleRouteError(error, res) {
    if (res.headersSent) {
        return;
    }
    const typed = error;
    const status = typeof typed.status === "number" ? typed.status : 500;
    const code = typed.code || "internal";
    const message = status >= 500 ? "Poplur AI backend failed. Please try again." : typed.message || "Request failed.";
    if (status >= 500) {
        firebase_functions_1.logger.error("poplur_ai_api_error", {
            code,
            message: typed.message,
        });
    }
    sendError(res, status, code, message);
}
function sendError(res, status, code, message) {
    res.status(status).json({
        error: {
            code,
            message,
        },
    });
}
