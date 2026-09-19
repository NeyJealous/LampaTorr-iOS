# LampaTorr iOS — LampaS-style + embedded TorrServer

iOS 18+ host app that combines a locally bundled **Lampa** UI with the official **TorrServerKit**.

The no-Mac workflow is:

`iPhone → GitHub Actions → unsigned IPA → Ksign → install`

## v0.3

This release fixes the startup `Script error` seen at **Account initialization** in v0.2.

The bundled Lampa UI is now served from an in-app loopback HTTP server:

- Lampa UI: `http://127.0.0.1:8091`
- TorrServer: `http://127.0.0.1:8090`

Using a normal HTTP origin instead of `file://` improves compatibility with Web Workers, CUB/account requests, plugins and browser storage.

## LampaS-style behavior

- LampaS-style app icon.
- Native mirror of Lampa `localStorage` into `UserDefaults` to preserve login/settings more reliably.
- `lampa_client lampatorr_ios` user agent suffix.
- WebView tuned for inline video, PiP, autoplay and touch use.
- Advertising modules are replaced with no-op implementations **before** the Lampa bundle is built.
- Lampa web source is pinned for reproducible builds.
- No upstream Android package/certificate identity is spoofed.

## Embedded TorrServer

TorrServerKit starts inside the iOS app on `127.0.0.1:8090`. Lampa is automatically configured to use that address.

For the most reliable streaming, use Lampa's **internal player**. iOS may suspend this app if playback is handed to a separate external player.

## Build on iPhone

Open:

`Actions → Build LampaTorr IPA → Run workflow`

Enter a Bundle ID accepted by your Ksign provisioning profile. The default is:

```text
dev.lampatorr.ios
```

After the run succeeds, download artifact **LampaTorr-LampaS-unsigned-ipa**, extract `LampaTorr-unsigned.ipa`, sign it in Ksign and install.

Do **not** upload your certificate, `.p12`, certificate password or `.mobileprovision` to GitHub.

## Pinned components

- Lampa source: `8150685226a5838040a5795a32be27108491cadb`
- TorrServerKit: **MatriX.145**
- Minimum iOS: **18.0**
- TorrServerKit SHA-256: `868969629a594c0f033192ed87e5b555b4a96bab69496e3d7dab1b394bc3cc6b`

## Licensing

The project combines GPL components. It is prepared for personal sideloaded use. Review the upstream licenses before redistributing a combined IPA.

See `THIRD_PARTY.md`.
