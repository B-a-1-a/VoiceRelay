import Foundation
import Network
import UniversalVoiceProtocol

final class Server: @unchecked Sendable {
    enum ServerState: Sendable, Equatable {
        case idle
        case listening(port: UInt16)
        case handshaking
        case connected
        case failed(String)
    }

    private let queue = DispatchQueue(label: "dev.balashukla.voicerelay.helper.server")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var session: SessionCrypto?
    private var pendingSalt: Data?
    private var psk: Data?
    private var portInUse: UInt16 = 0
    private(set) var state: ServerState = .idle

    var onMessage: (@Sendable (Message) -> Void)?
    var onStateChange: (@Sendable (ServerState) -> Void)?

    func start(
        port: UInt16,
        psk: Data,
        advertiseName: String?,
        deviceUUID: String?
    ) throws {
        stop()
        self.psk = psk
        self.portInUse = port

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        parameters.includePeerToPeer = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        if let advertiseName, let deviceUUID {
            var txt = NWTXTRecord()
            txt["uuid"] = deviceUUID
            txt["v"] = "1"
            listener.service = NWListener.Service(
                name: advertiseName,
                type: BonjourService.type,
                domain: nil,
                txtRecord: txt
            )
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        listener.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.update(state: .listening(port: port))
            case .failed(let err):
                self?.update(state: .failed(String(describing: err)))
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        session = nil
        pendingSalt = nil
        update(state: .idle)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        if let existing = self.connection {
            existing.cancel()
        }
        self.connection = connection
        self.session = nil
        self.pendingSalt = nil
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                self?.update(state: .handshaking)
                self?.receive(on: connection)
            case .failed(let err):
                self?.update(state: .failed(String(describing: err)))
            case .cancelled:
                self?.update(state: self?.listener != nil
                    ? .listening(port: self?.portInUse ?? HelperConfig.listenPort)
                    : .idle
                )
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handleFrame(data, on: connection)
            }
            if error == nil && connection.state == .ready {
                self.receive(on: connection)
            }
        }
    }

    private func handleFrame(_ data: Data, on connection: NWConnection) {
        if session == nil {
            // Awaiting handshake.
            do {
                let clientFrame = try HandshakeCodec.decode(data)
                let serverSalt = SessionCrypto.freshSalt()
                guard let psk else {
                    update(state: .failed("PSK missing"))
                    connection.cancel()
                    return
                }
                let key = SessionCrypto.deriveSessionKey(
                    psk: psk,
                    saltInitiator: clientFrame.salt,
                    saltResponder: serverSalt
                )
                session = SessionCrypto(key: key, role: .responder)
                let response = HandshakeCodec.encode(HandshakeFrame(salt: serverSalt))
                let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                let context = NWConnection.ContentContext(
                    identifier: "uv-handshake",
                    metadata: [metadata]
                )
                connection.send(content: response, contentContext: context, isComplete: true,
                                completion: .contentProcessed { _ in })
                update(state: .connected)
            } catch {
                NSLog("Handshake failed: \(error)")
                connection.cancel()
            }
            return
        }
        do {
            guard let message = try session?.open(data) else { return }
            onMessage?(message)
        } catch {
            NSLog("Decryption failed: \(error)")
            connection.cancel()
        }
    }

    private func update(state: ServerState) {
        self.state = state
        onStateChange?(state)
    }
}
