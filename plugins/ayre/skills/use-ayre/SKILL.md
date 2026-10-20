---
name: use-ayre
description: Create or refine a reusable prompt, save it to Ayre, and report its title and slug when the user asks to keep that prompt.
---

Create or refine the reusable prompt requested in this conversation. Preserve the user's intent and supplied Markdown body. Do not insert the prompt or send it anywhere.

1. Draft the complete Markdown prompt. If the user supplied a prompt body, preserve its headings and body; do not add a heading just to register it. For a new prompt, use a concise first-line # Title heading when that fits the requested content.
2. Derive a lowercase ASCII slug from the title or prompt subject using hyphens between words. Keep only letters, digits, dots, underscores, and hyphens; start with a letter or digit and avoid consecutive dots. If the supplied prompt has a # heading in its first 20 lines, set title to that heading exactly. If it has no such heading, set title to the slug so the original body remains unchanged.
3. Create an isolated temporary directory by running:
   /usr/bin/osascript -l JavaScript "$CLAUDE_PLUGIN_ROOT/scripts/ayre.js" prepare
   Read the JSON object it prints and use its directory value for the next two files. Use the file-writing tool to create prompt.md with the exact Markdown bytes and request.json with this shape:
   {"slug":"chosen-slug","title":"heading-or-slug","overwrite":false}
   Set overwrite to true only if the user explicitly asks to replace an existing prompt with the same slug.
4. Save the prompt by running:
   /usr/bin/osascript -l JavaScript "$CLAUDE_PLUGIN_ROOT/scripts/ayre.js" put "<directory-from-prepare>"
   The helper reads the files as data, checks for a compatible Ayre CLI, and sends the prompt bytes unchanged. Never place prompt text or title inside a shell command, heredoc, or command substitution. Quote the directory path. If saving fails, report the error and do not claim success.
5. After a successful save, report the title and slug, then say “Use Ayre Go in Spotlight to insert it.” Do not invoke Ayre Go for them.

Ayre checks the supplied title against the first # heading in the first 20 lines, or against the slug when there is no heading. Do not edit the requested prompt body to satisfy validation.
