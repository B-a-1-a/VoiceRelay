import SwiftUI
import UniversalVoiceProtocol

struct RecorderView: View {
    @State private var session = DictationSession()
    @State private var pairingPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                statusPill
                transcriptCard
                Spacer()
                recordButton
            }
            .padding()
            .navigationTitle("Universal Voice")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pairingPresented = true
                    } label: {
                        Image(systemName: session.pairedDevice == nil ? "qrcode.viewfinder" : "checkmark.seal.fill")
                    }
                }
            }
            .sheet(isPresented: $pairingPresented) {
                PairingView { payload in
                    session.setPairing(payload)
                }
            }
        }
    }

    private var statusPill: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: .capsule)

            if let mac = session.pairedDevice {
                Text("Paired with \(mac.serviceName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap the QR icon to pair with a Mac")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var transcriptCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !session.finalizedTranscript.isEmpty {
                    Text(session.finalizedTranscript)
                        .font(.body.weight(.medium))
                }
                if !session.liveTranscript.isEmpty {
                    Text(session.liveTranscript)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                if session.finalizedTranscript.isEmpty && session.liveTranscript.isEmpty {
                    Text("Tap Record and speak…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }

    private var recordButton: some View {
        Button {
            Task {
                switch session.phase {
                case .idle, .error:
                    await session.start()
                case .recording:
                    await session.stop()
                default:
                    break
                }
            }
        } label: {
            Label(buttonLabel, systemImage: buttonSymbol)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(buttonTint)
        .disabled(buttonDisabled)
    }

    private var buttonLabel: String {
        switch session.phase {
        case .idle: return session.pairedDevice == nil ? "Pair First" : "Record"
        case .preparing: return "Preparing…"
        case .recording: return "Stop"
        case .cleaning: return "Cleaning…"
        case .sending: return "Sending…"
        case .error: return "Try again"
        }
    }

    private var buttonSymbol: String {
        switch session.phase {
        case .recording: return "stop.fill"
        case .preparing, .cleaning, .sending: return "hourglass"
        case .error: return "arrow.clockwise"
        default: return session.pairedDevice == nil ? "qrcode.viewfinder" : "mic.fill"
        }
    }

    private var buttonTint: Color {
        switch session.phase {
        case .recording: return .red
        case .error: return .orange
        default: return .accentColor
        }
    }

    private var buttonDisabled: Bool {
        switch session.phase {
        case .preparing, .cleaning, .sending: return true
        case .idle, .error: return session.pairedDevice == nil
        default: return false
        }
    }

    private var statusLabel: String {
        switch session.phase {
        case .idle:
            switch session.connection {
            case .connected: return "Connected"
            case .handshaking: return "Handshaking…"
            case .connecting: return "Connecting…"
            case .failed(let msg): return msg
            case .idle: return session.pairedDevice == nil ? "Not paired" : "Ready"
            }
        case .preparing: return "Setting up…"
        case .recording: return "Listening…"
        case .cleaning: return "Cleaning transcript…"
        case .sending: return "Sending to Mac…"
        case .error(let msg): return msg
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .recording: return .red
        case .error: return .orange
        case .idle:
            switch session.connection {
            case .connected: return .green
            case .handshaking, .connecting: return .yellow
            case .failed: return .red
            case .idle: return session.pairedDevice == nil ? .orange : .gray
            }
        default: return .yellow
        }
    }
}

#Preview {
    RecorderView()
}
