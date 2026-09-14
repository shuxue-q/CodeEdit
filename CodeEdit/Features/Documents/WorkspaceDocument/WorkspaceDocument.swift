//
//  WorkspaceDocument.swift
//  CodeEdit
//
//  Created by Pavel Kasila on 17.03.22.
//

import AppKit
import SwiftUI
import Combine
import Foundation
import LanguageServerProtocol

@objc(WorkspaceDocument)
final class WorkspaceDocument: NSDocument, ObservableObject, NSToolbarDelegate {
    @Published var sortFoldersOnTop: Bool = true
    /// A string used to filter the displayed files and folders in the project navigator area based on user input.
    @Published var navigatorFilter: String = ""
    /// Whether the workspace only shows files with changes.
    @Published var sourceControlFilter = false

    private var workspaceState: [String: Any] {
        get {
            let key = "workspaceState-\(self.fileURL?.absoluteString ?? "")"
            return UserDefaults.standard.object(forKey: key) as? [String: Any] ?? [:]
        }
        set {
            let key = "workspaceState-\(self.fileURL?.absoluteString ?? "")"
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    var workspaceFileManager: CEWorkspaceFileManager?

    var editorManager: EditorManager? = EditorManager()
    var statusBarViewModel: StatusBarViewModel? = StatusBarViewModel()
    var utilityAreaModel: UtilityAreaViewModel? = UtilityAreaViewModel()
    var searchState: SearchState?
    var openQuicklyViewModel: OpenQuicklyViewModel?
    var commandsPaletteState: QuickActionsViewModel?
    var listenerModel: WorkspaceNotificationModel = .init()
    var sourceControlManager: SourceControlManager?

    var taskManager: TaskManager?
    var workspaceSettingsManager: CEWorkspaceSettings?
    var cmakeWorkspace: CMakeWorkspace?
    var cmakeBuildController: CMakeBuildController?
    var taskNotificationHandler: TaskNotificationHandler = TaskNotificationHandler()

    var undoRegistration: UndoManagerRegistration = UndoManagerRegistration()

    var notificationPanel = NotificationPanelViewModel()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        notificationPanel.workspace = self

        // Observe changes to notification panel
        notificationPanel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        NotificationCenter.default.removeObserver(self)
    }

    func getFromWorkspaceState(_ key: WorkspaceStateKey) -> Any? {
        return workspaceState[key.rawValue]
    }

    func addToWorkspaceState(key: WorkspaceStateKey, value: Any?) {
        if let value {
            workspaceState.updateValue(value, forKey: key.rawValue)
        } else {
            workspaceState.removeValue(forKey: key.rawValue)
        }
    }

    // MARK: NSDocument

    private let ignoredFilesAndDirectory = [
        ".DS_Store"
    ]

    override static var autosavesInPlace: Bool {
        false
    }

    override var isDocumentEdited: Bool {
        false
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Note For anyone hoping to switch back to a Root-SwiftUI window:
        // See Commit 0200c87 for more details and to see what was previously here.
        // -----
        // Setting the "min size" like this is hacky, but SwiftUI overrides the contentRect and
        // any of the built-in window size functions & autosave stuff. So we have to set it like this.
        // SwiftUI also ignores this value, so it just manages to set the initial window size. *Hopefully* this
        // is fixed in the future.
        // ----
        let windowController = CodeEditWindowController(
            window: window,
            workspace: self
        )

        if let rectString = getFromWorkspaceState(.workspaceWindowSize) as? String {
            window.setFrame(NSRectFromString(rectString), display: true, animate: false)
        } else {
            window.setFrame(NSRect(x: 0, y: 0, width: 1400, height: 900), display: true, animate: false)
            window.center()
        }

        window.setAccessibilityIdentifier("workspace")
        window.setAccessibilityDocument(self.fileURL?.absoluteString)

        self.addWindowController(windowController)

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Set Up Workspace

    private func initWorkspaceState(_ url: URL) throws {
        // Ensure the URL ends with a "/" to prevent certain URL(filePath:relativeTo) initializers from
        // placing the file one directory above our workspace. This quick fix appends a "/" if needed.
        var url = url
        if !url.absoluteString.hasSuffix("/") {
            url = URL(filePath: url.absoluteURL.path(percentEncoded: false) + "/")
        }

        self.fileURL = url
        self.displayName = url.lastPathComponent

        let sourceControlManager = SourceControlManager(
            workspaceURL: url,
            editorManager: editorManager!
        )

        self.workspaceFileManager = .init(
            folderUrl: url,
            ignoredFilesAndFolders: Set(ignoredFilesAndDirectory),
            sourceControlManager: sourceControlManager
        )
        self.sourceControlManager = sourceControlManager
        sourceControlManager.fileManager = workspaceFileManager
        self.searchState = .init(self)
        self.openQuicklyViewModel = .init(fileURL: url)
        self.commandsPaletteState = .init()
        self.workspaceSettingsManager = CEWorkspaceSettings(workspaceURL: url)
        if CMakeProject.isCMakeProject(at: url) {
            let cmakeWorkspace = CMakeWorkspace(sourceDirectory: url)
            self.cmakeWorkspace = cmakeWorkspace
            cmakeWorkspace.reload()
            let buildController = CMakeBuildController(sourceDirectory: url, workspace: cmakeWorkspace)
            buildController.onBuildFinished = { [weak self] success in
                // Failed builds surface their diagnostics; a build the user stopped does not.
                guard let self, !success, buildController.outcome != .cancelled else { return }
                if self.utilityAreaModel?.isCollapsed == true {
                    CommandManager.shared.executeCommand("open.drawer")
                }
                self.utilityAreaModel?.selectedTab = .problems
            }
            self.cmakeBuildController = buildController
        }
        if let workspaceSettingsManager {
            self.taskManager = TaskManager(
                workspaceSettings: workspaceSettingsManager.settings,
                workspaceURL: url
            )
            self.taskManager?.cmakeBuildController = cmakeBuildController
        }
        self.taskNotificationHandler.workspaceURL = url

        workspaceFileManager?.addObserver(undoRegistration)
        editorManager?.restoreFromState(self)
        utilityAreaModel?.restoreFromState(self)
    }

    override func read(from url: URL, ofType typeName: String) throws {
        try initWorkspaceState(url)
    }

    override func write(to url: URL, ofType typeName: String) throws {}

    // MARK: Close Workspace

    override func close() {
        super.close()
        editorManager?.saveRestorationState(self)
        utilityAreaModel?.saveRestorationState(self)

        cancellables.forEach({ $0.cancel() })
        statusBarViewModel = nil
        // Release the cached terminal views, so they and their shell processes are deallocated.
        utilityAreaModel?.terminals.forEach { TerminalCache.shared.removeCachedView($0.id) }
        utilityAreaModel = nil
        searchState = nil
        editorManager = nil
        openQuicklyViewModel = nil
        commandsPaletteState = nil
        sourceControlManager = nil
        workspaceFileManager?.cleanUp()
        workspaceFileManager = nil
        workspaceSettingsManager?.cleanUp()
        workspaceSettingsManager = nil
        cmakeWorkspace?.cancel()
        cmakeWorkspace = nil
        cmakeBuildController?.stop()
        cmakeBuildController = nil
        taskManager = nil
    }

    /// Determines the windows should be closed.
    ///
    /// This method iterates all edited documents If there are any edited documents.
    ///
    /// A panel giving the user the choice of canceling, discarding changes, or saving is presented while iteration.
    ///
    /// If the user chooses cancel on the panel, iteration is broken.
    ///
    /// In the last step, `shouldCloseSelector` is called with true if all documents are clean, otherwise false
    ///
    /// - Parameters:
    ///   - windowController: The windowController may be closed.
    ///   - delegate: The object which is a target of `shouldCloseSelector`.
    ///   - shouldClose: The callback which receives result of this method.
    ///   - contextInfo: The additional info which is not used in this method.
    override func shouldCloseWindowController(
        _ windowController: NSWindowController,
        delegate: Any?,
        shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let object = (delegate as? NSObject),
              let shouldCloseSelector = shouldCloseSelector,
              let contextInfo = contextInfo
        else {
            super.shouldCloseWindowController(
                windowController,
                delegate: delegate,
                shouldClose: shouldCloseSelector,
                contextInfo: contextInfo
            )
            return
        }
        // Save unsaved changes before closing
        let editedCodeFiles = editorManager?.editorLayout
            .gatherOpenFiles()
            .compactMap(\.fileDocument)
            .filter(\.isDocumentEdited) ?? []

        // Present a panel giving the user the choice of canceling, discarding changes, or saving,
        // one document at a time. `canClose` may invoke its delegate callback asynchronously,
        // so the iteration continues from the callback and ends by invoking `shouldCloseSelector`.
        canCloseEditedDocuments(editedCodeFiles[...]) { [weak self] in
            guard let self else { return }
            // Invoke shouldCloseSelector at delegate
            let implementation = object.method(for: shouldCloseSelector)
            let function = unsafeBitCast(
                implementation,
                to: (@convention(c)(Any, Selector, Any, Bool, UnsafeMutableRawPointer?) -> Void).self
            )
            let areAllOpenedCodeFilesClean = editorManager?.editorLayout.gatherOpenFiles()
                .compactMap(\.fileDocument)
                .allSatisfy { !$0.isDocumentEdited } ?? false
            function(object, shouldCloseSelector, self, areAllOpenedCodeFilesClean, contextInfo)
        }
    }

    /// Iterates edited documents, presenting a panel for each, until all agree to close or the user cancels.
    ///
    /// `canClose(withDelegate:shouldClose:contextInfo:)` may invoke its delegate callback
    /// asynchronously, so each step continues from ``document(_:shouldClose:contextInfo:)``.
    ///
    /// - Parameters:
    ///   - documents: The edited documents that still need to be asked.
    ///   - completion: Invoked exactly once, when the iteration is done.
    private func canCloseEditedDocuments(
        _ documents: ArraySlice<CodeFileDocument>,
        completion: @escaping () -> Void
    ) {
        guard let editedCodeFile = documents.first else {
            completion()
            return
        }
        // The context is retained until the delegate callback fires and releases it.
        let context = CanCloseContext { [weak self] shouldClose in
            guard let self else { return }
            if shouldClose {
                canCloseEditedDocuments(documents.dropFirst(), completion: completion)
            } else {
                // The user canceled on the panel, iteration is broken.
                completion()
            }
        }
        editedCodeFile.canClose(
            withDelegate: self,
            shouldClose: #selector(document(_:shouldClose:contextInfo:)),
            contextInfo: Unmanaged.passRetained(context).toOpaque()
        )
    }

    /// Box carrying a completion handler through `canClose(withDelegate:shouldClose:contextInfo:)`.
    ///
    /// Passed as a retained opaque `contextInfo` pointer; ``document(_:shouldClose:contextInfo:)``
    /// takes over the retain when the delegate callback fires, exactly once, synchronously or not.
    private final class CanCloseContext {
        let completion: (Bool) -> Void

        init(completion: @escaping (Bool) -> Void) {
            self.completion = completion
        }
    }

    // MARK: NSDocument delegate

    /// Receives the result of `canClose` and forwards it to the completion handler in `contextInfo`.
    ///
    /// - Parameters:
    ///   - document: The document which may be closed.
    ///   - shouldClose: The result of user selection.
    ///      `shouldClose` is false if the user selects cancel, otherwise true.
    ///   - contextInfo: A retained ``CanCloseContext`` as an opaque pointer; this method takes over
    ///       the retain.
    @objc
    func document(
        _ document: NSDocument,
        shouldClose: Bool,
        contextInfo: UnsafeMutableRawPointer
    ) {
        let context = Unmanaged<CanCloseContext>.fromOpaque(contextInfo).takeRetainedValue()
        context.completion(shouldClose)
    }
}
