# Third-party components

This project is a host/wrapper that downloads upstream components during `scripts/prepare.sh`.

- **Lampa** — https://github.com/yumata/lampa — GPL-2.0 license file in upstream repository.
- **TorrServer / TorrServerKit** — https://github.com/YouROK/TorrServer — GPL-3.0.

The iOS TorrServerKit is statically linked into the host application. TorrServer upstream explicitly notes that a combined iOS host is a GPL-3.0 derivative work. Review upstream licensing before redistribution. This project is intended for personal/sideloaded builds, not App Store distribution.


- **VLC for iOS player UI/interaction reference** — https://github.com/videolan/vlc-ios — GPL-2.0-or-later / MPL-2.0. LampaTorr v1.0 adapts the official VLC iOS player architecture and interaction model. Reference commit: `a96a4ecbdc86437a1a7ac559b60f4443bd4ad305`.
