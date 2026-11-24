#if os(iOS)
import Photos
import PhotosUI
import SwiftUI

/// The app's settings: what the map shows besides places, and what the calendar shows from Health.
struct SettingsView: View {
    @Environment(HealthStore.self) private var health
    @Environment(MapLayers.self) private var layers
    @Environment(\.dismiss) private var dismiss
    /// Kinds being turned on, while Health asks for access.
    @State private var pending = Set<HealthKind>()

    var body: some View {
        Form {
            Section {
                MapLayerToggle(layer: .photos)
                if layers.isEnabled(.photos) && PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                    Button("Choose Photos…") {
                        if let top = Presenter.topViewController {
                            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
                        }
                    }
                }
                MapLayerToggle(layer: .contacts)
            } header: {
                Text("Map")
            } footer: {
                Text("""
                    Shows where your photos were taken, and your contacts’ addresses, on the Space map. \
                    Addresses are looked up with Apple Maps, a few at a time.
                    """)
            }
            Section {
                if HealthStore.isAvailable {
                    healthToggle(.sleep, icon: "bed.double.fill", color: Theme.sleep)
                    healthToggle(.cycle, icon: "drop.fill", color: Theme.cycle)
                    healthToggle(.medications, icon: "pills.fill", color: Theme.medication)
                    if health.isEnabled(.medications) {
                        Button("Choose Medications…") {
                            Task {
                                do { try await health.chooseMedications() } catch {
                                    Presenter.showError("Couldn’t Open Health", error)
                                }
                            }
                        }
                    }
                } else {
                    Text("Health isn’t available on this device.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Health")
            } footer: {
                if HealthStore.isAvailable {
                    Text("""
                        Spacetime reads these from Health to show them in the day view, and never changes them. \
                        If something you’ve turned on doesn’t show, open Health, tap your picture, then Apps, \
                        and check what Spacetime can read.
                        """)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
            }
        }
    }

    private func healthToggle(_ kind: HealthKind, icon: String, color: Color) -> some View {
        let isOn = Binding {
            health.isEnabled(kind) || pending.contains(kind)
        } set: { on in
            if on { pending.insert(kind) }
            Task {
                do { try await health.setEnabled(kind, on) } catch {
                    Presenter.showError("Couldn’t Read \(kind.title)", error)
                }
                pending.remove(kind)
            }
        }
        return Toggle(isOn: isOn) {
            Label {
                Text(kind.title)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color, in: .rect(cornerRadius: 7))
            }
        }
    }
}
#endif
