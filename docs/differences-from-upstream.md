# What changed compared to the original

The original [MQTT Explorer](https://mqtt-explorer.com) by Thomas Nordquist
is an Electron app: Chromium, Node and a React frontend talking to a Node
backend over IPC. This is a rewrite in Swift and SwiftUI. No shared code,
no bundled browser, one binary for Apple Silicon.

The feature set is the same. What follows is where the two genuinely
differ.

## Native instead of Electron

| | Original | This build |
|---|---|---|
| Runtime | Electron (Chromium + Node) | Swift binary, arm64 |
| UI | React + Material UI | SwiftUI |
| Download | ~90 MB installer | ~5 MB DMG |
| Appearance | Its own theme | System light and dark, real macOS controls |

Practical effects: it launches immediately, holds a fraction of the memory,
respects your appearance and accent color, and behaves like a Mac app.
Standard controls pick up Liquid Glass on macOS 26.

## How the topic tree is built

The original merges messages into the tree on the main thread every 300 ms.
Under load that is what freezes the window.

Here the tree lives in a Swift actor off the main thread. Messages land in
a lock-guarded inbox straight from the network event loop, so wire order is
preserved, and the merge happens away from the UI. Four times a second the
main thread picks up a delta of what actually changed and touches only
those rows. Message and topic totals are tracked as they change instead of
being recounted by walking the tree.

The result is that a busy public broker is usable rather than a hang.

## Value mode

Both apps render payloads as JSON, text or a hex dump, and both diff the
current message against the previous one.

This build adds a third mode for payloads that hold numbers:

- a single number gets a live trend plot and the change since the last
  message
- a JSON object gets one row per numeric field, each with a sparkline, plus
  a ring showing how the fields divide the total
- a numeric array gets a bar chart

The mode only appears when there is something numeric to draw. Anything
plotted can still be pinned to the chart panel.

## Limits on large brokers

The original will happily try to expand a hundred thousand topics.

Here, auto-expansion stops above 5000 topics and Expand All declines rather
than opening tens of thousands of rows, telling you to filter first.
Topics are capped at 100k. When messages arrive faster than they can be
merged, the status bar reports how many were dropped instead of letting
memory grow until the process dies.

## Bugs fixed along the way

Several of these came from reading the upstream issue tracker, checking
whether the same defect existed here, and fixing the ones that did.

- Messages could reach the tree out of order, so a topic occasionally
  settled on a stale value.
- A topic deleted and republished within the same quarter second vanished
  for the rest of the session.
- A subscription the broker rejected showed up as an empty tree with no
  explanation.
- Retained state was lost on the first live publish under MQTT 3.1.1, where
  the broker clears the flag.
- Charts kept pointing at topics that had been cleared while the tree was
  paused.
- Copy and Save did nothing on a binary payload.
- The status bar could name a different broker than the one connected.

## Not included

- **Sparkplug B decoding.** The original decodes it. Deferred here.
- **The AI assistant.** Deliberately left out.
- **Windows and Linux.** This build is macOS only. Use the original.

## Licensing

Same license as the original, CC BY-ND 4.0. The original MQTT Explorer is
by Thomas Nordquist; this macOS version is by Luke van Enkhuizen.
