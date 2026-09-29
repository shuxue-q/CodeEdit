//
//  LineFoldRibbonDrawingTests.swift
//  CodeEditSourceEditor
//

import AppKit
import Testing
@testable import CodeEditSourceEditor

@MainActor
struct LineFoldRibbonDrawingTests {
    /// Two-space C++ with continuation lines indented past any block, closed by a brace at column 0. With the default
    /// four-space indent option the fold depths skip levels (1, 2, 4, 5), so a fold's depth is not the number of folds
    /// around it.
    static let source = """
    namespace app {
        int run(const Options& options) {
          if (options.log) {
            auto log_path = options.path;
            if (!avx::core::Logger::init_file_logger(
                    log_path.string(), /*also_console=*/true,
                    avx::core::Logger::get_level())) {
              std::println(std::cerr,
                           "Error: Failed to open or create log file '{}' in project "
                           "configuration.",
                           log_path.string());
              return 1;
            }
          }
          return 0;
        }
    }
    int after = 0;

    """

    /// Scrolling makes AppKit redraw only the strip it exposes. Each strip must paint what a full redraw paints there,
    /// or the ribbon stays patchy until something (like hovering) invalidates the whole view.
    @Test(arguments: [7.0, 13.0, 37.0])
    func stripRedrawsMatchFullRedraw(stripHeight: CGFloat) async throws {
        let controller = try await makeController()
        let ribbon = controller.gutterView.foldingRibbon
        let height = ribbon.bounds.height
        let strips = stride(from: 0.0, to: height, by: stripHeight).map {
            NSRect(x: 0, y: $0, width: ribbon.bounds.width, height: min(stripHeight, height - $0))
        }

        let full = try #require(render(ribbon, rects: [ribbon.bounds]))
        let stitched = try #require(render(ribbon, rects: strips))

        #expect(maxAlpha(in: full) > 0.05)
        #expect(maxChannelDifference(full, stitched) <= 1)
    }

    /// Strips that start exactly on a line, including the column-0 line that closes the outermost fold.
    @Test
    func lineByLineRedrawMatchesFullRedraw() async throws {
        let controller = try await makeController()
        let ribbon = controller.gutterView.foldingRibbon
        let layoutManager = controller.textView.layoutManager!
        // Whole-pixel edges, so no row is split between two draws. Rounding up keeps each strip's top on its line.
        let tops = (0..<layoutManager.lineCount).compactMap { layoutManager.textLineForIndex($0)?.yPos.rounded(.up) }
        let bottoms = tops.dropFirst() + [ribbon.bounds.height]
        let strips = zip(tops, bottoms).map { NSRect(x: 0, y: $0, width: ribbon.bounds.width, height: $1 - $0) }

        let full = try #require(render(ribbon, rects: [ribbon.bounds]))
        let stitched = try #require(render(ribbon, rects: strips))

        #expect(maxAlpha(in: full) > 0.05)
        #expect(maxChannelDifference(full, stitched) <= 1)
    }

    /// Creates a laid-out controller whose fold cache is ready. The fold model only holds the controller weakly.
    private func makeController() async throws -> TextViewController {
        let controller = TextViewController(
            string: Self.source,
            language: .default,
            configuration: Mock.config(),
            cursorPositions: [],
            highlightProviders: []
        )
        _ = controller.view

        let textView = controller.textView!
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.layoutManager.layoutLines()

        let ribbon = controller.gutterView.foldingRibbon
        ribbon.frame = NSRect(x: 0, y: 0, width: LineFoldRibbonView.width, height: 400)
        let model = try #require(ribbon.model)

        let documentRange = 0..<Self.source.utf16.count
        var cache = model.$foldCache.values.makeAsyncIterator()
        for _ in 0..<4 where model.getFolds(in: documentRange).isEmpty {
            _ = await cache.next()
        }
        #expect(!model.getFolds(in: documentRange).isEmpty)
        return controller
    }

    /// Draws each rect into one fresh bitmap. AppKit clears a dirty rect before drawing it, and these don't overlap.
    private func render(_ ribbon: LineFoldRibbonView, rects: [NSRect]) -> NSBitmapImageRep? {
        let size = ribbon.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for rect in rects {
            ribbon.draw(rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func maxAlpha(in rep: NSBitmapImageRep) -> CGFloat {
        var maxAlpha: CGFloat = 0
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: column, y: row) else { continue }
                maxAlpha = max(maxAlpha, color.alphaComponent)
            }
        }
        return maxAlpha
    }

    /// The largest difference between any two corresponding bytes of two same-sized bitmaps.
    private func maxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
        guard let lhsData = lhs.bitmapData, let rhsData = rhs.bitmapData,
              lhs.bytesPerRow == rhs.bytesPerRow, lhs.pixelsHigh == rhs.pixelsHigh else {
            return .max
        }
        var maxDifference = 0
        for index in 0..<(lhs.bytesPerRow * lhs.pixelsHigh) {
            maxDifference = max(maxDifference, abs(Int(lhsData[index]) - Int(rhsData[index])))
        }
        return maxDifference
    }
}
