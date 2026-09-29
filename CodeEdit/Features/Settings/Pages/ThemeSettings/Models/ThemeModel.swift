//
//  ThemeModel.swift
//  CodeEditModules/Settings
//
//  Created by Lukas Pistrol on 31.03.22.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

/// The Theme View Model. Accessible via the singleton "``ThemeModel/shared``".
///
/// **Usage:**
/// ```swift
/// @StateObject
/// private var themeModel: ThemeModel = .shared
/// ```
final class ThemeModel: ObservableObject {
    static let shared: ThemeModel = .init()

    private var cancellables = Set<AnyCancellable>()

    @AppSettings(\.theme)
    var settings

    /// Default instance of the `FileManager`
    let filemanager = FileManager.default

    /// The base folder url `~/Library/Application Support/CodeEdit/`
    private var baseURL: URL {
        filemanager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/CodeEdit")
    }

    var bundledThemesURL: URL? {
        Bundle.main.resourceURL?.appending(path: "DefaultThemes", directoryHint: .isDirectory) ?? nil
    }

    /// The URL of the `Themes` folder
    internal var themesURL: URL {
        baseURL.appending(path: "Themes", directoryHint: .isDirectory)
    }

    /// The URL of the `Extensions` folder
    internal var extensionsURL: URL {
        baseURL.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    /// The URL of the `settings.json` file
    internal var settingsURL: URL {
        baseURL.appending(path: "settings.json", directoryHint: .isDirectory)
    }

    /// System color scheme
    @Published var colorScheme: ColorScheme = .light

    /// Selected 'light' theme
    /// Used for auto-switching theme to match macOS system appearance
    @Published var selectedLightTheme: Theme? {
        didSet {
            DispatchQueue.main.async {
                Settings.shared
                    .preferences.theme.selectedLightTheme = self.selectedLightTheme?.name ?? "Broken"
            }
        }
    }

    /// Selected 'dark' theme
    /// Used for auto-switching theme to match macOS system appearance
    @Published var selectedDarkTheme: Theme? {
        didSet {
            DispatchQueue.main.async {
                Settings.shared
                    .preferences.theme.selectedDarkTheme = self.selectedDarkTheme?.name ?? "Broken"
            }
        }
    }

    @Published var detailsIsPresented: Bool = false

    @Published var isAdding: Bool = false

    @Published var detailsTheme: Theme?

    /// An array of loaded ``Theme``.
    @Published var themes: [Theme] = []

    /// The currently selected ``Theme``.
    @Published var selectedTheme: Theme? {
        didSet {
            DispatchQueue.main.async {
                Settings[\.theme].selectedTheme = self.selectedTheme?.name
            }
        }
    }

    @Published var previousTheme: Theme?

    /// Only themes where ``Theme/appearance`` == ``Theme/ThemeType/dark``
    var darkThemes: [Theme] {
        themes.filter { $0.appearance == .dark }
    }

    /// Only themes where ``Theme/appearance`` == ``Theme/ThemeType/light``
    var lightThemes: [Theme] {
        themes.filter { $0.appearance == .light }
    }

    private init() {
        do {
            try loadThemes()
        } catch {
            print(error)
        }

        NSApplication.shared.publisher(for: \.effectiveAppearance)
            .receive(on: RunLoop.main)
            .sink { [weak self] newAppearance in
                guard let self = self else { return }
                let isDark = newAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let newScheme: ColorScheme = isDark ? .dark : .light
                if self.colorScheme != newScheme {
                    self.colorScheme = newScheme
                }
                if self.settings.matchAppearance {
                    let matchingTheme = isDark ? self.selectedDarkTheme : self.selectedLightTheme
                    if self.selectedTheme != matchingTheme {
                        self.selectedTheme = matchingTheme
                    }
                }
            }
            .store(in: &cancellables)

        Settings.shared.$preferences
            .map(\.theme.matchAppearance)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] matchAppearance in
                guard let self = self, matchAppearance else { return }
                let isDark = self.colorScheme == .dark
                let matchingTheme = isDark ? self.selectedDarkTheme : self.selectedLightTheme
                if self.selectedTheme != matchingTheme {
                    self.selectedTheme = matchingTheme
                }
            }
            .store(in: &cancellables)
    }

    /// Whether the system or application is currently in dark appearance.
    static var isSystemInDarkMode: Bool {
        let appAppearance = Settings.shared.preferences.general.appAppearance
        if appAppearance == .dark {
            return true
        } else if appAppearance == .light {
            return false
        }
        if Thread.isMainThread {
            return NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        } else {
            return DispatchQueue.main.sync {
                NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            }
        }
    }

    /// This function stores  'dark' and 'light' themes into `ThemePreferences` if user happens to select a theme
    func updateAppearanceTheme() {
        if self.selectedTheme?.appearance == .dark {
            self.selectedDarkTheme = self.selectedTheme
        } else if self.selectedTheme?.appearance == .light {
            self.selectedLightTheme = self.selectedTheme
        }
    }

    func cancelDetails(_ theme: Theme) {
        if let index = themes.firstIndex(where: { $0.fileURL == theme.fileURL }),
        let detailsTheme = self.detailsTheme {
            self.themes[index] = detailsTheme
            self.save(self.themes[index])
        }
    }

    /// Initialize to the app's current appearance.
    var selectedAppearance: ThemeSettingsAppearances {
        Self.isSystemInDarkMode ? .dark : .light
    }

    enum ThemeSettingsAppearances: String, CaseIterable {
        case light = "Light Appearance"
        case dark = "Dark Appearance"
    }

    func getThemeActive(_ theme: Theme) -> Bool {
        return selectedTheme == theme
    }

    /// Activates the current theme, setting ``selectedTheme`` and ``selectedLightTheme``/``selectedDarkTheme`` as
    /// necessary.
    /// - Parameter theme: The theme to activate.
    func activateTheme(_ theme: Theme) {
        selectedTheme = theme
        if theme.appearance == .dark {
            selectedDarkTheme = theme
        } else {
            selectedLightTheme = theme
        }
    }

    /// Activates a theme the user picked, and brings the window chrome along with it.
    ///
    /// The navigator, tab bar, breadcrumbs, status bar and window frame follow `NSApp.appearance`, not the
    /// theme, so a dark theme under a light appearance would otherwise leave the chrome light. When the
    /// theme's ``Theme/appearance`` differs from the current one, the General appearance setting is switched
    /// to match and applied immediately.
    /// - Parameter theme: The theme the user chose.
    func chooseTheme(_ theme: Theme) {
        activateTheme(theme)
        guard (theme.appearance == .dark) != Self.isSystemInDarkMode else { return }
        let appearance: SettingsData.Appearances = theme.appearance == .dark ? .dark : .light
        Settings.shared.preferences.general.appAppearance = appearance
        appearance.applyAppearance()
    }

    /// Brings the selected theme along after the user changes the General appearance setting.
    ///
    /// The inverse of ``chooseTheme(_:)``: a dark theme under a newly chosen light appearance (or the reverse)
    /// would leave the editor and the window chrome disagreeing, so the remembered theme for the new
    /// appearance is activated. Nothing changes when the current theme already fits, or when no theme was
    /// remembered for that appearance.
    func followAppearanceSetting() {
        let isDark = Self.isSystemInDarkMode
        guard let current = selectedTheme, (current.appearance == .dark) != isDark else { return }
        guard let matching = isDark ? selectedDarkTheme : selectedLightTheme,
              (matching.appearance == .dark) == isDark else { return }
        selectedTheme = matching
    }

    /// Designates the theme used for one system appearance.
    ///
    /// The choice is stored in ``selectedLightTheme`` / ``selectedDarkTheme`` (persisted as the
    /// `selectedLightTheme` / `selectedDarkTheme` settings). When appearance matching is on and the app is
    /// currently in that appearance, the theme is also activated immediately, so the editor and window
    /// chrome update without waiting for the next appearance change.
    /// - Parameters:
    ///   - theme: The theme to designate.
    ///   - scheme: The system appearance the theme is paired with.
    func setPairedTheme(_ theme: Theme, for scheme: ColorScheme) {
        if scheme == .dark {
            selectedDarkTheme = theme
        } else {
            selectedLightTheme = theme
        }
        if settings.matchAppearance, colorScheme == scheme, selectedTheme != theme {
            selectedTheme = theme
        }
    }

    func exportTheme(_ theme: Theme) {
        guard let themeFileURL = theme.fileURL else {
            print("Theme file URL not found.")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "cetheme")!]
        savePanel.nameFieldStringValue = theme.displayName
        savePanel.prompt = "Export"
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                do {
                    try FileManager.default.copyItem(at: themeFileURL, to: destinationURL)
                    print("Theme exported successfully to \(destinationURL.path)")
                } catch {
                    print("Failed to export theme: \(error.localizedDescription)")
                }
            }
        }
    }

    func exportAllCustomThemes() {
            let openPanel = NSOpenPanel()
            openPanel.prompt = "Export"
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.allowsMultipleSelection = false

            openPanel.begin { result in
                if result == .OK, let exportDirectory = openPanel.url {
                    let customThemes = self.themes.filter { !$0.isBundled }

                    for theme in customThemes {
                        guard let sourceURL = theme.fileURL else { continue }

                        let destinationURL = exportDirectory.appending(path: "\(theme.displayName).cetheme")

                        do {
                            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                            print("Exported \(theme.displayName) to \(destinationURL.path)")
                        } catch {
                            print("Failed to export \(theme.displayName): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
}

extension ThemeModel {
    /// Follows a window color scheme after the current SwiftUI view update.
    ///
    /// `.task` and `.onChange` run while SwiftUI is still updating the window. Assigning
    /// ``colorScheme`` or ``selectedTheme`` there publishes from inside that update.
    /// - Parameters:
    ///   - colorScheme: The scheme reported by the window.
    ///   - matchAppearance: When true, ``selectedTheme`` follows the scheme's light or dark theme.
    func syncAppearance(to colorScheme: ColorScheme, matchAppearance: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.applyAppearance(colorScheme, matchAppearance: matchAppearance)
        }
    }

    /// Sets the color scheme, and the selected theme when appearance matching is on.
    ///
    /// Values that are already current are left alone so observers are not notified.
    /// - Parameters:
    ///   - colorScheme: The scheme to store.
    ///   - matchAppearance: When true, ``selectedTheme`` follows the scheme's light or dark theme.
    func applyAppearance(_ colorScheme: ColorScheme, matchAppearance: Bool) {
        if self.colorScheme != colorScheme {
            self.colorScheme = colorScheme
        }
        guard matchAppearance else { return }
        let matchingTheme = colorScheme == .dark ? selectedDarkTheme : selectedLightTheme
        if selectedTheme != matchingTheme {
            selectedTheme = matchingTheme
        }
    }
}
