# NameCards

A local macOS app that bulk-scans business cards with your camera (an iPhone through Continuity Camera
works best), lets you fix any OCR mistakes, then saves them to your iCloud Contacts, merging into people
you already have instead of creating duplicates.

- **Scan**: hold cards up one after another. Each is captured automatically once it's steady and sharp.
- **Review**: check each card beside its image. Uncertain fields are highlighted, and any line on the card
  can be moved to the right field.
- **Save**: approved cards are matched against your contacts. You choose new contact or merge, tick the
  changes, and they're written to iCloud with a group per event.

Everything runs on your Mac. Optionally, Settings › Claude sends the text read from each card (never the
image) to Claude for better field labelling.

```sh
make run     # build NameCards.app and launch it
make test    # run unit tests
swift run nc-scan --lines card.jpg   # try the OCR + parser on a photo
```

## Keyboard shortcuts

| | |
| --- | --- |
| ⌘1 / ⌘2 | Scan / Review |
| ⌘↩ | Capture now (Scan) · Approve card (Review) |
| ⇧⌘S | Skip card |
| ⌘R | Read card again |
| ⌘] / ⌘[ | Next / previous card |
| ⌥⌘↩ | Approve all cards with nothing highlighted |
| ⌘S | Save approved cards to Contacts |

See [AGENTS.md](AGENTS.md) for the architecture and contributor rules.
