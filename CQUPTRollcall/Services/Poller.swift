import Foundation

class Poller {
    private weak var appState: AppState?
    private var timer: Timer?
    private var curriculum: CurriculumData?
    private var lastFetch: Date?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        loadCurriculumFromCache()
        poll() // initial
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func triggerPoll() {
        poll()
    }

    private func poll() {
        Task { @MainActor [weak self] in
            guard let self, let appState = self.appState else { return }

            // Fetch curriculum if needed
            await self.fetchCurriculumIfNeeded()

            guard self.shouldPoll() else { return }

            appState.isPolling = true
            await appState.refreshRollcalls()
            appState.lastPollTime = Date()
            appState.isPolling = false

            // Update today courses
            self.updateTodayCourses()

            // Send tasks to center
            let hasQR = appState.rollcalls.contains { $0.source == "qr" && $0.isAbsent }
            let numbers: [[String: Any]] = appState.rollcalls
                .filter { $0.source == "number" && $0.isAbsent }
                .map { ["rollcall_id": $0.rollcallID, "course_title": $0.courseTitle] }
            appState.centerWS?.sendRollcallTasks(hasQR: hasQR, numbers: numbers)

            // Auto location checkin
            if AppConfig.shared.autoLocationCheckin {
                await self.autoLocationCheckin()
            }
        }
    }

    private func shouldPoll() -> Bool {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute

        let config = AppConfig.shared
        guard !config.studentID.isEmpty else {
            // Default windows
            let windows = [(7*60+50, 12*60), (13*60+50, 18*60), (18*60+50, 22*60+40)]
            return windows.contains { nowMinutes >= $0.0 && nowMinutes <= $0.1 }
        }

        guard let curriculum else { return true }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: now)

        for inst in curriculum.instances where inst.date == todayStr {
            guard let start = inst.startDate, let end = inst.endDate else { continue }
            let pollStart = start.addingTimeInterval(-Double(config.curriculumPreMinutes) * 60)
            if now >= pollStart && now <= end { return true }
        }
        return false
    }

    private func autoLocationCheckin() async {
        guard let appState, let curriculum else { return }

        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: now)

        // Find current course
        var currentInst: CurriculumInstance?
        for inst in curriculum.instances where inst.date == todayStr {
            guard let start = inst.startDate, let end = inst.endDate else { continue }
            if now >= start.addingTimeInterval(-15 * 60) && now <= end {
                currentInst = inst
                break
            }
        }

        guard let inst = currentInst else { return }

        for r in appState.rollcalls where r.source == "radar" && r.isAbsent {
            if let coords = LocationData.getCoords(for: inst.location) {
                await appState.checkinLocation(rollcallID: r.rollcallID, lat: coords.lat, lon: coords.lon)
            }
        }
    }

    private func updateTodayCourses() {
        guard let curriculum, let appState else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        Task { @MainActor in
            appState.todayCourses = curriculum.instances.filter { $0.date == todayStr }
        }
    }

    // MARK: - Curriculum

    private func fetchCurriculumIfNeeded() async {
        let config = AppConfig.shared
        guard !config.curriculumAPI.isEmpty else { return }
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 30 * 60 { return }

        guard let url = URL(string: config.curriculumAPI) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CurriculumData.self, from: data)
            curriculum = decoded
            lastFetch = Date()
            saveCurriculumCache(decoded)
            updateTodayCourses()
        } catch {
            print("课表获取失败: \(error)")
        }
    }

    private func loadCurriculumFromCache() {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CurriculumCache.self, from: data) else { return }
        curriculum = cache.data
        updateTodayCourses()
    }

    private func saveCurriculumCache(_ data: CurriculumData) {
        guard let url = cacheURL else { return }
        let cache = CurriculumCache(
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            data: data
        )
        if let encoded = try? JSONEncoder().encode(cache) {
            try? encoded.write(to: url)
        }
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("curriculum_cache.json")
    }
}
