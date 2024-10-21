import { openai } from "npm:@ai-sdk/openai";
import { generateObject } from "npm:ai";
import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";

const schema = z.object({
  intent: z.string().describe("What is the intent"),
  hiddenIntent: z
    .string()
    .describe(
      "Careful observation of user input, ambitions and goals that users potentially want to achieve",
    ),
  keyMessage: z
    .string()
    .describe("Key messages inferred from user intentions."),
  reason: z.string().describe("Why is this the intent"),
  sections: z
    .array(
      z.object({
        title: z.string().describe("Title of the section"),
        keyMessage: z.string().describe("Key message of the section"),
        subMessages: z
          .array(z.string())
          .describe("3 ~ 5 sub messages to ensure the key message"),
        searchQueries: z
          .array(z.string())
          .describe(
            "Search Google for three queries to get more information on the key message",
          ),
      }),
    )
    .describe("3 ~ 5 sections to reinforce the Key Message"),
});
export async function inferIntent(prompt: string) {
  const result = await generateObject({
    model: openai("gpt-4o-mini-2024-07-18"),
    prompt,
    schema,
  });
  return schema.parse(result.object);
}
