import SwiftUI
import AppKit

/// The connection setup, shown while not connected: a profile list on the
/// left, native grouped settings forms on the right.
struct ConnectionSetupView: View {
    @Bindable var model: AppModel

    @State private var draft = ConnectionProfile()
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var portText = "1883"
    @State private var pane: Pane = .connection
    @State private var newTopic = ""
    @State private var newQos = 0

    enum Pane {
        case connection
        case advanced
        case certificates
    }

    var body: some View {
        HStack(spacing: 0) {
            profileList
                .frame(width: 260)
            Divider()
            form
        }
        .task(id: model.selectedProfileId) {
            loadDraft()
        }
    }

    private func loadDraft() {
        guard let profile = model.selectedProfile else { return }
        draft = profile
        password = KeychainStore.password(for: profile.id) ?? ""
        portText = String(profile.port)
        pane = .connection
    }

    private var connecting: Bool {
        model.phase == .connecting
    }

    private var connectionURL: String {
        let basePath = draft.basePath.isEmpty ? "" : draft.basePath
        return "\(draft.transport.rawValue)://\(draft.host):\(draft.port)/\(basePath)"
    }

    // MARK: Left side - profile list

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()
                Button {
                    model.addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add connection")
            }
            .padding(10)

            Divider()

            List(selection: $model.selectedProfileId) {
                ForEach(model.profiles) { profile in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name.isEmpty ? "mqtt broker" : profile.name)
                            .lineLimit(1)
                        Text("\(profile.transport.rawValue)://\(profile.host):\(profile.port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(profile.id)
                    .onTapGesture(count: 2) {
                        connect()
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: Right side - the form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MQTT Connection")
                    .font(.title3.bold())
                Text(connectionURL)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            Divider()

            switch pane {
            case .connection: connectionPane
            case .advanced: advancedPane
            case .certificates: certificatesPane
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity)
        .onKeyPress(.escape) {
            model.disconnect()
            return .handled
        }
    }

    // MARK: Connection pane

    private var connectionPane: some View {
        Form {
            Section("Connection") {
                TextField("Name", text: $draft.name, prompt: Text("My MQTT Connection"))

                Toggle(isOn: $draft.certValidation) {
                    Text("Validate certificate (\(draft.certValidation ? "On" : "Off"))")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $draft.encryption) {
                    Text("Encryption (tls) (\(draft.encryption ? "On" : "Off"))")
                }
                .toggleStyle(.checkbox)

                Picker("Protocol", selection: $draft.transport) {
                    Text("mqtt://(Standard)").tag(TransportProtocol.mqtt)
                    Text("ws://(WebSocket)").tag(TransportProtocol.ws)
                }
                .help("Use 'mqtt' for standard connections or 'ws' for WebSocket connections")
                .onChange(of: draft.transport) { _, transport in
                    if transport == .ws && draft.basePath.isEmpty {
                        draft.basePath = "ws"
                    } else if transport == .mqtt {
                        draft.basePath = ""
                    }
                }

                TextField("Host", text: $draft.host, prompt: Text("broker.example.com"))

                LabeledContent("Port") {
                    TextField("Port", text: $portText, prompt: Text("1883"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .onChange(of: portText) { _, text in
                            if let value = Int(text), (1...65535).contains(value) {
                                draft.port = value
                            }
                        }
                }

                if draft.transport == .ws {
                    TextField("Basepath", text: $draft.basePath, prompt: Text("ws"))
                }
            }

            Section("Credentials") {
                TextField("Username", text: $draft.username, prompt: Text("Optional"))

                LabeledContent("Password") {
                    HStack(spacing: 4) {
                        Group {
                            if passwordVisible {
                                TextField("Optional", text: $password)
                            } else {
                                SecureField("Optional", text: $password)
                            }
                        }
                        Button {
                            passwordVisible.toggle()
                        } label: {
                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Advanced pane

    private var advancedPane: some View {
        Form {
            Section("Topics to subscribe") {
                HStack(spacing: 6) {
                    TextField("example/topic", text: $newTopic)
                    Picker("", selection: $newQos) {
                        Text("QoS 0").tag(0)
                        Text("QoS 1").tag(1)
                        Text("QoS 2").tag(2)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90)
                    Button("Add") {
                        guard !newTopic.isEmpty else { return }
                        draft.subscriptions.append(SubscriptionConfig(topic: newTopic, qos: newQos))
                        newTopic = ""
                    }
                }

                ForEach(draft.subscriptions) { subscription in
                    HStack {
                        Button {
                            draft.subscriptions.removeAll { $0.id == subscription.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        Text(subscription.topic)
                            .lineLimit(1)
                        Spacer()
                        Text("QoS \(subscription.qos)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Client") {
                TextField("MQTT Client ID", text: $draft.clientId, prompt: Text("Client ID"))

                Picker("MQTT Version", selection: $draft.mqttVersion) {
                    ForEach(MqttProtocolVersion.allCases, id: \.self) { version in
                        Text(version.label).tag(version)
                    }
                }
            }

            Section {
                HStack(spacing: 8) {
                    Button {
                        pane = .certificates
                    } label: {
                        Label("Certificates", systemImage: "lock")
                    }
                    .help("Manage tls connection certificates")

                    Button("Back") {
                        pane = .connection
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Certificates pane

    private var certificatesPane: some View {
        Form {
            Section("Certificates") {
                certificateSelector(
                    title: "Server Certificate (CA)",
                    value: $draft.selfSignedCertificate
                )
                certificateSelector(
                    title: "Client Certificate",
                    value: $draft.clientCertificate
                )
                certificateSelector(
                    title: "Client Key",
                    value: $draft.clientKey
                )
            }

            Section {
                Button("Back") {
                    pane = .advanced
                }
            }
        }
        .formStyle(.grouped)
    }

    private func certificateSelector(title: String, value: Binding<CertificateData?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .font(.caption)
            HStack(spacing: 6) {
                Button {
                    if let file = FileDialogs.openFileData() {
                        value.wrappedValue = CertificateData(name: file.name, data: file.data)
                    }
                } label: {
                    Label("Select certificate", systemImage: "lock")
                }
                if let certificate = value.wrappedValue {
                    Text(certificate.name)
                        .lineLimit(1)
                    Button {
                        value.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Footer (Delete / Advanced / Save / Connect)

    private var footer: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                deleteProfile()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete connection")

            Spacer()

            if pane == .connection {
                Button("Advanced") {
                    pane = .advanced
                }
                .help("Advanced connection settings")
            }
            Button("Save") {
                save()
            }
            .help("Save connection settings")

            connectButton
        }
        .padding(12)
    }

    private var connectButton: some View {
        Button {
            if connecting {
                model.disconnect()
            } else {
                connect()
            }
        } label: {
            if connecting {
                Label("Cancel", systemImage: "xmark")
            } else {
                Label("Connect", systemImage: "power")
            }
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!connecting && draft.host.isEmpty)
    }

    // MARK: Actions

    private func save() {
        model.updateProfile(draft)
        model.savePassword(password, for: draft.id)
    }

    private func connect() {
        save()
        model.connect()
    }

    private func deleteProfile() {
        let profile = draft
        Task {
            let confirmed = await model.requestConfirmation(
                title: "Delete Connection",
                message: """
                Are you sure you want to delete the connection "\(profile.name)"?

                This action cannot be undone.
                """
            )
            if confirmed {
                model.deleteProfile(profile.id)
                loadDraft()
            }
        }
    }
}
