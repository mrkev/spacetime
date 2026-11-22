import Foundation
import SQLite3

/// A small string key-value store. The app keeps its data under the same keys (and in the same JSON)
/// the React Native app used, so that app's data can be imported as is (see `ExpoStorageImport`).
nonisolated protocol KeyValueStorage: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

extension KeyValueStorage {
    func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let raw = string(forKey: key), let data = raw.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("[storage] couldn't read \(key): \(error)")
            return nil
        }
    }

    func encode<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            set(String(decoding: data, as: UTF8.self), forKey: key)
        } catch {
            print("[storage] couldn't save \(key): \(error)")
        }
    }
}

/// One file per key, under Application Support.
nonisolated final class FileStorage: KeyValueStorage {
    static let shared = FileStorage()

    private let directory: URL
    private var cache: [String: String?] = [:]
    private let lock = NSLock()

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "storage", directoryHint: .isDirectory)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ key: String) -> URL {
        directory.appending(path: key.replacingOccurrences(of: "/", with: "_"))
    }

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let value = try? String(contentsOf: url(key), encoding: .utf8)
        cache[key] = value
        return value
    }

    func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = value
        if let value {
            try? value.write(to: url(key), atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: url(key))
        }
    }

    func hasValue(forKey key: String) -> Bool {
        string(forKey: key) != nil
    }
}

/// For tests and previews.
nonisolated final class MemoryStorage: KeyValueStorage {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String?, forKey key: String) { values[key] = value }
}

/// Copies what the React Native app saved (places, collections, reminder addresses, and where the
/// map and calendar were left) into this app's storage, once. That only finds anything when this
/// app replaces that one, with the same bundle ID, so it can read its files.
nonisolated enum ExpoStorageImport {
    private static let doneKey = "spacetime.importedExpoStorage"

    static func runIfNeeded(into storage: FileStorage = .shared) {
        guard !storage.hasValue(forKey: doneKey) else { return }
        defer { storage.set("1", forKey: doneKey) }
        let path = URL.documentsDirectory.appending(path: "SQLite/ExpoSQLiteStorage").path
        guard FileManager.default.fileExists(atPath: path) else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM storage", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        var imported = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let k = sqlite3_column_text(statement, 0), let v = sqlite3_column_text(statement, 1) else { continue }
            let key = String(cString: k)
            // Data saved by this app wins over what's being imported.
            guard key.hasPrefix("spacetime."), !storage.hasValue(forKey: key) else { continue }
            storage.set(String(cString: v), forKey: key)
            imported += 1
        }
        print("[storage] imported \(imported) values from the React Native app")
    }
}

func createId() -> String {
    let time = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    let random = String((0..<8).map { _ in alphabet.randomElement()! })
    return time + random
}
