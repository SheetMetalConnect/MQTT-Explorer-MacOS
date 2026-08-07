# MQTT Explorer for macOS

Native build for Apple Silicon. SwiftUI on macOS 15, MQTT 3.1.1 and 5.0
(via mqtt-nio), TLS and WebSocket transports, topic tree with pause and
search, payload diff view, publish tab with history, charts, light and
dark mode.

## Build

Requires Xcode with the macOS 15 SDK.

```
./make-app.sh
```

Produces `build/MQTT Explorer.app` (ad-hoc signed).

## Tests

```
swift test
```

The live-broker test connects to localhost:1883 and skips itself when no
broker is running.

## License

Same terms as this repository, see `LICENSE.md` in the root
(CC BY-ND 4.0). Original MQTT Explorer by Thomas Nordquist.
macOS version by Luke van Enkhuizen.
