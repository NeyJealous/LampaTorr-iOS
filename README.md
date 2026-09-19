# LampaTorr iOS — build from iPhone + Ksign

Personal iOS 18+ host app that runs the official **TorrServerKit in-process** and opens a bundled **Lampa** UI in `WKWebView`.

The intended no-Mac workflow is:

`iPhone → GitHub Actions (macOS/Xcode) → unsigned IPA → Ksign → install on iPhone`

## What the app does

- Starts official TorrServerKit on `http://127.0.0.1:8090`.
- Waits for `/echo` before opening Lampa.
- Bundles Lampa into the app during the cloud build.
- On first run sets Lampa's `torrserver_url` to `http://127.0.0.1:8090`.
- Keeps Lampa and TorrServer in the same iOS process.
- Rechecks/restarts TorrServer when the app becomes active again.
- Enables inline media, Picture in Picture and the audio background mode.

## Build entirely from an iPhone

Open the repository:

`Actions → Build LampaTorr IPA → Run workflow`

The workflow asks for **Bundle ID**. If your provisioning profile accepts any App ID, the default can be left as:

```text
dev.lampatorr.ios
```

If your provisioning profile is tied to a specific App ID, enter that exact Bundle ID instead.

GitHub's macOS runner downloads Lampa and official TorrServerKit, generates the Xcode project and builds an **unsigned device IPA**.

After the workflow is green:

`Actions → completed run → Artifacts → LampaTorr-unsigned-ipa`

GitHub downloads an artifact ZIP. Open it in Files and extract it. Inside is `LampaTorr-unsigned.ipa`.

Open the IPA in **Ksign**, choose your installed certificate and provisioning profile, sign it, then install the resulting signed IPA.

Do **not** upload your `.p12`, certificate password or `.mobileprovision` to GitHub. Signing is done locally in Ksign.

## Versions pinned for reproducibility

- TorrServerKit: **MatriX.145**
- Minimum iOS: **18.0**
- Lampa commit: `d3d3d1cbd943b7fb9de9b470c2f8bc0f3e241a94` (2026-09-17)
- TorrServerKit SHA-256: `868969629a594c0f033192ed87e5b555b4a96bab69496e3d7dab1b394bc3cc6b`

## iOS limitation

For the most reliable streaming, use Lampa's **internal player**. If playback is handed to another app, iOS can suspend LampaTorr and therefore its in-process TorrServer. Background audio mode is not a general permission to run an HTTP server indefinitely.

## Licensing / redistribution

This project downloads two upstream GPL components during the build. TorrServer upstream states that its statically linked iOS XCFramework makes the combined host a GPL-3.0 derivative; Lampa's repository carries GPL-2.0. This package is prepared for **personal sideloaded builds**. Review the upstream licenses before redistributing a combined IPA.

See `THIRD_PARTY.md`.
