import SwiftUI
import UIKit

struct SolarChartTouchSurface: UIViewRepresentable {
    let onSelect: (CGFloat) -> Void
    let onDoubleTap: (CGFloat) -> Void
    let onPinch: (CGFloat, UIGestureRecognizer.State) -> Void
    var onPan: (CGFloat, UIGestureRecognizer.State) -> Void = { _, _ in }
    var panEnabled = false

    func makeUIView(context: Context) -> SolarChartTouchView { SolarChartTouchView() }

    func updateUIView(_ view: SolarChartTouchView, context: Context) {
        view.onSelect = onSelect
        view.onDoubleTap = onDoubleTap
        view.onPinch = onPinch
        view.onPan = onPan
        if view.panRecognizer.isEnabled != panEnabled { view.panRecognizer.isEnabled = panEnabled }
    }
}

final class SolarChartTouchView: UIView, UIGestureRecognizerDelegate {
    var onSelect: (CGFloat) -> Void = { _ in }
    var onDoubleTap: (CGFloat) -> Void = { _ in }
    var onPinch: (CGFloat, UIGestureRecognizer.State) -> Void = { _, _ in }
    var onPan: (CGFloat, UIGestureRecognizer.State) -> Void = { _, _ in }

    private(set) lazy var holdRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
    private(set) lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
    private(set) lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
    private(set) lazy var doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
    private(set) lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        holdRecognizer.minimumPressDuration = 0.18
        holdRecognizer.allowableMovement = 18
        holdRecognizer.numberOfTouchesRequired = 1
        doubleTapRecognizer.numberOfTapsRequired = 2
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.isEnabled = false
        // Movement before the hold threshold pans; a stationary hold owns scrubbing.
        panRecognizer.require(toFail: holdRecognizer)
        tapRecognizer.require(toFail: doubleTapRecognizer)
        tapRecognizer.require(toFail: holdRecognizer)
        doubleTapRecognizer.require(toFail: holdRecognizer)
        tapRecognizer.require(toFail: panRecognizer)
        doubleTapRecognizer.require(toFail: panRecognizer)
        let recognizers: [UIGestureRecognizer] = [holdRecognizer, pinchRecognizer, tapRecognizer, doubleTapRecognizer, panRecognizer]
        for recognizer in recognizers {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func inspect(at x: CGFloat) {
        guard x.isFinite, bounds.width > 0 else { return }
        onSelect(min(bounds.width, max(0, x)))
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed, .ended: inspect(at: gesture.location(in: self).x)
        default: break
        }
    }

    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { inspect(at: gesture.location(in: self).x) }
    }

    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { onDoubleTap(min(bounds.width, max(0, gesture.location(in: self).x))) }
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        onPinch(gesture.scale, gesture.state)
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard bounds.width > 0 else { return }
        let fraction = gesture.translation(in: self).x / bounds.width
        if fraction.isFinite { onPan(fraction, gesture.state) }
    }

    static func isHorizontal(_ velocity: CGPoint) -> Bool {
        velocity.x.isFinite && velocity.y.isFinite && abs(velocity.x) > abs(velocity.y) * 1.2
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panRecognizer {
            return panRecognizer.isEnabled && Self.isHorizontal(panRecognizer.velocity(in: self))
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // A quick swipe fails the hold; once the hold begins, its parent cannot steal the drag.
        guard gestureRecognizer === holdRecognizer || gestureRecognizer === pinchRecognizer || gestureRecognizer === panRecognizer,
              otherGestureRecognizer is UIPanGestureRecognizer,
              let scroll = otherGestureRecognizer.view as? UIScrollView else { return false }
        return isDescendant(of: scroll)
    }
}
