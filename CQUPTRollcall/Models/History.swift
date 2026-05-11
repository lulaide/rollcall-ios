import Foundation

struct Course: Identifiable, Codable {
    let id: Int
    let name: String?
    let department: Department?

    struct Department: Codable {
        let name: String?
    }

    var displayName: String { name ?? "未命名课程" }
}

struct VisitedCoursesResponse: Codable {
    let visitedCourses: [Course]

    enum CodingKeys: String, CodingKey {
        case visitedCourses = "visited_courses"
    }
}

struct CourseStudent: Codable {
    let id: Int
    let userNo: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userNo = "user_no"
        case name
    }
}

struct CourseStudentsResponse: Codable {
    let students: [CourseStudent]
}

struct RollcallHistory: Identifiable, Codable {
    let rollcallID: Int
    let source: String
    let status: String           // server overall status
    let studentStatus: String    // this student's status (on_call/absent/late)
    let rollcallTime: String?
    let title: String?
    let isExpired: Bool?
    let scored: Bool?

    var id: Int { rollcallID }

    var sourceLabel: String {
        switch source {
        case "qr": return "扫码"
        case "number": return "数字"
        case "radar": return "定位"
        default: return source
        }
    }

    var studentStatusLabel: String {
        switch studentStatus {
        case "on_call": return "已签到"
        case "absent": return "缺勤"
        case "late": return "迟到"
        default: return studentStatus
        }
    }

    var isSuccess: Bool { studentStatus == "on_call" || studentStatus == "late" }

    enum CodingKeys: String, CodingKey {
        case rollcallID = "rollcall_id"
        case source
        case status
        case studentStatus = "student_status"
        case rollcallTime = "rollcall_time"
        case title
        case isExpired = "is_expired"
        case scored
    }
}

struct RollcallHistoryResponse: Codable {
    let rollcalls: [RollcallHistory]
}
