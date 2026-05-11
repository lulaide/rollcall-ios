import Foundation

struct Coordinate {
    let lat: Double
    let lon: Double
}

enum LocationData {
    // CQUPT teaching buildings in GCJ-02 coordinate system
    private static let teachingBuildings: [Character: (lat: Double, lon: Double)] = [
        "1": (29.531049, 106.605647),
        "2": (29.532345, 106.606620),
        "3": (29.535101, 106.609243),
        "4": (29.536307, 106.609269),
        "5": (29.536018, 106.610354),
        "8": (29.534461, 106.611013),
        "9": (29.525971, 106.606189),
    ]

    private static let otherBuildings: [(keyword: String, lat: Double, lon: Double)] = [
        ("综合实验楼A", 29.525598, 106.605528),
        ("综合实验楼B", 29.525013, 106.605611),
        ("综合实验楼C", 29.524309, 106.605629),
        ("桂花篮球场", 29.530162, 106.607208),
        ("灯光篮球场", 29.532465, 106.608514),
        ("风华运动场", 29.532786, 106.607568),
        ("太极运动场", 29.532896, 106.609731),
    ]

    static func getCoords(for locationName: String) -> Coordinate? {
        guard !locationName.isEmpty else { return nil }

        // 4-digit room number: first digit = building
        if locationName.count == 4 && locationName.allSatisfy(\.isNumber) {
            if let first = locationName.first, let b = teachingBuildings[first] {
                return applyJitter(lat: b.lat, lon: b.lon)
            }
        }

        // Keyword match
        for b in otherBuildings {
            if locationName.contains(b.keyword) {
                return applyJitter(lat: b.lat, lon: b.lon)
            }
        }

        return nil
    }

    private static func applyJitter(lat: Double, lon: Double) -> Coordinate {
        let jitterLat = (Double.random(in: 0...1) - 0.2) * 0.0008
        let jitterLon = (Double.random(in: 0...1) - 0.2) * 0.0008
        return Coordinate(lat: lat + jitterLat, lon: lon + jitterLon)
    }
}
