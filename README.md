<img src="docs/images/banner.png" alt="MQTT Explorer for macOS" width="100%">

[![Latest release](https://img.shields.io/github/v/release/SheetMetalConnect/MQTT-Explorer-MacOS?label=download&color=2d5bd0)](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey)](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases/latest)
[![Apple Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases/latest)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-CC%20BY--ND%204.0-blue)](LICENSE.md)

A native macOS build of [MQTT Explorer](https://mqtt-explorer.com), the
topic tree browser for MQTT brokers. Swift and SwiftUI, Apple Silicon, no
Electron. It opens instantly, stays out of the way, and looks like the rest
of your Mac in light and dark.

<img width="1280" alt="MQTT Explorer running against a broker with 19k topics" src="https://github.com/user-attachments/assets/eb426076-2a3c-4b21-a9ed-f6ccc7423872" />

Based on the original [MQTT Explorer](https://mqtt-explorer.com) by Thomas
Nordquist, which defined what this tool is. Same license, same attribution.
See [what changed](docs/differences-from-upstream.md).

## What it does

- Live topic tree with counts, a filter (Cmd-F) and one-click expand or
  collapse
- JSON payloads as a field table with dot paths, or as text, or as a diff
  against the previous message
- Numbers get charted on sight: trend plots, per-field sparklines with a
  share ring for JSON objects, bar charts for arrays
- UNS data contracts (`_historian`, `_analytics`, `_process`) picked out in
  the tree, so structure and payload are easy to tell apart
- Retained messages marked clearly and cleared with one click
- Per-topic history you can diff and copy from
- Chart panel with adjustable ranges, interpolation and colors, saved per
  connection
- Publish raw or JSON payloads, retained or not, at any QoS
- Broker profiles with MQTT 5.0 and 3.1.1, TLS, WebSocket, passwords in the
  Keychain

## Speed is the point

The Electron original merges messages on the main thread, which is why it
stalls on a busy broker. Here the tree lives in an actor off the main
thread, messages keep their wire order through a lock-guarded inbox, and
the main thread only touches rows that actually changed.

Tested against test.mosquitto.org at 19,000 topics and 98,000 messages
while staying responsive. A 10,000-topic tree builds in about 0.13 seconds,
and there are benchmarks in the test suite so that does not quietly
regress.

## Install

Grab the DMG from the
[releases page](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases)
and drag it to Applications. First launch is blocked because the app is
signed ad-hoc, not notarized: right-click, Open, confirm.

## Build it yourself

macOS 15 or newer, Xcode 26 or the matching command line tools.

```sh
cd macos
./make-app.sh        # -> macos/build/MQTT Explorer.app
./make-dmg.sh        # -> macos/build/MQTT Explorer-1.2.0.dmg
swift test           # live broker tests skip without one on localhost:1883
```

## Docs

- [Usage](docs/usage.md), from connecting to charting
- [What changed compared to the original](docs/differences-from-upstream.md)

## Feedback

I use this daily and keep working on it. Bugs and requests go in the
[issue tracker](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/issues).

## License

CC BY-ND 4.0, same as the original. See `LICENSE.md`.

Original MQTT Explorer by Thomas Nordquist.
macOS version by Luke van Enkhuizen.
