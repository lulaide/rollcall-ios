import Foundation

struct CurriculumInstance: Codable, Identifiable {
    let date: String
    let startTime: String
    let endTime: String
    let course: String
    let location: String

    var id: String { "\(date)-\(startTime)-\(course)" }

    enum CodingKeys: String, CodingKey {
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case course, location
    }

    var startDate: Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt.date(from: "\(date) \(startTime)")
    }

    var endDate: Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt.date(from: "\(date) \(endTime)")
    }

    var isNow: Bool {
        guard let start = startDate, let end = endDate else { return false }
        let now = Date()
        return now >= start.addingTimeInterval(-15 * 60) && now <= end
    }
}

struct CurriculumData: Codable {
    let instances: [CurriculumInstance]
}

struct CurriculumCache: Codable {
    let updatedAt: String
    let data: CurriculumData

    enum CodingKeys: String, CodingKey {
        case updatedAt = "_updated_at"
        case data
    }
}
