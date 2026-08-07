# Using MQTT Explorer for macOS

## Install

Open the DMG, drag MQTT Explorer to Applications.

The app is signed ad-hoc rather than notarized, so the first launch gets
blocked. Right-click it in Finder, choose Open, confirm. Or clear the flag
yourself:

```sh
xattr -dr com.apple.quarantine "/Applications/MQTT Explorer.app"
```

## Connecting

Add a connection on the start screen:

- **Host** and **port**. 1883 plain, 8883 with TLS.
- **Encryption (tls)** turns on TLS, with optional certificate validation.
- **Protocol**: `mqtt://` or `ws://` for WebSocket, which takes a basepath.
- **Username and password** if the broker wants them. Passwords go to the
  Keychain, not the config file.
- **Subscriptions**: which topics to watch, each with its own QoS. `#` gets
  everything.
- **MQTT version**: 5.0 by default, 3.1.1 if you need it, plus an optional
  client ID.

Connections are saved as profiles, so a homelab broker and a production one
sit side by side. A dropped connection reconnects on its own.

If the broker refuses a subscription you get told, rather than staring at
an empty tree.

## The tree

Topics appear as they arrive.

- Type in the filter, or hit Cmd-F to jump to it.
- The two buttons next to it expand or collapse everything.
- Click a topic to open it on the right.
- The bar along the bottom shows the connection, the broker you are
  actually attached to, and how many topics and messages are in the tree.

Press `p` to freeze the tree. Changes keep recording while paused and get
applied when you resume.

On a large broker the tree stops auto-expanding past 5000 topics, and
Expand All will refuse rather than open tens of thousands of rows. Filter
first. If messages ever come in faster than they can be merged, the status
bar says how many were dropped.

## Reading a topic

The workspace drills left to right: the tree picks a topic, the middle panel
inspects it, and charts stack up on the right as you add them.

Selecting a topic gives you, top to bottom:

**The path**, with a chart button, copy and delete. The chart button plots
everything measurable at once, whether the numbers arrive as fields of a
single JSON payload or as separate child topics. Delete publishes an empty
payload, which is how you clear a retained message. On a topic with children
it clears the whole subtree.

**A status line**: when the last message landed, its QoS, and whether the
value is retained. Retained shows in orange with a pin, and the x beside it
clears the value on the broker.

**The value**, in one of three modes:

- *Diff* highlights what changed against the previous message.
- *Raw* shows the payload as it arrived, as highlighted JSON, text or a hex
  dump.
- *Value* appears when the payload holds numbers, and charts them. One
  number gets a trend plot. A JSON object gets a row per numeric field with
  its own sparkline, plus a ring showing how the fields divide the total. A
  numeric array gets a bar chart.

Copy and Save sit on the right and handle binary payloads too.

**Live values**, on any topic with children. A table of the direct children
sorted by what changed most recently, with the current value, the time and
the message count. Flip on Recent only and it narrows to what moved in the
last ten seconds, which is how you find the one sensor that is actually
reporting inside a branch of two hundred. Click a row to jump to it.

**History**, newest first. Click a message to diff against it and see its
payload. Numeric messages get a sparkline and a button to chart them.

**Counts** for the topic and its subtree.

## Publishing

The Publish tab takes a topic, a payload, a QoS and a retain flag. Useful
for poking an actuator, or for clearing a retained value by publishing an
empty one.

## Charts

Click the chart button on any numeric value and it lands in the column on
the right. Per chart you can pause it, set the value and time ranges, and
change the interpolation and color. Hovering gives you the exact reading.

Charts are remembered per connection.

## Settings

In the toolbar, or Cmd-,. Appearance follows the system by default and can
be pinned to light or dark. Timestamp formatting lives here too.

## Shortcuts

| Key | Does |
|-----|------|
| Cmd-F | Jump to the filter |
| p | Freeze or resume the tree |
| Arrows | Move and expand in the tree |
| Delete | Clear the selected topic and its subtree |
| Cmd-, | Settings |
| Cmd-Q | Quit |
