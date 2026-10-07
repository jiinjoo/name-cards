# NameCards

A Mac app that turns a stack of business cards into contacts. Hold each card up to the camera (your iPhone
works best). NameCards captures it automatically, reads it, lets you fix any mistakes, and then adds it to
your Contacts. If you already have someone, their contact is updated instead of a duplicate being created.

Everything happens on your Mac. Card images and contact details aren't sent anywhere, unless you turn on
the optional Claude feature described below.

## Download and install

1. Go to the [**Releases**](../../releases/latest) page and download **NameCards-….dmg** (under *Assets*).
2. Open the downloaded file and drag **NameCards** onto **Applications**.
3. **First launch only.** Open NameCards from your Applications folder. macOS will warn that it
   *"could not verify NameCards is free of malware"*. That's expected:
   1. Click **Done** (not *Move to Trash*).
   2. Open **System Settings › Privacy & Security** and scroll down to **Security**.
   3. Next to *"NameCards was blocked…"*, click **Open Anyway**, then confirm with your password or Touch ID.

   After this, NameCards opens normally.

macOS shows this warning because the app isn't registered with Apple, which needs a paid developer
account. The app's full source code is in this repository for anyone who wants to check it.

**Requirements:** macOS 14 Sonoma or later, on an Apple Silicon or Intel Mac. Using an iPhone as the camera
needs iOS 16 or later, with both devices signed in to the same Apple Account and Wi-Fi and Bluetooth turned
on ([Continuity Camera](https://support.apple.com/en-us/102546)). The Mac's built-in camera works too, but
reads small print less well.

## Using NameCards

1. **Scan** (⌘1). Optionally type where you met these people in the **Event** box, for example
   *Tech Expo 2026*. Then hold up one card after another. Each card is captured when it's steady,
   with a sound and a flash.
   - Use a plain, darker background behind light cards, and avoid glare.
   - No green outline appearing? Press **⌘↩** to capture anyway.
   - A bad capture? Click the trash icon next to it.
2. **Review** (⌘2). Check each card against its picture. Fields the app is unsure about are highlighted
   in orange. If something landed in the wrong field, use **Use as** on a line under *Text read from the
   card*. Then **Approve** (⌘↩) or **Skip** (⇧⌘S). **Approve All Clean** (⌥⌘↩) approves every card with
   nothing highlighted.
3. **Save to Contacts** (⌘S). NameCards checks your existing contacts. For each card you choose
   **New contact** or **Merge into** someone you already have, and tick which details to add or replace.
   Nothing is ever deleted from your contacts. New contacts go to your iCloud account, so they appear on
   your iPhone too, and each one is added to a group named after the event.

The first time you scan and save, macOS asks for permission to use the **camera** and your **contacts**.
Click **Allow** both times.

Your scans are kept until you remove them, even if you quit the app. You can clear cards already saved to
Contacts in **Settings** (⌘,).

### Optional: better reading with Claude

In **Settings › Claude**, NameCards can send the *text* read from each card (never the image) to
Anthropic's Claude AI, which is better at telling names, titles and companies apart. This needs an
**Anthropic API key**:

- A claude.ai account (Free, Pro or Max) does **not** include API access. API use is billed separately, at
  roughly a cent or two per card.
- Create an account in the [Claude Console](https://platform.claude.com/), add credit (new accounts may get
  a small amount of free credit to try it), create an API key, and paste it into Settings.

Without a key, NameCards works fully on its own. Claude is only an extra.

### Keyboard shortcuts

| | |
| --- | --- |
| ⌘1 / ⌘2 | Scan / Review |
| ⌘↩ | Capture now (Scan) · Approve card (Review) |
| ⇧⌘S | Skip card |
| ⌘R | Read card again |
| ⌘] / ⌘[ | Next / previous card |
| ⌥⌘↩ | Approve all cards with nothing highlighted |
| ⌘S | Save approved cards to Contacts |

### Something went wrong?

If the app crashes or misreads cards, please tell the person who shared NameCards with you. These help:

- **Crash:** the report macOS shows (click *Report…*, then copy the text).
- **Camera problems:** open Terminal and run this, then copy the output:
  ```sh
  /usr/bin/log show --last 10m --info --predicate 'subsystem == "com.jiinjoo.namecards"' --style compact
  ```
- **Misread card:** a photo of the card (if the owner doesn't mind), or the text shown under
  *Text read from the card*.

## For developers

Building needs macOS 14+ and Swift 6 (the Xcode Command Line Tools are enough; full Xcode isn't needed).

```sh
make run     # build NameCards.app and launch it
make test    # run unit tests
make dmg     # universal app packaged as NameCards-<version>.dmg
swift run nc-scan --lines card.jpg   # try the OCR + parser on a photo
```

Releases are built by GitHub Actions (`.github/workflows/release.yml`) when a version tag such as `v0.2.0`
is pushed. See [AGENTS.md](AGENTS.md) for the architecture and contributor conventions.

## License

[MIT](LICENSE)
