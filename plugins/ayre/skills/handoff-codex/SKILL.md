---
name: handoff-codex
description: Turn an implementation discussion into a self-contained Codex handoff prompt and save it to Ayre when the user wants to move implementation from Claude Code to Codex without exposing the source session or investigation directories.
---

Prepare an implementation handoff from this conversation to a separate Codex session, then register it with Ayre. The source discussion may run in Claude Code on Bedrock and involve restricted information. The destination must be able to work from the handoff and its explicitly authorized implementation repository, without reading the source session, research workspace, or worktree. Do not start or message Codex, perform the implementation, insert text, or submit a message as part of this skill.

## Gather the minimum transferable context

Use the current conversation and already available evidence. Extract the intended outcome, agreed design, relevant current behavior, constraints, decisions and rationale, implementation starting state, tests already performed, known failures, remaining work, and acceptance criteria. Distinguish verified facts, user decisions, assumptions, and unverified suggestions. Summarize decisions rather than reproducing the transcript or raw investigation output.

Identify the destination implementation repository and working directory separately from the source workspace. Include the destination URL/path, branch or base commit, and worktree instructions only when known and authorized. Do not assume Claude Code's current directory is the Codex implementation directory. If that destination or another prerequisite is missing and prevents an actionable handoff, ask a focused question before saving. Do not invent a path, commit, repository, or completed test.

If implementation depends on source-only uncommitted changes or artifacts, include a permissible minimal patch/specification in the handoff or resolve how they will reach the destination with the user. Do not claim a destination checkout contains changes that only exist in the source worktree. Do not tell Codex to retrieve missing context from the source workspace.

## Respect the information boundary

A request to hand off work does not make every fact in the source conversation transferable to Codex. Follow the user's stated information classification and transfer scope.

- Exclude credentials, tokens, personal/customer records, raw logs, confidential source excerpts, and other information the user has not authorized for the destination. Replace source-specific examples with minimal synthetic examples and describe technical behavior without copying sensitive values.
- Do not include source-session transcripts, Claude configuration/history paths, source research/worktree paths, or instructions to inspect them. Prohibit reading, searching, listing, or modifying the source workspace and all subagent access to it, without embedding its sensitive path as a locator. A path provided explicitly as the authorized destination is distinct from a source reference.
- Do not copy restricted data into the handoff or Ayre merely because both currently run on the same Mac. The saved prompt is intended for eventual Codex consumption.
- Where the transfer status of a necessary detail is uncertain, ask specifically whether an abstracted version may be included. If essential details cannot be shared, identify the resulting implementation blocker; do not fill gaps with guesses or claim the handoff is ready.

## Build the destination prompt

Write in the user's requested language, otherwise match the implementation discussion. Skill instructions and plugin metadata stay in English. Put the concrete goal on the **first line**, before any heading. Add a concise `#` title within the first 20 lines for Ayre's title convention.

Make the prompt directly actionable and self-contained. Use the following content as a checklist, combining sections where appropriate:

- **Goal and completion criteria:** the user-visible result, in-scope deliverables, explicit non-goals, and observable acceptance checks.
- **Authorized workspace and starting state:** the destination repository/directory/ref and relevant destination files. Source-session and investigation directories are out of bounds, including for subagents. Read applicable instructions in the authorized destination only.
- **Context and decisions:** current architecture, relevant contracts/interfaces and dependencies, chosen approach and tradeoffs, rejected approaches only when they prevent a known trap. Include safe examples/specifications that would otherwise require source-only context.
- **Implementation and validation:** remaining work, meaningful automated checks, existing evidence versus still-unverified behavior, manual/environment prerequisites, and any actual limits on committing, pushing, deployment, or external actions. Do not turn an implementation handoff into authorization to publish, access secrets, or message others.
- **Coordination and escalation:** include the delegation requirements below and concrete known questions/blockers. Never use “as discussed,” “see the previous session,” or source-only references as a substitute for necessary context.

Include these destination-agent instructions, adapted to the available tools without weakening their intent:

> Track the goal explicitly from the start; use a goal-tracking tool if one is available. The main agent is accountable for achieving the integrated goal and validating the result, but does not need to perform every task alone. Delegate bounded implementation, investigation, testing, or review tasks to **GPT-6 Luna subagents** (model identifier `gpt-6-luna` where supported). Give each worker the necessary sanitized context, an authorized working directory, expected output, and clear file ownership. Avoid conflicting edits; review and integrate their work. Give workers a fresh, scoped context rather than forwarding an entire sensitive source history. Do not silently substitute another model if GPT-6 Luna is unavailable; explain the limitation and consult the user about how to proceed.
>
> All agents must stay within the authorized destination workspace and transfer scope. Do not inspect the originating Claude Code session, transcript, history, research directories, or source worktrees. Do not ask another agent to retrieve that material. If essential context is missing, ask the user.
>
> Progress autonomously on routine reversible work within the authorized scope. Consult the user when a difficult tradeoff materially changes the goal, a consequential decision lacks authorization, or investigation reaches a dead end. Explain the evidence, options, and a recommendation; continue independent work where possible. Do not repeatedly spin or conceal uncertainty. The main agent owns goal completion, integration, and truthful reporting of tests and remaining limitations. It's a lonely load. But you (we) are not alone.

Before saving, check the prompt as if Codex has only this text and the authorized destination repository. Remove unsafe source details and resolve essential missing facts. Do not promise that a prompt instruction itself enforces filesystem isolation; actual Codex workspace permissions must also exclude the source workspace.

## Save with the shared Ayre helper

Use the existing plugin helper directly; do not require a fixed application location, PATH changes, or another installed skill.

1. Choose a lowercase ASCII slug such as `handoff-codex-<task>`, obeying Ayre's slug rules. Set `title` to the first nonempty `# ` heading in the first 20 lines. Keep the goal as the first line; do not prepend the title above it.
2. Run:
   ```sh
   /usr/bin/osascript -l JavaScript "$CLAUDE_PLUGIN_ROOT/scripts/ayre.js" prepare
   ```
   Read the JSON `directory` field. Using a file-writing tool, write the destination prompt to `prompt.md` in that directory and create `request.json`:
   ```json
   {"slug":"handoff-codex-task","title":"Implement the agreed feature","overwrite":false}
   ```
   Replace the example slug/title with the actual values. Set `overwrite` to true only when the user explicitly requests replacing that same saved prompt. On a collision, use a new descriptive slug or ask about replacing it; do not overwrite silently.
3. Run:
   ```sh
   /usr/bin/osascript -l JavaScript "$CLAUDE_PLUGIN_ROOT/scripts/ayre.js" put "<directory-from-prepare>"
   ```
   Pass prompt content and metadata as files, never interpolate them into shell commands, heredocs, or command substitutions. Quote paths. A helper failure is not a successful save; report its error and leave the draft available for correction.
4. After successful registration, report the title and slug, summarize any deliberately omitted information or prerequisites without disclosing the omitted data, and say: “Use Ayre Go in Spotlight to insert this handoff into Codex.” The user chooses the destination input field and submits it. Do not launch Codex or invoke Ayre Go automatically.
