import AppKit
import SwiftUI
import Combine
import UniversalVoiceProtocol

@MainActor
final class StatusItemController: ObservableObject {
    @Published var serverStateLabel: String = "Starting…"
    @Published var serverStateColor: NSColor = .systemGray
    @Published var serviceName: String
    @Published var qrImage: NSImage?
    @Published var pairingPayload: PairingPayload?

    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(pairing: PairingPayload?, serverState: Server.ServerState, serviceName: String) {
        self.serviceName = serviceName
        self.pairingPayload = pairing
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 420)

        if let pairing, let qrText = try? pairing.qrString() {
            qrImage = QRRenderer.image(for: qrText, size: 220)
        }

        let view = StatusItemView(controller: self)
        popover.contentViewController = NSHostingController(rootView: view)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "Universal Voice Helper"
            )
            button.target = self
            button.action = #selector(toggle(_:))
        }
        update(serverState: serverState)
    }

    func update(serverState: Server.ServerState) {
        switch serverState {
        case .idle:
            serverStateLabel = "Idle"
            serverStateColor = .systemGray
        case .listening(let port):
            serverStateLabel = "Ready on :\(port)"
            serverStateColor = .systemGreen
        case .handshaking:
            serverStateLabel = "Handshaking…"
            serverStateColor = .systemYellow
        case .connected:
            serverStateLabel = "iPhone connected"
            serverStateColor = .systemBlue
        case .failed(let msg):
            serverStateLabel = "Error: \(msg)"
            serverStateColor = .systemRed
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private struct StatusItemView: View {
    @ObservedObject var controller: StatusItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Universal Voice", systemImage: "waveform")
                .font(.headline)
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(controller.serverStateColor))
                    .frame(width: 8, height: 8)
                Text(controller.serverStateLabel)
                    .font(.subheadline)
            }
            Text("Hostname: \(controller.serviceName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let qrImage = controller.qrImage {
                Divider()
                Text("Scan with the iPhone app to pair")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                    Spacer()
                }
                if let hint = controller.pairingPayload?.hostHint {
                    Text("Or use the IP \(hint) on port \(controller.pairingPayload?.port ?? 0).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Pairing unavailable.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(minWidth: 280, alignment: .topLeading)
    }
}
