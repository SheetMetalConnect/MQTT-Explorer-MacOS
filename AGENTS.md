# Working in this repo

Swift package at `macos/`, no Xcode project. Everything below is enforced by
tests or by review; none of it is preference.

## The constraint

This fork exists because the Electron original stalls under load. Performance
comes before features and before looks. A change that risks the hot path does
not ship.

Hot paths, in order of how often they run:

1. `MqttClientManager` publish listener, once per message on the NIO event loop
2. `TopicTreeEngine.flush()`, four times a second
3. `UITreeModel.apply()`, four times a second on the main actor
4. `TopicRowView`, once per visible row per redraw

Anything called from these must not allocate per message, decode whole
payloads, or build a `DateFormatter`. Rows read precomputed values only.

## Layout

| Path | Holds |
|---|---|
| `Core/TopicTreeEngine.swift` | The actor. Merge, history, retained-delete cascade |
| `Core/MessageInbox.swift` | Lock-guarded hand-off from the event loop |
| `Core/UITree.swift` | `@Observable` mirror tree and the visible row list |
| `Core/AppModel.swift` | Flush loop, connection lifecycle, everything the views bind to |
| `Core/MqttClientManager.swift` | MQTTNIO wrapper |
| `Views/` | SwiftUI only. No parsing, no payload inspection |
| `Models/ConnectionProfile.swift` | Persisted profile shape |

Data flows one way: NIO → inbox → engine actor → delta → mirror tree → views.
Never reach back the other way.

## Rules that have bitten before

**`index` in `UITreeModel` is `@ObservationIgnored`.** Routing thousands of
inserts through the observation registrar is what caused a CPU-resource kill.

**Never pre-allocate per node.** `RingBuffer` grows on demand. It once
reserved 96 KB per node, including branch nodes with no payload.

**Rebuild rows only when the visible set changed.** A node added under a
collapsed parent changes nothing on screen.

**Preserve wire order.** One `Task` per message let messages race, so a topic
could settle on a stale payload. Messages go through `MessageInbox`.

**Cache formatters.** `DateFormatter` construction was the hottest frame in a
sample.

## Tests

```sh
cd macos && swift test
```

`TreePerformanceTests` holds the budgets: 10k topics apply under 2s, 2k
payload updates under a collapsed parent cause zero row rebuilds, a collapsed
10k tree exposes under 200 rows. Do not relax these to make a change pass.

`LiveBrokerTests` and `AppModelConnectTests` need a broker on
localhost:1883 and skip without one. `AppModelConnectTests` writes to the
real settings file, so it saves and restores it. Any new test touching
`AppModel` must do the same.

## Building

```sh
cd macos
./make-app.sh    # -> build/MQTT Explorer.app
./make-dmg.sh    # rebuilds, then packages
```

`make-app.sh` fails if the bundled binary is not the one just built. A stale
binary shipped once; the check exists so it cannot happen again.

## Style

Match the surrounding code. Comments explain why, never what. No comment on a
line that already reads clearly.

Copy that users see follows the rules in the repo owner's global
instructions: no em dashes, no AI vocabulary, no padding.

## Verifying

Claims about performance need a measurement, not an assumption. `sample <pid>`
against a running instance, or a benchmark. A test suite passing is not
evidence that a feature works in the app.
