import SwiftUI
import VisionKit
import AudioToolbox

struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable { value in
                        guard !scanned else { return }
                        scanned = true
                        onScan(value)
                    }
                    .ignoresSafeArea()
                } else {
                    // Fallback: manual input
                    ManualQRInputView(onSubmit: onScan)
                }
            }
            .navigationTitle("扫码签到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning {
            try? vc.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue {
                    handled = true
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    onScan(value)
                    return
                }
            }
        }
    }
}

// Fallback when DataScanner is unavailable (e.g. simulator)
struct ManualQRInputView: View {
    let onSubmit: (String) -> Void
    @State private var input = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("相机不可用")
                .font(.headline)
            Text("请手动输入二维码数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("粘贴二维码内容", text: $input)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
            Button("提交") {
                guard !input.isEmpty else { return }
                onSubmit(input)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
