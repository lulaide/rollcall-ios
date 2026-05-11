import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showScanner = false
    @State private var showNumberInput = false
    @State private var selectedRollcall: Rollcall?
    @State private var numberInput = ""

    var body: some View {
        NavigationStack {
            List {
                // Status
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: appState.centerConnected ? "wifi" : "wifi.slash")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(appState.centerConnected ? .green : .red)
                        Text(appState.centerConnected ? "Center 已连接" : "Center 未连接")
                        Spacer()
                        if appState.isPolling {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if let time = appState.lastPollTime {
                            Text(time, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Rollcalls
                if appState.rollcalls.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "暂无签到任务",
                            systemImage: "checkmark.circle",
                            description: Text("当前没有需要处理的签到")
                        )
                    }
                } else {
                    Section("签到任务") {
                        ForEach(appState.rollcalls) { rollcall in
                            RollcallRow(rollcall: rollcall) {
                                selectedRollcall = rollcall
                                handleRollcallAction(rollcall)
                            }
                        }
                    }
                }
            }
            .navigationTitle("签到")
            .refreshable {
                await appState.refreshRollcalls()
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { qrData in
                    showScanner = false
                    if let rc = selectedRollcall {
                        Task { await appState.checkinQR(rollcallID: rc.rollcallID, qrData: qrData) }
                    }
                }
            }
            .alert("输入签到码", isPresented: $showNumberInput) {
                TextField("4位数字", text: $numberInput)
                    .keyboardType(.numberPad)
                Button("确定") {
                    if let rc = selectedRollcall {
                        Task { await appState.checkinNumber(rollcallID: rc.rollcallID, number: numberInput) }
                    }
                    numberInput = ""
                }
                Button("取消", role: .cancel) { numberInput = "" }
            }
            .overlay(alignment: .bottom) {
                if let msg = appState.checkinMessage {
                    ToastView(message: msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 80)
                }
            }
            .animation(.spring(duration: 0.3), value: appState.checkinMessage)
            .onChange(of: appState.checkinMessage) { _, newValue in
                if newValue != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        appState.checkinMessage = nil
                    }
                }
            }
        }
    }

    private func handleRollcallAction(_ rollcall: Rollcall) {
        guard rollcall.isAbsent else { return }
        switch rollcall.source {
        case "qr":
            showScanner = true
        case "number":
            showNumberInput = true
        case "radar":
            Task {
                if let course = appState.todayCourses.first(where: { $0.isNow }),
                   let coords = LocationData.getCoords(for: course.location) {
                    await appState.checkinLocation(rollcallID: rollcall.rollcallID, lat: coords.lat, lon: coords.lon)
                } else {
                    appState.checkinMessage = "无法确定当前位置"
                }
            }
        default: break
        }
    }
}

struct RollcallRow: View {
    let rollcall: Rollcall
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rollcall.sourceIcon)
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
                .foregroundStyle(rollcall.isAbsent ? .orange : .green)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(rollcall.courseTitle)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(rollcall.sourceLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12))
                        .clipShape(Capsule())
                    Text(rollcall.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(rollcall.isAbsent ? .orange : .green)
                }
            }

            Spacer()

            if rollcall.isAbsent {
                Button(action: action) {
                    Text("签到")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ToastView: View {
    let message: String

    var isSuccess: Bool { message.contains("成功") }

    var body: some View {
        Label(message, systemImage: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(radius: 8)
    }
}
