# ScreenOCR

**Copy any text on your screen. Press ⌥S, drag, done.**

ScreenOCR is a tiny macOS menu bar app that turns any part of your screen into text you can paste: images, videos, PDFs, slides in a video call, a screenshot of a textbook, even text inside apps that won't let you select it.

<!-- Demo: add a GIF here, e.g. ![demo](docs/demo.gif) -->

## Features

- **One shortcut, instant copy.** Press **⌥S** (Option + S), drag over the text, and it's already on your clipboard.
- **Translate.** One click opens Apple's built-in translator for what you just copied.
- **History.** Your last 10 copies are one click away, from the result card or the menu bar. Pick one and it's copied again.
- **QR codes.** Drag over a QR code and its content is copied. If it's a link, you can open it right away.
- **Korean, English, Russian and more.** Uses Apple's on-device text recognition.
- **Private by design.** Everything runs on your Mac. No internet, no accounts, nothing saved except your last 10 copies.
- **Lightweight.** A native Swift app with no third-party dependencies.

## Requirements

- macOS 14.6 (Sonoma) or later

## Installation (no coding needed)

1. Go to the [**Releases**](../../releases) page and download `ScreenOCR.zip`.
2. Unzip it and drag **ScreenOCR.app** into your **Applications** folder.
3. Open the app. macOS will warn that it "cannot verify the developer", because the app is not notarized by Apple. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to ScreenOCR.
5. Press **⌥S**. macOS will ask for **Screen Recording** permission: turn on ScreenOCR in **System Settings → Privacy & Security → Screen & System Audio Recording**.
6. Quit ScreenOCR from the menu bar icon and open it again. macOS applies the permission after a restart.
7. Optional: click the menu bar icon and turn on **Launch at login**.

If **Open Anyway** doesn't appear, run this in Terminal and open the app again:

```bash
xattr -cr /Applications/ScreenOCR.app
```

## Usage

1. Press **⌥S** anywhere.
2. Drag over the text you want. Press **Esc** to cancel.
3. The text is copied. A small card shows what was copied, with these options:

| Button | What it does |
|---|---|
| Translate | Opens Apple's translator. Use **Replace** in it to copy the translation |
| History | Shows your last 10 copies. Click one to copy it again |
| Open link | Appears when a QR code contains a link |
| Copy text instead | Appears when you selected a QR code and some text, and you want the text |

The card hides itself after a few seconds. Hover over it to keep it open.

The menu bar icon also has **Capture text**, **Recent copies**, **Launch at login** and **Quit**.

## How it works

1. **Shortcut.** A system-wide hot key (Carbon `RegisterEventHotKey`) listens for ⌥S in every app.
2. **Selection.** A transparent overlay covers each screen so you can drag a rectangle.
3. **Capture.** ScreenCaptureKit takes a picture of only that rectangle, leaving ScreenOCR's own windows out.
4. **Recognition.** Apple's Vision framework reads the text (`VNRecognizeTextRequest`) and looks for QR codes (`VNDetectBarcodesRequest`). The pieces are put back into lines in reading order.
5. **Copy.** The result goes to the clipboard and into the 10-item history.

## Build from source

1. Clone the repository and open the project:

   ```bash
   git clone https://github.com/khodiboev/ScreenOCR.git
   cd ScreenOCR
   open ScreenOCR.xcodeproj
   ```

2. In Xcode, select the **ScreenOCR** target, then go to **Signing & Capabilities**:
   - Set **Team** to your own Apple ID (a free *Personal Team* works).
   - Change the **Bundle Identifier** to something unique, e.g. `com.yourname.ScreenOCR`.

3. Press **⌘R** to build and run.

To change the shortcut, edit `defaultKeyCode` and `defaultModifiers` in `HotKey.swift`.

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens on ⌥S | Make sure ScreenOCR is running (menu bar icon), and that no other app uses ⌥S |
| "Allow screen access" message | Turn on ScreenOCR in **Screen & System Audio Recording**, then quit and reopen the app |
| "No text found" | Select a larger area, or zoom in so the text is bigger on screen |
| Translation asks to download a language | That's Apple's translator downloading its on-device language model |
| Uzbek text has small mistakes | Uzbek isn't in Apple's official recognition languages; Latin letters usually work, but check letters like o' and g' |

## Project structure

```
ScreenOCR/
├── ScreenOCRApp.swift      # App entry point + menu bar menu
├── AppController.swift     # Capture flow, clipboard, 10-item history
├── HotKey.swift            # System-wide ⌥S shortcut
├── SelectionOverlay.swift  # Drag-to-select overlay on every screen
├── OCREngine.swift         # ScreenCaptureKit capture + Vision text and QR recognition
└── ResultPanel.swift       # Result card with Translate, History and QR actions
```

## License

[MIT](LICENSE)
