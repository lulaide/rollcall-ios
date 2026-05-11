import Foundation

class AppConfig: ObservableObject, @unchecked Sendable {
    static let shared = AppConfig()

    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "username") }
    }
    @Published var password: String {
        didSet { UserDefaults.standard.set(password, forKey: "password") }
    }
    @Published var studentID: String {
        didSet { UserDefaults.standard.set(studentID, forKey: "studentID") }
    }
    @Published var centerServerURL: String {
        didSet { UserDefaults.standard.set(centerServerURL, forKey: "centerServerURL") }
    }
    @Published var centerServerSecret: String {
        didSet { UserDefaults.standard.set(centerServerSecret, forKey: "centerServerSecret") }
    }
    @Published var autoLocationCheckin: Bool {
        didSet { UserDefaults.standard.set(autoLocationCheckin, forKey: "autoLocationCheckin") }
    }
    @Published var curriculumPreMinutes: Int {
        didSet { UserDefaults.standard.set(curriculumPreMinutes, forKey: "curriculumPreMinutes") }
    }
    @Published var pauseSharedRollcall: Bool {
        didSet { UserDefaults.standard.set(pauseSharedRollcall, forKey: "pauseSharedRollcall") }
    }

    var curriculumAPI: String {
        guard !studentID.isEmpty else { return "" }
        return "https://cqupt.ishub.top/api/curriculum/\(studentID)/curriculum.json"
    }

    var clientID: String {
        if let id = UserDefaults.standard.string(forKey: "clientID"), !id.isEmpty {
            return id
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "clientID")
        return id
    }

    var isConfigured: Bool {
        !username.isEmpty && !password.isEmpty
    }

    private init() {
        let ud = UserDefaults.standard
        self.username = ud.string(forKey: "username") ?? ""
        self.password = ud.string(forKey: "password") ?? ""
        self.studentID = ud.string(forKey: "studentID") ?? ""
        self.centerServerURL = ud.string(forKey: "centerServerURL") ?? "wss://cqupt.ishub.top/api/rollcall/ws"
        self.centerServerSecret = ud.string(forKey: "centerServerSecret") ?? ""
        self.autoLocationCheckin = ud.object(forKey: "autoLocationCheckin") as? Bool ?? true
        self.curriculumPreMinutes = ud.object(forKey: "curriculumPreMinutes") as? Int ?? 10
        self.pauseSharedRollcall = ud.object(forKey: "pauseSharedRollcall") as? Bool ?? false
    }

    func logout() {
        password = ""
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}
