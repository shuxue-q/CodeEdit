//
//  EditorTabCloseButton.swift
//  CodeEdit
//
//  Created by Austin Condiff on 1/17/23.
//

import SwiftUI

struct EditorTabCloseButton: View {
    var isActive: Bool
    var isHoveringTab: Bool
    var isDragging: Bool
    var closeAction: () -> Void
    @Binding var closeButtonGestureActive: Bool
    var isDocumentEdited: Bool = false

    @Environment(\.controlActiveState)
    private var activeState

    @State private var isPressingClose: Bool = false
    @Binding var isHoveringClose: Bool

    /// Diameter of the hover circle inside the tab capsule's leading end.
    private static let buttonSize: CGFloat = 16

    /// Leading inset that puts this circle on the same center as the capsule's leading end.
    private static var leadingInset: CGFloat {
        let capDiameter = EditorTabBarView.height - (EditorTabBackground.verticalInset * 2)
        let capCenterX = EditorTabBackground.horizontalInset + (capDiameter / 2)
        return capCenterX - (buttonSize / 2)
    }

    /// Distance from the tab's leading edge to the circle's trailing edge.
    static var trailingEdge: CGFloat {
        leadingInset + buttonSize
    }

    /// Unsaved files keep a dot in the blue circle until the pointer is on that circle.
    private var showsCloseGlyph: Bool {
        !isDocumentEdited || isHoveringClose || isPressingClose
    }

    /// Opaque accent so the circle stays visible on the tinted tab capsule.
    private var circleColor: Color {
        let accent = Color(nsColor: .controlAccentColor)
        if activeState == .inactive {
            return accent.opacity(0.55)
        }
        return accent.opacity(isActive ? 1 : 0.88)
    }

    var body: some View {
        Image(systemName: showsCloseGlyph ? "xmark" : "circle.fill")
            .font(
                .system(
                    size: showsCloseGlyph ? 10 : 7,
                    weight: .bold,
                    design: .rounded
                )
            )
            .foregroundStyle(Color.white)
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background {
                Circle()
                    .fill(circleColor)
                    .overlay {
                        if isPressingClose {
                            Circle().fill(Color.black.opacity(0.18))
                        }
                    }
            }
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged({ _ in
                        isPressingClose = true
                        closeButtonGestureActive = true
                    })
                    .onEnded({ value in
                        if isInsideCircle(value.location) {
                            closeAction()
                        }
                        isPressingClose = false
                        closeButtonGestureActive = false
                    })
            )
            .onHover { hover in
                isHoveringClose = hover
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Close"))
            // Shown while the pointer is on the tab, and kept visible for unsaved files.
            .opacity((isHoveringTab || isDocumentEdited) && !isDragging ? 1 : 0)
            .animation(.easeInOut(duration: 0.08), value: isHoveringTab)
            .animation(.easeInOut(duration: 0.08), value: isHoveringClose)
            .animation(.easeInOut(duration: 0.08), value: isDocumentEdited)
            .animation(.easeInOut(duration: 0.08), value: isPressingClose)
            .padding(.leading, Self.leadingInset)
    }

    /// The circle is the capsule's leading end, so a point in the square bounds is only a hit inside that circle.
    private func isInsideCircle(_ location: CGPoint) -> Bool {
        let radius = Self.buttonSize / 2
        let deltaX = location.x - radius
        let deltaY = location.y - radius
        return (deltaX * deltaX) + (deltaY * deltaY) <= (radius * radius)
    }
}

@available(macOS 14.0, *)
#Preview {
    @Previewable @State var closeButtonGestureActive: Bool = false
    @Previewable @State var isHoveringClose: Bool = false

    return EditorTabCloseButton(
        isActive: false,
        isHoveringTab: false,
        isDragging: false,
        closeAction: { print("Close tab") },
        closeButtonGestureActive: $closeButtonGestureActive,
        isHoveringClose: $isHoveringClose
    )
}
