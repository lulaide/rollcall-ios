import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showScanner = false
    @State private var showNumberInput = false
    @State private var selectedRollcall: Rollcall?
    @State private var numberInput = ""

    var body: some View {
        NavigationView {
            List {
                // Status section
                Section {
                    HStack {
                        Circle()
                            .fill(appState.centerConnected ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(appState.centerConnected ? "Center 已连接" : "Center 未连接")
                            .font(.subheadline)
                        Spacer()
                        if appState.isPolling {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        if let time = appState.lastPollTime {
                            Text(time, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Rollcalls
                if appState.rollcalls.isEmpty {
                    Section {
                        ContentUnavailableView("暂无签到任务", systemImage: "checkmark.circle", description: Text("当前没有需要处理的签到"))
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
            .overlay {
                if let msg = appState.checkinMessage {
                    checkinToast(msg)
                }
            }
            .onChange(of: appState.checkinMessage) { _ in
                if appState.checkinMessage != nil {
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
            // Find location and auto-checkin
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

    private func checkinToast(_ msg: String) -> some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.subheadline.bold())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(msg.contains("成功") ? Color.green : Color.red)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .padding(.bottom, 80)
        }
        .animation(.easeInOut, value: msg)
        .transition(.move(edge: .bottom))
    }
}

struct RollcallRow: View {
    let rollcall: Rollcall
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: rollcall.sourceIcon)
                .font(.title2)
                .foregroundStyle(rollcall.isAbsent ? .orange : .green)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(rollcall.courseTitle)
                    .font(.headline)
                HStack {
                    Text(rollcall.sourceLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Text(rollcall.statusLabel)
                        .font(.caption)
                        .foregroundStyle(rollcall.isAbsent ? .orange : .green)
                }
            }

            Spacer()

            if rollcall.isAbsent {
                Button(action: action) {
                    Text("签到")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
