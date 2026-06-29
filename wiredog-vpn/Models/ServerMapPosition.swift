import Foundation

struct ServerMapPosition {
    /// SVG viewBox dimensions — must match the map.svg file
    static let svgWidth: CGFloat = 2000
    static let svgHeight: CGFloat = 1200

    /// Hardcoded city positions on the SVG map, keyed by city name.
    /// Matches Android's ServerMapPosition.kt exactly.
    private static let positions: [String: (x: CGFloat, y: CGFloat)] = [
        "Atlanta":       (x: 1505, y: 775),
        "Boston":        (x: 1870, y: 333),
        "Chantilly":     (x: 1700, y: 525),
        "Charlotte":     (x: 1630, y: 700),
        "Chicago":       (x: 1355, y: 440),
        "Columbus":      (x: 1515, y: 500),
        "Dallas":        (x: 1050, y: 850),
        "Denver":        (x: 775,  y: 535),
        "Las Vegas":     (x: 440,  y: 635),
        "Miami":         (x: 1707, y: 1095),
        "Nashville":     (x: 1390, y: 690),
        "Newark":        (x: 1776, y: 420),
        "New York":      (x: 1800, y: 415),
        "Philadelphia":  (x: 1776, y: 450),
        "Phoenix":       (x: 525,  y: 755),
        "Portland":      (x: 300,  y: 185),
        "Richmond":      (x: 1715, y: 580),
        "Salt Lake City":(x: 575,  y: 455),
        "San Francisco": (x: 210,  y: 510),
        "Seattle":       (x: 330,  y: 96),
    ]

    /// Look up the SVG position for a server city name.
    static func position(forCity city: String) -> (x: CGFloat, y: CGFloat)? {
        return positions[city]
    }
}
