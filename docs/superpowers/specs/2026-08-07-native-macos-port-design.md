# Native macOS port of MQTT Explorer — design

Date: 2026-08-07
Status: approved by mandate (goal session, no permission loops)

## Goal

A native Apple Silicon version of MQTT Explorer with the same functionality as the
Electron desktop app, optimized for performance and macOS look-and-feel. macOS only.
Not a light version: full desktop feature parity.

Rejected prior art:

- Upstream PR #1103: Electron dependency bump, not native.
- `raulriverouria/mqtt-explorer-swift`: 3k-line generated snapshot, license-incompatible
  (Apache-2.0 vs upstream CC-BY-SA-4.0), missing charts/hex/binary handling. Used only as
  independent confirmation of the library choice.

Scope calls made this session (user directives):

- LLM assistant: out. It only ever worked in upstream browser/server mode anyway.
- Sparkplug B decoding: optional, deferred.
- MQTT 5.0: required. Protocol version selectable per connection (default 5.0, 3.1.1
  available).

## Stack (checked against 2026 state of play)

- Swift 6 + SwiftUI, deployment target macOS 15.0, arm64 (M-series).
- `swift-server-community/mqtt-nio` v2.13.x stable (Feb 2026 release line):
  MQTT 3.1.1 + 5.0, TLS via NIOSSL, WebSocket transport. The v3.0 structured-concurrency
  rewrite is alpha (June 2026); revisit when stable, API surface changes are contained
  in MqttClientManager.
- Swift Charts for numeric topic plots.
- 2026 SwiftUI practice: `@Observable` classes injected via `.environment`, lazy stacks
  with stable IDs, per-node observation so a payload update invalidates one row.
- No Electron, no JS, no node.

## Repo layout

The Electron app stays untouched. New work lives in `macos/`:

```
macos/
  Package.swift                 # SwiftPM executable + test target
  Sources/MQTTExplorer/
  Tests/TopicTreeTests/
  make-app.sh                   # swift build -c release -> build/MQTT Explorer.app
```

Bundle id `com.sheetmetalconnect.mqttexplorer`, icon reuses `res/icon.icns`.
Ad-hoc codesign, no sandbox (direct distribution; revisit for notarized distribution).

## Architecture

Four layers, mirroring the Electron split (backend model + frontend rendering), collapsed
into one process.

1. **MqttClientManager** — wraps MQTTNIO. Async connect/disconnect/publish/subscribe,
   protocol version 3.1.1/5.0, TLS with CA/client-cert/key (PEM/DER files via
   NSOpenPanel), state machine: disconnected / connecting / connected / error. Incoming
   publishes are handed to the ingestion buffer on the NIO event loop, never parsed on
   the main thread.

2. **Ingestion + TopicTree** — the performance core.
   - Incoming messages collect in a lock-protected buffer (topic, payload Data, qos,
     retain, received-at).
   - A 250 ms flush task drains the buffer into the tree off the main actor, applying
     the same semantics as `backend/src/Model/Tree`:
     - topic split on `/` into edges
     - message count, lastUpdate, last payload + history ring (2000 messages) per node
     - merge into existing nodes; empty payload on empty leaf removes the node
       (this is how topic deletion via empty retained publish works)
     - payloads > 20000 bytes truncated, same as the Electron backend
   - Only nodes that changed get flagged; SwiftUI observes per-node `@Observable`
     classes so a payload update re-renders one row, not the tree.

3. **SettingsStore** — connection profiles + app settings as JSON in
   `~/Library/Application Support/MQTT Explorer/settings.json` (same mental model as the
   Electron lowdb file). Broker passwords go to the Keychain
   (kSecClassGenericPassword, one item per profile id), never to the JSON.

4. **SwiftUI frontend** — layout matches the Electron app, controls are native:
   - Left pane, top: connection panel (collapsible). Profile list (add/remove),
     connection form: name, host, port, protocol mqtt/ws, encryption toggle, cert
     validation, username, password, clientId, MQTT version, subscriptions list with
     QoS, certificate file pickers. Connect/disconnect button + status indicator.
   - Left pane, bottom: live topic tree. Rows show segment name, message count,
     last-update age; disclosure triangles; update flash (settings toggle); arrow-key
     navigation; topic filter field (Cmd-F).
   - Right sidebar (when a topic is selected): breadcrumb path, value renderer
     (pretty JSON with syntax colors / plain text / hex+ASCII for binary), diff/raw
     display mode, copy, save to file, message history list, publish form (topic
     prefilled, payload, QoS 0/1/2, retain), delete topic + recursive delete, chart
     toggle for numeric topics.
   - Toolbar/menus: pause/resume, clear old topics, settings (theme light/dark/system,
     topic order none/messages/abc/topics, highlight updates, auto-expand limit,
     value renderer display mode), connection health indicator.

## Feature parity

v1: everything in the layout bullets above, MQTT 5.0 default, charts, Keychain
credential storage.

Deferred (documented): Sparkplug B decoding (optional per user), auto-updater
(Sparkle candidate), notarization/distribution packaging, MQTTNIO v3 upgrade.

## Performance notes

- Batched ingestion (250 ms) instead of per-message UI updates; same trick as the
  Electron app's 300 ms interval, but merge work runs off the main thread.
- Per-node observation -> minimal SwiftUI invalidation.
- Payloads stay `Data` until display; string conversion only for the selected node.
- Expectation: handles `#` on a busy broker without UI stalls, <100 MB resident where
  Electron sits >500 MB.

## Testing

- SwiftPM tests for TopicTree: insert/merge, message counting, retained-empty removal,
  path lookup, leaf cleanup, truncation.
- `swift build -c release` must be green on arm64.
- Smoke test against a local mosquitto (`brew install mosquitto`) if available,
  else `mqtt.eclipseprojects.io`.
