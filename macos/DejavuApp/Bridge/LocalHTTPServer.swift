import Foundation
import Network

@MainActor final class LocalHTTPServer {
    private var listener: NWListener?
    private var clients: [UUID: BridgeConnection] = [:]
    var onState: ((Bool, UInt16?) -> Void)?

    func start(port: UInt16, handler: @escaping @MainActor (BridgeRequest) async -> BridgeResponse) throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready: self.onState?(true, listener.port?.rawValue)
                case .failed: self.stop(); self.onState?(false, nil)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener, self.clients.count < 16,
                      case let .hostPort(host, _) = connection.endpoint, host == NWEndpoint.Host("127.0.0.1") else {
                    connection.cancel(); return
                }
                let id = UUID()
                let client = BridgeConnection(connection: connection, handler: handler) { [weak self] in self?.clients.removeValue(forKey: id) }
                self.clients[id] = client
                client.start()
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel(); listener = nil
        let old = clients.values
        clients.removeAll()
        for client in old { client.close() }
    }
}

@MainActor private final class BridgeConnection {
    private let connection: NWConnection
    private let handler: @MainActor (BridgeRequest) async -> BridgeResponse
    private let onClose: () -> Void
    private var buffer = Data()
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var closed = false
    private var responding = false

    init(connection: NWConnection, handler: @escaping @MainActor (BridgeRequest) async -> BridgeResponse, onClose: @escaping () -> Void) {
        self.connection = connection; self.handler = handler; self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed = state { self?.close() }
            }
        }
        connection.start(queue: .main)
        setDeadline(seconds: 10)
        receive()
    }

    private func setDeadline(seconds: Int) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.close()
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                do {
                    if let request = try BridgeHTTPParser.parse(self.buffer) {
                        self.buffer.removeAll()
                        self.setDeadline(seconds: 95)
                        self.work = Task { [weak self] in
                            guard let self else { return }
                            let response = await self.handler(request)
                            guard !Task.isCancelled else { return }
                            self.send(response)
                        }
                        self.watchDisconnect()
                    } else if complete || error != nil { self.close() }
                    else { self.receive() }
                } catch {
                    self.send(.error(error as? BridgeHTTPParser.Failure == .tooLarge ? 413 : 400,
                                     "invalid_http", "Некорректный HTTP-запрос."))
                }
            }
        }
    }

    private func watchDisconnect() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
            Task { @MainActor in
                guard let self, !self.responding else { return }
                self.close()
            }
        }
    }

    private func send(_ response: BridgeResponse) {
        guard !closed else { return }
        responding = true
        connection.send(content: response.wire, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
    }

    func close() {
        guard !closed else { return }
        closed = true
        work?.cancel(); work = nil
        deadline?.cancel(); deadline = nil
        buffer.removeAll()
        connection.cancel()
        onClose()
    }
}
