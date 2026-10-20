# AXReplaceRangeWithText investigation — 2026-10-19

Both Receiver and Codex advertised `AXReplaceRangeWithText` among their parameterized attributes. Advertising a name does not establish a supported external calling convention or guarantee that an operation works.

The installed MacOSX27.0 SDK Accessibility headers did not provide a definition. WebKit implements `accessibilityReplaceRange:withText:`, accepting an NSRange and NSString and forwarding them to `replaceTextInRange`. Its test runner declares the same Objective-C method. These are in-process methods; neither source established the argument representation for an external `AXUIElementCopyParameterizedAttributeValue` call.

No speculative invocation was added or performed. This remains an investigation, not an implemented feature or a failed Codex test. The earlier description of it as a public API was inaccurate.

Primary references:

- [WebKit accessibility wrapper](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm)
- [WebKit accessibility test runner](https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/InjectedBundle/mac/AccessibilityUIElementMac.mm)

The separately implemented alternative constructs a complete replacement from the original AXValue and selected UTF-16 range, writes it through AXValue, verifies the entire result, and restores the caret. Receiver validation preceded Codex use.
