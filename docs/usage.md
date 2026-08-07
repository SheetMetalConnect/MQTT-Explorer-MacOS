# Using MQTT Explorer for macOS

## Installation

Open the DMG and drag MQTT Explorer to Applications.

The app is ad-hoc codesigned, not notarized. The first time macOS blocks it
("cannot be opened because the developer cannot be verified"), right-click
the app in Finder, choose Open, and confirm. Alternatively:

```sh
xattr -dr com.apple.quarantine "/Applications/MQTT Explorer.app"
```

## Connecting to a broker

On startup you see the connection setup. Add a connection:

- **Name**, **Host**, **Port** (defaults: 1883 plain, 8883 TLS)
- **Encryption (tls)** toggles TLS, with optional certificate validation
- **Protocol**: `mqtt://` (standard) or `ws://` (WebSocket, with basepath)
- **Username / password** if the broker requires authentication
- **Subscriptions**: the topics to subscribe to, each with its own QoS
  (0/1/2). `#` subscribes to everything
- **MQTT Version**: 5.0 (default) or 3.1.1, plus an optional client ID

Connections are stored as profiles, so you can keep several brokers
(homelab, staging, production) and switch between them. While connected the
app reconnects automatically when the connection drops.

## The topic tree

The main window shows every topic as a tree, updated live as messages
arrive.

- Type in the filter field (or press Cmd-F) to narrow the tree by topic
  name
- The two buttons right of the filter expand or collapse the entire tree
- Click a topic to open it in the sidebar
- The status bar at the bottom shows the connection state, broker address
  and the total number of topics and messages

Pause with `p` (or the toolbar button) to freeze the tree; changes keep
recording into a buffer and are applied when you resume.

On a busy broker the tree stops expanding automatically past 5000 topics,
and Expand All refuses rather than opening tens of thousands of rows. Use
the filter to narrow down first. If messages ever arrive faster than they
can be merged, the status bar reports how many were dropped instead of
letting memory grow without bound.

## The Details tab

Selecting a topic shows, top to bottom:

- **Breadcrumb**: the full topic path, with copy and delete. Deleting
  publishes an empty payload to the topic; on a topic with children it
  clears the whole subtree
- **Status bar**: time of the last message, QoS, and the retained state.
  A retained message is marked in orange with a pin; the x next to it
  clears the retained message
- **Current value**: the latest payload, in one of three modes. Diff
  highlights what changed against the previous message. Raw shows the full
  payload as highlighted JSON, text or hex. Value appears whenever the
  payload holds numbers and charts them: a single number gets a live trend
  plot, a JSON object gets one row per numeric field with its own sparkline
  plus a ring showing each field's share, and a numeric array gets a bar
  chart. Copy and save buttons sit on the right and fall back to a hex dump
  or the raw bytes for binary payloads
- **History**: expand to see previous messages, newest first. Click a
  message to select it as the diff reference and view its payload; numeric
  messages get a sparkline and a chart button
- **Statistics**: message count, subtopic count and the total across the
  subtree

## The Publish tab

Publish a message to any topic: enter the topic, the payload, QoS and
whether the message should be retained. Handy for testing actuators or
clearing retained values by publishing an empty retained payload.

## Charts

Numeric values can be plotted. In the Details tab, click the chart icon on
a message, or use the value preview. Charts appear in the panel below the
tree. Per chart you can:

- Pause/resume the plot
- Set Y-axis (value) and X-axis (time window) ranges
- Choose curve interpolation, line color and width
- Hover for the exact time and value

## Settings

Open Settings from the toolbar slider or the app menu. You can switch
between system, light and dark appearance, and configure formatting of
timestamps.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd-F | Focus the topic filter |
| p | Pause / resume tree updates |
| Cmd-, | Settings |
| Cmd-Q | Quit (asks for confirmation while connected) |
