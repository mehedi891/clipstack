import AppKit

@main
enum Main {
    // Must be main-actor isolated: AppDelegate touches AppKit state on creation.
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Menu-bar agent: .accessory keeps it out of the Dock and app switcher.
        // LSUIElement in Info.plist does the same for the launched bundle;
        // setting it here keeps `swift run` behaving identically in development.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
