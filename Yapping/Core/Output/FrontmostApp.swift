import AppKit

struct FrontmostApp: Sendable {
    let name: String?
    let bundleID: String?

    @MainActor
    static func current() -> FrontmostApp {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostApp(name: app?.localizedName, bundleID: app?.bundleIdentifier)
    }
}
