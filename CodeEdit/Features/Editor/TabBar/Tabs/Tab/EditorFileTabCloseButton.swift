//
//  FileEditorTabCloseButton.swift
//  CodeEdit
//
//  Created by Albert Vinizhanau on 10/13/23.
//

import Foundation
import SwiftUI
import Combine

struct EditorFileTabCloseButton: View {
    var isActive: Bool
    var isHoveringTab: Bool
    var isDragging: Bool
    var closeAction: () -> Void
    @Binding var closeButtonGestureActive: Bool
    var item: CEWorkspaceFile
    @Binding var isHoveringClose: Bool

    @StateObject private var editedObserver: EditorTabEditedObserver

    init(
        isActive: Bool,
        isHoveringTab: Bool,
        isDragging: Bool,
        closeAction: @escaping () -> Void,
        closeButtonGestureActive: Binding<Bool>,
        item: CEWorkspaceFile,
        isHoveringClose: Binding<Bool>
    ) {
        self.isActive = isActive
        self.isHoveringTab = isHoveringTab
        self.isDragging = isDragging
        self.closeAction = closeAction
        self._closeButtonGestureActive = closeButtonGestureActive
        self.item = item
        self._isHoveringClose = isHoveringClose
        self._editedObserver = StateObject(wrappedValue: EditorTabEditedObserver(file: item))
    }

    var body: some View {
        EditorTabCloseButton(
            isActive: isActive,
            isHoveringTab: isHoveringTab,
            isDragging: isDragging,
            closeAction: closeAction,
            closeButtonGestureActive: $closeButtonGestureActive,
            isDocumentEdited: editedObserver.isDocumentEdited,
            isHoveringClose: $isHoveringClose
        )
    }
}

/// Tracks whether the tab's document has unsaved edits, including edits made before the view appeared.
private final class EditorTabEditedObserver: ObservableObject {
    @Published private(set) var isDocumentEdited = false
    private var cancellable: AnyCancellable?

    init(file: CEWorkspaceFile) {
        cancellable = file.fileDocumentPublisher
            .prepend(file.fileDocument)
            .map { document -> AnyPublisher<Bool, Never> in
                guard let document else {
                    return Just(false).eraseToAnyPublisher()
                }
                return document.isDocumentEditedPublisher
                    .prepend(document.isDocumentEdited)
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEdited in
                self?.isDocumentEdited = isEdited
            }
    }
}
