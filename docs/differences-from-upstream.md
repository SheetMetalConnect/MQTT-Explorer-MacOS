# Compared to the original

The original [MQTT Explorer](https://mqtt-explorer.com) is an Electron app.
This is a Swift rewrite. No shared code.

## Runtime

| | Original | This build |
|---|---|---|
| Stack | Electron, React, Material UI | Swift, SwiftUI |
| Download | ~90 MB | ~5 MB |
| Platforms | macOS, Windows, Linux | macOS 15+, arm64 |
| Appearance | Own theme | System light and dark |

## Topic tree

The original merges messages on the main thread every 300 ms, which is what
freezes the window under load.

Here the merge runs in an actor off the main thread. Messages reach it in
wire order through a lock-guarded inbox. Four times a second the main
thread takes a delta and touches only the rows it changes, and only when
those rows are visible. Counts are tracked as they change rather than by
walking the tree.

Measured: 19,000 topics and 98,000 messages while staying responsive, and a
10,000-topic tree built in 0.13 seconds. Benchmarks live in the test suite.

## Added

**Value mode.** A third render mode beside Diff and Raw, for payloads that
hold numbers.

| Payload | Renders as |
|---|---|
| One number | Trend plot with the change since the last message |
| JSON object | A sparkline per numeric field, plus a ring showing the split |
| Numeric array | Bar chart |

**Chart a whole topic.** One button plots everything measurable on a topic
and its direct children, whether the values arrive as JSON fields or as
separate topics.

**JSON as a field table.** Raw mode flattens objects to dot paths with a
chart button per numeric field.

**Payload markers.** `{}` `[]` `#` `Aa` `hex` beside each topic name.

**Data contracts.** Segments starting with an underscore are tinted, the
UNS convention for `_historian` and `_process`.

**Live values.** Any branch lists its direct children by what changed most
recently, with a switch for the last ten seconds only.

**Diagnostics.** A session log, and JSON export or import of connections.
Passwords stay in the Keychain.

## Layout

Three columns instead of a bottom dock: tree, details, charts. Last
message, QoS and retained state share one status line. Settings is split
into General, Broker and Diagnostics.

## Limits

| | Behaviour |
|---|---|
| Above 5,000 topics | Auto-expand stops |
| Above 8,000 topics | Offers to collapse or search |
| Above 100,000 topics | New topics refused, count reported |
| Merge falls behind | Dropped messages shown in the status bar |

## Bugs fixed

Found by reading the upstream tracker and checking whether the same defect
existed here.

- Messages could reach the tree out of order, leaving a topic on a stale
  value
- A topic deleted and republished within the same quarter second vanished
  for the session
- A rejected subscription showed as an empty tree with no explanation
- Retained state was lost on the first live publish under MQTT 3.1.1
- Charts kept pointing at topics cleared while paused
- Copy and Save did nothing on binary payloads
- The status bar could name a broker other than the connected one

## Not ported

| | Status |
|---|---|
| [Sparkplug B](https://sparkplug.eclipse.org/) decoding | Planned |
| [Last will messages](https://mqtt.org/) | Planned |
| The AI assistant | Not planned |
| Windows and Linux | Not planned, use the original |

## License

CC BY-ND 4.0, same as the original. Original MQTT Explorer by Thomas
Nordquist. macOS version by Luke van Enkhuizen.
