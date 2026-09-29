//
//  FirstResponderPropertyWrapper.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 14/03/2023.
//

import SwiftUI

/// A property wrapper which allows for easy access to the current first responder.
/// This differs from the SwiftUI Focus System, as you get AppKit NSResponders, which you can call methods on.
/// It can also be easily checked if the current first selector accepts some event.
@propertyWrapper
struct FirstResponder: DynamicProperty {
    @StateObject var helper = HelperClass()

    var wrappedValue: NSResponder? {
        helper.responder
    }

    class HelperClass: ObservableObject {
        @Published var responder: NSResponder? = NSApp.keyWindow?.firstResponder

        init() {
            // The key window changes while SwiftUI is still showing a window (e.g. the Welcome window at launch).
            // Publishing synchronously from that KVO callback is a publish from inside a view update.
            NSApp.publisher(for: \.keyWindow?.firstResponder)
                .receive(on: DispatchQueue.main)
                .assign(to: &$responder)
        }
    }
}
