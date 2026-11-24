import OSLog

/// The app's logs, which Console.app shows with the phone connected (filter by the subsystem).
nonisolated enum Log {
    private static let subsystem = "com.aykev.Spacetime"
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let places = Logger(subsystem: subsystem, category: "places")
    static let errors = Logger(subsystem: subsystem, category: "errors")
    static let health = Logger(subsystem: subsystem, category: "health")
}
