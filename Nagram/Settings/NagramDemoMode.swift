import Foundation

/// Launch-only mode: never persisted or synchronized to another device.
public enum NagramDemoMode {
    public static let isEnabled = CommandLine.arguments.contains("--demo")

    public static let userDefaults: UserDefaults = {
        guard isEnabled else {
            return .standard
        }
        guard let defaults = UserDefaults(suiteName: "nagram.screenshot-demo") else {
            preconditionFailure("Could not open demo settings")
        }
        return defaults
    }()
}
