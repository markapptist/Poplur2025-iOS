import { genkit, z } from "genkit";
import { googleAI } from "@genkit-ai/google-genai";

export const PremiumAIActionSchema = z.enum([
  "generate_caption",
  "suggest_post_idea",
  "business_promo",
  "translate_caption",
]);

export type PremiumAIAction = z.infer<typeof PremiumAIActionSchema>;

const GenerateCaptionInputSchema = z.object({
  mediaType: z.enum(["image", "video"]),
  locationName: z.string().max(120).optional(),
  userPrompt: z.string().max(1000).optional(),
});

const GenerateCaptionOutputSchema = z.object({
  title: z.string(),
  caption: z.string(),
  hashtags: z.array(z.string()),
  radiusTip: z.string(),
});

const SuggestPostIdeaInputSchema = z.object({
  locationName: z.string().max(120),
  category: z.string().max(80),
  vibe: z.string().max(120),
});

const SuggestPostIdeaOutputSchema = z.object({
  postIdea: z.string(),
  suggestedCaption: z.string(),
  bestTimeToPost: z.string(),
  radiusStrategy: z.string(),
});

const BusinessPromoInputSchema = z.object({
  businessName: z.string().max(120),
  businessType: z.string().max(80),
  offerDetails: z.string().max(500),
  locationName: z.string().max(120),
});

const BusinessPromoOutputSchema = z.object({
  promoTitle: z.string(),
  promoCaption: z.string(),
  couponText: z.string(),
  callToAction: z.string(),
});

const TranslateCaptionInputSchema = z.object({
  text: z.string().min(1).max(2000),
  targetLanguage: z.string().min(2).max(80),
});

const TranslateCaptionOutputSchema = z.object({
  translatedText: z.string(),
});

export const PremiumAIFlowInputSchema = z.object({
  action: PremiumAIActionSchema,
  input: z.record(z.unknown()),
});

export const PremiumAIFlowOutputSchema = z.object({
  action: PremiumAIActionSchema,
  output: z.record(z.unknown()),
});

const ai = genkit({
  plugins: [googleAI()],
});

const modelName = process.env.POPLUR_AI_MODEL || "gemini-flash-latest";

export function validatePremiumAIInput(action: PremiumAIAction, input: unknown): Record<string, unknown> {
  switch (action) {
  case "generate_caption":
    return GenerateCaptionInputSchema.parse(input);
  case "suggest_post_idea":
    return SuggestPostIdeaInputSchema.parse(input);
  case "business_promo":
    return BusinessPromoInputSchema.parse(input);
  case "translate_caption":
    return TranslateCaptionInputSchema.parse(input);
  }
}

export const premiumAiFlow = ai.defineFlow(
  {
    name: "premiumAiFlow",
    inputSchema: PremiumAIFlowInputSchema,
    outputSchema: PremiumAIFlowOutputSchema,
  },
  async ({ action, input }) => {
    switch (action) {
    case "generate_caption": {
      const parsed = GenerateCaptionInputSchema.parse(input);
      const output = await generateStructured(
        [
          "You are Poplur's premium create-flow assistant.",
          "Return punchy, map-native social copy as JSON only.",
          `Media type: ${parsed.mediaType}`,
          parsed.locationName ? `Location: ${parsed.locationName}` : "Location: not provided",
          parsed.userPrompt ? `Creator direction: ${parsed.userPrompt}` : "Creator direction: infer a tasteful local angle",
        ].join("\n"),
        GenerateCaptionOutputSchema,
        mockCaption(parsed)
      );
      return { action, output };
    }
    case "suggest_post_idea": {
      const parsed = SuggestPostIdeaInputSchema.parse(input);
      const output = await generateStructured(
        [
          "You are Poplur's premium local content strategist.",
          "Return one concrete post idea as JSON only.",
          `Location: ${parsed.locationName}`,
          `Category: ${parsed.category}`,
          `Vibe: ${parsed.vibe}`,
        ].join("\n"),
        SuggestPostIdeaOutputSchema,
        mockPostIdea(parsed)
      );
      return { action, output };
    }
    case "business_promo": {
      const parsed = BusinessPromoInputSchema.parse(input);
      const output = await generateStructured(
        [
          "You are Poplur's premium business promo generator.",
          "Write local promotional copy that is clear, specific, and not spammy. Return JSON only.",
          `Business: ${parsed.businessName}`,
          `Type: ${parsed.businessType}`,
          `Offer: ${parsed.offerDetails}`,
          `Location: ${parsed.locationName}`,
        ].join("\n"),
        BusinessPromoOutputSchema,
        mockBusinessPromo(parsed)
      );
      return { action, output };
    }
    case "translate_caption": {
      const parsed = TranslateCaptionInputSchema.parse(input);
      const output = await generateStructured(
        [
          "Translate the caption for Poplur while keeping hashtags and proper nouns natural.",
          "Return JSON only.",
          `Target language: ${parsed.targetLanguage}`,
          `Caption: ${parsed.text}`,
        ].join("\n"),
        TranslateCaptionOutputSchema,
        mockTranslation(parsed)
      );
      return { action, output };
    }
    }
  }
);

async function generateStructured<T>(
  prompt: string,
  schema: z.ZodType<T>,
  emulatorFallback: T
): Promise<T> {
  if (!process.env.GEMINI_API_KEY && process.env.FUNCTIONS_EMULATOR === "true") {
    return emulatorFallback;
  }

  const response = await ai.generate({
    model: googleAI.model(modelName),
    prompt,
    output: { schema },
  });

  if (!response.output) {
    throw new Error("AI provider returned no structured output.");
  }

  return response.output;
}

function mockCaption(input: z.infer<typeof GenerateCaptionInputSchema>) {
  const place = input.locationName || "right here";
  return {
    title: `Poplur moment in ${place}`,
    caption: `A fresh ${input.mediaType} from ${place}. ${input.userPrompt || "Tap in and see what is happening nearby."}`,
    hashtags: ["#Poplur", "#Local", "#Radius"],
    radiusTip: "Start with a tight radius, then boost if early engagement is strong.",
  };
}

function mockPostIdea(input: z.infer<typeof SuggestPostIdeaInputSchema>) {
  return {
    postIdea: `Capture a ${input.vibe} ${input.category} moment at ${input.locationName}.`,
    suggestedCaption: `Found this at ${input.locationName}. Worth the radius.`,
    bestTimeToPost: "Late afternoon or early evening when local traffic is highest.",
    radiusStrategy: "Begin local, watch saves and replies, then expand radius.",
  };
}

function mockBusinessPromo(input: z.infer<typeof BusinessPromoInputSchema>) {
  return {
    promoTitle: `${input.businessName} local drop`,
    promoCaption: `${input.offerDetails} at ${input.businessName} in ${input.locationName}.`,
    couponText: "Show this Poplur post in-store.",
    callToAction: "Tap in, save it, and stop by today.",
  };
}

function mockTranslation(input: z.infer<typeof TranslateCaptionInputSchema>) {
  return {
    translatedText: `[${input.targetLanguage}] ${input.text}`,
  };
}
