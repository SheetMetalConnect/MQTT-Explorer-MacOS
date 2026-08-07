<img src="docs/images/banner.png" alt="MQTT Explorer for macOS" width="100%">

[![Latest release](https://img.shields.io/github/v/release/SheetMetalConnect/MQTT-Explorer-MacOS?label=download&color=2d5bd0)](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases/latest)
[![License](https://img.shields.io/badge/license-CC%20BY--ND%204.0-blue)](LICENSE.md)

[MQTT Explorer](https://mqtt-explorer.com) rebuilt in Swift and SwiftUI for
Apple Silicon. Same tool, same workflow, tuned for speed on macOS with a few
opinionated tweaks for people who look at business data on a broker.

## Install

Download the DMG from the
[releases page](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/releases/latest)
and drag it to Applications. The app is signed ad-hoc rather than notarized,
so the first launch is blocked: right-click, Open, confirm.

<img width="1280" alt="MQTT Explorer showing a broker with 19,000 topics" src="https://github.com/user-attachments/assets/eb426076-2a3c-4b21-a9ed-f6ccc7423872" />

## What is different

Added, mostly from integration work between ERP, MES and machines:

- Numbers get charted on sight. A single value becomes a trend plot, a JSON
  object becomes one sparkline per field with a ring showing the split.
- Payload types are marked in the tree, so business records and sensor
  readings stop looking alike at a glance.
- Topic segments starting with an underscore are tinted, following the UNS
  convention for `_historian` and friends.
- Any branch lists which children changed, when, and how often, with a
  switch for the last ten seconds only.

Not ported: Sparkplug B decoding and last will messages. If you need those,
use the original.

## Speed

The tree is merged in an actor off the main thread, and the main thread only
touches rows you can actually see.

It holds 19,000 topics and 98,000 messages from test.mosquitto.org while
staying usable, and builds a 10,000-topic tree in about 0.13 seconds. The
test suite has benchmarks so it stays that way.

## Build it yourself

macOS 15 or newer, Xcode 26 or the matching command line tools.

```sh
cd macos
./make-dmg.sh   # builds the app and packages it
swift test      # live broker tests skip without one on localhost:1883
```

## Docs

- [Usage](docs/usage.md)
- [What changed compared to the original](docs/differences-from-upstream.md)

## License

CC BY-ND 4.0, same as the original. See `LICENSE.md`.

Original MQTT Explorer by Thomas Nordquist. macOS version by Luke van
Enkhuizen. Bugs and requests go in the
[issue tracker](https://github.com/SheetMetalConnect/MQTT-Explorer-MacOS/issues).
