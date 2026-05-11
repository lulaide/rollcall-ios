import SwiftUI
import VisionKit
import AudioToolbox

struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status: ScanStatus = .scanning
    @State private var showManualInput = false
    @State private var manualInput = ""

    enum ScanStatus: Equatable {
        case scanning
        case recognized(String)
        case submitted(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable { value in
                        handleScannedValue(value)
                    }
                    .ignoresSafeArea()
                } else {
                    manualInputContent
                }

                // Status overlay
                if status != .scanning {
                    VStack {
                        Spacer()
                        statusCard
                            .padding()
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom))
                    .animation(.spring(duration: 0.3), value: status)
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
                    dismiss()
                }
                Button("取消", role: .cancel) { manualInput = "" }
            }
        }
    }

    private func handleScannedValue(_ value: String) {
        guard status == .scanning else { return }

        // Try to extract QR data
        let extracted = QRUtil.extractQRData(value)
        if !extracted.isEmpty {
            // Valid 42-hex QR — auto submit and close
            status = .submitted(extracted)
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onScan(value)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
            }
        } else {
            // Recognized but not matching format
            status = .recognized(value)
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch status {
        case .scanning:
            EmptyView()
        case .submitted(let data):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("已提交")
                        .font(.headline)
                    Text(data.prefix(20) + "...")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        case .recognized(let value):
            VStack(spacing: 10) {
                Label("已识别（非签到码格式）", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                Text(value.prefix(60) + (value.count > 60 ? "..." : ""))
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Button("继续扫描") { status = .scanning }
                    .buttonStyle(.bordered)
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var manualInputContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("相机不可用")
                .font(.headline)
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

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue, !value.isEmpty {
                    onScan(value)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item,
               let value = barcode.payloadStringValue, !value.isEmpty {
                onScan(value)
            }
        }
    }
}
