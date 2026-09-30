import Foundation
import Network
import Combine

/// Capturely provider for the EnhancedPresence v1 local protocol.
@MainActor final class DiscordPresenceBridge: ObservableObject {
    static let shared = DiscordPresenceBridge()
    @Published var enabled = UserDefaults.standard.bool(forKey: "discordPresenceEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "discordPresenceEnabled")
            if enabled { start() } else { stop() }
        }
    }
    @Published private(set) var status = "Off"
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var startedAt: Int?
    private var payload = Data("{\"version\":1,\"type\":\"clear\"}".utf8)
    struct Activity: Codable {
        var appId = "com.capturely.app"
        var appName = "Capturely"
        var details: String
        var state = "Instant replay"
        var activityType = "PLAYING"
        var timestamps: Timestamps
        var source = "capturely"
        var confidence = 1.0
        struct Timestamps: Codable { var start: Int }
    }
    struct Message: Encodable { var version = 1; var type: String; var activity: Activity? }
    func update(_ capture: CaptureState) {
        var activity: Activity?
        switch capture {
        case .recording, .savingClip:
            if startedAt == nil { startedAt = Int(Date().timeIntervalSince1970) }
            let saving: Bool
            if case .savingClip = capture { saving = true } else { saving = false }
            activity = Activity(details: saving ? "Saving a replay" : "Buffering gameplay", timestamps: .init(start: startedAt!))
        default: startedAt = nil
        }
        guard let next = try? JSONEncoder().encode(Message(type: activity == nil ? "clear" : "activity", activity: activity)), next != payload else { return }
        payload = next
        if enabled { for client in clients.values { send(next, to: client) } }
    }
    func start() {
        guard enabled, listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 48731)
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.status = "Ready · 127.0.0.1:48731"
                    case .failed(let error): self?.status = error.localizedDescription; self?.listener?.cancel(); self?.listener = nil
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.start(queue: .main)
        } catch { status = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        guard enabled, clients.count < 4 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.send(self.payload, to: connection); self.status = "Plugin connected"
                case .cancelled, .failed:
                    self.clients.removeValue(forKey: id)
                    if self.enabled && self.clients.isEmpty { self.status = "Ready · waiting for plugin" }
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive(connection)
    }
    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] _, _, _, error in
            Task { @MainActor in
                if error != nil { connection.cancel() }
                else if self?.enabled == true { self?.receive(connection) }
            }
        }
    }
    private func send(_ data: Data, to connection: NWConnection, close: Bool = false) {
        let context = NWConnection.ContentContext(identifier: "presence", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if close || error != nil { connection.cancel() }
        })
    }
    private func stop() {
        for client in clients.values { send(Data("{\"version\":1,\"type\":\"clear\"}".utf8), to: client, close: true) }
        clients.removeAll()
        listener?.cancel()
        listener = nil
        status = "Off"
    }
}
