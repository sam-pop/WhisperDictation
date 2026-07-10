import Foundation

extension Bundle {
    /// Short marketing version (`CFBundleShortVersionString`), e.g. "1.0.9".
    /// Single source for the version string shown in the menu bar and Settings.
    /// Falls back to "1.0" when unavailable (e.g. the unit-test host bundle).
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
