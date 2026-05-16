import SwiftUI
import AVFoundation
import UniversalVoiceProtocol

struct PairingView: View {
    @Environment(\.dismiss) private var dismiss
    var onPaired: (PairingPayload) -> Void

    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pair with Mac")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task {
            if permission == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    permission = granted ? .authorized : .denied
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch permission {
        case .authorized:
            ZStack(alignment: .bottom) {
                QRScannerView { code in
                    handleScan(code)
                }
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    if let lastError {
                        Text(lastError)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.85), in: .capsule)
                    }
                    Text("Aim at the QR code shown by your Mac helper")
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.65), in: .capsule)
                }
                .padding(.bottom, 60)
            }
        case .denied, .restricted:
            VStack(spacing: 16) {
                Image(systemName: "camera.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Camera access denied")
                    .font(.headline)
                Text("Enable camera access for Universal Voice in Settings to scan the pairing QR.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        case .notDetermined:
            ProgressView("Requesting camera access…")
        @unknown default:
            EmptyView()
        }
    }

    private func handleScan(_ code: String) {
        do {
            let payload = try PairingPayload.parse(qrString: code)
            onPaired(payload)
            dismiss()
        } catch {
            lastError = "QR code not recognized."
        }
    }
}
