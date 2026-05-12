import Foundation
import Combine

enum TodaySignStatus: String {
    case unknown
    case notStarted
    case inProgress
    case signed
    case absent
    case late

    var label: String {
        switch self {
        case .unknown: return "..."
        case .notStarted: return "未发起"
        case .inProgress: return "进行中"
        case .signed: return "已签到"
        case .absent: return "缺勤"
        case .late: return "迟到"
        }
    }
}

struct TodayCourseEntry: Identifiable {
    let instance: CurriculumInstance
    let course: Course?         // matched LMS course (nil if no match)
    let status: TodaySignStatus
    let rollcallID: Int?        // for active rollcalls

    var id: String { instance.id }
}

@MainActor
class AppState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var isLoggingIn = false
    @Published var loginError: String?
    @Published var rollcalls: [Rollcall] = []
    @Published var todayCourses: [CurriculumInstance] = []
    @Published var centerConnected = false
    @Published var isPolling = false
    @Published var lastPollTime: Date?
    @Published var checkinMessage: String?
    @Published var userName: String?

    /// All courses for the current semester. Populated after login.
    @Published var allCourses: [Course] = []

    /// Per-course-id rollcall history loaded for status computation.
    @Published var historyByCourseID: [Int: [RollcallHistory]] = [:]

    var config = AppConfig.shared
    let lmsClient = LMSClient()
    var centerWS: CenterWSClient?
    var poller: Poller?

    init() {
        if config.isConfigured {
            Task { await checkSession() }
        }
    }

    func login() async {
        isLoggingIn = true
        loginError = nil
        do {
            try await lmsClient.login()
            isLoggedIn = true
            startServices()
        } catch {
            loginError = error.localizedDescription
        }
        isLoggingIn = false
    }

    func checkSession() async {
        do {
            let list = try await lmsClient.getRollcalls()
            rollcalls = list
            isLoggedIn = true
            startServices()
        } catch {
            isLoggedIn = false
        }
    }

    func startServices() {
        // Fetch user name in background
        Task {
            if let name = await lmsClient.getMyName() {
                userName = name
            }
        }

        // Load semester courses + today's history in background
        Task { await loadCoursesAndHistory() }

        // Start WebSocket
        if !config.centerServerURL.isEmpty {
            centerWS = CenterWSClient(appState: self)
            centerWS?.connect()
        }

        // Start poller
        poller = Poller(appState: self)
        poller?.start()
    }

    func stopServices() {
        centerWS?.disconnect()
        centerWS = nil
        poller?.stop()
        poller = nil
    }

    func refreshRollcalls() async {
        do {
            rollcalls = try await lmsClient.getRollcalls()
        } catch LMSError.sessionExpired {
            handleSessionExpired()
        } catch {
            // Silent fail for network errors — keep showing existing data
        }
    }

    /// Called when any API returns 302/401. Drops back to login screen.
    /// User must manually re-login (we never auto-retry to avoid IDS rate limits).
    func handleSessionExpired() {
        stopServices()
        lmsClient.clearCaches()
        allCourses = []
        historyByCourseID = [:]
        isLoggedIn = false
        loginError = "会话已过期，请重新登录"
    }

    // MARK: - Course / history loading

    private func loadCoursesAndHistory() async {
        do {
            let courses = try await lmsClient.getCourses()
            allCourses = courses
            await refreshTodayHistory()
        } catch LMSError.sessionExpired {
            handleSessionExpired()
        } catch {
            // silent
        }
    }

    /// Reload history for every course matched in today's curriculum.
    func refreshTodayHistory() async {
        guard !allCourses.isEmpty else { return }
        let userID: Int
        do {
            userID = try await lmsClient.getMyUserID()
        } catch { return }

        let targetCourses = Set(todayCourses.compactMap { findCourse(forCurriculumName: $0.course)?.id })
        for cid in targetCourses {
            do {
                let list = try await lmsClient.getRollcallHistory(courseID: cid, userID: userID, forceRefresh: true)
                historyByCourseID[cid] = list
            } catch { continue }
        }
    }

    /// Match a curriculum course name to an LMS course by normalizing both.
    /// Curriculum format: "大学体育2（下）-大学体育2（下）网球1班" (separator `-`).
    /// LMS format:        "大学体育2（下）(大学体育2（下）网球1班)" (halfwidth `(` class suffix).
    /// Fullwidth `（` is part of the actual course name and must not be stripped.
    func findCourse(forCurriculumName name: String) -> Course? {
        let target = canonicalCourseName(name)
        if target.isEmpty { return nil }
        return allCourses.first { canonicalCourseName($0.name ?? "") == target }
    }

    private func canonicalCourseName(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        var cutIdx = s.endIndex
        for ch in ["-", "("] as [Character] {
            if let idx = s.firstIndex(of: ch), idx < cutIdx {
                cutIdx = idx
            }
        }
        return String(s[..<cutIdx]).trimmingCharacters(in: .whitespaces)
    }

    /// Compute today's check-in status for each curriculum instance, in order.
    var todayEntries: [TodayCourseEntry] {
        let cal = Calendar.current
        let today = Date()
        return todayCourses.map { inst in
            let matched = findCourse(forCurriculumName: inst.course)

            // Active rollcall takes priority
            if inst.isNow,
               let active = rollcalls.first(where: { $0.courseTitle == inst.course && $0.isAbsent }) {
                return TodayCourseEntry(instance: inst, course: matched, status: .inProgress, rollcallID: active.rollcallID)
            }

            // Look in history for an entry today within this slot
            if let cid = matched?.id,
               let history = historyByCourseID[cid],
               let slotStart = inst.startDate, let slotEnd = inst.endDate {
                let entry = history.first { rc in
                    guard let t = rc.time else { return false }
                    let sameDay = cal.isDate(t, inSameDayAs: today)
                    let inSlot = t >= slotStart.addingTimeInterval(-30 * 60)
                                 && t <= slotEnd.addingTimeInterval(30 * 60)
                    return sameDay && inSlot
                }
                if let entry {
                    let status: TodaySignStatus
                    switch entry.studentStatus {
                    case "on_call": status = .signed
                    case "absent": status = .absent
                    case "late": status = .late
                    default: status = .notStarted
                    }
                    return TodayCourseEntry(instance: inst, course: matched, status: status, rollcallID: entry.rollcallID)
                }
            }

            // If history not loaded yet for matched course → unknown
            if let cid = matched?.id, historyByCourseID[cid] == nil {
                return TodayCourseEntry(instance: inst, course: matched, status: .unknown, rollcallID: nil)
            }

            // No rollcall today for this slot
            return TodayCourseEntry(instance: inst, course: matched, status: .notStarted, rollcallID: nil)
        }
    }

    /// Global QR scan — submit to all absent QR rollcalls + share to center.
    /// Works even without active rollcalls (for helping others).
    func submitGlobalQR(_ rawData: String) async {
        let extracted = QRUtil.extractQRData(rawData)
        guard !extracted.isEmpty else {
            checkinMessage = "无效或过期的二维码"
            return
        }

        // Always share to center regardless of local rollcalls
        centerWS?.sendRollcallSuccess(type: "qr", data: ["rollcall_data": extracted])

        // Try local batch checkin if we have rollcalls
        let qrRollcalls = rollcalls.filter { $0.source == "qr" && $0.isAbsent }
        if qrRollcalls.isEmpty {
            checkinMessage = "已共享到 Center"
        } else {
            var successCount = 0
            for r in qrRollcalls {
                do {
                    try await lmsClient.doCheckin(rollcallID: r.rollcallID, type: "qr", payload: ["data": extracted])
                    successCount += 1
                } catch {}
            }
            if successCount > 0 {
                checkinMessage = "签到成功 (\(successCount)门课)"
                await refreshRollcalls()
                await refreshTodayHistory()
            } else {
                checkinMessage = "已共享到 Center（本地签到失败）"
            }
        }
    }

    func checkinQR(rollcallID: Int, qrData: String) async {
        let extracted = QRUtil.extractQRData(qrData)
        guard !extracted.isEmpty else {
            checkinMessage = "无效或过期的二维码"
            return
        }
        do {
            try await lmsClient.doCheckin(rollcallID: rollcallID, type: "qr", payload: ["data": extracted])
            checkinMessage = "扫码签到成功"
            centerWS?.sendRollcallSuccess(type: "qr", data: ["rollcall_data": extracted])
            await refreshRollcalls()
            await refreshTodayHistory()
        } catch LMSError.sessionExpired {
            handleSessionExpired()
        } catch {
            checkinMessage = "签到失败: \(error.localizedDescription)"
        }
    }

    func checkinNumber(rollcallID: Int, number: String) async {
        do {
            try await lmsClient.doCheckin(rollcallID: rollcallID, type: "number", payload: ["numberCode": number])
            checkinMessage = "数字签到成功"
            centerWS?.sendRollcallSuccess(type: "number", data: [
                "rollcall_id": rollcallID,
                "rollcall_number": Int(number) ?? 0
            ])
            await refreshRollcalls()
            await refreshTodayHistory()
        } catch LMSError.sessionExpired {
            handleSessionExpired()
        } catch {
            checkinMessage = "签到失败: \(error.localizedDescription)"
        }
    }

    func checkinLocation(rollcallID: Int, lat: Double, lon: Double) async {
        do {
            try await lmsClient.doCheckin(rollcallID: rollcallID, type: "radar", payload: ["lat": lat, "lon": lon])
            checkinMessage = "定位签到成功"
            await refreshRollcalls()
            await refreshTodayHistory()
        } catch LMSError.sessionExpired {
            handleSessionExpired()
        } catch {
            checkinMessage = "签到失败: \(error.localizedDescription)"
        }
    }

    func logout() {
        stopServices()
        lmsClient.clearCaches()
        allCourses = []
        historyByCourseID = [:]
        config.logout()
        isLoggedIn = false
        rollcalls = []
    }
}
