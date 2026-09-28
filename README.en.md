# TuneC

**TuneC** is a tiny macOS menu bar utility that lets you control your external monitor's volume and brightness with the keyboard and the scroll wheel, just like you would on the built-in speakers.

English | [简体中文](README.md)

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/iRoy930/TuneC)
[![Swift](https://img.shields.io/badge/Swift-5-orange)](https://github.com/iRoy930/TuneC)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

> **Requirements**: macOS 13.0 or later (the Process Tap backend needs macOS 14.2+). Both Apple Silicon and Intel Macs are supported.

## Why

Connect your Mac to a monitor with built-in speakers over Type-C or DisplayPort, and you hit a familiar annoyance:

> **The volume keys do nothing. The volume icon in the menu bar is greyed out. There is no volume slider in System Settings.**

The reason is that audio travels through the monitor's own DAC. macOS sees it as a fixed-level output device that exposes no `VolumeScalar` (software volume) property, so macOS concludes the device **has no volume to control at all** and hands the job entirely to the monitor's physical buttons. TuneC fills that gap: it takes over the volume keys and the scroll wheel, tries the device directly first, falls back to DDC/CI hardware control, and finally falls back to a software audio loopback engine.

---

## Features

**Menu bar**

- Lives in the menu bar, no Dock icon (`LSUIElement`)
- View and switch the current output / input device from the menu
- Volume slider and mute toggle, reflecting the active backend in real time
- Detects the external display model and its capabilities, and shows a brightness slider automatically

**Volume control with automatic backend routing**

- **CoreAudio backend**: when the device exposes a writable `VolumeScalar`, control it directly, exactly like the system does
- **DDC/CI backend**: when the monitor supports DDC volume (VCP `0x62`), control it in hardware. TuneC runs a write-then-read-back probe first and only switches once writability is confirmed
- **Virtual audio backend**: the software fallback when the monitor firmware does not implement DDC volume (see below)

**DDC/CI display control**

- Brightness (VCP `0x10`), via menu slider and hotkeys
- Contrast (VCP `0x12`), via scroll gesture
- Automatic re-detection on display hot-plug
- A small set of built-in capability profiles for known models (currently Mi 27 NU), applied automatically once a model is recognized

**Virtual audio loopback**

When the output device's volume is not writable and the monitor does not support DDC volume, TuneC can take over system audio → apply a single volume control → output to the physical device. Two capture backends are available:

| Backend | Requirement | Permission | Extra install |
| --- | --- | --- | --- |
| **Core Audio Process Tap** (default) | macOS 14.2+ | System Audio Recording | None |
| **BlackHole** (fallback) | macOS 13.0+ | Microphone | Install BlackHole 2ch yourself |

The Process Tap backend does not use the microphone, so it **does not light up the orange microphone indicator** in the menu bar, and it needs no driver installation.

**Global controls**

- Global hotkeys (Carbon `RegisterEventHotKey`), working inside any app
- Edge scroll gestures: scroll along the **top edge** of the screen to adjust brightness, along the **bottom edge** to adjust volume. Off by default; enabling requires Accessibility permission

**Volume / brightness HUD**

- Minimal translucent overlay showing the current value and a progress bar
- Positioned at 61.8% of the screen height (the golden ratio), horizontally centered
- Follows the system light / dark appearance

**Self-check**

```bash
/Applications/TuneC.app/Contents/MacOS/TuneC --selfcheck
```

Prints 30+ checks covering device enumeration, volume read/write, the DDC channel, the loopback path and gesture configuration, useful for diagnosing environment problems.

> TuneC does **not** include EQ, reverb or any other audio processing. It does **not** record, and it **never** uploads any audio.

---

## Installation

### Option 1: Download a prebuilt release

1. Go to [Releases](https://github.com/iRoy930/TuneC/releases) and download the latest `.zip`
2. Unzip and drag `TuneC.app` into `/Applications`
3. If macOS warns that the developer cannot be verified on first launch, click "Open Anyway" in **System Settings → Privacy & Security**

### Option 2: Build from source (Command Line Tools only, no full Xcode needed)

```bash
git clone https://github.com/iRoy930/TuneC.git
cd TuneC
bash scripts/build.sh
```

The build output is `build/TuneC.app`; run it with `open build/TuneC.app`. See [docs/BUILD.md](docs/BUILD.md) for details.

---

## Permissions

TuneC requests only the permissions a feature actually needs, keeping the scope minimal:

| Permission | When it is needed | Notes |
| --- | --- | --- |
| System Audio Recording | Using the Process Tap backend | Captures what the system is playing. Does not involve the microphone |
| Microphone | The BlackHole backend is selected | BlackHole is a virtual input device, so reading it falls under the microphone permission; it is requested at launch whenever that backend is active |
| Accessibility | Enabling edge scroll gestures | Needed to intercept system-wide scroll events; not requested if gestures stay off |

TuneC does not record, does not save audio, and performs no network uploads whatsoever. See [docs/PERMISSIONS.md](docs/PERMISSIONS.md).

---

## Hotkeys

| Shortcut | Action |
| --- | --- |
| `⌃⌥ O` | Switch output device (cycle) |
| `⌃⌥ I` | Switch input device (cycle) |
| `⌃⌥ ↑` | Volume up |
| `⌃⌥ ↓` | Volume down |
| `⌃⌥ M` | Toggle mute |
| `⌃⌥ →` | Brightness up |
| `⌃⌥ ←` | Brightness down |

**Edge scroll gestures** (off by default, requires Accessibility permission):

| Position | Scroll | `⌥` + scroll | `⌃` + scroll | `⌘` + scroll |
| --- | --- | --- | --- | --- |
| Top edge | Brightness | Fine adjustment | Contrast | — |
| Bottom edge | Volume | Fine adjustment | Switch output device | Toggle mute |

---

## FAQ

**Q: The volume keys still do nothing. Why?**

Check the "volume backend" line in the menu bar menu first. If it says "unsupported", the current device has neither software volume nor DDC volume support — turn on **Virtual Audio Loopback** from the menu and the volume keys will start working.

**Q: An orange microphone indicator appeared in the menu bar. Is that expected?**

It means the active capture backend is **BlackHole**. BlackHole is a virtual input device, so reading it counts as microphone access and the system shows the indicator. To avoid it, switch to **System Audio Capture** under "Virtual Audio → Capture Method" (requires macOS 14.2+).

**Q: Do I need to install BlackHole?**

Not on macOS 14.2 or later. The default Process Tap backend captures system audio directly with no driver at all. BlackHole is only needed on macOS 13.x or when you deliberately want the legacy path.

**Q: The scroll gestures do nothing?**

Gestures are off by default and require **Accessibility** permission. Grant it in **System Settings → Privacy & Security → Accessibility**, then enable "Edge Scroll Gestures" from the menu. Note that in full-screen apps you must hold `⌥` by default (configurable in settings).

**Q: The brightness slider does not appear?**

The brightness slider only appears when an external display is detected and its DDC channel is usable. The DDC channel may be temporarily unavailable while the display is asleep or behind certain adapters.

For anything else, start with [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Repository layout

```
TuneC/
├── Sources/TuneC/      # Open source: menu bar UI, hotkeys, gestures, HUD, self-check
├── Core/               # Closed-source prebuilt binary core + text interface (.swiftinterface)
├── Resources/          # Info.plist, app icon
├── scripts/            # Build and helper scripts
├── docs/               # Build, architecture, permissions, troubleshooting, release docs
└── README.md
```

---

## About the closed-source core

To keep the project sustainable, part of its capability is shipped as a **precompiled library**: the core audio engine and the DDC protocol implementation live in the `Core/` directory, together with a text interface file (`.swiftinterface`) for compile-time type checking. The source is not public.

`Core/` is **proprietary software** and is not covered by this repository's MIT license; you are granted only the right to link against it within this project's build process. Everything else in the repository (`Sources/`, `scripts/`, `Resources/`, and so on) is fully open, readable and modifiable.

See [NOTICE](NOTICE) for the exact terms and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the architecture.

---

## License

The open source portion of this repository is licensed under the **MIT License**, see [LICENSE](LICENSE).

The precompiled binaries under `Core/` are not covered by MIT, see [NOTICE](NOTICE).

---

## Credits

- [m1ddc](https://github.com/waydabber/m1ddc) — the DDC/CI implementation in this project was written with reference to that project
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) — open source virtual audio driver, installed by the user

Thanks to everyone who files issues and sends pull requests.
