import Foundation

/// Where the app is running from.
///
/// Accessibility permission is bound to an app at a location. Two situations
/// break that binding, and both look to the user like macOS forgetting the
/// permission every launch:
///
/// - running straight from a mounted disk image, a read-only volume that goes
///   away and may mount elsewhere next time;
/// - App Translocation, where macOS runs a quarantined app from a randomised
///   read-only path instead of where it appears to live.
///
/// Neither is recoverable in code — the app has to be moved — so the panel says
/// so rather than showing a permission prompt that can never be satisfied.
public enum InstallLocation {

    public enum Status: Equatable {
        case normal
        case diskImage
        case translocated

        /// True when permissions cannot persist from here.
        public var blocksPermissions: Bool { self != .normal }
    }

    public static func current(bundleURL: URL = Bundle.main.bundleURL) -> Status {
        status(forPath: bundleURL.path)
    }

    /// Split out from the bundle lookup so the rules can be unit tested.
    public static func status(forPath path: String) -> Status {
        // macOS randomises this path per launch; the app is nowhere near where
        // the user thinks it is.
        if path.contains("/AppTranslocation/") {
            return .translocated
        }

        // "/Volumes/..." covers mounted disk images and external drives alike.
        // The startup volume is "/", so a real install never matches.
        if path.hasPrefix("/Volumes/") {
            return .diskImage
        }

        return .normal
    }
}
