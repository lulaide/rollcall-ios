import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showScanner = false
    @State private var showGlobalScanner = false
    @State private var showNumberInput = false
    @State private var actionRollcallID: Int?
    @State private var numberInput = ""

    /// Active rollcalls not matched to any today's curriculum entry.
    var orphanActiveRollcalls: [Rollcall] {
        let matchedTitles = Set(appState.todayEntries
            .filter { $0.status == .inProgress }
            .map { $0.instance.course })
        return appState.rollcalls.filter { rc in
            !matchedTitles.contains(rc.courseTitle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showGlobalScanner = true
                    } label: {
                        Label("扫一扫签到", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

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

                if appState.todayEntries.isEmpty && orphanActiveRollcalls.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "今日无课",
                            systemImage: "calendar.badge.checkmark",
                            description: Text("今天没有课程安排")
                        )
                    }
                }

                if !appState.todayEntries.isEmpty {
                    Section("今日课程") {
                        ForEach(appState.todayEntries) { entry in
                            TodayEntryRow(entry: entry) {
                                handleAction(entry: entry)
                            }
                        }
                    }
                }

                if !orphanActiveRollcalls.isEmpty {
                    Section("其他签到") {
                        ForEach(orphanActiveRollcalls) { rc in
                            RollcallRow(rollcall: rc) {
                                handleRollcallAction(rc)
                            }
                        }
                    }
                }
            }
            .navigationTitle("签到")
            .refreshable {
                await appState.refreshRollcalls()
                await appState.refreshTodayHistory()
            }
            .sheet(isPresented: $showGlobalScanner) {
                QRScannerView { qrData in
                    showGlobalScanner = false
                    Task { await appState.submitGlobalQR(qrData) }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { qrData in
                    showScanner = false
                    if let id = actionRollcallID {
                        Task { await appState.checkinQR(rollcallID: id, qrData: qrData) }
                    }
                }
            }
            .alert("输入签到码", isPresented: $showNumberInput) {
                TextField("4位数字", text: $numberInput)
                    .keyboardType(.numberPad)
                Button("确定") {
                    if let id = actionRollcallID {
                        Task { await appState.checkinNumber(rollcallID: id, number: numberInput) }
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

    private func handleAction(entry: TodayCourseEntry) {
        guard entry.status == .inProgress, let rcID = entry.rollcallID else { return }
        guard let rc = appState.rollcalls.first(where: { $0.rollcallID == rcID }) else { return }
        actionRollcallID = rcID
        handleRollcallAction(rc)
    }

    private func handleRollcallAction(_ rollcall: Rollcall) {
        guard rollcall.isAbsent else { return }
        actionRollcallID = rollcall.rollcallID
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

struct TodayEntryRow: View {
    let entry: TodayCourseEntry
    let onAction: () -> Void

    @EnvironmentObject var appState: AppState

    var rowContent: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(entry.instance.startTime)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(entry.instance.endTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)

            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor.opacity(entry.instance.isNow ? 1.0 : 0.4))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.instance.course)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !entry.instance.location.isEmpty {
                        Label(entry.instance.location, systemImage: "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                StatusBadge(status: entry.status)
            }

            Spacer()

            if entry.status == .inProgress {
                Button(action: onAction) {
                    Text("签到")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        if let course = entry.course {
            NavigationLink {
                CourseRollcallsView(course: course)
                    .environmentObject(appState)
            } label: {
                rowContent
            }
        } else {
            rowContent
        }
    }

    var statusColor: Color {
        switch entry.status {
        case .signed: return .green
        case .late: return .orange
        case .absent: return .red
        case .inProgress: return .blue
        case .notStarted, .unknown: return .gray
        }
    }
}

struct StatusBadge: View {
    let status: TodaySignStatus

    var color: Color {
        switch status {
        case .signed: return .green
        case .late: return .orange
        case .absent: return .red
        case .inProgress: return .blue
        case .notStarted: return .gray
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch status {
        case .signed: return "checkmark.circle.fill"
        case .late: return "clock.fill"
        case .absent: return "xmark.circle.fill"
        case .inProgress: return "dot.radiowaves.left.and.right"
        case .notStarted: return "circle.dotted"
        case .unknown: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(status.label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
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

    var isSuccess: Bool { message.contains("成功") || message.contains("已共享") || message.contains("已识别") }

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
