import Foundation
import Combine

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

    let config = AppConfig.shared
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
        } catch {
            // Session might be expired
            if let list = try? await retryAfterLogin() {
                rollcalls = list
            }
        }
    }

    private func retryAfterLogin() async throws -> [Rollcall] {
        try await lmsClient.login()
        return try await lmsClient.getRollcalls()
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
        } catch {
            checkinMessage = "签到失败: \(error.localizedDescription)"
        }
    }

    func checkinLocation(rollcallID: Int, lat: Double, lon: Double) async {
        do {
            try await lmsClient.doCheckin(rollcallID: rollcallID, type: "radar", payload: ["lat": lat, "lon": lon])
            checkinMessage = "定位签到成功"
            await refreshRollcalls()
        } catch {
            checkinMessage = "签到失败: \(error.localizedDescription)"
        }
    }

    func logout() {
        stopServices()
        config.logout()
        isLoggedIn = false
        rollcalls = []
    }
}
