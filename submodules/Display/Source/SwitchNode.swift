import Foundation
import UIKit
import AsyncDisplayKit

private final class SwitchNodeViewLayer: CALayer {
    override func setNeedsDisplay() {
    }
}

private final class LegacySwitch: UIControl {
    var isOn: Bool = false {
        didSet {
            if oldValue != isOn {
                stateDidChange()
            }
        }
    }

    var onTintColor: UIColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1) {
        didSet {
            if !isLayingOut && oldValue != onTintColor {
                trackLayer.backgroundColor = getBackgroundColor()
            }
        }
    }

    override var tintColor: UIColor? {
        get {
            return super.tintColor
        }
        set {
            guard super.tintColor != newValue else { return }
            super.tintColor = newValue
            if !isLayingOut {
                trackLayer.backgroundColor = getBackgroundColor()
            }
        }
    }

    var thumbTintColor: UIColor = .white {
        didSet {
            thumbLayer.backgroundColor = thumbTintColor.cgColor
        }
    }

    var interactionBegan: (() -> Void)?
    var interactionEnded: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 51, height: 24)
    }

    let trackLayer = CALayer()
    let innerLayer = CALayer()
    let thumbLayer = CALayer()
    private let thumbView = UIView()
    let backgroundPillView = UIView()

    private var isTouchDown: Bool = false
    private var isLayingOut: Bool = false
    private var isDragging: Bool = false
    private var dragStartPosition: CGPoint = .zero
    private var dragStartThumbX: CGFloat = 0
    private var currentThumbX: CGFloat = 0
    private var originalIsOnAtDragStart: Bool = false
    private var stateChangedDuringDrag: Bool = false

    override init(frame: CGRect) {
        var actualFrame = frame
        if frame.size.width == 0 || frame.size.height == 0 {
            actualFrame.size = CGSize(width: 51, height: 24)
        }
        super.init(frame: actualFrame)
        controlDidLoad()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        controlDidLoad()
    }

    func controlDidLoad() {
        super.tintColor = UIColor(rgb: 0x808080, alpha: 0.6)

        if bounds.size.width == 0 || bounds.size.height == 0 {
            bounds.size = intrinsicContentSize
        }

        isOpaque = false
        backgroundColor = .clear
        disablesInteractiveTransitionGestureRecognizer = true

        layer.addSublayer(trackLayer)
        layer.addSublayer(innerLayer)
        layer.addSublayer(thumbLayer)

        thumbView.isUserInteractionEnabled = false
        addSubview(thumbView)
        
        backgroundPillView.isUserInteractionEnabled = false
        backgroundPillView.backgroundColor = UIColor(cgColor: getBackgroundColor())
        backgroundPillView.layer.cornerRadius = 0
        insertSubview(backgroundPillView, at: 0)

        trackLayer.backgroundColor = getBackgroundColor()
        trackLayer.borderColor = getBackgroundColor()
        trackLayer.borderWidth = 0

        innerLayer.backgroundColor = UIColor.white.cgColor

        thumbLayer.backgroundColor = thumbTintColor.cgColor
        thumbLayer.shadowColor = UIColor.gray.cgColor
        thumbLayer.shadowRadius = 2
        thumbLayer.shadowOpacity = 0.4
        thumbLayer.shadowOffset = CGSize(width: 0.75, height: 2)
        thumbLayer.isHidden = true

        addTarget(self, action: #selector(valueChanged), for: .valueChanged)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.minimumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        addGestureRecognizer(panGesture)

        layoutSublayers(of: layer)
    }

    override func sizeToFit() {
        bounds.size = intrinsicContentSize
    }

    override func layoutSublayers(of layer: CALayer) {
        guard !isLayingOut else { return }
        guard layer.bounds.width > 0 && layer.bounds.height > 0 else { return }

        isLayingOut = true
        defer { isLayingOut = false }

        super.layoutSublayers(of: layer)
        layoutTrackLayer(for: layer.bounds)
        layoutInnerLayer(for: layer.bounds)
        layoutBackgroundPill(for: layer.bounds)
        if !isDragging {
            layoutThumbLayer(for: layer.bounds)
        }
    }
    
    func layoutBackgroundPill(for bounds: CGRect) {
        let scale: CGFloat = 0.8
        let pillWidth = bounds.width * scale
        let pillHeight = bounds.height * scale
        let pillX = (bounds.width - pillWidth) / 2
        let pillY = (bounds.height - pillHeight) / 2
        
        backgroundPillView.frame = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
        backgroundPillView.layer.cornerRadius = pillHeight / 2
        backgroundPillView.backgroundColor = UIColor(cgColor: getBackgroundColor())
    }

    func layoutTrackLayer(for bounds: CGRect) {
        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        trackLayer.backgroundColor = getBackgroundColor()
    }

    func layoutInnerLayer(for bounds: CGRect) {
        let isInnerHidden = isOn || isTouchDown
        if isInnerHidden {
            innerLayer.frame = CGRect(origin: trackLayer.position, size: .zero)
            innerLayer.cornerRadius = 0
        } else {
            innerLayer.frame = CGRect(origin: trackLayer.position, size: .zero)
            innerLayer.cornerRadius = 0
        }
    }

    func layoutThumbLayer(for bounds: CGRect) {
        let size = getThumbSize()
        let origin = getThumbOrigin(for: size.width)
        thumbLayer.frame = CGRect(origin: origin, size: size)
        thumbLayer.cornerRadius = size.height / 2
        thumbView.frame = thumbLayer.frame
    }

    func stateDidChange() {
        if !isLayingOut {
            trackLayer.backgroundColor = getBackgroundColor()
            trackLayer.borderColor = getBackgroundColor()
            trackLayer.borderWidth = 0
            backgroundPillView.backgroundColor = UIColor(cgColor: getBackgroundColor())
            setNeedsLayout()
        }
    }

    func setOn(_ on: Bool, animated: Bool) {
        guard isOn != on else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        isOn = on
        if !animated {
            layoutSublayers(of: layer)
        } else {
            let thumbSize = getThumbSize()
            let insetX: CGFloat = 7
            let finalX = isOn ? bounds.width - thumbSize.width - insetX : insetX
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            thumbLayer.frame = CGRect(
                origin: CGPoint(x: finalX, y: 2),
                size: thumbSize
            )
            thumbLayer.cornerRadius = thumbSize.height / 2
            thumbView.frame = thumbLayer.frame
            CATransaction.commit()
            
            // Update track and inner layers
            layoutTrackLayer(for: bounds)
            layoutInnerLayer(for: bounds)
        }
        sendActions(for: .valueChanged)
        CATransaction.commit()
    }

    func getBackgroundColor() -> CGColor {
        let color = isOn ? onTintColor : (tintColor ?? UIColor(rgb: 0x808080, alpha: 0.6))
        return color.cgColor
    }

    func getThumbSize() -> CGSize {
        let height = bounds.height - 4
        let baseWidth = height * 1.1
        let width = isTouchDown ? baseWidth * 1.2 : baseWidth
        return CGSize(width: width, height: height)
    }

    func getThumbOrigin(for width: CGFloat) -> CGPoint {
        let insetY: CGFloat = 2
        let insetX: CGFloat = 7
        var x: CGFloat
        if isDragging {
            x = currentThumbX
        } else {
            x = isOn ? bounds.width - width - insetX : insetX
        }
        x = max(insetX, min(x, bounds.width - width - insetX))
        return CGPoint(x: x, y: insetY)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began, .changed:
            if !isDragging && gesture.state == .changed {
                isDragging = true
                isTouchDown = true
                dragStartPosition = location

                let thumbSize = getThumbSize()
                let insetX: CGFloat = 7
                dragStartThumbX = isOn ? bounds.width - thumbSize.width - insetX : insetX
                currentThumbX = dragStartThumbX
                originalIsOnAtDragStart = isOn
                stateChangedDuringDrag = false

                interactionBegan?()
            }

            if isDragging {
                let rawX = dragStartThumbX + translation.x
                let thumbSize = getThumbSize()
                let insetX: CGFloat = 7
                let minX = insetX
                let maxX = bounds.width - thumbSize.width - insetX
                
                let trackWidth = maxX - minX
                let edgeResistance: CGFloat = trackWidth * 0.2
                let resistanceFactor: CGFloat = 0.3
                
                let clampedX: CGFloat
                if rawX < minX {
                    let overshoot = minX - rawX
                    let resistance = min(overshoot * resistanceFactor, edgeResistance)
                    clampedX = minX - resistance
                } else if rawX > maxX {
                    let overshoot = rawX - maxX
                    let resistance = min(overshoot * resistanceFactor, edgeResistance)
                    clampedX = maxX + resistance
                } else {
                    clampedX = rawX
                }
                
                currentThumbX = clampedX

                let thumbCenter = currentThumbX + thumbSize.width / 2
                let switchCenter = bounds.width / 2
                
                let newIsOn = thumbCenter > switchCenter

                if newIsOn != isOn {
                    isOn = newIsOn
                    stateChangedDuringDrag = true
                    animateBackgroundColor()
                    layoutInnerLayer(for: bounds)
                    sendActions(for: .valueChanged)
                }

                CATransaction.begin()
                CATransaction.setDisableActions(true)

                thumbLayer.frame = CGRect(
                    origin: CGPoint(x: currentThumbX, y: 2),
                    size: thumbSize
                )
                thumbLayer.cornerRadius = thumbSize.height / 2
                thumbView.frame = thumbLayer.frame

                CATransaction.commit()
            }

        case .ended, .cancelled:
            if isDragging {
                let newIsOn: Bool
                if stateChangedDuringDrag {
                    newIsOn = isOn
                } else {
                    newIsOn = !originalIsOnAtDragStart
                }

                if newIsOn != isOn {
                    isOn = newIsOn
                    animateBackgroundColor()
                    layoutInnerLayer(for: bounds)
                    sendActions(for: .valueChanged)
                }

                isTouchDown = false
                let finalThumbSize = getThumbSize()
                let insetX: CGFloat = 7
                let finalX = newIsOn ? bounds.width - finalThumbSize.width - insetX : insetX

                CATransaction.begin()
                CATransaction.setAnimationDuration(0.25)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                CATransaction.setCompletionBlock { [weak self] in
                    guard let self = self else { return }
                    self.isDragging = false
                    self.currentThumbX = 0

                    self.interactionEnded?()
                }

                thumbLayer.frame = CGRect(
                    origin: CGPoint(x: finalX, y: 2),
                    size: finalThumbSize
                )
                thumbLayer.cornerRadius = finalThumbSize.height / 2
                thumbView.frame = thumbLayer.frame

                CATransaction.commit()
            }

        default:
            break
        }
    }

    private func animateBackgroundColor() {
        let newColor = getBackgroundColor()

        let currentBgColor = trackLayer.presentation()?.backgroundColor ?? trackLayer.backgroundColor

        trackLayer.removeAnimation(forKey: "backgroundColor")
        trackLayer.removeAnimation(forKey: "borderColor")

        let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
        colorAnimation.fromValue = currentBgColor
        colorAnimation.toValue = newColor
        colorAnimation.duration = 0.3
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        colorAnimation.fillMode = .forwards
        colorAnimation.isRemovedOnCompletion = false
        trackLayer.add(colorAnimation, forKey: "backgroundColor")
        trackLayer.backgroundColor = newColor

        let borderAnimation = CABasicAnimation(keyPath: "borderColor")
        borderAnimation.fromValue = currentBgColor
        borderAnimation.toValue = newColor
        borderAnimation.duration = 0.3
        borderAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        borderAnimation.fillMode = .forwards
        borderAnimation.isRemovedOnCompletion = false
        trackLayer.add(borderAnimation, forKey: "borderColor")
        trackLayer.borderColor = newColor
        
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.backgroundPillView.backgroundColor = UIColor(cgColor: newColor)
        })
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if !isDragging {
            isTouchDown = false

            interactionBegan?()
            let newIsOn = !isOn
            setOn(newIsOn, animated: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.interactionEnded?()
            }
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        if !isDragging {
            isTouchDown = false
        }
    }

    @objc private func valueChanged() { }

    var knobView: UIView? {
        return thumbView
    }
}

private final class SwitchNodeView: UISwitch {
    var interactionBegan: (() -> Void)?
    var interactionEnded: (() -> Void)?
    var shouldAdjustTrackHeight: Bool = false
    private var isAdjustingTrackHeight: Bool = false
    private var isUserTracking: Bool = false

    override class var layerClass: AnyClass {
        if #available(iOS 26.0, *) {
            return super.layerClass
        } else {
            return SwitchNodeViewLayer.self
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if shouldAdjustTrackHeight && !isIOS26OrLater() && !isAdjustingTrackHeight && !isUserTracking {
            adjustTrackHeight()
        }
    }

    func adjustTrackHeight() {
        guard !isAdjustingTrackHeight else { return }
        guard let firstSubview = self.subviews.first else { return }

        isAdjustingTrackHeight = true
        defer { isAdjustingTrackHeight = false }

        func findAllTrackViews(in view: UIView) -> [UIView] {
            var trackViews: [UIView] = []

            if view.bounds.height >= 20.0 && view.bounds.height <= 44.0 && view.bounds.width > 40 {
                trackViews.append(view)
            }

            for subview in view.subviews {
                trackViews.append(contentsOf: findAllTrackViews(in: subview))
            }

            return trackViews
        }

        let allTrackViews = findAllTrackViews(in: firstSubview)

        let targetHeight: CGFloat = 24.0
        let pillRadius = targetHeight * 0.45

        for trackView in allTrackViews {
            let currentHeight = trackView.frame.height

            if abs(currentHeight - targetHeight) > 0.5 {
                var trackFrame = trackView.frame
                let heightDiff = currentHeight - targetHeight
                trackFrame.size.height = targetHeight
                trackFrame.origin.y += heightDiff / 2.0
                trackView.frame = trackFrame
            }

            if abs(trackView.layer.cornerRadius - pillRadius) > 0.5 {
                trackView.layer.cornerRadius = pillRadius
                trackView.layer.masksToBounds = true
            }
        }
    }

    override func setOn(_ on: Bool, animated: Bool) {
        super.setOn(on, animated: animated)

        if shouldAdjustTrackHeight && !isIOS26OrLater() {
            let delay = animated ? 0.35 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.adjustTrackHeight()
            }
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.beginTracking(touch, with: event)
        if !result {
            return false
        }

        if #available(iOS 26.0, *) {
            return result
        }

        isUserTracking = true
        interactionBegan?()
        return result
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)

        if #available(iOS 26.0, *) {
            return
        }

        isUserTracking = false

        if shouldAdjustTrackHeight {
            DispatchQueue.main.async { [weak self] in
                self?.adjustTrackHeight()
            }
        }

        interactionEnded?()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)

        if #available(iOS 26.0, *) {
            return
        }

        isUserTracking = false

        if shouldAdjustTrackHeight {
            DispatchQueue.main.async { [weak self] in
                self?.adjustTrackHeight()
            }
        }

        interactionEnded?()
    }

    var knobView: UIView? {
        guard !isIOS26OrLater() else {
            return nil
        }

        if let firstSubview = self.subviews.first {
            if #available(iOS 13.0, *) {
                if firstSubview.subviews.count > 1,
                   let secondSubview = firstSubview.subviews[safe: 1],
                   let knobView = secondSubview.subviews.last {
                    return knobView
                }
            }
            if let knobView = firstSubview.subviews.last {
                return knobView
            }
        }
        return nil
    }

    private func isIOS26OrLater() -> Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

open class SwitchNode: ASDisplayNode {
    public var valueUpdated: ((Bool) -> Void)?
    public var interactionBegan: (() -> Void)?
    public var interactionEnded: (() -> Void)?

    public var frameColor = UIColor(rgb: 0xe0e0e0) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.frameColor {
                    if #available(iOS 26.0, *) {
                        (self.view as! SwitchNodeView).tintColor = self.frameColor
                    } else {
                        (self.view as! LegacySwitch).tintColor = self.frameColor
                    }
                }
            }
        }
    }
    public var handleColor = UIColor(rgb: 0xffffff) {
        didSet {
            if self.isNodeLoaded {
                if #available(iOS 26.0, *) { } else {
                    (self.view as! LegacySwitch).thumbTintColor = self.handleColor
                }
            }
        }
    }
    public var contentColor = UIColor(rgb: 0x42d451) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.contentColor {
                    if #available(iOS 26.0, *) {
                        (self.view as! SwitchNodeView).onTintColor = self.contentColor
                    } else {
                        (self.view as! LegacySwitch).onTintColor = self.contentColor
                    }
                }
            }
        }
    }

    private var _isOn: Bool = false
    public var isOn: Bool {
        get {
            return self._isOn
        } set(value) {
            if (value != self._isOn) {
                self._isOn = value
                if self.isNodeLoaded {
                    if #available(iOS 26.0, *) {
                        (self.view as! SwitchNodeView).setOn(value, animated: false)
                    } else {
                        (self.view as! LegacySwitch).setOn(value, animated: false)
                    }
                }
            }
        }
    }

    override public init() {
        super.init()

        self.setViewBlock({
            if #available(iOS 26.0, *) {
                return SwitchNodeView()
            } else {
                return LegacySwitch()
            }
        })
    }

    override open func didLoad() {
        super.didLoad()

        self.view.isAccessibilityElement = false

        if #available(iOS 26.0, *) {
            let switchView = self.view as! SwitchNodeView

            switchView.backgroundColor = self.backgroundColor
            switchView.tintColor = self.frameColor
            switchView.onTintColor = self.contentColor

            switchView.setOn(self._isOn, animated: false)
            switchView.addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)
        } else {
            let customSwitch = self.view as! LegacySwitch

            customSwitch.backgroundColor = self.backgroundColor
            customSwitch.tintColor = self.frameColor
            customSwitch.onTintColor = self.contentColor
            customSwitch.thumbTintColor = self.handleColor

            customSwitch.setOn(self._isOn, animated: false)
            customSwitch.addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)

            customSwitch.interactionBegan = { [weak self] in
                self?.interactionBegan?()
            }

            customSwitch.interactionEnded = { [weak self] in
                self?.interactionEnded?()
            }
        }
    }

    public var knobView: UIView? {
        if #available(iOS 26.0, *) {
            return nil
        }
        if let customSwitch = self.view as? LegacySwitch {
            return customSwitch.knobView
        }
        if let switchView = self.view as? SwitchNodeView {
            return switchView.knobView
        }
        return nil
    }

    public func setOn(_ value: Bool, animated: Bool) {
        self._isOn = value
        if self.isNodeLoaded {
            if #available(iOS 26.0, *) {
                (self.view as! SwitchNodeView).setOn(value, animated: animated)
            } else {
                (self.view as! LegacySwitch).setOn(value, animated: animated)
            }
        }
    }

    override open func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        if #available(iOS 26.0, *) {
            return CGSize(width: 63.0, height: 28.0)
        } else {
            return CGSize(width: 51.0, height: 24.0)
        }
    }

    @objc func switchValueChanged(_ view: UIControl) {
        if #available(iOS 26.0, *) {
            if let switchView = view as? SwitchNodeView {
                self._isOn = switchView.isOn
                self.valueUpdated?(switchView.isOn)
            }
        } else {
            if let customSwitch = view as? LegacySwitch {
                self._isOn = customSwitch.isOn
                self.valueUpdated?(customSwitch.isOn)
            }
        }
    }
}
