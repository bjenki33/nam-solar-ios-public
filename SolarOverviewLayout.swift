import SwiftUI

struct SolarOverviewMetrics {
    static let topGap: CGFloat = 6
    static let groupGap: CGFloat = 5
    static let bottomGap: CGFloat = 16
    static let minimumFlowHeight: CGFloat = 300

    let summaryHeight: CGFloat
    let statusHeight: CGFloat
    let flowHeight: CGFloat

    init(viewportHeight: CGFloat, summaryHeight: CGFloat, statusHeight: CGFloat) {
        self.summaryHeight = summaryHeight
        self.statusHeight = statusHeight
        let sectionGap = Self.topGap + statusHeight + Self.groupGap
        let fixedHeight = 2 * sectionGap + summaryHeight + Self.bottomGap
        flowHeight = max(Self.minimumFlowHeight, viewportHeight - fixedHeight)
    }

    var statusY: CGFloat { Self.topGap }
    var summaryY: CGFloat { statusY + statusHeight + Self.groupGap }
    // Match the upper status band and card-to-diagram gap, keeping the old footer inset.
    var sectionGap: CGFloat { summaryY }
    var summaryToFlowGap: CGFloat { sectionGap }
    var flowY: CGFloat { summaryY + summaryHeight + summaryToFlowGap }
    var totalHeight: CGFloat { flowY + flowHeight + Self.bottomGap }
}

// Measure the data groups, then fit the diagram between the outer margins.
struct SolarOverviewLayout: Layout {
    let viewportHeight: CGFloat

    private func metrics(width: CGFloat, subviews: Subviews) -> SolarOverviewMetrics {
        let proposal = ProposedViewSize(width: width, height: nil)
        return SolarOverviewMetrics(viewportHeight: viewportHeight,
                                    summaryHeight: subviews[1].sizeThatFits(proposal).height,
                                    statusHeight: subviews[0].sizeThatFits(proposal).height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 375
        guard subviews.count == 3 else { return .zero }
        return CGSize(width: width, height: metrics(width: width, subviews: subviews).totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let m = metrics(width: bounds.width, subviews: subviews)
        let origins = [m.statusY, m.summaryY, m.flowY]
        let heights = [m.statusHeight, m.summaryHeight, m.flowHeight]
        for index in 0..<3 {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.minY + origins[index]),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
        }
    }
}
