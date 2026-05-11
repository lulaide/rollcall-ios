import Foundation

class CenterWSClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private weak var appState: AppState?
    private var isConnected = false
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 60

    init(appState: AppState) {
        self.appState = appState
    }

    func connect() {
        let config = AppConfig.shared
        guard !config.centerServerURL.isEmpty,
              let url = URL(string: config.centerServerURL) else { return }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        // Send register
        let reg: [String: Any] = [
            "type": "register",
            "client_id": config.clientID,
            "secret": config.centerServerSecret
        ]
        send(reg)

        Task { @MainActor in
            appState?.centerConnected = true
        }
        reconnectDelay = 1
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        Task { @MainActor in
            appState?.centerConnected = false
        }
    }

    func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { _ in }
    }

    func sendRollcallSuccess(type: String, data: [String: Any]) {
        let config = AppConfig.shared
        var msg: [String: Any] = [
            "type": "rollcall_success",
            "client_id": config.clientID,
            "rollcall_type": type,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        msg.merge(data) { _, new in new }
        send(msg)
    }

    func sendRollcallTasks(hasQR: Bool, numbers: [[String: Any]]) {
        let config = AppConfig.shared
        send([
            "type": "rollcall_tasks",
            "client_id": config.clientID,
            "rollcall_qr": hasQR,
            "rollcall_number": numbers,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self?.handleMessage(json)
                    }
                default: break
                }
                self?.receiveMessage() // continue listening
            case .failure:
                self?.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ msg: [String: Any]) {
        guard msg["type"] as? String == "rollcall_share" else { return }
        guard !(AppConfig.shared.pauseSharedRollcall) else { return }

        let rollcallType = msg["rollcall_type"] as? String ?? ""

        Task { @MainActor [weak self] in
            guard let self, let appState = self.appState else { return }

            switch rollcallType {
            case "qr":
                let rawQR = msg["rollcall_qr_data"] as? String ?? ""
                let qrData = QRUtil.extractQRData(rawQR)
                guard !qrData.isEmpty else { return }
                for r in appState.rollcalls where r.source == "qr" && r.isAbsent {
                    await appState.checkinQR(rollcallID: r.rollcallID, qrData: rawQR)
                    break
                }
            case "number":
                let rollcallID = msg["rollcall_id"] as? Int ?? 0
                let number = msg["rollcall_number"] as? Int ?? 0
                for r in appState.rollcalls where r.rollcallID == rollcallID && r.isAbsent {
                    await appState.checkinNumber(rollcallID: rollcallID, number: "\(number)")
                    break
                }
            default: break
            }
        }
    }

    private func handleDisconnect() {
        Task { @MainActor in
            appState?.centerConnected = false
        }

        // Exponential backoff reconnect
        DispatchQueue.global().asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self else { return }
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
            self.connect()
        }
    }
}
