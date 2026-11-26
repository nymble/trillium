# Notices and attribution

## This project

Copyright (C) 2026 Paul Lambert (d/b/a M-of-N). Licensed under `GPL-3.0-or-later OR LicenseRef-Commercial`; see [LICENSE](LICENSE), [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md) and [LICENSES/](LICENSES/). Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).

Versions published before this change were offered under GPL-3.0-only. Those published copies keep the terms they were published under; this notice applies from the commit that introduces it.

The wiring diagrams in `docs/images/` are original drawings created for this project.

## Independent implementation

`trill-driver` was written independently from the published Trill I²C protocol description in the *Trill Capacitive Touch Sensors* datasheet (Rev C, v1.3, 2025-02-03). Its behaviour was cross-checked against Bela's open-source host libraries. No source code was copied from them. Timing constants (identify delay, acknowledgement polling budget, legacy inter-command delay) and default settings (for example Flex prescaler 4 and noise threshold 0.03) follow values observed in these libraries:

- [BelaPlatform/Trill-Linux](https://github.com/BelaPlatform/Trill-Linux) (reviewed at commit `a3e1880`)
- [BelaPlatform/Trill-Arduino](https://github.com/BelaPlatform/Trill-Arduino) (reviewed at commit `c99966e`, BSD-3-Clause, © Augmented Instruments Ltd.)

## Third-party hardware and documentation

The Trill hardware designs belong to their authors and are published under CC BY-SA 3.0, and the Trill firmware under the GPL, per [BelaPlatform/Trill](https://github.com/BelaPlatform/Trill). This repository does not redistribute them.

Seeed Studio XIAO nRF52840 pin and schematic facts are taken from Seeed Studio's public wiki and schematics, which are marked CC BY-SA 4.0. Raspberry Pi facts come from Raspberry Pi Ltd documentation. Nordic nRF52840 electrical figures come from the nRF52840 Product Specification v1.5. These sources are cited, not reproduced.

## Trademarks

Bela and Trill are trademarks of Augmented Instruments Ltd. XIAO and Seeed Studio are trademarks of Seeed Technology Co., Ltd. Raspberry Pi is a trademark of Raspberry Pi Ltd. Nordic Semiconductor and nRF52840 are trademarks of Nordic Semiconductor ASA. QWIIC is a trademark of SparkFun Electronics. All other trademarks belong to their owners. These names are used here only to identify compatible hardware. This project is not affiliated with or endorsed by any of these companies.

`lsm6ds3trc` was written from the ST LSM6DS3TR-C datasheet (DocID030071 Rev 3). XIAO nRF52840 Sense pin and memory-layout facts were cross-checked against Zephyr's `xiao_ble` board files (Apache-2.0) and Seeed's Arduino variant. No code was copied from them.

## Omi

[docs/omi-integration.md](docs/omi-integration.md) cites facts (pins, UUIDs, codec IDs, framing, flash procedure) from [BasedHardware/omi](https://github.com/BasedHardware/omi) (MIT, © 2024 Based Hardware Contributors), reviewed at commit `28c785960fa7`. No Omi source code is included in this repository. Omi is a trademark of its owner.

## Rust dependencies

Third-party crates keep their own licences (mostly MIT/Apache-2.0); see `Cargo.lock`, `firmware/xiao-sense/Cargo.lock` and each crate's metadata. Run `cargo tree` to list them. Firmware binaries link permissively licensed crates only (MIT, Apache-2.0, BSD-3-Clause `nrf-pac`, Zlib, Unlicense). Anyone distributing a firmware binary must ship those notices with it.

## Names and marks

"Trillium", "Trillium Sense", "Trillium Zero", "Trillium Base" and the Rhodonea mark are names and marks of the copyright holder. They are not licensed by the GPL or by a commercial licence, which cover the code and content, not the names. You may say a build is based on this project, but a modified or redistributed build must not use these names or marks as its own product name or logo without permission. No trademark registration is claimed here.

## Known exceptions and files not covered by the project licence

- Bela Trill hardware designs, firmware, libraries and datasheets, Seeed Studio and Raspberry Pi documentation, Nordic documentation and the Nordic S140 SoftDevice keep their own licences and are not part of this repository (see above).
- The Nordic SoftDevice binary is neither included in nor distributed with any release.
- Third-party Rust crates keep their own licences; see `Cargo.lock` and `firmware/xiao-sense/Cargo.lock`.
- Fonts (Outfit, Inter, IBM Plex Mono; SIL OFL 1.1) are not bundled in this repository; the wordmark letters are outlines made from Outfit.
- `REUSE.toml` records the licence of files that cannot carry a header (images, JSON, CSV, Markdown, property lists, lock files).
