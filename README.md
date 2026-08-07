# MQTT Explorer for macOS

<img width="1280" height="726" alt="image" src="https://github.com/user-attachments/assets/eb426076-2a3c-4b21-a9ed-f6ccc7423872" />

A native macOS build of [MQTT Explorer](https://mqtt-explorer.com), the
topic tree browser for MQTT brokers. Written in Swift and SwiftUI for Apple
Silicon. No Electron, no browser engine: one small binary that starts
instantly, uses a fraction of the memory, and behaves like any other Mac app
in light and dark mode.

Based on the original [MQTT Explorer](https://mqtt-explorer.com) by Thomas
Nordquist, which defined what this tool is and remains the reference for
the concept. This repository carries the same license and attribution as
the original project.

## Features

- Topic tree with live updates, message counts and a filter field (Cmd-F)
- Expand / collapse the whole tree with one click
- JSON, text and binary payload rendering with a diff view against the
  previous message
- Automatic visualization of numeric payloads: trend plots for single
  values, per-field sparklines and share rings for JSON objects, bar
  charts for numeric arrays
- Retained message handling: clearly marked in the status bar, clearable
  with one click
- Per-topic history with sparklines, message compare and copy
- Live charts for numeric values, with interpolation, color, axis range and
  time window settings
- Publish: raw payloads, JSON payloads, retained messages
- Multiple broker profiles with MQTT 3.1.1 and MQTT 5.0 (default), TLS,
  username/password and client certificates
- Connection status bar with topic and message counts

## Build

Requires macOS 15 or newer and Xcode 26 (or the matching command line
tools).

```sh
cd macos
./make-app.sh        # release build -> macos/build/MQTT Explorer.app
```

Run the tests (a broker on localhost:1883 is optional, the live tests skip
themselves without one):

```sh
cd macos
swift test
```

## Install

Download the latest DMG from the
[releases page](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases),
open it and drag MQTT Explorer to Applications. Or build it yourself:

```sh
cd macos
./make-dmg.sh        # -> macos/build/MQTT Explorer-1.1.0.dmg
```

## Usage

See [docs/usage.md](docs/usage.md) for connecting to brokers, navigating
the topic tree, retained messages, history, charts and publishing.

## Feedback

This app is in active use and development. Bug reports, feature requests
and general feedback are welcome: open an
[issue](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/issues).

## License

Same as the original MQTT Explorer: CC BY-ND 4.0, see `LICENSE.md`.

Original MQTT Explorer by Thomas Nordquist.
macOS version by Luke van Enkhuizen.
