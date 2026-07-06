from __future__ import annotations

import html
import os
import textwrap
from datetime import date

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    Flowable,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = "/Users/matrix/Documents/Poplur2025-iOS"
OUT = os.path.join(ROOT, "output/pdf/poplur_ai_backend_completion_guide.pdf")

ACCENT = colors.HexColor("#31E760")
DARK = colors.HexColor("#0B0F12")
INK = colors.HexColor("#161A1D")
MUTED = colors.HexColor("#5E6872")
PANEL = colors.HexColor("#F4F7F5")
PANEL_DARK = colors.HexColor("#102016")
LINE = colors.HexColor("#DDE5DE")
WARN = colors.HexColor("#FFF4D7")
RED = colors.HexColor("#E74747")
BLUE = colors.HexColor("#2B77F0")


class Rule(Flowable):
    def __init__(self, width="100%", height=1, color=LINE):
        super().__init__()
        self.width = width
        self.height = height
        self.color = color

    def wrap(self, avail_width, avail_height):
        self._width = avail_width if self.width == "100%" else self.width
        return self._width, self.height + 6

    def draw(self):
        self.canv.setStrokeColor(self.color)
        self.canv.setLineWidth(self.height)
        self.canv.line(0, 3, self._width, 3)


def styles():
    base = getSampleStyleSheet()
    return {
        "Title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=30,
            leading=34,
            textColor=colors.white,
            alignment=TA_LEFT,
            spaceAfter=14,
        ),
        "Subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=12.5,
            leading=17,
            textColor=colors.HexColor("#D7F8DF"),
            alignment=TA_LEFT,
        ),
        "H1": ParagraphStyle(
            "H1",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=19,
            leading=23,
            textColor=INK,
            spaceBefore=4,
            spaceAfter=8,
        ),
        "H2": ParagraphStyle(
            "H2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=13,
            leading=16,
            textColor=INK,
            spaceBefore=10,
            spaceAfter=4,
        ),
        "Body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9.6,
            leading=13.2,
            textColor=INK,
            spaceAfter=6,
        ),
        "BodySmall": ParagraphStyle(
            "BodySmall",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.8,
            leading=12,
            textColor=INK,
            spaceAfter=5,
        ),
        "Muted": ParagraphStyle(
            "Muted",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.6,
            leading=11.5,
            textColor=MUTED,
            spaceAfter=5,
        ),
        "Callout": ParagraphStyle(
            "Callout",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=10,
            leading=13.5,
            textColor=INK,
        ),
        "Code": ParagraphStyle(
            "Code",
            parent=base["BodyText"],
            fontName="Courier",
            fontSize=7.3,
            leading=9.6,
            textColor=colors.HexColor("#1B1F23"),
            spaceAfter=0,
        ),
        "Step": ParagraphStyle(
            "Step",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9.4,
            leading=12.4,
            textColor=INK,
            leftIndent=0,
            firstLineIndent=0,
            spaceAfter=4,
        ),
        "TableHead": ParagraphStyle(
            "TableHead",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=10.5,
            textColor=colors.white,
            alignment=TA_LEFT,
        ),
        "TableCell": ParagraphStyle(
            "TableCell",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.8,
            leading=10.2,
            textColor=INK,
        ),
        "TableCellBold": ParagraphStyle(
            "TableCellBold",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=7.8,
            leading=10.2,
            textColor=INK,
        ),
        "Footer": ParagraphStyle(
            "Footer",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.2,
            leading=8,
            textColor=MUTED,
            alignment=TA_CENTER,
        ),
        "Badge": ParagraphStyle(
            "Badge",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=10,
            textColor=colors.white,
            alignment=TA_CENTER,
        ),
        "Center": ParagraphStyle(
            "Center",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9.5,
            leading=13,
            textColor=INK,
            alignment=TA_CENTER,
        ),
    }


S = styles()


def p(text: str, style: str = "Body"):
    return Paragraph(text, S[style])


def bullet(items, style="BodySmall"):
    return ListFlowable(
        [ListItem(p(item, style), leftIndent=12) for item in items],
        bulletType="bullet",
        leftIndent=14,
        bulletFontName="Helvetica-Bold",
        bulletFontSize=7,
        bulletColor=ACCENT,
    )


def numbered(items, style="BodySmall"):
    return ListFlowable(
        [ListItem(p(item, style), leftIndent=15) for item in items],
        bulletType="1",
        start="1",
        leftIndent=16,
        bulletFontName="Helvetica-Bold",
        bulletFontSize=8,
        bulletColor=INK,
    )


def box(flowables, bg=PANEL, border=LINE, pad=8):
    return Table(
        [[flowables]],
        colWidths=[6.85 * inch],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), bg),
                ("BOX", (0, 0), (-1, -1), 0.75, border),
                ("LEFTPADDING", (0, 0), (-1, -1), pad),
                ("RIGHTPADDING", (0, 0), (-1, -1), pad),
                ("TOPPADDING", (0, 0), (-1, -1), pad),
                ("BOTTOMPADDING", (0, 0), (-1, -1), pad),
            ]
        ),
    )


def code_block(text: str):
    lines = []
    for raw in text.strip("\n").splitlines():
        if not raw:
            lines.append("")
            continue
        lines.extend(textwrap.wrap(raw, width=86, replace_whitespace=False, drop_whitespace=False) or [""])
    body = "<br/>".join(html.escape(line) for line in lines)
    return box([Paragraph(body, S["Code"])], bg=colors.HexColor("#F8FAF8"), border=colors.HexColor("#CED9CF"), pad=7)


def two_col(left, right, widths=(3.32 * inch, 3.32 * inch)):
    return Table(
        [[left, right]],
        colWidths=list(widths),
        style=TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (0, 0), 7),
                ("LEFTPADDING", (1, 0), (1, 0), 7),
            ]
        ),
    )


def data_table(headers, rows, col_widths):
    data = [[Paragraph(h, S["TableHead"]) for h in headers]]
    for row in rows:
        data.append([Paragraph(str(cell), S["TableCell"]) for cell in row])
    table = Table(data, colWidths=col_widths, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), DARK),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CBD6CC")),
                ("BACKGROUND", (0, 1), (-1, -1), colors.HexColor("#FBFCFB")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F6F9F6")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    return table


def section(title, body):
    return KeepTogether([p(title, "H2")] + body)


def header_footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.5)
    canvas.line(doc.leftMargin, 0.55 * inch, letter[0] - doc.rightMargin, 0.55 * inch)
    footer = f"Poplur AI Backend Completion Guide - Page {doc.page}"
    footer_para = Paragraph(footer, S["Footer"])
    footer_para.wrap(letter[0] - doc.leftMargin - doc.rightMargin, 0.2 * inch)
    footer_para.drawOn(canvas, doc.leftMargin, 0.32 * inch)
    canvas.restoreState()


def title_page(story):
    story.append(
        Table(
            [
                [
                    [
                        p("POPLUR", "Badge"),
                        Spacer(1, 0.23 * inch),
                        p("Poplur AI Backend Completion Guide", "Title"),
                        p(
                            "Step-by-step implementation plan for real backend endpoints, server-side Google AI Studio credentials, and Firestore transactional credit enforcement.",
                            "Subtitle",
                        ),
                        Spacer(1, 0.25 * inch),
                        p(f"Prepared: {date.today().isoformat()}", "Subtitle"),
                    ]
                ]
            ],
            colWidths=[6.85 * inch],
            rowHeights=[5.2 * inch],
            style=TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, -1), DARK),
                    ("BOX", (0, 0), (-1, -1), 1.2, ACCENT),
                    ("LEFTPADDING", (0, 0), (-1, -1), 28),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 28),
                    ("TOPPADDING", (0, 0), (-1, -1), 28),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 28),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ]
            ),
        )
    )
    story.append(Spacer(1, 0.18 * inch))
    story.append(
        box(
            [
                p("What this document completes", "Callout"),
                bullet(
                    [
                        "Premium Poplur AI requests are moved behind real backend endpoints.",
                        "Google AI Studio runs server-side only through GOOGLE_AI_API_KEY.",
                        "Credits are reserved, charged, and refunded in Firestore transactions.",
                        "iOS and Android call the same authenticated API and never store provider secrets.",
                    ]
                ),
            ],
            bg=colors.HexColor("#EBFFF0"),
            border=ACCENT,
        )
    )
    story.append(Spacer(1, 0.16 * inch))
    story.append(
        data_table(
            ["Milestone", "Definition of done"],
            [
                ["Backend endpoints", "Every AI action is exposed as an authenticated endpoint that creates an aiGenerationJob and returns a job id."],
                ["Secrets", "GOOGLE_AI_API_KEY and any provider keys exist only in Firebase Secret Manager or the hosting platform secret store."],
                ["Credits", "A Firestore transaction prevents negative balances and logs every spend, refund, grant, and radius boost."],
                ["Mobile", "Both iOS and Android upload inputs, call backend endpoints, poll jobs, then publish generated assets to map/profile/channel."],
            ],
            [1.6 * inch, 5.1 * inch],
        )
    )
    story.append(PageBreak())


def page_architecture(story):
    story.append(p("1. Target Architecture", "H1"))
    story.append(
        p(
            "Use Firebase Cloud Functions v2 for the fastest path because Poplur already uses Firebase Auth and Firestore. Cloud Run also works, but the first complete version should minimize moving parts.",
            "Body",
        )
    )
    story.append(
        box(
            [
                p("Mobile apps never call Google AI Studio directly.", "Callout"),
                p(
                    "iOS and Android send Firebase-authenticated requests to the backend. The backend validates the user, enforces credits transactionally, calls Google AI Studio with GOOGLE_AI_API_KEY, stores results, and returns a job id/status.",
                    "BodySmall",
                ),
            ],
            bg=colors.HexColor("#EBFFF0"),
            border=ACCENT,
        )
    )
    story.append(Spacer(1, 0.08 * inch))
    story.append(
        code_block(
            """
iOS / Android
  -> Firebase Auth ID token
  -> Backend HTTPS endpoint
  -> Firestore transaction: reserve credits + create aiGenerationJob
  -> Google AI Studio provider adapter reads GOOGLE_AI_API_KEY server-side
  -> Firebase Storage stores output
  -> Firestore transaction: complete job + charge or refund
  -> App polls job and publishes to map/channel/profile
"""
        )
    )
    story.append(Spacer(1, 0.08 * inch))
    story.append(
        section(
            "Non-negotiable rules",
            [
                bullet(
                    [
                        "Premium AI uses Google AI Studio through the backend only.",
                        "Replicate is not the premium provider. Keep any free-tier fallback separate from premium routing.",
                        "GOOGLE_AI_API_KEY is a server secret. It must never be checked into iOS, Android, Remote Config, or Firestore.",
                        "Credits are never trusted from the client. The client can request work; the server decides if the user can pay.",
                        "No job publishes to map/channel/profile until the backend confirms the asset belongs to that user and generation is complete.",
                    ]
                )
            ],
        )
    )
    story.append(
        section(
            "Endpoint groups to build",
            [
                data_table(
                    ["Group", "Endpoints"],
                    [
                        ["AI jobs", "POST /ai/generate/image, /video, /edit, /vfx, /3d, /voice, /music, /game; GET /ai/jobs/:id; POST /ai/jobs/:id/cancel"],
                        ["Publishing", "POST /ai/jobs/:id/publish-to-map; POST /posts/:id/publish-to-channel"],
                        ["Credits", "GET /credits/balance; GET /credits/transactions"],
                        ["Radius boosts", "POST /posts/:id/radius-boost"],
                        ["Business campaigns", "POST /businesses/:businessId/ai-campaigns; GET /businesses/:businessId/ai-campaigns/:id"],
                    ],
                    [1.45 * inch, 5.25 * inch],
                )
            ],
        )
    )
    story.append(PageBreak())


def page_setup_secrets(story):
    story.append(p("2. Backend Setup And Secrets", "H1"))
    story.append(p("Create a backend workspace beside the apps, then initialize Firebase Functions with TypeScript.", "Body"))
    story.append(
        code_block(
            """
mkdir backend
cd backend
firebase login
firebase use --add
firebase init functions firestore emulators

# Recommended choices
# Functions language: TypeScript
# Runtime: Node.js 20 or current Firebase-supported Node LTS
# Enable ESLint: yes if your team uses it
"""
        )
    )
    story.append(p("Install baseline dependencies from the functions directory.", "Body"))
    story.append(
        code_block(
            """
cd backend/functions
npm install firebase-admin firebase-functions

# Add the current Google GenAI SDK or REST client according to Google AI docs.
# Keep model ids in config so model changes do not require mobile releases.
"""
        )
    )
    story.append(
        section(
            "Add server-side secrets",
            [
                p("Use Firebase Functions Secret Manager for GOOGLE_AI_API_KEY and any other provider key.", "BodySmall"),
                code_block(
                    """
firebase functions:secrets:set GOOGLE_AI_API_KEY
firebase functions:secrets:set MESHY_API_KEY
firebase functions:secrets:set ELEVENLABS_API_KEY
firebase functions:secrets:set SUNO_API_KEY
firebase functions:secrets:set GAME_PROVIDER_API_KEY
firebase functions:secrets:set VFX_PROVIDER_API_KEY
"""
                ),
            ],
        )
    )
    story.append(
        section(
            "Read the secret inside a function",
            [
                code_block(
                    """
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const googleAIKey = defineSecret("GOOGLE_AI_API_KEY");

export const generateImage = onRequest(
  { secrets: [googleAIKey], timeoutSeconds: 300, memory: "1GiB" },
  async (req, res) => {
    const apiKey = googleAIKey.value();
    // Use apiKey only inside the backend provider adapter.
  }
);
"""
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("Credential checklist", "Callout"),
                bullet(
                    [
                        "Remove premium provider keys from iOS and Android source, plist, gradle files, and config assets.",
                        "Do not expose GOOGLE_AI_API_KEY through Firebase Remote Config.",
                        "Rotate any key that was previously shipped to devices.",
                        "Restrict logs so prompts and provider raw responses do not leak private data.",
                    ]
                ),
            ],
            bg=WARN,
            border=colors.HexColor("#E1B84A"),
        )
    )
    story.append(PageBreak())


def page_schema(story):
    story.append(p("3. Firestore Data Model", "H1"))
    story.append(
        p(
            "Create collections that separate balances, immutable ledger entries, generation jobs, generated assets, posts, boosts, and business campaigns.",
            "Body",
        )
    )
    story.append(
        data_table(
            ["Collection", "Required fields"],
            [
                [
                    "creatorCreditBalances/{uid}",
                    "availableCredits, reservedCredits, lifetimeEarned, lifetimeSpent, updatedAt, planTier",
                ],
                [
                    "creatorCreditTransactions/{transactionId}",
                    "userId, amount, type, relatedJobId, relatedPostId, provider, contentType, createdAt, metadata",
                ],
                [
                    "aiGenerationJobs/{jobId}",
                    "userId, provider, contentType, prompt, inputAssetIds, status, creditsReserved, creditsCharged, outputAssetIds, errorMessage, createdAt, updatedAt, completedAt",
                ],
                [
                    "generatedAssets/{assetId}",
                    "userId, jobId, provider, contentType, storagePath, downloadUrl, mimeType, moderationStatus, createdAt",
                ],
                [
                    "posts/{postId}",
                    "userId, assetIds, channelId, latitude, longitude, radiusMeters, organicRadiusMeters, boostedRadiusMeters, boostExpiresAt, visibilityStatus, businessId",
                ],
                [
                    "radiusBoostTransactions/{id}",
                    "userId, postId, amount, radiusMetersAdded, expiresAt, createdAt",
                ],
                [
                    "aiCampaigns/{id}",
                    "businessId, ownerUid, prompt, assetIds, status, channels, coupon, caption, tags, createdAt, updatedAt",
                ],
            ],
            [2.05 * inch, 4.65 * inch],
        )
    )
    story.append(Spacer(1, 0.1 * inch))
    story.append(
        section(
            "Status values",
            [
                two_col(
                    box(
                        [
                            p("aiGenerationJobs.status", "Callout"),
                            bullet(
                                [
                                    "queued",
                                    "processing",
                                    "provider_pending",
                                    "completed",
                                    "failed",
                                    "cancelled",
                                    "refunded",
                                ]
                            ),
                        ],
                        bg=PANEL,
                    ),
                    box(
                        [
                            p("moderationStatus", "Callout"),
                            bullet(
                                [
                                    "not_required",
                                    "pending",
                                    "approved",
                                    "rejected",
                                    "needs_review",
                                ]
                            ),
                        ],
                        bg=PANEL,
                    ),
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("Ledger principle", "Callout"),
                p(
                    "Treat creatorCreditTransactions as the audit trail. Balances are fast summaries, but every balance change must have a matching transaction row. That makes refunds, support investigations, and fraud checks possible.",
                    "BodySmall",
                ),
            ],
            bg=colors.HexColor("#EEF5FF"),
            border=BLUE,
        )
    )
    story.append(PageBreak())


def page_rules_auth(story):
    story.append(p("4. Auth And Security Rules", "H1"))
    story.append(
        p(
            "All write paths that affect money, credits, AI jobs, generated assets, or boosted reach should go through the backend. Mobile clients can read their own records but cannot directly mutate balances or job status.",
            "Body",
        )
    )
    story.append(
        section(
            "Backend auth middleware",
            [
                p("Every endpoint should require a Firebase ID token in the Authorization header.", "BodySmall"),
                code_block(
                    """
Authorization: Bearer <firebase-id-token>

Backend steps:
1. Read the Bearer token.
2. admin.auth().verifyIdToken(token).
3. Use decoded.uid as the only trusted user id.
4. Reject any body.userId that does not match decoded.uid.
"""
                ),
            ],
        )
    )
    story.append(
        section(
            "Minimum Firestore rules posture",
            [
                code_block(
                    """
match /creatorCreditBalances/{uid} {
  allow read: if request.auth.uid == uid;
  allow write: if false;
}

match /creatorCreditTransactions/{id} {
  allow read: if request.auth.uid == resource.data.userId;
  allow write: if false;
}

match /aiGenerationJobs/{jobId} {
  allow read: if request.auth.uid == resource.data.userId;
  allow write: if false;
}

match /generatedAssets/{assetId} {
  allow read: if request.auth.uid == resource.data.userId;
  allow write: if false;
}
"""
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("Why writes are blocked", "Callout"),
                p(
                    "The Admin SDK used by Cloud Functions bypasses client rules. That is good here: it lets backend code write trusted records while stopping clients from faking completed jobs, changing credit balances, or publishing someone else's generated asset.",
                    "BodySmall",
                ),
            ],
            bg=colors.HexColor("#EBFFF0"),
            border=ACCENT,
        )
    )
    story.append(PageBreak())


def page_credit_transactions(story):
    story.append(p("5. Atomic Credit Enforcement", "H1"))
    story.append(
        p(
            "The credit system should reserve credits before the provider call, then either charge the reserved amount on success or refund it on failure. The reserve step must happen inside a Firestore transaction.",
            "Body",
        )
    )
    story.append(
        data_table(
            ["Step", "Server action"],
            [
                ["1. Estimate", "Calculate cost from contentType, provider, duration, resolution, and planTier using a server-side cost table."],
                ["2. Transaction", "Read creatorCreditBalances/{uid}; verify availableCredits >= cost; update availableCredits -= cost and reservedCredits += cost."],
                ["3. Ledger", "Create creatorCreditTransactions row with type ai_generation_reserve, amount -cost, relatedJobId."],
                ["4. Job", "Create aiGenerationJobs/{jobId} with status processing and creditsReserved = cost."],
                ["5. Provider", "Call Google AI Studio or another server-side provider adapter."],
                ["6A. Success", "Create generatedAssets, update job completed, move reservedCredits down, increment lifetimeSpent."],
                ["6B. Failure", "Update job failed, add refund transaction, restore availableCredits, decrease reservedCredits."],
            ],
            [1.15 * inch, 5.55 * inch],
        )
    )
    story.append(Spacer(1, 0.1 * inch))
    story.append(
        section(
            "Transaction pseudocode",
            [
                code_block(
                    """
await db.runTransaction(async (tx) => {
  const balanceRef = db.doc(`creatorCreditBalances/${uid}`);
  const balanceSnap = await tx.get(balanceRef);
  const balance = balanceSnap.data() ?? { availableCredits: 0, reservedCredits: 0 };

  if (balance.availableCredits < cost) {
    throw new InsufficientCreditsError();
  }

  tx.update(balanceRef, {
    availableCredits: balance.availableCredits - cost,
    reservedCredits: balance.reservedCredits + cost,
    updatedAt: FieldValue.serverTimestamp(),
  });

  tx.create(jobRef, {
    userId: uid,
    status: "processing",
    creditsReserved: cost,
    contentType,
    provider,
    createdAt: FieldValue.serverTimestamp(),
  });

  tx.create(transactionRef, {
    userId: uid,
    amount: -cost,
    type: "ai_generation_reserve",
    relatedJobId: jobRef.id,
    createdAt: FieldValue.serverTimestamp(),
  });
});
"""
                )
            ],
        )
    )
    story.append(PageBreak())


def page_endpoints(story):
    story.append(p("6. Implement Endpoints In This Order", "H1"))
    story.append(
        p(
            "Build the smallest complete vertical slice first: image generation with real credits, real job record, real provider call, storage output, and mobile polling. Then copy the same pattern to video, voice, music, 3D, games, VFX, and business campaigns.",
            "Body",
        )
    )
    story.append(
        numbered(
            [
                "GET /credits/balance - authenticated, read-only balance summary.",
                "GET /ai/jobs/:id - authenticated job lookup; only owner can read.",
                "POST /ai/generate/image - reserve credits, call Google AI Studio, store output, complete/refund.",
                "POST /ai/generate/video - same contract as image, but allow provider_pending for longer-running jobs.",
                "POST /ai/generate/edit - accepts source asset id plus prompt; verifies ownership before provider call.",
                "POST /ai/generate/vfx - adds cinematic effects to an existing asset.",
                "POST /ai/generate/3d - generates or updates 3D head/avatar/asset.",
                "POST /ai/generate/voice - creates narration using configured provider.",
                "POST /ai/generate/music - creates soundtrack or short loop.",
                "POST /ai/generate/game - creates mini-game concept/assets for business campaigns.",
                "POST /ai/jobs/:id/cancel - cancels cancellable jobs and refunds any reserved amount.",
                "POST /ai/jobs/:id/publish-to-map - publishes completed generated asset with map location.",
                "POST /posts/:id/radius-boost - deducts credits and boosts radius atomically.",
                "POST /businesses/:businessId/ai-campaigns - builds a campaign bundle for verified business accounts.",
            ],
            "BodySmall",
        )
    )
    story.append(Spacer(1, 0.1 * inch))
    story.append(
        section(
            "Shared endpoint response",
            [
                code_block(
                    """
{
  "jobId": "abc123",
  "status": "processing",
  "provider": "google_ai_studio",
  "contentType": "image",
  "creditsReserved": 12,
  "estimatedSeconds": 30
}
"""
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("Queue rule", "Callout"),
                p(
                    "If an operation can exceed a normal HTTPS timeout, return quickly after creating the job and move provider work to Cloud Tasks, Pub/Sub, or a background queue. The mobile app should already be polling job status, so the UX stays the same.",
                    "BodySmall",
                ),
            ],
            bg=WARN,
            border=colors.HexColor("#E1B84A"),
        )
    )
    story.append(PageBreak())


def page_google_adapter(story):
    story.append(p("7. Google AI Studio Provider Adapter", "H1"))
    story.append(
        p(
            "Wrap Google AI Studio behind a provider adapter so Poplur can swap or route providers without changing iOS and Android again.",
            "Body",
        )
    )
    story.append(
        section(
            "Adapter interface",
            [
                code_block(
                    """
export interface AIProviderAdapter {
  generateImage(input: GenerateInput): Promise<GenerateResult>;
  generateVideo(input: GenerateInput): Promise<GenerateResult>;
  editAsset(input: EditInput): Promise<GenerateResult>;
}

export type GenerateResult = {
  provider: "google_ai_studio";
  contentType: "image" | "video";
  mimeType: string;
  bytes?: Buffer;
  remoteUrl?: string;
  providerJobId?: string;
  raw?: unknown; // store admin-only or omit from client responses
};
"""
                )
            ],
        )
    )
    story.append(
        section(
            "Implementation steps",
            [
                numbered(
                    [
                        "Read GOOGLE_AI_API_KEY inside the Cloud Function using defineSecret or your host's secret API.",
                        "Build prompt payload from the user's single Poplur AI prompt plus server-side safety/context fields.",
                        "Call the selected Google model for image or video based on contentType.",
                        "Normalize the response into GenerateResult.",
                        "Store bytes or downloaded media in Firebase Storage under generated/{uid}/{jobId}/output.",
                        "Create generatedAssets record with storagePath, contentType, provider, and moderationStatus.",
                        "Return only jobId/status to mobile; never return provider secrets or full raw provider responses.",
                    ],
                    "BodySmall",
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("Provider routing", "Callout"),
                p(
                    "Keep a server-side route table: premium routes to google_ai_studio; free-tier routes can use your cheaper/free experience. The mobile app should pass intent, not provider names, unless you intentionally expose provider selection.",
                    "BodySmall",
                ),
            ],
            bg=colors.HexColor("#EBFFF0"),
            border=ACCENT,
        )
    )
    story.append(PageBreak())


def page_mobile(story):
    story.append(p("8. iOS And Android Hookup", "H1"))
    story.append(
        p(
            "Both platforms should share the same backend contract. Mobile gathers media, prompt, location, and channel selection; backend decides credits, provider, and publish validity.",
            "Body",
        )
    )
    story.append(
        two_col(
            box(
                [
                    p("iOS steps", "Callout"),
                    numbered(
                        [
                            "Create PoplurAIBackendClient.",
                            "Read base URL from environment/config.",
                            "Get Firebase Auth currentUser ID token.",
                            "Send Authorization: Bearer token.",
                            "Upload source media to signed upload URL or Firebase Storage path.",
                            "Call /ai/generate/image or /video.",
                            "Poll /ai/jobs/:id until completed/failed.",
                            "Show output preview and call publish endpoint.",
                        ],
                        "BodySmall",
                    ),
                ],
                bg=PANEL,
            ),
            box(
                [
                    p("Android steps", "Callout"),
                    numbered(
                        [
                            "Create PoplurAIBackendClient.",
                            "Use FirebaseAuth.getInstance().currentUser.",
                            "Fetch ID token before each protected request.",
                            "Send the same JSON body as iOS.",
                            "Use WorkManager/coroutines for polling.",
                            "Render completed output from generatedAssets URL.",
                            "Call publish endpoint with channel and map location.",
                            "Do not store provider keys in BuildConfig.",
                        ],
                        "BodySmall",
                    ),
                ],
                bg=PANEL,
            ),
        )
    )
    story.append(Spacer(1, 0.1 * inch))
    story.append(
        section(
            "Generate request body",
            [
                code_block(
                    """
{
  "contentType": "video",
  "prompt": "Make this look like a movie trailer for the restaurant",
  "sourceAssetId": "optional-existing-upload",
  "location": { "lat": 44.3567, "lng": -79.6418 },
  "channelId": "food",
  "postIntent": "premium_poplur_ai"
}
"""
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("UX contract", "Callout"),
                p(
                    "The app should show one Poplur AI prompt textarea, submit it, then show a job progress state. If generation fails, show the server error and confirm credits were refunded when applicable.",
                    "BodySmall",
                ),
            ],
            bg=colors.HexColor("#EEF5FF"),
            border=BLUE,
        )
    )
    story.append(PageBreak())


def page_publish_business(story):
    story.append(p("9. Publish, Radius Boost, And Business Campaigns", "H1"))
    story.append(
        section(
            "Publish generated asset to the map",
            [
                numbered(
                    [
                        "Verify Firebase ID token and job ownership.",
                        "Read aiGenerationJobs/{jobId}; require status completed.",
                        "Verify every generatedAssets id belongs to the same uid/job.",
                        "Validate latitude, longitude, selected channel, and radius.",
                        "Run content/channel classification. If the selected channel is wrong, record originalChannelId and chosenChannelId.",
                        "Create posts/{postId} with map, profile, channel, and generated asset references.",
                        "Return postId and chosenChannelId to both mobile platforms.",
                    ],
                    "BodySmall",
                )
            ],
        )
    )
    story.append(
        section(
            "Radius boost transaction",
            [
                p("Radius boosts are just another credit spend and must use the same ledger approach.", "BodySmall"),
                code_block(
                    """
POST /posts/:id/radius-boost
{
  "tier": "local_plus",
  "radiusMetersAdded": 5000,
  "durationHours": 24
}

Server transaction:
- verify owner or business admin
- calculate cost
- deduct credits
- create radiusBoostTransactions row
- update post boostedRadiusMeters and boostExpiresAt
"""
                ),
            ],
        )
    )
    story.append(
        section(
            "Business campaign generator",
            [
                p(
                    "For verified businesses, the prompt can create a bundle: generated ad image/video, caption, coupon, tags, target channel, radius recommendation, and optional voice/music/game assets.",
                    "BodySmall",
                ),
                data_table(
                    ["Campaign field", "Purpose"],
                    [
                        ["businessId / ownerUid", "Attach campaign to verified business profile and admins."],
                        ["prompt", "Single business intent prompt."],
                        ["assetIds", "Generated image/video/audio/game assets."],
                        ["coupon", "Optional discount or CTA generated by AI."],
                        ["channels", "AI-recommended channels plus user requested channel."],
                        ["status", "draft, generating, ready, published, failed."],
                    ],
                    [1.75 * inch, 4.95 * inch],
                ),
            ],
        )
    )
    story.append(PageBreak())


def page_tests_deploy(story):
    story.append(p("10. Tests, Deploy, And Done Checklist", "H1"))
    story.append(
        section(
            "Automated tests to add first",
            [
                bullet(
                    [
                        "Free user without credits cannot create premium generation job.",
                        "User with enough credits reserves credits and creates aiGenerationJobs row.",
                        "Provider success completes job, stores generatedAssets, and charges reserved credits.",
                        "Provider failure refunds credits and writes failed job with errorMessage.",
                        "Two simultaneous requests cannot drive availableCredits below zero.",
                        "Mobile cannot write creatorCreditBalances or aiGenerationJobs directly.",
                        "Publish endpoint rejects jobs owned by another user.",
                        "Channel classifier can override an inappropriate selected channel and records both channel ids.",
                        "Radius boost deducts credits and updates post radius atomically.",
                    ]
                )
            ],
        )
    )
    story.append(
        section(
            "Local and production deploy path",
            [
                code_block(
                    """
cd backend/functions
npm test
npm run lint

cd ..
firebase emulators:start

# After emulator QA from iOS and Android:
firebase deploy --only functions,firestore:rules,firestore:indexes
"""
                )
            ],
        )
    )
    story.append(
        box(
            [
                p("Feature complete means", "Callout"),
                bullet(
                    [
                        "GOOGLE_AI_API_KEY exists server-side and is never present in app bundles.",
                        "iOS and Android can generate image/video through backend and poll job status.",
                        "Credits reserve, charge, refund, and radius boost through Firestore transactions.",
                        "Generated content can be published to map/channel/profile after backend validation.",
                        "Business campaign endpoint exists for verified business accounts.",
                        "Rules block client writes to balances, ledger, jobs, and generated assets.",
                    ]
                ),
            ],
            bg=colors.HexColor("#EBFFF0"),
            border=ACCENT,
        )
    )
    story.append(Spacer(1, 0.1 * inch))
    story.append(
        section(
            "Official references",
            [
                bullet(
                    [
                        "Firebase HTTPS Functions: https://firebase.google.com/docs/functions/http-events",
                        "Firebase Functions secrets and environment config: https://firebase.google.com/docs/functions/config-env",
                        "Firebase Admin verify ID tokens: https://firebase.google.com/docs/auth/admin/verify-id-tokens",
                        "Cloud Firestore transactions: https://firebase.google.com/docs/firestore/manage-data/transactions",
                        "Google AI Studio / Gemini API key docs: https://ai.google.dev/gemini-api/docs/api-key",
                        "Gemini API documentation: https://ai.google.dev/gemini-api/docs",
                    ],
                    "Muted",
                )
            ],
        )
    )


def build():
    doc = SimpleDocTemplate(
        OUT,
        pagesize=letter,
        rightMargin=0.7 * inch,
        leftMargin=0.7 * inch,
        topMargin=0.58 * inch,
        bottomMargin=0.7 * inch,
        title="Poplur AI Backend Completion Guide",
        author="OpenAI Codex",
    )
    story = []
    title_page(story)
    page_architecture(story)
    page_setup_secrets(story)
    page_schema(story)
    page_rules_auth(story)
    page_credit_transactions(story)
    page_endpoints(story)
    page_google_adapter(story)
    page_mobile(story)
    page_publish_business(story)
    page_tests_deploy(story)
    doc.build(story, onFirstPage=header_footer, onLaterPages=header_footer)
    print(OUT)


if __name__ == "__main__":
    build()
