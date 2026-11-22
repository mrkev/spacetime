import SwiftUI

/// Location reminders used to be places in our own store, notified by our own geofencing. Moves any
/// left from then into Apple Reminders, once there's access to it.
enum LegacyReminderMigration {
    static func run(space: SpaceStore, calendar: CalendarStore) async {
        guard space.places.contains(where: \.isLegacyReminder) else { return }
        if calendar.remindersStatus == .undetermined { await calendar.requestAccess() }
        guard calendar.remindersStatus == .granted, let list = calendar.defaultReminderList() else { return }
        for place in space.places where place.isLegacyReminder {
            do {
                try LocationReminders.create(
                    in: list,
                    LocationReminderInput(
                        title: place.reminder?.title.isEmpty == false ? place.reminder!.title : place.name,
                        placeName: place.name, address: place.address, notes: place.notes,
                        trigger: place.reminder?.trigger ?? .arrive, radius: place.reminder?.radius ?? 250,
                        latitude: place.latitude, longitude: place.longitude),
                    completed: place.reminder.map { !$0.enabled } ?? false,
                    calendar: calendar)
                space.deletePlace(place.id)
            } catch {
                print("[space] couldn't move reminder “\(place.name)” to Reminders: \(error)")
            }
        }
    }
}
