import Foundation

struct Rollcall: Identifiable, Codable {
    let rollcallID: Int
    let source: String       // "qr", "number", "radar"
    let status: String       // "absent", "on_call", "late"
    let courseTitle: String
    let rollcallTime: String?

    var id: Int { rollcallID }

    var isAbsent: Bool { status == "absent" }

    var sourceLabel: String {
        switch source {
        case "qr": return "扫码"
        case "number": return "数字"
        case "radar": return "定位"
        default: return source
        }
    }

    var statusLabel: String {
        switch status {
        case "absent": return "未签到"
        case "on_call": return "已签到"
        case "late": return "迟到"
        default: return status
        }
    }

    var sourceIcon: String {
        switch source {
        case "qr": return "qrcode.viewfinder"
        case "number": return "number.circle"
        case "radar": return "location.circle"
        default: return "questionmark.circle"
        }
    }

    enum CodingKeys: String, CodingKey {
        case rollcallID = "rollcall_id"
        case source, status
        case courseTitle = "course_title"
        case rollcallTime = "rollcall_time"
    }
}

struct RollcallsResponse: Codable {
    let rollcalls: [Rollcall]
}

struct CheckinResponse: Codable {
    let status: String?
    let errorCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case errorCode = "error_code"
        case message
    }
}
