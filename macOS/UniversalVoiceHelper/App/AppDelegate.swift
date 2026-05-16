import AppKit
import SwiftUI
import UniversalVoiceProtocol

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private let server = Server()
    private let poster = EventPoster(charactersPerSecond: HelperConfig.typingCharactersPerSecond)
    private let pskStore = PSKStore()
    private let typingQueue = DispatchQueue(label: "dev.balashukla.voicerelay.helper.typing")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let serviceName = pskStore.serviceName()
        let deviceUUID = pskStore.deviceUUID()

        let psk: Data
        do {
            psk = try pskStore.loadOrCreate()
        } catch {
            statusController = StatusItemController(
                pairing: nil,
                serverState: .failed("PSK storage failed: \(error)"),
                serviceName: serviceName
            )
            return
        }

        let payload = PairingPayload(
            serviceName: serviceName,
            deviceUUID: deviceUUID,
            pskBase64: psk.base64EncodedString(),
            port: HelperConfig.listenPort,
            hostHint: PrimaryAddress.firstNonLoopbackIPv4()
        )
        statusController = StatusItemController(
            pairing: payload,
            serverState: .idle,
            serviceName: serviceName
        )

        server.onMessage = { [weak self] message in
            DispatchQueue.main.async {
                self?.handle(message: message)
            }
        }
        server.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.statusController?.update(serverState: state)
            }
        }

        do {
            try server.start(
                port: HelperConfig.listenPort,
                psk: psk,
                advertiseName: serviceName,
                deviceUUID: deviceUUID
            )
        } catch {
            statusController?.update(serverState: .failed(error.localizedDescription))
        }
    }

    private func handle(message: Message) {
        switch message {
        case .text(let payload):
            typingQueue.async { [poster] in
                _ = poster.deliver(payload.content + (payload.isFinalUtterance ? " " : ""))
            }
        case .ping, .contextRequest, .contextResponse:
            break
        }
    }
}
