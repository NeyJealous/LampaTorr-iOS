# Third-party components

This project is a host/wrapper that downloads upstream components during `scripts/prepare.sh`.

- **Lampa** — https://github.com/yumata/lampa — GPL-2.0 license file in upstream repository.
- **TorrServer / TorrServerKit** — https://github.com/YouROK/TorrServer — GPL-3.0.

The iOS TorrServerKit is statically linked into the host application. TorrServer upstream explicitly notes that a combined iOS host is a GPL-3.0 derivative work. Review upstream licensing before redistribution. This project is intended for personal/sideloaded builds, not App Store distribution.


- **VLC for iOS / VLC for Mobile** — https://github.com/videolan/vlc-ios — optional external playback application. VLC and VLCKit are not bundled in LampaTorr v1.1.0; LampaTorr opens the installed VLC app through its documented URL schemes.
