# Squish

A fast, fun, drop-focused macOS app for compressing images to a target **file size**, **dimension**, and/or **format**. Native SwiftUI — no dependencies.

![Squish](Squish/Assets.xcassets/AppIcon.appiconset/icon_256.png)

## What it does

Drop an image, a bunch of images, or a whole folder. Squish processes them according to up to three optional targets (use any combination — at least one must be on):

- **File size** — squish each image to ~a target size or smaller (KB/MB).
- **Dimensions** — max long side, max width, max height, or fit-within W×H. Images smaller than the limit are left alone.
- **Format** — convert to JPEG or HEIC.

Each control is a tile with quick-pick presets; choose **popovers + sliders** or **rotary dials** in Settings. Output is never upscaled, and a re-encode that would only grow a file keeps the original instead.

### Output placement
- **Auto** (mirrors how the drop arrived):
  - a single image → saved beside the original as `name (squished).ext`
  - several items → a `Squished` folder in their common parent
  - a folder → a sibling `<name> (squished)` folder, structure preserved
- **Choose…** — pick one destination folder for everything.

## How it works
- Reads anything ImageIO supports (incl. WebP, PNG); writes JPEG / HEIC. Inputs that aren't already JPEG/HEIC convert to your **default format** (Settings → General).
- **File-size targeting** binary-searches encoder quality, then downscales if the quality floor still overshoots.
- **Batches** either hit the target per-image, or *match quality across the batch* (Settings) — the quality that lands the heaviest image on target is applied to all so they look consistent.
- **Settings** (⌘,): default format, batch strategy, control style, plus editable **pixel-size** and **file-size** presets.
- Batches run concurrently across CPU cores; failures are per-file and never abort the batch.

## Build & run
```sh
xcodebuild -project Squish.xcodeproj -scheme Squish -configuration Debug build
```
Or open `Squish.xcodeproj` in Xcode and hit Run. Requires macOS 14+ / Xcode 16+ (uses a filesystem-synchronized project group, so new files in `Squish/` are picked up automatically).

The app is **not sandboxed** (personal/direct distribution) so it can write next to originals.

## Project layout
```
Squish/
  SquishApp.swift            App entry, single window
  Models/                    Settings, DropInput classification, JobResult
  Core/                      ImageCompressor, OutputPlanner, JobRunner
  Views/                     ContentView, DropZone, Controls, Processing, Results
  Assets.xcassets/           App icon + accent color
```

## Possible follow-ons
WebP **output** (needs a bundled encoder like libwebp), App Sandbox / Mac App Store packaging + notarization, saved presets, a CLI.
