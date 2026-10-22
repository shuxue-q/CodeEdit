import SwiftUI

extension String {
    func localized(_ custom: String? = nil) -> LocalizedStringKey {
        if let custom {
            return LocalizedStringKey(custom)
        } else {
            return LocalizedStringKey(self)
        }
    }
}

extension LocalizedStringKey {
    static let helloWorld = "Hello, world!".localized()
}

extension String {
    /// This string translated through the app's `Localizable` table at runtime.
    ///
    /// Use it for display text that reaches a view as a `String` (for example a title parameter that callers
    /// pass as a literal). Unlike `LocalizedStringKey`, the result is not parsed as Markdown, so user data such
    /// as task names or paths shows unchanged. Returns the string itself when there is no translation.
    var localizedAtRuntime: String {
        Bundle.main.localizedString(forKey: self, value: nil, table: nil)
    }
}
