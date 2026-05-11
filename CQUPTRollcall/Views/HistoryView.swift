import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var courses: [Course] = []
    @State private var selectedCourse: Course?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading && courses.isEmpty {
                    ProgressView("加载课程列表...")
                } else if let error {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if courses.isEmpty {
                    ContentUnavailableView(
                        "暂无课程",
                        systemImage: "books.vertical",
                        description: Text("还未访问过任何课程")
                    )
                } else {
                    List(courses) { course in
                        NavigationLink {
                            CourseRollcallsView(course: course)
                                .environmentObject(appState)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.tint)
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text(course.displayName)
                                        .font(.headline)
                                    if let dept = course.department?.name {
                                        Text(dept)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("签到历史")
            .refreshable {
                await loadCourses()
            }
            .task {
                if courses.isEmpty {
                    await loadCourses()
                }
            }
        }
    }

    private func loadCourses() async {
        loading = true
        error = nil
        do {
            courses = try await appState.lmsClient.getCourses()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CourseRollcallsView: View {
    let course: Course
    @EnvironmentObject var appState: AppState
    @State private var rollcalls: [RollcallHistory] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        Group {
            if loading && rollcalls.isEmpty {
                ProgressView("加载签到记录...")
            } else if let error {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if rollcalls.isEmpty {
                ContentUnavailableView(
                    "暂无签到记录",
                    systemImage: "list.bullet.rectangle",
                    description: Text("这门课还没有签到记录")
                )
            } else {
                List {
                    Section {
                        SummaryCard(rollcalls: rollcalls)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section("签到记录") {
                        ForEach(rollcalls) { rc in
                            HistoryRow(rollcall: rc)
                        }
                    }
                }
            }
        }
        .navigationTitle(course.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if rollcalls.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let userID = try await appState.lmsClient.getMyUserID()
            rollcalls = try await appState.lmsClient.getRollcallHistory(courseID: course.id, userID: userID)
            // Sort by date desc
            rollcalls.sort { ($0.rollcallTime ?? "") > ($1.rollcallTime ?? "") }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct SummaryCard: View {
    let rollcalls: [RollcallHistory]

    var total: Int { rollcalls.count }
    var present: Int { rollcalls.filter { $0.studentStatus == "on_call" }.count }
    var absent: Int { rollcalls.filter { $0.studentStatus == "absent" }.count }
    var late: Int { rollcalls.filter { $0.studentStatus == "late" }.count }

    var rate: Double {
        total == 0 ? 0 : Double(present + late) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("出勤率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(rate >= 0.9 ? .green : (rate >= 0.7 ? .orange : .red))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatPill(label: "已签", count: present, color: .green)
                    StatPill(label: "缺勤", count: absent, color: .red)
                    if late > 0 {
                        StatPill(label: "迟到", count: late, color: .orange)
                    }
                }
            }
            ProgressView(value: rate)
                .tint(rate >= 0.9 ? .green : (rate >= 0.7 ? .orange : .red))
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

struct StatPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct HistoryRow: View {
    let rollcall: RollcallHistory

    var statusColor: Color {
        switch rollcall.studentStatus {
        case "on_call": return .green
        case "absent": return .red
        case "late": return .orange
        default: return .secondary
        }
    }

    var statusIcon: String {
        switch rollcall.studentStatus {
        case "on_call": return "checkmark.circle.fill"
        case "absent": return "xmark.circle.fill"
        case "late": return "clock.fill"
        default: return "questionmark.circle"
        }
    }

    var formattedTime: String {
        guard let timeStr = rollcall.rollcallTime else { return "" }
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: timeStr) else { return rollcall.title ?? "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedTime)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(rollcall.sourceLabel)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12))
                        .clipShape(Capsule())
                    Text(rollcall.studentStatusLabel)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
