//
//  TextViewController+ReloadUI.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 4/17/25.
//

import AppKit

extension TextViewController {
    func reloadUI() {
        // The configuration has already been applied by its `didSet` observer at this point. Pass it as the old
        // configuration so this doesn't redundantly reapply everything (eg: re-theming the entire document).
        configuration.didSetOnController(controller: self, oldConfig: configuration)

        styleScrollView()
        styleTextView()

        minimapView.updateContentViewHeight()
        minimapView.updateDocumentVisibleViewPosition()
        reformattingGuideView.updatePosition(in: self)
    }
}
