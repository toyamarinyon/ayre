# Prototype verification guide

This project originated as PromptInsertProbe. Internal project and receiver names, prompt storage, and log paths retain that identifier for compatibility. The app is Ayre.app with Bundle ID com.toyamarinyon.ayre; use scripts/build.sh for complete CLI packaging. User-facing labels and command titles are English; see the [README](../README.md) for current usage.

## Receiver tests

1. Launch PromptInsertProbeReceiver.
2. Select Short test, Markdown test, or Long test.
3. Select Empty field, Insert within existing text, or Replace selection.
4. Click Prepare Scenario.
5. Run the CLI with a delay, then Cmd+Tab back to Receiver without clicking the field.
6. Click Verify and check the strict UTF-16 comparison and edit-event count.

Repeat across sample sizes and scenarios. Keep NFC/NFD, emoji sequences, Japanese, tabs, blank lines, code fences, and trailing newlines intact.

## Codex and Spotlight

Use a Team ID signed application installed in /Applications with Accessibility permission. Place the cursor in the Codex input field. Invoke Ayre Pick through Spotlight and select a saved prompt, or invoke Ayre Go for the most recently modified prompt. Check the visible text and the application log at `~/Library/Logs/PromptInsertProbe/probe.log`.

Confirm exact text, existing-text preservation, selection replacement, caret position, and the enabled send control. Do not send a message automatically during insertion tests. Repeat after clearing the field to detect placeholder contamination.

If the command is missing, compare with the Shortcuts app, but do not count that as Spotlight success. If the original target cannot be resolved or focus does not return within five seconds, the operation must abort. Wrong targets and unknown field structures must never trigger fallback writes.

## Reporting

Record application/OS versions, signature type, entry point, sample, field scenario, exact/mismatch/unverifiable result, caret state, and visible behavior. A successful AX write alone is not proof of insertion. Avoid copying private field contents into reports.
