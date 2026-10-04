# AGENTS.md

Guide for AI coding agents (and humans) working in this repository.

## What this is

**NameCards** is a local, native macOS app for bulk-scanning business cards into iCloud Contacts:

1. **Scan** – a live camera feed (Continuity Camera iPhone preferred, built-in camera fallback) auto-detects
   business cards, waits for a steady, sharp frame, captures a perspective-corrected crop, and skips a card it
   has already captured.
2. **Extract** – Apple Vision OCR (English/Latin, Simplified & Traditional Chinese, Japanese, Korean) followed by
   rule-based parsing into a `DraftContact`. Optionally the *OCR text* (never the image) is sent to the Claude
   API for better field labelling.
3. **Review** – the user verifies and fixes every draft in a list beside the card image. Low-confidence fields
   are highlighted.
4. **Merge & save** – each draft is matched against existing contacts. A field-by-field merge is proposed and
   the user confirms it. The result is written to the **iCloud** contacts container and added to a per-session
   "Met at" group.

## Non-negotiable rules

- **Local-first privacy.** Card images and contact data never leave the Mac. The only network call allowed is
  the optional Claude parser. It is off by default and sends OCR text only.
- **Never write to Contacts without user confirmation.** Every create or merge goes through the review and
  merge UI. Never delete contacts. Never overwrite an existing value silently: replacements need an explicit
  tick, and additive changes (a new phone or email) may be pre-ticked.
- **Tests never touch the real Contacts database.** Use the `ContactStoring` protocol with an in-memory fake.
- **No Xcode project.** The build is SwiftPM only (the machine has Command Line Tools, not Xcode). The `.app`
  bundle is assembled by `scripts/bundle.sh`.
- **No project-local `.claude/` directory.** Claude Code config lives in the user's `~/.claude/`.
- Secrets (the Claude API key) live in the macOS Keychain, never in files or `UserDefaults`.

## Commands

| Task | Command |
| --- | --- |
| Build (debug) | `swift build` |
| Unit tests | `make test` (Swift Testing; see note below) |
| Build `NameCards.app` (release, signed) | `make app` |
| Build and launch the app | `make run` |
| OCR + parse card images from the terminal | `swift run nc-scan [--region SG] [--lines] card.jpg …` |
| Clean | `make clean` |

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). XCTest is not available with Command Line
Tools, and plain `swift test` can't find the Testing framework, so always use `make test`.

Camera and Contacts permission prompts only work when the app is launched as a bundled `.app` (they need
`Info.plist` usage strings). `swift run` is fine for non-permission work only.

## Architecture

```
Package.swift
Resources/Info.plist              bundle metadata + NSCameraUsageDescription / NSContactsUsageDescription
scripts/bundle.sh                 swift build -c release → NameCards.app → codesign
Sources/NameCardsCore/            pure logic, no SwiftUI; everything here is unit-testable
  Model/        DraftContact (fields + per-field confidence), FieldChange, etc.
  OCR/          TextRecognizer: two-pass Vision OCR → lines with bounding boxes
  Parse/        CardParser (line classification + name selection), PhoneNumbers (labels, E.164),
                NameSplitter (Latin/Malay/CJK name order), Keywords (multilingual tables), Script;
                ClaudeParser (optional, URLSession — not built yet)
  Match/        ContactMatcher: normalised email/phone exact match, fuzzy name + company
  Merge/        MergePlanner: DraftContact × existing contact → [FieldChange]
  Store/        ContactStoring protocol + CNContactStore implementation (iCloud container, groups)
Sources/nc-scan/                  developer CLI: run OCR + parser on image files
Sources/NameCards/                SwiftUI app target
  Capture/      CameraController (AVCaptureSession), CardDetector (rectangles, stability, sharpness, dedupe)
  UI/           ScanView, ReviewListView, MergeSheet, SettingsView
Tests/NameCardsCoreTests/         parser fixtures (EN/ZH/JA/KO OCR outputs), end-to-end Vision tests on
                                  rendered cards, matcher, merge planner
```

Pipeline: `capture → crop → OCR → parse (+ optional Claude) → match → review queue → merge sheet → save`.

## Conventions

- Swift 6 language mode with strict concurrency. UI state lives in `@MainActor` `@Observable` view models.
  Camera and processing run in actors or on dedicated queues, and capture never blocks on OCR.
- Keep `NameCardsCore` free of SwiftUI and AVFoundation so it stays fast to test. Vision, Contacts and
  Foundation are fine there.
- Parsing and matching functions should be pure: input is OCR lines and fields, output is values. Add a
  fixture test for every parser bug fixed.
- Phone numbers are normalised to E.164. The region comes from the card itself (address country, then the
  email/web TLD, then kana/hangul), falling back to the configured default. Numbers whose country can't be
  determined are kept as printed, with lower confidence. Emails are compared lowercased and trimmed.
- OCR: Vision only reads CJK well when that language is listed *first* in `recognitionLanguages`, and no
  single ordering covers zh/ja/ko together. `TextRecognizer` therefore auto-detects first, then re-runs with
  the dominant CJK language first. Keep the `TextRecognizerTests` end-to-end tests passing if you touch this.
- When a fixture comes from a real card, capture its OCR lines with `swift run nc-scan --lines`.
- CJK cards: the native-script name is the primary name. A Latin-script variant goes to the phonetic name
  fields or the nickname.
- Prefer Apple frameworks over third-party dependencies. Add a package only with a clear reason recorded in
  the commit message.
- If you touch the Claude parser, look up the current model ID and Messages API shape (the `claude-api`
  skill) rather than relying on memory.

## Definition of done

- `swift build` and `make test` pass with no warnings introduced.
- New logic in `NameCardsCore` has tests.
- UI changes are checked by running `make run` and exercising the flow. Say so explicitly if you could not
  (e.g. there was no camera or permissions were denied).
- Commits are small and scoped to one milestone or fix, with a descriptive message.

## Known limitations

- Ad-hoc code signing changes the code identity on each rebuild, so macOS may ask for camera and contacts
  permission again. Signing with a stable local certificate (`SIGN_IDENTITY=... make app`) avoids this.
- Writing the contact note field (`CNContactNoteKey`) needs an Apple-granted entitlement. Without it, the
  app skips notes and records "Met at" through Contacts groups instead.
