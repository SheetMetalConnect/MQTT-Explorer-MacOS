# MQTT Explorer for macOS

<img width="1280" height="726" alt="image" src="https://github.com/user-attachments/assets/eb426076-2a3c-4b21-a9ed-f6ccc7423872" />

A native macOS build of [MQTT Explorer](https://mqtt-explorer.com), the
topic tree browser for MQTT brokers. Swift and SwiftUI, Apple Silicon, no
Electron. It opens instantly, stays out of the way, and looks like the rest
of your Mac in light and dark.

Based on the original [MQTT Explorer](https://mqtt-explorer.com) by Thomas
Nordquist, which defined what this tool is. Same license, same attribution.
See [what changed](docs/differences-from-upstream.md).

## What it does

- Live topic tree with counts, a filter (Cmd-F) and one-click expand or
  collapse
- Payloads as JSON, text or hex, with a diff against the previous message
- Numbers get charted on sight: trend plots, per-field sparklines with a
  share ring for JSON objects, bar charts for arrays
- Retained messages marked clearly and cleared with one click
- Per-topic history you can diff and copy from
- Chart panel with adjustable ranges, interpolation and colors, saved per
  connection
- Publish raw or JSON payloads, retained or not, at any QoS
- Broker profiles with MQTT 5.0 and 3.1.1, TLS, WebSocket, passwords in the
  Keychain

Busy brokers stay usable: the merge runs off the main thread, and the tree
stops auto-expanding once it gets big rather than opening fifty thousand
rows.

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
./make-dmg.sh        # -> macos/build/MQTT Explorer-1.1.0.dmg
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
