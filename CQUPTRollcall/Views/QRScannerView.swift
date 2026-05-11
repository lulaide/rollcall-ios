import SwiftUI
import VisionKit
import AudioToolbox

struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var showManualInput = false
    @State private var manualInput = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable { value in
                        guard scannedValue == nil else { return }
                        scannedValue = value
                        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                    }
                    .ignoresSafeArea()
                } else {
                    manualInputContent
                }

                // Scanned result overlay
                if let value = scannedValue {
                    VStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Label("已识别二维码", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text(value.prefix(60) + (value.count > 60 ? "..." : ""))
                                .font(.caption.monospaced())
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                Button("重新扫描") {
                                    scannedValue = nil
                                }
                                .buttonStyle(.bordered)
                                Button("提交签到") {
                                    onScan(value)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding()
                        .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom))
                    .animation(.spring(duration: 0.3), value: scannedValue)
                }
            }
            .navigationTitle("扫码签到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("手动输入") { showManualInput = true }
                }
            }
            .alert("手动输入二维码", isPresented: $showManualInput) {
                TextField("粘贴二维码内容", text: $manualInput)
                Button("提交") {
                    guard !manualInput.isEmpty else { return }
                    onScan(manualInput)
                    manualInput = ""
                }
                Button("取消", role: .cancel) { manualInput = "" }
            }
        }
    }

    private var manualInputContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("相机不可用")
                .font(.headline)
            Text("请手动粘贴二维码内容")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("手动输入") { showManualInput = true }
                .buttonStyle(.borderedProminent)
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

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        // Called when items are first recognized
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue, !value.isEmpty {
                    onScan(value)
                    return
                }
            }
        }

        // Called when user taps on a recognized item
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item,
               let value = barcode.payloadStringValue, !value.isEmpty {
                onScan(value)
            }
        }
    }
}
