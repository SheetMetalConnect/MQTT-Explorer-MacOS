# Usage

- [Install](#install)
- [Connecting](#connecting)
- [The tree](#the-tree)
- [Reading a topic](#reading-a-topic)
- [Charts](#charts)
- [Publishing](#publishing)
- [Settings](#settings)
- [Shortcuts](#shortcuts)

## Install

Open the DMG, drag MQTT Explorer to Applications. Signed ad-hoc, not
notarized, so the first launch needs right-click, Open, confirm. Or:

```sh
xattr -dr com.apple.quarantine "/Applications/MQTT Explorer.app"
```

## Connecting

| Field | Notes |
|---|---|
| Host, port | 1883 plain, 8883 TLS |
| Encryption (tls) | Optional certificate validation |
| Protocol | `mqtt://` or `ws://`, which takes a basepath |
| Username, password | Passwords go to the Keychain |
| Subscriptions | One per line, each with its own QoS. `#` gets everything |
| MQTT version | 5.0 default, 3.1.1 available, plus an optional client ID |

Connections save as profiles. A dropped connection reconnects on its own.
A subscription the broker refuses is reported rather than leaving an empty
tree.

## The tree

| Action | How |
|---|---|
| Filter | Type in the field, or Cmd-F |
| Expand or collapse all | The two buttons beside the filter |
| Open a topic | Click it |
| Freeze updates | `p`. Changes keep recording and apply on resume |

The status bar shows the connected broker, topic and message counts, and a
warning if messages arrived faster than they could be merged.

Above 5,000 topics the tree stops auto-expanding. Above 8,000 it offers to
collapse or search instead.

## Reading a topic

Left to right: the tree picks a topic, the middle panel inspects it, charts
stack on the right.

**Path** with three buttons: chart everything measurable on the topic and
its children, copy, and delete. Delete publishes an empty payload, which
clears a retained message. On a branch it clears the whole subtree.

**Status line** with the time of the last message, its QoS, and retained
state. Retained shows in orange with a pin, and the x clears it on the
broker.

**Value** in one of three modes:

| Mode | Shows |
|---|---|
| Diff | What changed against the previous message |
| Raw | The payload as JSON fields, text, or a hex dump |
| Value | Numbers charted: a trend plot, per-field sparklines with a share ring, or a bar chart |

Copy and Save handle binary payloads.

**Live values** on any branch: direct children sorted by what changed most
recently, with value, time and message count. Recent only narrows to the
last ten seconds. Click a row to jump to it.

**History**, newest first. Click a message to diff against it. Numeric
messages get a sparkline and a chart button.

### Payload markers

| Marker | Payload |
|---|---|
| `{}` | JSON object |
| `[]` | JSON array |
| `#` | Number |
| `Aa` | Text |
| `hex` | Binary |

Topic segments starting with an underscore are tinted, following the UNS
convention for `_historian`, `_analytics` and similar. Both markers can be
turned off under Settings, Payloads.

## Charts

Any chart button sends a value to the right-hand column. Per chart: pause,
value and time ranges, interpolation, color. Hover for the exact reading.
Charts are remembered per connection.

## Publishing

The Publish tab takes a topic, payload, QoS and retain flag. Publishing an
empty retained payload clears a retained value.

## Settings

Cmd-, or the toolbar.

| Tab | Holds |
|---|---|
| General | Auto-expand by width and depth, payload markers, time locale, appearance |
| Broker | `$SYS` statistics, when the broker publishes them |
| Diagnostics | Session log, and JSON export or import of connections |

The export never contains passwords, and import merges rather than
overwrites.

## Shortcuts

| Key | Action |
|---|---|
| Cmd-F | Filter |
| `p` | Freeze or resume |
| Arrows | Move and expand |
| Delete | Clear topic and subtree |
| Cmd-, | Settings |
| Cmd-Q | Quit |
