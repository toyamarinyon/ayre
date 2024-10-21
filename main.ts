// %% import
import { openai } from "npm:@ai-sdk/openai";
import { generateObject } from "npm:ai";
import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";

const prompt = `
  There are many talks, books, blogs and videos that talk about the importance of MVPs, but few that can be used as a reference when you actually start building them.
  Engineers tend to design for the future as they progress in their careers, which is generally welcomed, but it is often over-engineered when creating MVPs.
  Sometimes the best choice when building an MVP is to design and implement something that would be considered bad practice in the short term, but making that choice requires a great deal of commitment.
  At such times, it can be helpful to know of cases where unconventional methods have produced overwhelming results.
  The SpaceX Raptor engine is an example of this, and I would like to introduce it as an analogy.
`;

const intent = await inferIntent(prompt);

for (const section of intent.sections) {
  let pages: WebSearchResult[] = [];
  section.searchQueries;
}

// %% Search Proto
import "jsr:@std/dotenv/load";
import { search, type WebSearchResult } from "./tavily.ts";
import { inferIntent } from "./infer-intent.ts";

let pages: WebSearchResult[] = [];
for (const query of intent.queries) {
  const response = await search(query);
  pages = [...pages, ...response];
}

pages;

// %% drafting
const section = {
  title: "The Concept of MVPs",
  keyMessage: "MVPs are essential for testing ideas quickly and efficiently",
  subMessages: [
    "MVPs allow for rapid iteration and feedback",
    "Focus on core functionalities to validate concepts",
    "Avoid over-engineering to save time and resources",
  ],
  searchQueries: [
    "What is an MVP?",
    "Importance of MVP in product development",
    "How to build an effective MVP",
  ],
};
const result = await generateObject({
  model: openai("gpt-4o-mini-2024-07-18"),
  prompt: `
Please write a text about the following topic:

${section.title}

that includes the following key message:
${section.subMessages.map((msg) => `- ${msg}`).join("\n")}

You use the following relevant content to write the text:

${JSON.stringify(pages)}
  `,
  schema: z.object({
    sectionTitle: z.string().describe("Title of the section"),
    text: z.string().describe(
      `
          Write a comprehensive section of approximately 500 words on the given topic. Please adhere to the following guidelines:

          1. Content:
             - Provide a clear and informative overview of the subject.
             - Include relevant details, examples, and explanations to support your points.
             - Ensure the information is accurate and up-to-date.

          2. Structure:
             - Organize the content logically with a clear introduction, body, and conclusion.
             - Use appropriate headings and subheadings to improve readability.
             - Include short paragraphs and bullet points where suitable to enhance clarity.

          3. Language:
             - Use concise and engaging language appropriate for the target audience.
             - Maintain a consistent tone throughout the section.
             - Proofread for grammar, spelling, and punctuation errors.

          4. Links:
             - When referencing external sources or additional information, use markdown link notation: [Link text](URL)
             - Ensure all links are relevant and add value to the content.
             - Prefer authoritative and reputable sources for links.

          5. Formatting:
             - Use markdown formatting for emphasis where appropriate (e.g., *italics*, **bold**).
             - If including code snippets or technical terms, use \`inline code\` formatting.

          6. Word count:
             - Aim for approximately 500 words, with a tolerance of ±10% (450-550 words).
             - If the topic requires significantly more or less content, please note this in your response.

          Please begin your section with a brief introductory sentence or paragraph to set the context for the reader.
        `,
    ),
    citations: z
      .array(
        z.object({
          title: z.string().describe("Title of the source"),
          url: z.string().url().describe("URL of the source"),
        }),
      )
      .describe("Citations for the text"),
  }),
});

result.object;
