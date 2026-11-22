#if os(macOS)
import OSLog
import SwiftUI
import AppKit

/// Alerts, and views in sheets, presented over whatever is on screen (a sheet included), for flows
/// that ask something partway through.
enum Presenter {
    /// The window on top: the key window, or the sheet it shows.
    static var topWindow: NSWindow? {
        var window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        while let sheet = window?.attachedSheet { window = sheet }
        return window
    }

    struct Option {
        var label: String
        var destructive = false
    }

    /// The Mac has no action sheets; this asks in an alert. Resolves with the index of the option
    /// picked, or nil if canceled.
    static func actionSheet(title: String?, message: String? = nil, options: [Option]) async -> Int? {
        await choose(title: title ?? "", message: message, options: options)
    }

    /// An alert with a Cancel button. Resolves with the index of the option picked, or nil if canceled.
    static func confirm(title: String, message: String? = nil, options: [Option]) async -> Int? {
        await choose(title: title, message: message, options: options)
    }

    /// An alert that only explains something.
    static func alert(title: String, message: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message ?? ""
        if let window = topWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    static func showError(_ title: String, _ error: Error) {
        Log.errors.error("\(title, privacy: .public): \(String(describing: error), privacy: .public)")
        alert(title: title, message: error.localizedDescription)
    }

    private static func choose(title: String, message: String?, options: [Option]) async -> Int? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message ?? ""
        for option in options {
            let button = alert.addButton(withTitle: option.label)
            button.hasDestructiveAction = option.destructive
        }
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let response: NSApplication.ModalResponse
        if let window = topWindow {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return index >= 0 && index < options.count ? index : nil
    }

    /// Privacy & Security in System Settings, where Calendar, Reminders, and Location access are.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows a SwiftUI view in a sheet over whatever is on screen. The view gets a function that
    /// closes the sheet.
    static func present(_ view: (_ close: @escaping () -> Void) -> some View) {
        guard let window = topWindow else { return }
        weak var presented: NSWindow?
        let hosting = NSHostingController(rootView: view { [weak window] in
            if let window, let presented { window.endSheet(presented) }
        })
        let sheet = NSWindow(contentViewController: hosting)
        presented = sheet
        window.beginSheet(sheet)
    }
}
#endif
