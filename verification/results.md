# Hardware verification results

This is a condensed English account of the prototype investigation. The original detailed record is preserved in Git history at the initial commit. Historical results below describe the versions tested at the time, not a fresh validation of the English UI.

## Receiver — 2026-10-19

The nonactivating panel returned focus to the original Receiver PID and element before writing.

| Sample / scenario | Method | Result |
| --- | --- | --- |
| Short / empty | AXSelectedText | Independent UTF-16 exact match: 30 UTF-16 units, 54 UTF-8 bytes, one line; caret {30,0} |
| Short / middle | AXSelectedText | Original 33 UTF-16 units, selection {16,0}; result 63 UTF-16 units, 119 UTF-8 bytes, two lines; caret {46,0}; surrounding text and emoji preserved |
| Short / selection | AXSelectedText | Original 28 UTF-16 units, selection {7,15}; result 43 UTF-16 units, caret {37,0}; independent exact match later confirmed in the user's screenshot |
| Markdown / empty | AXSelectedText | User reported independent exact match; AX log also EXACT: 401 UTF-16 units, 649 UTF-8 bytes, 31 lines |
| Long / empty | AXSelectedText | User reported independent exact match; AX log also EXACT: 33,530 UTF-16 units, 52,828 UTF-8 bytes, 424 lines |
| Short / selection | AXValue | Full replacement exact, preserving BEFORE-/AFTER markers. Initial caret was at full-text end {43,0} instead of insertion end {37,0}; this preceded caret restoration |

One selection test initially observed the wrong Receiver instance because two copies were running. Its AX result was not counted as independent receiver verification until the user's screenshot confirmed the actual instance.

## Codex: AXSelectedText versus AXValue — 2026-10-19

Target: `com.openai.codex`, AXTextArea, label `Work with Codex`.

AXSelectedText reported settable=true and the write returned success. After approximately two seconds, AXValue was still 16 UTF-16 units with caret {0,0}; expected length was 46 and inserted-text occurrence growth was zero. The API return value therefore did not establish successful insertion.

AXValue replacement did update the visible field and enabled the send control according to the user. Early versions inherited the empty field's apparent AXValue as actual text, introducing `Work with Codex` into the result. A strict mismatch was retained when exactly one trailing LF was missing; normalization and line-ending differences were diagnostic only, never accepted as exact.

Setting AXSelectedTextRange restored the caret to {30,0}, verified by readback with unchanged text. The first approximately two-second delay came from waiting for exact comparison before restoring the caret.

An explicit user-confirmed empty-field mode was introduced as an intermediate experiment. It required selection {0,0} plus an empty value or a UI-label match. It was not treated as automatic placeholder detection.

## Placeholder investigation — 2026-10-20

AXPlaceholderValue returned noValue in the observed Codex field. AXTitle and AXDescription returned `Work with Codex`. An empty field's AXValue was `Work with Codex` plus LF, indistinguishable by root text alone from the same deliberately typed string.

Read-only snapshots compared empty, manually typed label text, manually typed label text plus newline, and the all-deleted state. Root DOM class information was not a reliable distinction. Child DOM class counts differed, but class strings were not retained and were not used as a hardcoded signal.

The repeatable distinction was descendant editability:

- Empty: TextArea → editable Group → noneditable Group → noneditable StaticText. The hint leaf had neither writable AXValue/AXSelectedText nor an AXEditableAncestor.
- Real text, including the exact hint string and a trailing newline: StaticText had writable AXValue/AXSelectedText and AXEditableAncestor pointing to the root TextArea.
- Deleting all real text restored the empty structure and noneditable hint leaf.

Snapshot collection checked root text, selection, and focus before and after reading. It did not claim atomic snapshots. Same-app element changes could be compared diagnostically, but were not proof of the same input field.

## Automatic Codex empty-field classification

The adapter uses live labels and descendant editability, never hardcoded removal of `Work with Codex`. Empty fields produce the inserted text alone; actual content produces the complete selection-replacement expectation. Unknown, mixed, unreadable, or changed structures abort.

Collection is bounded to 64 nodes, depth six, and five seconds. Immediately before writing, the implementation rechecks classification, full text, character count, selection, and focus. Caret restoration requires strict text readback and preserves the verified text.

An initial implementation incorrectly treated a missing AXEditableAncestor as a failed read. The correction distinguishes an attribute absent from a successfully read attribute-name list from an advertised attribute that cannot be read. The latter remains unknown and aborts.

Tests covered empty → identical real text → real text with LF → empty, changed labels, mixed/unknown structures, nonempty selection, and incomplete editability information. Subsequent user tests confirmed insertion, clearing, and reinsertion without hint contamination, with exact text and caret {30,0}.

## Spotlight signing investigation and short-text success

Ad-hoc signed builds failed with “Shortcuts couldn't communicate with the app”; perform() was never reached. System logs reported missing Team ID/bundle identity and an AppleEvents communication failure. A free Personal Team Apple Development signature resolved this in the tested environment; no paid membership was required.

At 09:21 JST on 2026-10-20, the user executed the Spotlight action and reported successful short-text insertion into Codex. The log showed trusted=true, both system-wide and frontmost-app resolution finding the same AXTextArea, focus confirmation after 0.10 seconds, empty classification, AXValue success, full UTF-16 EXACT, and caret EXACT {30,0} with unchanged text.

At perform() time, Codex already held focus. This does not establish success when Spotlight still retains focus and the original target cannot be identified. That condition must abort.

## Saved-prompt picker baseline

Based on Devin commit abfefb2, the local picker adds Return/keypad Enter/Esc handling when the table is focused, prevents reentry while waiting for insertion, clears stale targets before capture, and displays search counts/no results.

All 19 core tests passed. An AppKit check directly delivered keyDown events to the table and confirmed Return, keypad Enter, and Escape callbacks without posting input to external applications. Signed build, signature validation, granted Accessibility status, three saved samples, and hotkey registration OSStatus 0 were confirmed. Automated GUI hotkey input did not establish panel invocation; manual keyboard behavior remains a separate check.

## Spotlight long-text success — 2026-10-20 19:09 JST

The user executed sample-long through Spotlight and reported lines L0001–L0400 and the END-OF-LONG-TEST marker. The installed app log confirmed:

- 33,126 characters; 33,530 UTF-16 units; 52,828 UTF-8 bytes; 424 lines.
- Both target-resolution routes found the Codex AXTextArea; focus returned after 0.11 seconds.
- Automatic classification: empty. AXValue write: success.
- Entire inserted text: strict UTF-16 EXACT.
- Caret restored to {33530,0}: EXACT, text unchanged.

The report text also arrived in the chat. Ayre itself did not trigger submission.

## Parameter-free latest prompt action

InsertLatestPromptIntent uses the existing modification-time descending order, breaking ties by slug. No readable prompts produces an error. Target resolution and deferred insertion share the established implementation.

The signed build and installed signature validation passed. Generated App Intents metadata confirmed discoverable=true and parameters=[]. The user's end-to-end test of this entry point is still pending. English titles are now Ayre Go and Ayre Pick; their visibility and operation require a newly installed build and Spotlight testing.

## Remaining validation

Do not infer Spotlight middle insertion, selection replacement, wrong-target handling, or all sample combinations from the successful empty-field tests. Never equate unit-test success, a writable attribute, or a successful write return with hardware-confirmed insertion.
