import UIKit

public protocol ElasticRubberBandOverlay: AnyObject {
    func beginElasticInteraction()
    func updateElasticInteraction(translation: CGPoint)
    func endElasticInteraction(velocity: CGPoint)
}

open class HighlightTrackingButton: UIButton, UIGestureRecognizerDelegate {
    private var internalHighlighted = false

    public var internalHighlightedChanged: (Bool) -> Void = { _ in }
    public var highlightedChanged: (Bool) -> Void = { _ in }

    private var elasticGestureRecognizer: UIPanGestureRecognizer?
    private weak var targetRubberBandView: ElasticRubberBandOverlay?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.setupElasticGesture()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupElasticGesture() {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(self.handleElasticPan(_:)))
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.cancelsTouchesInView = true
        gesture.delegate = self
        self.addGestureRecognizer(gesture)
        self.elasticGestureRecognizer = gesture
    }

    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === self.elasticGestureRecognizer {
            self.findRubberBandOverlay()
            if self.targetRubberBandView == nil {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === self.elasticGestureRecognizer {
            return true
        }
        return false
    }

    private func findRubberBandOverlay() {
        if self.targetRubberBandView == nil {
            var candidate: UIView? = self.superview
            while let current = candidate {
                if let rubberBandView = current as? ElasticRubberBandOverlay {
                    self.targetRubberBandView = rubberBandView
                    break
                }
                candidate = current.superview
            }
        }
    }

    @objc private func handleElasticPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            self.findRubberBandOverlay()
            self.targetRubberBandView?.beginElasticInteraction()

            if !self.internalHighlighted {
                self.internalHighlighted = true
                self.highlightedChanged(true)
                self.internalHighlightedChanged(true)
            }

        case .changed:
            guard let target = self.targetRubberBandView, let view = target as? UIView else { return }
            let translation = gesture.translation(in: view.superview)
            target.updateElasticInteraction(translation: translation)

        case .ended:
            guard let target = self.targetRubberBandView, let view = target as? UIView else { return }
            let velocity = gesture.velocity(in: view.superview)
            target.endElasticInteraction(velocity: velocity)
            self.targetRubberBandView = nil

            let location = gesture.location(in: self)
            if self.bounds.contains(location) {
                self.sendActions(for: .touchUpInside)
            }

            if self.internalHighlighted {
                self.internalHighlighted = false
                self.highlightedChanged(false)
                self.internalHighlightedChanged(false)
            }

        case .cancelled, .failed:
            guard let target = self.targetRubberBandView, let view = target as? UIView else { return }
            let velocity = gesture.velocity(in: view.superview)
            target.endElasticInteraction(velocity: velocity)
            self.targetRubberBandView = nil

            if self.internalHighlighted {
                self.internalHighlighted = false
                self.highlightedChanged(false)
                self.internalHighlightedChanged(false)
            }

        default:
            break
        }
    }

    // MARK: - Standard Tracking Overrides

    open override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.findRubberBandOverlay()
        self.targetRubberBandView?.beginElasticInteraction()

        if !self.internalHighlighted {
            self.internalHighlighted = true
            self.highlightedChanged(true)
            self.internalHighlightedChanged(true)
        }
        return super.beginTracking(touch, with: event)
    }

    open override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let isPanActive = self.elasticGestureRecognizer?.state == .began || self.elasticGestureRecognizer?.state == .changed

        if !isPanActive {
            self.targetRubberBandView?.endElasticInteraction(velocity: .zero)
            self.targetRubberBandView = nil
        }

        if self.internalHighlighted && !isPanActive {
            self.internalHighlighted = false
            self.highlightedChanged(false)
            self.internalHighlightedChanged(false)
        }
        super.endTracking(touch, with: event)
    }

    open override func cancelTracking(with event: UIEvent?) {
        let isPanActive = self.elasticGestureRecognizer?.state == .began || self.elasticGestureRecognizer?.state == .changed

        if !isPanActive {
            self.targetRubberBandView?.endElasticInteraction(velocity: .zero)
            self.targetRubberBandView = nil
        }

        if self.internalHighlighted && !isPanActive {
            self.internalHighlighted = false
            self.highlightedChanged(false)
            self.internalHighlightedChanged(false)
        }
        super.cancelTracking(with: event)
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let isPanActive = self.elasticGestureRecognizer?.state == .began || self.elasticGestureRecognizer?.state == .changed

        if !isPanActive {
            self.targetRubberBandView?.endElasticInteraction(velocity: .zero)
            self.targetRubberBandView = nil
        }

        if self.internalHighlighted && !isPanActive {
            self.internalHighlighted = false
            self.highlightedChanged(false)
            self.internalHighlightedChanged(false)
        }
        super.touchesCancelled(touches, with: event)
    }
}
