# MQTT Explorer for macOS

A native macOS build of [MQTT Explorer](https://mqtt-explorer.com), the
topic tree browser for MQTT brokers. Written in Swift and SwiftUI for Apple
Silicon. No Electron, no browser engine: one small binary that starts
instantly, uses a fraction of the memory, and behaves like any other Mac app
in light and dark mode.

Based on the original MQTT Explorer by Thomas Nordquist. This repository
carries the same license and attribution as the original project.

## Features

- Topic tree with live updates, message counts and a filter field (Cmd-F)
- Expand / collapse the whole tree with one click
- JSON, text and binary payload rendering with a diff view against the
  previous message
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

```sh
cd macos
./make-dmg.sh        # -> macos/build/MQTT Explorer-1.0.0.dmg
```

Open the DMG and drag MQTT Explorer to Applications.

## License

Same as the original MQTT Explorer: CC BY-ND 4.0, see `LICENSE.md`.

Original MQTT Explorer by Thomas Nordquist.
macOS version by Luke van Enkhuizen.
