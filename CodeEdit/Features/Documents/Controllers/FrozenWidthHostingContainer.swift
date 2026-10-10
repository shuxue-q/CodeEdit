//
//  FrozenWidthHostingContainer.swift
//  CodeEdit
//
//  Created by CodeEdit Developer on 10/10/26.
//

import SwiftUI

/// Hosts a SwiftUI view and can hold it at a fixed width while the container itself resizes.
///
/// Collapsing or revealing a sidebar changes the width of the workspace content on every frame of the
/// animation, and each width change makes SwiftUI lay out the whole nested editor tree again. While the
/// content is frozen the container only reveals or covers it (it clips its content), and the real layout runs
/// once after the animation settles.
final class FrozenWidthHostingContainer: NSViewController {
    /// Which edge of the container stays fixed relative to the frozen content.
    enum Anchor {
        /// The content keeps its leading edge, so the trailing side is revealed or covered.
        case leading
        /// The content keeps its trailing edge, so the leading side is revealed or covered.
        case trailing
    }

    /// How long the container frame must stay unchanged before the freeze ends.
    private static var settleDelay: TimeInterval { 0.15 }

    private let hostingController: NSHostingController<AnyView>
    private var frozenWidth: CGFloat?
    private var anchor: Anchor = .leading
    private var settleTimer: Timer?

    init(rootView: some View) {
        hostingController = NSHostingController(rootView: AnyView(rootView))
        // The enclosing split view controller sizes this view, SwiftUI must not report sizes back.
        hostingController.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = ContainerView()
        container.onLayout = { [weak self] in self?.layoutHostedView() }
        container.clipsToBounds = true
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(hostingController.view)
        layoutHostedView()
    }

    /// Holds the hosted view at `width` until the container's size stops changing.
    /// - Parameters:
    ///   - width: The width to keep the hosted view at. Usually the largest width of the coming animation.
    ///   - anchor: The container edge the content stays aligned with.
    func freeze(width: CGFloat, anchor: Anchor) {
        guard width > 0 else { return }
        frozenWidth = width
        self.anchor = anchor
        layoutHostedView()
        scheduleUnfreeze(after: 1)
    }

    private func scheduleUnfreeze(after delay: TimeInterval) {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.unfreeze()
        }
    }

    private func unfreeze() {
        settleTimer?.invalidate()
        settleTimer = nil
        frozenWidth = nil
        layoutHostedView()
    }

    /// Positions the hosted view: filling the container, or at the frozen width while frozen.
    private func layoutHostedView() {
        let bounds = view.bounds
        guard let frozenWidth else {
            hostingController.view.frame = bounds
            return
        }
        let originX = anchor == .leading ? 0 : bounds.width - frozenWidth
        hostingController.view.frame = CGRect(x: originX, y: 0, width: frozenWidth, height: bounds.height)
        // Frames keep changing while the animation runs; end the freeze once they stop.
        scheduleUnfreeze(after: Self.settleDelay)
    }

    /// Reports layout passes so the hosted view can follow the container.
    private final class ContainerView: NSView {
        var onLayout: (() -> Void)?

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            onLayout?()
        }
    }
}
