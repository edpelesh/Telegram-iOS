import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow
import LiquidGlassEffect

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount {
                return false
            }
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            if lhs.markPositions != rhs.markPositions {
                return false
            }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content {
            return false
        }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor {
            return false
        }
        if lhs.trackForegroundColor != rhs.trackForegroundColor {
            return false
        }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor {
            return false
        }
        if lhs.knobSize != rhs.knobSize {
            return false
        }
        if lhs.knobColor != rhs.knobColor {
            return false
        }
        return true
    }
    
    final class SliderView: UISlider {
        
    }
    
    public final class View: UIView {
        private var nativeSliderView: SliderView?
        private var sliderView: TGPhotoEditorSliderView?
        private var glassKnob: LiquidGlassKnobView?
        
        private var component: SliderComponent?
        private weak var state: EmptyComponentState?
        private var interactionUpdateTimer: ConstantDisplayLinkAnimator?
        
        private var lastGestureVelocity: SIMD2<Float> = SIMD2<Float>(0, 0)
        private var lastTouchLocation: CGPoint?
        private var lastTouchTime: CFTimeInterval = 0
        private var lastKnobPosition: SIMD2<Float>?
        private var isInteracting: Bool = false
        
        public var hitTestTarget: UIView? {
            return self.sliderView
        }
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
                
        public func cancelGestures() {
            if let sliderView = self.sliderView, let gestureRecognizers = sliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    if gestureRecognizer.isEnabled {
                        gestureRecognizer.isEnabled = false
                        gestureRecognizer.isEnabled = true
                    }
                }
            }
        }
        
        func update(component: SliderComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            if #available(iOS 26.0, *), component.useNative {
                let sliderView: SliderView
                if let current = self.nativeSliderView {
                    sliderView = current
                } else {
                    sliderView = SliderView()
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    
                    self.addSubview(sliderView)
                    self.nativeSliderView = sliderView
                    
                    switch component.content {
                    case let .continuous(continuous):
                        sliderView.minimumValue = Float(continuous.minValue ?? 0.0)
                        sliderView.maximumValue = 1.0
                    case let .discrete(discrete):
                        sliderView.minimumValue = 0.0
                        sliderView.maximumValue = Float(discrete.valueCount - 1)
                        sliderView.trackConfiguration = .init(numberOfTicks: discrete.valueCount)
                    }
                }
                switch component.content {
                case let .continuous(continuous):
                    sliderView.value = Float(continuous.value)
                case let .discrete(discrete):
                    sliderView.value = Float(discrete.value)
                }
                sliderView.minimumTrackTintColor = component.trackForegroundColor
                sliderView.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
            } else {
                var internalIsTrackingUpdated: ((Bool) -> Void)?
                if let isTrackingUpdated = component.isTrackingUpdated {
                    internalIsTrackingUpdated = { [weak self] isTracking in
                        if let self {
                            if !"".isEmpty {
                                if isTracking {
                                    self.sliderView?.bordered = true
                                } else {
                                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: { [weak self] in
                                        self?.sliderView?.bordered = false
                                    })
                                }
                            }
                        }
                        isTrackingUpdated(isTracking)
                    }
                }
                
                let sliderView: TGPhotoEditorSliderView
                if let current = self.sliderView {
                    sliderView = current
                } else {
                    sliderView = TGPhotoEditorSliderView()
                    sliderView.enablePanHandling = true
                    sliderView.enableEdgeTap = false
                    sliderView.useGlass = true
                    if let knobSize = component.knobSize {
                        sliderView.lineSize = knobSize + 4.0
                    } else {
                        sliderView.lineSize = 4.0
                    }
                    sliderView.trackCornerRadius = sliderView.lineSize * 0.5
                    sliderView.dotSize = 0.0
                    sliderView.minimumValue = 0.0
                    sliderView.startValue = 0.0
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    
                    switch component.content {
                    case let .discrete(discrete):
                        sliderView.maximumValue = CGFloat(discrete.valueCount - 1)
                        sliderView.positionsCount = discrete.valueCount
                        sliderView.useLinesForPositions = true
                        sliderView.markPositions = discrete.markPositions
                    case .continuous:
                        sliderView.maximumValue = 1.0
                    }
                    
                    sliderView.backgroundColor = nil
                    sliderView.isOpaque = false
                    sliderView.backColor = component.trackBackgroundColor
                    sliderView.startColor = component.trackBackgroundColor
                    sliderView.trackColor = component.trackForegroundColor
                    sliderView.knobImage = nil
                    sliderView.clipsToBounds = false


                    sliderView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size)
                    sliderView.hitTestEdgeInsets = UIEdgeInsets(top: -sliderView.frame.minX, left: 0.0, bottom: 0.0, right: -sliderView.frame.minX)
                    
                    var knobFrame = sliderView.bounds
                    knobFrame.size.height += 10.0
                    knobFrame.size.width += 30.0
                    knobFrame.origin.y -= 5.0
                    knobFrame.origin.x -= 15.0
                    let glassKnob = LiquidGlassKnobView(frame: knobFrame, disableVerticalStretch: true)
                    glassKnob.isUserInteractionEnabled = false
                    sliderView.addSubview(glassKnob)
                    self.glassKnob = glassKnob

                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.layer.allowsGroupOpacity = true
                    self.sliderView = sliderView
                    self.addSubview(sliderView)
                }
                sliderView.lowerBoundTrackColor = component.minTrackForegroundColor
                switch component.content {
                case let .discrete(discrete):
                    sliderView.value = CGFloat(discrete.value)
                    if let minValue = discrete.minValue {
                        sliderView.lowerBoundValue = CGFloat(minValue)
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                case let .continuous(continuous):
                    sliderView.value = continuous.value
                    if let minValue = continuous.minValue {
                        sliderView.lowerBoundValue = minValue
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                }
                
                DispatchQueue.main.async { [weak self] in
                    self?.updateKnobPosition()
                }

                sliderView.interactionBegan = {
                    internalIsTrackingUpdated?(true)
                    if let glassKnob = self.glassKnob {
                        glassKnob.setInteractionState(true)
                    }
                    self.lastGestureVelocity = SIMD2<Float>(0, 0)
                    self.lastTouchLocation = nil
                    self.lastTouchTime = 0
                    
                    if let sliderView = self.sliderView, let glassKnob = self.glassKnob {
                        sliderView.setNeedsLayout()
                        sliderView.layoutIfNeeded()
                        
                        let knobCenterInSlider = sliderView.knobView.center
                        let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSlider, from: sliderView)
                        let quantizedX = round(knobCenterInGlassKnob.x)
                        let quantizedY = round(knobCenterInGlassKnob.y)
                        let lockedPosition = SIMD2<Float>(Float(quantizedX), Float(quantizedY))
                        self.lastKnobPosition = lockedPosition
                        glassKnob.updateKnobPosition(lockedPosition)
                    }
                    
                    self.isInteracting = true
                    self.startInteractionTracking()
                }
                sliderView.interactionEnded = {
                    internalIsTrackingUpdated?(false)
                    self.stopInteractionTracking()
                    self.glassKnob?.setInteractionState(false)
                    self.glassKnob?.updateTouchPosition(nil, velocity: self.lastGestureVelocity)
                    self.lastGestureVelocity = SIMD2<Float>(0, 0)
                    self.lastTouchLocation = nil
                    self.lastTouchTime = 0
                    
                    if case .discrete = component.content, let sliderView = self.sliderView, let glassKnob = self.glassKnob, sliderView.positionsCount > 1 {
                        let startPosition = self.lastKnobPosition
                        
                        sliderView.setNeedsLayout()
                        sliderView.layoutIfNeeded()
                        
                        let knobCenterInSlider = sliderView.knobView.center
                        let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSlider, from: sliderView)
                        let quantizedX = round(knobCenterInGlassKnob.x)
                        let quantizedY = round(knobCenterInGlassKnob.y)
                        let targetPosition = SIMD2<Float>(Float(quantizedX), Float(quantizedY))
                        
                        if let startPos = startPosition, abs(targetPosition.x - startPos.x) > 0.5 || abs(targetPosition.y - startPos.y) > 0.5 {
                            let startTime = CACurrentMediaTime()
                            let duration = 0.5
                            
                            let animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/120.0, repeats: true) { [weak self] timer in
                                guard let self = self else {
                                    timer.invalidate()
                                    return
                                }
                                
                                let elapsed = CACurrentMediaTime() - startTime
                                let t = min(1.0, CGFloat(elapsed / duration))
                                
                                let c1: CGFloat = 1.70158
                                let c3: CGFloat = c1 + 1.0
                                let easedProgress = 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
                                
                                let progress = max(0.0, min(1.05, easedProgress))
                                
                                let currentX = Float(startPos.x) + Float(progress) * (targetPosition.x - Float(startPos.x))
                                let currentY = Float(startPos.y) + Float(progress) * (targetPosition.y - Float(startPos.y))
                                let interpolatedPosition = SIMD2<Float>(currentX, currentY)
                                
                                glassKnob.updateKnobPosition(interpolatedPosition)
                                
                                if t >= 1.0 {
                                    timer.invalidate()
                                    self.lastKnobPosition = targetPosition
                                    self.isInteracting = false
                                    self.updateKnobPosition()
                                }
                            }
                            RunLoop.main.add(animationTimer, forMode: .common)
                        } else {
                            self.isInteracting = false
                            self.updateKnobPosition()
                        }
                    } else {
                        self.isInteracting = false
                        self.updateKnobPosition()
                    }
                }
                
                sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                sliderView.addTarget(self, action: #selector(self.sliderTouchDown), for: .touchDown)
                sliderView.addTarget(self, action: #selector(self.sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
                sliderView.hitTestEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
                
                if let glassKnob = self.glassKnob {
                    var knobFrame = sliderView.bounds
                    knobFrame.size.height += 10.0
                    knobFrame.size.width += 40.0
                    knobFrame.origin.y -= 5.0
                    knobFrame.origin.x -= 20.0
                    glassKnob.frame = knobFrame
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.updateKnobPosition()
                        glassKnob.setNeedsDisplay()
                    }
                }
            }
            
            return size
        }
        
        private func startInteractionTracking() {
            interactionUpdateTimer?.invalidate()
            interactionUpdateTimer = nil
            
            let displayLink = ConstantDisplayLinkAnimator(update: { [weak self] in
                self?.updateInteractionState()
            })
            displayLink.isPaused = false
            self.interactionUpdateTimer = displayLink
        }
        
        private func stopInteractionTracking() {
            interactionUpdateTimer?.isPaused = true
            interactionUpdateTimer = nil
        }
        
        private func updateKnobPosition(force: Bool = false) {
            guard let sliderView = self.sliderView,
                  let glassKnob = self.glassKnob else {
                return
            }
            
            guard sliderView.bounds.width > 0 && sliderView.bounds.height > 0 else {
                DispatchQueue.main.async { [weak self] in
                    self?.updateKnobPosition(force: force)
                }
                return
            }
            
            if isInteracting && !force {
                return
            }
            
            let knobCenterInSlider = sliderView.knobView.center
            let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSlider, from: sliderView)
            
            let quantizedX = round(knobCenterInGlassKnob.x)
            let quantizedY = round(knobCenterInGlassKnob.y)
            let newPosition = SIMD2<Float>(Float(quantizedX), Float(quantizedY))
            
            if let lastPosition = lastKnobPosition {
                let threshold: Float = 0.5
                if abs(newPosition.x - lastPosition.x) < threshold && abs(newPosition.y - lastPosition.y) < threshold {
                    return
                }
            }
            
            lastKnobPosition = newPosition
            glassKnob.updateKnobPosition(newPosition)
        }
        
        private func updateInteractionState() {
            guard let sliderView = self.sliderView,
                  let glassKnob = self.glassKnob else {
                return
            }

            let knobCenterInSlider = sliderView.knobView.center
            let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSlider, from: sliderView)
            
            let quantizedX = round(knobCenterInGlassKnob.x)
            let quantizedY = round(knobCenterInGlassKnob.y)
            let currentPosition = SIMD2<Float>(Float(quantizedX), Float(quantizedY))
            
            if !isInteracting {
                if lastKnobPosition == nil ||
                   abs(currentPosition.x - lastKnobPosition!.x) > 0.5 || 
                   abs(currentPosition.y - lastKnobPosition!.y) > 0.5 {
                    lastKnobPosition = currentPosition
                    glassKnob.updateKnobPosition(currentPosition)
                }
            }
            
            let storedKnobPosition: SIMD2<Float>
            if isInteracting {
                if let lastPos = lastKnobPosition {
                    storedKnobPosition = lastPos
                } else {
                    storedKnobPosition = currentPosition
                }
            } else {
                if let lastPos = lastKnobPosition, lastPos.x != 0 || lastPos.y != 0 {
                    storedKnobPosition = lastPos
                } else {
                    storedKnobPosition = currentPosition
                    if lastKnobPosition == nil {
                        lastKnobPosition = currentPosition
                        glassKnob.updateKnobPosition(currentPosition)
                    }
                }
            }
            
            if let gestureRecognizers = sliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    var touchLocation: CGPoint?
                    var gestureVel = CGPoint.zero
                    
                    if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                        if panGesture.state == .began || panGesture.state == .changed {
                            touchLocation = panGesture.location(in: sliderView)
                            gestureVel = panGesture.velocity(in: sliderView)
                        }
                    } else if let longPressGesture = gestureRecognizer as? UILongPressGestureRecognizer {
                        if longPressGesture.state == .began || longPressGesture.state == .changed {
                            let currentLocation = longPressGesture.location(in: sliderView)
                            let currentTime = CACurrentMediaTime()
                            
                            if let lastLocation = lastTouchLocation, lastTouchTime > 0 {
                                let dt = CGFloat(currentTime - lastTouchTime)
                                if dt > 0 {
                                    gestureVel = CGPoint(
                                        x: (currentLocation.x - lastLocation.x) / dt,
                                        y: (currentLocation.y - lastLocation.y) / dt
                                    )
                                }
                            }
                            
                            lastTouchLocation = currentLocation
                            lastTouchTime = currentTime
                            touchLocation = currentLocation
                        }
                    }
                    
                    if let touchLocation = touchLocation {
                        let velocityInGlassKnob = glassKnob.convert(CGPoint(x: gestureVel.x, y: gestureVel.y), from: sliderView)
                        let gestureVelocity = SIMD2<Float>(Float(velocityInGlassKnob.x), Float(velocityInGlassKnob.y))
                        lastGestureVelocity = gestureVelocity
                        
                        let touchLocationInGlassKnob = glassKnob.convert(touchLocation, from: sliderView)
                        let touchRelativeToKnob = SIMD2<Float>(
                            Float(touchLocationInGlassKnob.x - CGFloat(storedKnobPosition.x)),
                            Float(touchLocationInGlassKnob.y - CGFloat(storedKnobPosition.y))
                        )
                        
                        glassKnob.updateTouchPosition(touchRelativeToKnob, velocity: gestureVelocity)
                        break
                    }
                }
            }
        
        }
        
        @objc private func sliderValueChanged() {
            guard let component = self.component else {
                return
            }
            let floatValue: CGFloat
            if let sliderView = self.sliderView {
                floatValue = sliderView.value
                updateKnobPosition(force: true)
            } else if let nativeSliderView = self.nativeSliderView {
                floatValue = CGFloat(nativeSliderView.value)
            } else {
                return
            }
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
            }
        }
        
        
        @objc private func sliderTouchDown() {
            self.startInteractionTracking()
            self.glassKnob?.setInteractionState(true)
        }
        
        @objc private func sliderTouchUp() {
            self.glassKnob?.setInteractionState(false)
            self.glassKnob?.updateTouchPosition(nil, velocity: lastGestureVelocity)
            self.lastGestureVelocity = SIMD2<Float>(0, 0)
            self.lastTouchLocation = nil
            self.lastTouchTime = 0
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
