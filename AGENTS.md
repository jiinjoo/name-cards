# AGENTS.md

Guide for AI coding agents (and humans) working in this repository.

## What this is

**NameCards** is a local, native macOS app for bulk-scanning business cards into iCloud Contacts:

1. **Scan** – a live camera feed (Continuity Camera iPhone preferred, built-in camera fallback) auto-detects
   business cards, waits for a steady, sharp frame, takes a full-resolution photo and crops the card from it
   with perspective correction. A card is captured once while it stays in view, and a card shown again
   later is dropped by content (same email or mobile, or same name and company).
2. **Extract** – Apple Vision OCR (English/Latin, Simplified & Traditional Chinese, Japanese, Korean) followed by
   rule-based parsing into a `DraftContact`. Optionally the *OCR text* (never the image) is sent to the Claude
   API for better field labelling.
3. **Review** – the user verifies and fixes every draft in a list beside the card image. Low-confidence fields
   are highlighted, and any OCR line can be re-assigned to a field ("Use as"). Each card is approved or
   skipped. The whole session is saved to disk continuously, so quitting mid-event loses nothing.
4. **Merge & save** – each draft is matched against existing contacts. A field-by-field merge is proposed and
   the user confirms it. The result is written to the **iCloud** contacts container and added to a per-session
   "Met at" group.

## Non-negotiable rules

- **Local-first privacy.** Card images and contact data never leave the Mac. The only network call allowed is
  the optional Claude parser. It is off by default and sends OCR text only.
- **Never write to Contacts without user confirmation.** Every create or merge goes through the review and
  merge UI. Never delete contacts. Never overwrite an existing value silently: replacements need an explicit
  tick, and additive changes (a new phone or email) may be pre-ticked.
- **Never write to the user's real Contacts while developing or testing**. It syncs to iCloud and every
  device. Writes happen only from the Save sheet, after the user clicks Save.
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
| Regenerate the app icon | `./scripts/make-icon.sh` |
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
  Model/        ContactSnapshot (plain copy of an existing contact), DraftContact (fields + per-field confidence; Codable), editing helpers (LineAssignment,
                fieldsNeedingAttention), CardRecord (one card's review state), OCRLine
  Session/      SessionStore: session.json + card images in ~/Library/Application Support/NameCards
  Capture/      CaptureGate (when to auto-capture: pure state machine), CardDetector (Vision rectangles +
                perspective crop), ImageMetrics (sharpness), Quad
  OCR/          TextRecognizer: two-pass Vision OCR → lines with bounding boxes (async, private queue);
                CardReader: OCR + parse, recovering sideways/upside-down cards
  Parse/        CardParser (line classification + name selection), PhoneNumbers (labels, E.164),
                NameSplitter (Latin/Malay/CJK name order), Keywords (multilingual tables), Script,
                TextCleanup (rejoins "a b@x" emails, punctuation spacing, all-caps → capital case;
                applied to every draft via DraftContact.tidied());
                ClaudeParser (optional: raw HTTP to the Messages API, schema-constrained JSON, merged
                with the on-device result so no phone/email it found is lost)
  Match/        SessionDeduper (same card scanned twice in a session); ContactMatcher (email / mobile exact,
                Jaro-Winkler name incl. phonetic + company); TextSimilarity
  Merge/        MergePlanner: DraftContact × ContactSnapshot → MergePlan of FieldChanges (add pre-ticked,
                replace un-ticked, never remove); SaveItem: one card's destination + ticked changes
  Store/        ContactMapper (CNContact ⇄ values; unit-tested with in-memory CNMutableContacts),
                ContactStoring protocol + ContactStore (real DB on a private queue; iCloud container, groups)
Sources/nc-scan/                  developer CLI: run OCR + parser on image files
Sources/NameCards/                SwiftUI app target
  App/          NameCardsApp, AppState (mode + shared models), AppCommands (Go and Card menus: every keyboard
                shortcut is defined here, not on buttons, except Scan's ⌘↩ Capture Now)
  Capture/      CameraController: AVCaptureSession, analyses frames on its video queue, photo capture
  Scan/         CardSession (@MainActor @Observable: all cards, reading, dedupe, debounced persistence),
                ScanModel (camera state only), CardProcessor (actor: OCR one card at a time; image I/O)
  Settings/     AppSettings (UserDefaults keys), APIKeyStore (Keychain), SettingsView (region, contact
                options, Claude toggle + key + Test, clear saved cards)
  Save/         SaveModel (permission → match approved cards → save; marks cards saved), SaveSheet (new vs
                merge picker, tickable changes, event group / photo options)
  Review/       ReviewModel (filter, selection, approve/skip/next, Approve All Clean, save sheet state),
                ReviewView (list + toolbar), ReviewDetail (field editor)
  UI/           RootView (Scan | Review switch, Dock badge; camera stops while reviewing), ScanView,
                CameraPreview, CardTray (double-click → Review)
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
- **Never call Vision synchronously from Swift-concurrency threads** (tasks, actors, async tests). On
  macOS 26 that deadlocks once every pool thread is blocked inside Vision. `TextRecognizer` runs on a private
  dispatch queue behind an async API. Other Vision calls (`CardDetector`) run on the camera's own
  dispatch queues. Follow the same pattern for any new Vision work.
- **AVFoundation raises Objective-C exceptions that Swift can't catch, and the app aborts.** Check
  preconditions before calling into it. For example, `capturePhoto` requires the photo output's video
  connection to be enabled and active, which isn't the case while macOS video effects reconfigure a
  Continuity Camera. `CameraController.takePhoto` checks and falls back to the video-frame crop.
- Camera diagnostics are logged under subsystem `com.jiinjoo.namecards` (category `camera`). Read them
  with `/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.jiinjoo.namecards"'`. Use the
  full path: in zsh, `log` is a shell builtin.
- When a fixture comes from a real card, capture its OCR lines with `swift run nc-scan --lines`.
- CJK cards: the native-script name is the primary name. A Latin-script variant goes to the phonetic name
  fields or the nickname.
- Prefer Apple frameworks over third-party dependencies. Add a package only with a clear reason recorded in
  the commit message.
- Claude parser: Swift has no official Anthropic SDK, so it's raw HTTP (`URLSession`). Model `claude-opus-5-5`
  at effort `low`, structured outputs via `output_config.format` (every schema property required,
  `additionalProperties: false`), and `fallbacks: "default"` with the `server-side-fallback-2026-07-01`
  beta header. Check `stop_reason` (`refusal`, `max_tokens`) before reading the text block, and skip
  thinking blocks. Before changing any of this, look up the current API in the `claude-api` skill rather
  than relying on memory. If Claude fails, the card falls back to the on-device result and a notice is shown.

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
