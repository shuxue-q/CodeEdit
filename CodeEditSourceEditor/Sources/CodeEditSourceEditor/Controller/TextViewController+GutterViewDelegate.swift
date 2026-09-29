//
//  TextViewController+GutterViewDelegate.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 4/17/25.
//

import Foundation

extension TextViewController: GutterViewDelegate {
    public func gutterViewWidthDidUpdate() {
        updateTextInsets()
    }

    public func gutterView(_ gutterView: GutterView, didClickLine line: Int) {
        for coordinator in textCoordinators.values() {
            coordinator.textViewDidClickGutter(controller: self, atLine: line)
        }
    }
}
