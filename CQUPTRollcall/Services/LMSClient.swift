import Foundation

enum LMSError: LocalizedError {
    case loginFailed(String)
    case sessionExpired
    case checkinFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .loginFailed(let msg): return "登录失败: \(msg)"
        case .sessionExpired: return "会话已过期"
        case .checkinFailed(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        }
    }
}

class LMSClient {
    private let lmsBase = "http://lms.tc.cqupt.edu.cn"
    private let idsBase = "https://ids.cqupt.edu.cn"
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: cfg, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
    }()

    // Session that follows redirects (for final login step)
    private lazy var followSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: cfg)
    }()

    func login() async throws {
        let config = AppConfig.shared

        // Clear cookies
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }

        // Step 1: Get callback URL (follow 2 redirects)
        let callbackURL = try await getCallbackURL()

        // Step 2: Get login page params
        let loginURL = "\(idsBase)/authserver/login?service=\(callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callbackURL)"
        let (salt, execution) = try await getLoginPageParams(loginURL)

        // Step 3: POST login
        let encPwd = CryptoUtil.encryptPassword(config.password, key: salt)
        let formBody = [
            "username": config.username,
            "password": encPwd,
            "captcha": "",
            "_eventId": "submit",
            "cllt": "userNameLogin",
            "dllt": "generalLogin",
            "lt": "",
            "execution": execution
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")

        var req = URLRequest(url: URL(string: loginURL)!)
        req.httpMethod = "POST"
        req.httpBody = formBody.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await session.data(for: req)

        var redirectURL: String?

        if let httpResp = resp as? HTTPURLResponse {
            if httpResp.statusCode == 302 {
                redirectURL = httpResp.value(forHTTPHeaderField: "Location")
            } else if httpResp.statusCode == 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                if body.contains("踢出会话") || body.contains("kickout") {
                    if let exec2 = extractExecution(from: body) {
                        let formBody2 = "execution=\(exec2.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? exec2)&_eventId=continue"
                        var req2 = URLRequest(url: URL(string: loginURL)!)
                        req2.httpMethod = "POST"
                        req2.httpBody = formBody2.data(using: .utf8)
                        req2.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                        let (_, resp2) = try await session.data(for: req2)
                        if let httpResp2 = resp2 as? HTTPURLResponse, httpResp2.statusCode == 302 {
                            redirectURL = httpResp2.value(forHTTPHeaderField: "Location")
                        }
                    }
                } else if body.contains("badCredentials") || body.contains("用户名或密码") {
                    throw LMSError.loginFailed("账号或密码错误")
                } else if body.contains("needCaptcha") || body.contains("captcha") {
                    throw LMSError.loginFailed("需要验证码（账号被临时锁定，请稍后再试）")
                } else {
                    throw LMSError.loginFailed("IDS 返回意外响应 (200)")
                }
            } else {
                // 401/403/etc — IDS rejected the login
                throw LMSError.loginFailed("IDS 登录被拒绝 (HTTP \(httpResp.statusCode))")
            }
        }

        // Must have got a redirect URL from successful IDS login
        guard let redirectURL else {
            throw LMSError.loginFailed("未获取到登录重定向")
        }

        // Step 4: Follow redirect to LMS (CAS validates and sets real session cookie)
        guard let url = URL(string: redirectURL) else {
            throw LMSError.loginFailed("重定向 URL 无效")
        }
        _ = try? await followSession.data(from: url)

        // Verify session cookie on LMS domain
        let lmsURL = URL(string: lmsBase)!
        let cookies = HTTPCookieStorage.shared.cookies(for: lmsURL) ?? []
        guard cookies.contains(where: { $0.name == "session" }) else {
            throw LMSError.loginFailed("未获取到 session cookie")
        }

        // Final sanity check: actually try the API to confirm session is authenticated
        let testURL = URL(string: "\(lmsBase)/api/radar/rollcalls?api_version=1.1.0")!
        let (_, testResp) = try await session.data(from: testURL)
        if let httpResp = testResp as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw LMSError.loginFailed("登录后 API 验证失败 (HTTP \(httpResp.statusCode))")
        }
    }

    func getRollcalls() async throws -> [Rollcall] {
        let url = URL(string: "\(lmsBase)/api/radar/rollcalls?api_version=1.1.0")!
        let (data, resp) = try await session.data(from: url)

        if let httpResp = resp as? HTTPURLResponse {
            if httpResp.statusCode == 302 || httpResp.statusCode == 401 {
                throw LMSError.sessionExpired
            }
            if httpResp.statusCode != 200 {
                throw LMSError.networkError(URLError(.badServerResponse))
            }
        }

        let result = try JSONDecoder().decode(RollcallsResponse.self, from: data)
        return result.rollcalls
    }

    func doCheckin(rollcallID: Int, type: String, payload: [String: Any]) async throws {
        let endpoint: String
        switch type {
        case "qr": endpoint = "\(lmsBase)/api/rollcall/\(rollcallID)/answer_qr_rollcall"
        case "number": endpoint = "\(lmsBase)/api/rollcall/\(rollcallID)/answer_number_rollcall"
        case "radar": endpoint = "\(lmsBase)/api/rollcall/\(rollcallID)/answer"
        default: throw LMSError.checkinFailed("未知签到类型")
        }

        var body = payload
        body["deviceId"] = AppConfig.shared.clientID

        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await session.data(for: req)

        if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["status"] as? String == "on_call" {
            return // success
        }

        let errorMsg: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            errorMsg = json["error_code"] as? String ?? json["message"] as? String ?? "未知错误"
        } else {
            errorMsg = "请求失败"
        }
        throw LMSError.checkinFailed(errorMsg)
    }

    // MARK: - History

    private var cachedUserID: Int?
    private var cachedUserName: String?

    /// Get current user's LMS internal user_id. Caches the result.
    func getMyUserID() async throws -> Int {
        if let id = cachedUserID { return id }
        try await loadMyProfile()
        guard let id = cachedUserID else {
            throw LMSError.networkError(URLError(.cannotFindHost))
        }
        return id
    }

    /// Get current user's display name from LMS, nil if not found.
    func getMyName() async -> String? {
        if let name = cachedUserName { return name }
        try? await loadMyProfile()
        return cachedUserName
    }

    private func loadMyProfile() async throws {
        let courses = try await getCourses()
        guard let firstCourse = courses.first else {
            throw LMSError.networkError(URLError(.cannotFindHost))
        }

        let studentID = AppConfig.shared.studentID
        let students = try await getCourseStudents(courseID: firstCourse.id)
        guard let me = students.first(where: { $0.userNo == studentID }) else {
            throw LMSError.networkError(URLError(.cannotFindHost))
        }

        cachedUserID = me.id
        cachedUserName = me.name
    }

    /// Get user's recently visited courses.
    func getCourses() async throws -> [Course] {
        let url = URL(string: "\(lmsBase)/api/user/recently-visited-courses")!
        let data = try await getJSON(from: url)
        return try JSONDecoder().decode(VisitedCoursesResponse.self, from: data).visitedCourses
    }

    /// Get students of a course (used to resolve user_id by user_no).
    func getCourseStudents(courseID: Int) async throws -> [CourseStudent] {
        let url = URL(string: "\(lmsBase)/api/course/\(courseID)/students")!
        let data = try await getJSON(from: url)
        return try JSONDecoder().decode(CourseStudentsResponse.self, from: data).students
    }

    /// Get rollcall history for a specific course.
    func getRollcallHistory(courseID: Int, userID: Int) async throws -> [RollcallHistory] {
        let url = URL(string: "\(lmsBase)/api/course/\(courseID)/student/\(userID)/rollcalls")!
        let data = try await getJSON(from: url)
        return try JSONDecoder().decode(RollcallHistoryResponse.self, from: data).rollcalls
    }

    /// GET a JSON endpoint. Throws sessionExpired on 302/401 — caller decides what to do.
    private func getJSON(from url: URL) async throws -> Data {
        let (data, resp) = try await session.data(from: url)
        guard let httpResp = resp as? HTTPURLResponse else {
            throw LMSError.networkError(URLError(.badServerResponse))
        }
        if httpResp.statusCode == 302 || httpResp.statusCode == 401 {
            throw LMSError.sessionExpired
        }
        guard httpResp.statusCode == 200 else {
            throw LMSError.networkError(URLError(.badServerResponse))
        }
        return data
    }

    // MARK: - Private

    private func getCallbackURL() async throws -> String {
        var currentURL = "\(lmsBase)/login"
        for _ in 0..<2 {
            guard let url = URL(string: currentURL) else { break }
            let (_, resp) = try await session.data(from: url)
            guard let httpResp = resp as? HTTPURLResponse,
                  (300...399).contains(httpResp.statusCode),
                  let loc = httpResp.value(forHTTPHeaderField: "Location") else { break }
            if let resolved = URL(string: loc, relativeTo: url)?.absoluteString {
                currentURL = resolved
            } else {
                currentURL = loc
            }
        }
        return currentURL
    }

    private func getLoginPageParams(_ loginURL: String) async throws -> (salt: String, execution: String) {
        let (data, _) = try await session.data(from: URL(string: loginURL)!)
        let html = String(data: data, encoding: .utf8) ?? ""

        let salt = extractValue(from: html, id: "pwdEncryptSalt")
        let execution = extractExecution(from: html) ?? ""

        guard !execution.isEmpty else {
            throw LMSError.loginFailed("无法获取 execution token")
        }

        return (salt, execution)
    }

    private func extractValue(from html: String, id: String) -> String {
        let pattern = "id=\"\(id)\"[^>]*value=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range])
    }

    private func extractExecution(from html: String) -> String? {
        let pattern = "name=\"execution\"[^>]*value=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
}

// Delegate to prevent auto-redirect following
class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirectDelegate()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
