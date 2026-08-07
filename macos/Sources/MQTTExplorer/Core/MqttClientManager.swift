import Foundation
import MQTTNIO
import NIOCore
import NIOSSL
import NIOPosix
import Logging

/// Connection lifecycle events surfaced to the UI as an AsyncStream.
enum MqttClientEvent: Sendable {
    case connecting
    case connected
    case reconnecting
    case disconnected(reason: String?)
    case error(String)
}

/// Wraps MQTTNIO. Incoming messages land in a MessageInbox on the NIO event
/// loop, preserving wire order; only lifecycle events go to the UI.
actor MqttClientManager {
    private var client: MQTTClient?
    private let group: MultiThreadedEventLoopGroup
    private var reconnectTask: Task<Void, Never>?
    private var userInitiatedDisconnect = false

    init() {
        // Two threads: one for IO, one spare for TLS handshakes etc.
        group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }

    func connect(
        profile: ConnectionProfile,
        password: String?,
        inbox: MessageInbox
    ) -> AsyncStream<MqttClientEvent> {
        userInitiatedDisconnect = false
        let (stream, continuation) = AsyncStream<MqttClientEvent>.makeStream()
        continuation.yield(.connecting)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.runConnectionLoop(profile: profile, password: password, inbox: inbox, continuation: continuation)
        }
        return stream
    }

    func disconnect() async {
        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        await tearDownClient()
    }

    func publish(topic: String, payload: Data, qos: Int, retain: Bool) async throws {
        guard let client else { throw MqttManagerError.notConnected }
        var buffer = ByteBufferAllocator().buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        let level = MQTTQoS(rawValue: UInt8(qos)) ?? .atMostOnce
        try await client.publish(to: topic, payload: buffer, qos: level, retain: retain)
    }

    func shutdown() async {
        await disconnect()
        try? await group.shutdownGracefully()
    }

    // MARK: - Internals

    private func runConnectionLoop(
        profile: ConnectionProfile,
        password: String?,
        inbox: MessageInbox,
        continuation: AsyncStream<MqttClientEvent>.Continuation
    ) async {
        var firstAttempt = true
        while !Task.isCancelled {
            do {
                try await connectOnce(profile: profile, password: password, inbox: inbox, continuation: continuation)
                continuation.yield(.connected)

                // Wait until the connection drops again.
                await waitForClose()

                if userInitiatedDisconnect || Task.isCancelled {
                    break
                }
                continuation.yield(.reconnecting)
                // Brief pause before reconnecting.
                try await Task.sleep(for: .seconds(3))
                continuation.yield(.connecting)
            } catch {
                continuation.yield(.error(error.localizedDescription))
                if firstAttempt {
                    // Likely a configuration/auth problem: don't hammer the
                    // broker, the user needs to fix the profile. (Same
                    // reasoning as not retrying AD auth in a loop.)
                    break
                }
                if Task.isCancelled { break }
                continuation.yield(.reconnecting)
                try? await Task.sleep(for: .seconds(5))
            }
            firstAttempt = false
        }
        continuation.finish()
    }

    private func connectOnce(
        profile: ConnectionProfile,
        password: String?,
        inbox: MessageInbox,
        continuation: AsyncStream<MqttClientEvent>.Continuation
    ) async throws {
        await tearDownClient()

        let tlsConfig: MQTTClient.TLSConfigurationType? = profile.encryption
            ? .niossl(try buildTLSConfig(profile: profile))
            : nil

        let wsPath: String? = profile.transport == .ws
            ? (profile.basePath.isEmpty ? "/mqtt" : (profile.basePath.hasPrefix("/") ? profile.basePath : "/" + profile.basePath))
            : nil

        let configuration = MQTTClient.Configuration(
            version: profile.mqttVersion == .v5_0 ? .v5_0 : .v3_1_1,
            keepAliveInterval: .seconds(60),
            connectTimeout: .seconds(15),
            userName: profile.username.isEmpty ? nil : profile.username,
            password: password?.isEmpty == false ? password : nil,
            useSSL: profile.encryption,
            useWebSockets: profile.transport == .ws,
            tlsConfiguration: tlsConfig,
            webSocketURLPath: wsPath
        )

        let client = MQTTClient(
            host: profile.host,
            port: profile.port,
            identifier: profile.clientId,
            eventLoopGroupProvider: .shared(group),
            logger: Logger(label: "mqtt-explorer"),
            configuration: configuration
        )
        self.client = client

        // Messages go straight to the tree engine, off the main thread.
        client.addPublishListener(named: "explorer") { result in
            switch result {
            case .success(let publish):
                var buffer = publish.payload
                let data = buffer.readData(length: buffer.readableBytes) ?? Data()
                inbox.append(
                    IncomingMessage(
                        topic: publish.topicName,
                        payload: data,
                        qos: Int(publish.qos.rawValue),
                        retain: publish.retain,
                        received: Date()
                    )
                )
            case .failure:
                break
            }
        }

        let closed = AsyncStream<Void>.makeStream()
        client.addCloseListener(named: "explorer-close") { _ in
            closed.continuation.yield(())
            closed.continuation.finish()
        }
        self.closeSignal = closed.stream

        try await client.connect()

        let subscriptions = profile.subscriptions.isEmpty
            ? [SubscriptionConfig(topic: "#", qos: 0)]
            : profile.subscriptions
        let infos = subscriptions.map {
            MQTTSubscribeInfo(topicFilter: $0.topic, qos: MQTTQoS(rawValue: UInt8($0.qos)) ?? .atMostOnce)
        }
        let suback = try await client.subscribe(to: infos)
        let rejected = zip(infos, suback.returnCodes)
            .filter { if case .failure = $0.1 { return true } else { return false } }
            .map(\.0.topicFilter)
        if !rejected.isEmpty {
            continuation.yield(.error("Broker rejected subscription: \(rejected.joined(separator: ", "))"))
        }
    }

    private var closeSignal: AsyncStream<Void>?

    private func waitForClose() async {
        guard let closeSignal else { return }
        for await _ in closeSignal {
            break
        }
    }

    private func tearDownClient() async {
        guard let client else { return }
        client.removePublishListener(named: "explorer")
        client.removeCloseListener(named: "explorer-close")
        closeSignal = nil
        try? await client.disconnect()
        // MQTTNIO requires an explicit shutdown before the client is
        // released, otherwise its deinit traps.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            client.shutdown { _ in
                continuation.resume()
            }
        }
        self.client = nil
    }

    private func buildTLSConfig(profile: ConnectionProfile) throws -> TLSConfiguration {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = profile.certValidation ? .fullVerification : .none

        if let ca = profile.selfSignedCertificate, !ca.data.isEmpty {
            tls.trustRoots = .certificates([try parseCertificate(ca)])
        }
        if let cert = profile.clientCertificate, !cert.data.isEmpty,
           let key = profile.clientKey, !key.data.isEmpty {
            let chain = [try parseCertificate(cert)]
            let keyFormat: NIOSSLSerializationFormats = key.isPEM ? .pem : .der
            let privateKey = try NIOSSLPrivateKey(bytes: [UInt8](key.data), format: keyFormat)
            tls.certificateChain = chain.map { NIOSSLCertificateSource.certificate($0) }
            tls.privateKey = .privateKey(privateKey)
        }
        return tls
    }

    private func parseCertificate(_ certificate: CertificateData) throws -> NIOSSLCertificate {
        try NIOSSLCertificate(
            bytes: [UInt8](certificate.data),
            format: certificate.isPEM ? .pem : .der
        )
    }
}

enum MqttManagerError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to a broker."
        }
    }
}
