import Foundation

/// What Spacetime keeps about a reminder that Apple Reminders has no field for. Reminders made in
/// other apps have none of it, so every field is optional.
nonisolated struct ReminderMeta: Codable, Hashable, Sendable {
    /// A location reminder's address (Reminders only keeps the place's name and coordinates).
    var address: String?

    var isEmpty: Bool { address == nil }
}

/// Identifies a reminder. `id` is this device's ID for it, which a full resync can change;
/// `externalId` is the server's, the same on every device, but not every reminder has one.
nonisolated struct ReminderRef: Hashable, Sendable {
    var id: String
    var externalId: String?
}

/// Reminder metadata, kept on this device and keyed on both of a reminder's IDs.
@Observable
final class ReminderMetaStore {
    static let storageKey = "spacetime.reminderMeta.v1"

    nonisolated struct Entry: Codable, Hashable, Sendable {
        var id: String
        var externalId: String?
        var address: String?

        var meta: ReminderMeta { ReminderMeta(address: address) }
    }

    private(set) var entries: [Entry]
    @ObservationIgnored private let storage: KeyValueStorage

    init(storage: KeyValueStorage) {
        self.storage = storage
        entries = storage.decode([Entry].self, forKey: Self.storageKey) ?? []
    }

    private func setEntries(_ next: [Entry]) {
        entries = next
        storage.encode(next, forKey: Self.storageKey)
    }

    private static func matches(_ entry: Entry, _ ref: ReminderRef) -> Bool {
        (ref.externalId != nil && entry.externalId == ref.externalId) || entry.id == ref.id
    }

    func meta(for ref: ReminderRef) -> ReminderMeta {
        entries.first { Self.matches($0, ref) }?.meta ?? ReminderMeta()
    }

    /// Replaces what's kept for a reminder (and forgets it when `meta` is empty).
    func set(_ meta: ReminderMeta, for ref: ReminderRef) {
        var rest = entries.filter { !Self.matches($0, ref) }
        if !meta.isEmpty {
            rest.append(Entry(id: ref.id, externalId: ref.externalId, address: meta.address))
        }
        setEntries(rest)
    }

    /// Brings the metadata up to date with the reminders we can see: updates IDs that changed and
    /// fills in external IDs that arrived after the reminder synced, then forgets reminders that were
    /// deleted. Completed reminders aren't in `seen`, so those are looked up before being forgotten.
    func reconcile(seen: [ReminderRef], exists: (String) async -> Bool) async {
        let snapshot = entries
        var updated: [Entry: Entry] = [:]
        var unseen: [Entry] = []
        for entry in snapshot {
            guard let ref = seen.first(where: { Self.matches(entry, $0) }) else {
                unseen.append(entry)
                continue
            }
            let externalId = ref.externalId ?? entry.externalId
            if ref.id != entry.id || externalId != entry.externalId {
                updated[entry] = Entry(id: ref.id, externalId: externalId, address: entry.address)
            }
        }
        var gone = Set<Entry>()
        for entry in unseen where !(await exists(entry.id)) {
            gone.insert(entry)
        }
        guard !updated.isEmpty || !gone.isEmpty else { return }
        // Entries may have changed while we were checking; only drop and update what we looked at.
        setEntries(entries.filter { !gone.contains($0) }.map { updated[$0] ?? $0 })
    }
}
