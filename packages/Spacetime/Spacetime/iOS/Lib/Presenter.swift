#if os(iOS)
import OSLog
import SwiftUI
import UIKit

/// Alerts, action sheets, and system view controllers, presented over whatever is on screen (a
/// sheet included), for flows that ask something partway through.
enum Presenter {
    static var topViewController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    struct Option {
        var label: String
        var destructive = false
    }

    /// An action sheet. Resolves with the index of the option picked, or nil if canceled.
    static func actionSheet(title: String?, message: String? = nil, options: [Option]) async -> Int? {
        await choose(style: .actionSheet, title: title, message: message, options: options, cancel: "Cancel")
    }

    /// An alert with a Cancel button. Resolves with the index of the option picked, or nil if canceled.
    static func confirm(title: String, message: String? = nil, options: [Option]) async -> Int? {
        await choose(style: .alert, title: title, message: message, options: options, cancel: "Cancel")
    }

    /// An alert that only explains something.
    static func alert(title: String, message: String? = nil) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default))
        topViewController?.present(controller, animated: true)
    }

    static func showError(_ title: String, _ error: Error) {
        Log.errors.error("\(title, privacy: .public): \(String(describing: error), privacy: .public)")
        alert(title: title, message: error.localizedDescription)
    }

    private static func choose(style: UIAlertController.Style, title: String?, message: String?,
                               options: [Option], cancel: String) async -> Int? {
        guard let top = topViewController else { return nil }
        return await withCheckedContinuation { continuation in
            let controller = UIAlertController(title: title, message: message, preferredStyle: style)
            for (i, option) in options.enumerated() {
                controller.addAction(UIAlertAction(title: option.label,
                                                   style: option.destructive ? .destructive : .default) { _ in
                    continuation.resume(returning: i)
                })
            }
            controller.addAction(UIAlertAction(title: cancel, style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            top.present(controller, animated: true)
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
#endif
