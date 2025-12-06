import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import UIKitRuntimeUtils
import CoreImage
import AppBundle

private final class ContentContainer: UIView {
    private let maskContentView: UIView

    init(maskContentView: UIView) {
        self.maskContentView = maskContentView

        super.init(frame: CGRect())
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else {
            return nil
        }
        if result === self {
            if let gestureRecognizers = self.gestureRecognizers, !gestureRecognizers.isEmpty {
                return result
            }
            return nil
        }
        return result
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)

        if let subview = subview as? GlassBackgroundView.ContentView {
            self.maskContentView.addSubview(subview.tintMask)
        }
    }

    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)

        if let subview = subview as? GlassBackgroundView.ContentView {
            subview.tintMask.removeFromSuperview()
        }
    }
}

public class GlassBackgroundView: UIView, ElasticRubberBandOverlay {
    public protocol ContentView: UIView {
        var tintMask: UIView { get }
    }

    open class ContentLayer: SimpleLayer {
        public var targetLayer: CALayer?

        override init() {
            super.init()
        }

        override init(layer: Any) {
            super.init(layer: layer)
        }

        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override public var position: CGPoint {
            get {
                return super.position
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.position = value
                }
                super.position = value
            }
        }

        override public var bounds: CGRect {
            get {
                return super.bounds
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.bounds = value
                }
                super.bounds = value
            }
        }

        override public var anchorPoint: CGPoint {
            get {
                return super.anchorPoint
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.anchorPoint = value
                }
                super.anchorPoint = value
            }
        }

        override public var anchorPointZ: CGFloat {
            get {
                return super.anchorPointZ
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.anchorPointZ = value
                }
                super.anchorPointZ = value
            }
        }

        override public var opacity: Float {
            get {
                return super.opacity
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.opacity = value
                }
                super.opacity = value
            }
        }

        override public var sublayerTransform: CATransform3D {
            get {
                return super.sublayerTransform
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.sublayerTransform = value
                }
                super.sublayerTransform = value
            }
        }

        override public var transform: CATransform3D {
            get {
                return super.transform
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.transform = value
                }
                super.transform = value
            }
        }

        override public func add(_ animation: CAAnimation, forKey key: String?) {
            if let targetLayer = self.targetLayer {
                targetLayer.add(animation, forKey: key)
            }

            super.add(animation, forKey: key)
        }

        override public func removeAllAnimations() {
            if let targetLayer = self.targetLayer {
                targetLayer.removeAllAnimations()
            }

            super.removeAllAnimations()
        }

        override public func removeAnimation(forKey: String) {
            if let targetLayer = self.targetLayer {
                targetLayer.removeAnimation(forKey: forKey)
            }

            super.removeAnimation(forKey: forKey)
        }
    }

    public final class ContentColorView: UIView, ContentView {
        override public static var layerClass: AnyClass {
            return ContentLayer.self
        }

        public let tintMask: UIView

        override public init(frame: CGRect) {
            self.tintMask = UIView()

            super.init(frame: CGRect())

            self.tintMask.tintColor = .black
        }

        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    public final class ContentImageView: UIImageView, ContentView {
        override public static var layerClass: AnyClass {
            return ContentLayer.self
        }

        private let tintImageView: UIImageView
        public var tintMask: UIView {
            return self.tintImageView
        }

        override public var image: UIImage? {
            didSet {
                self.tintImageView.image = self.image
            }
        }

        override public var tintColor: UIColor? {
            didSet {
                if self.tintColor != oldValue {
                    self.setMonochromaticEffect(tintColor: self.tintColor)
                }
            }
        }

        override public init(frame: CGRect) {
            self.tintImageView = UIImageView()

            super.init(frame: CGRect())

            self.tintImageView.tintColor = .black
        }

        override public init(image: UIImage?) {
            self.tintImageView = UIImageView()

            super.init(image: image)

            self.tintImageView.image = image
            self.tintImageView.tintColor = .black
        }

        override public init(image: UIImage?, highlightedImage: UIImage?) {
            self.tintImageView = UIImageView()

            super.init(image: image, highlightedImage: highlightedImage)

            self.tintImageView.image = image
            self.tintImageView.tintColor = .black
        }

        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    public struct TintColor: Equatable {
        public enum Kind {
            case panel
            case custom
        }

        public let kind: Kind
        public let color: UIColor
        public let innerColor: UIColor?

        public init(kind: Kind, color: UIColor, innerColor: UIColor? = nil) {
            self.kind = kind
            self.color = color
            self.innerColor = innerColor
        }
    }

    public enum Shape: Equatable {
        case roundedRect(cornerRadius: CGFloat)
    }

    private final class ClippingShapeContext {
        let view: UIView

        private(set) var shape: Shape?

        init(view: UIView) {
            self.view = view
        }

        func update(shape: Shape, size: CGSize, transition: ComponentTransition) {
            self.shape = shape

            switch shape {
            case let .roundedRect(cornerRadius):
                transition.setCornerRadius(layer: self.view.layer, cornerRadius: cornerRadius)
            }
        }
    }

    public struct Params: Equatable {
        public let shape: Shape
        public let isDark: Bool
        public let tintColor: TintColor
        public let isInteractive: Bool

        init(shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool) {
            self.shape = shape
            self.isDark = isDark
            self.tintColor = tintColor
            self.isInteractive = isInteractive
        }
    }

    private let backgroundNode: NavigationBackgroundNode?

    private let nativeView: UIVisualEffectView?
    private let nativeViewClippingContext: ClippingShapeContext?
    private let nativeParamsView: EffectSettingsContainerView?

    private let foregroundView: UIImageView?
    private let shadowView: UIImageView?

    private let maskContainerView: UIView
    public let maskContentView: UIView
    private let contentContainer: ContentContainer

    private var innerBackgroundView: UIView?

    public var contentView: UIView {
        if let nativeView = self.nativeView {
            return nativeView.contentView
        } else {
            return self.contentContainer
        }
    }

    public private(set) var params: Params?

    public static var useCustomGlassImpl: Bool = false

    public override init(frame: CGRect) {
        if #available(iOS 26.0, *), !GlassBackgroundView.useCustomGlassImpl {
            self.backgroundNode = nil

            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = false
            let nativeView = UIVisualEffectView(effect: glassEffect)
            self.nativeViewClippingContext = ClippingShapeContext(view: nativeView)
            self.nativeView = nativeView

            let nativeParamsView = EffectSettingsContainerView(frame: CGRect())
            self.nativeParamsView = nativeParamsView

            nativeParamsView.addSubview(nativeView)

            self.foregroundView = nil
            self.shadowView = nil
        } else {
            let backgroundNode = NavigationBackgroundNode(color: .black, enableBlur: true, customBlurRadius: 8.0)
            self.backgroundNode = backgroundNode
            self.nativeView = nil
            self.nativeViewClippingContext = nil
            self.nativeParamsView = nil
            self.foregroundView = UIImageView()

            self.shadowView = UIImageView()
        }

        self.maskContainerView = UIView()
        self.maskContainerView.backgroundColor = .white
        if let filter = CALayer.luminanceToAlpha() {
            self.maskContainerView.layer.filters = [filter]
        }

        self.maskContentView = UIView()
        self.maskContainerView.addSubview(self.maskContentView)

        self.contentContainer = ContentContainer(maskContentView: self.maskContentView)

        super.init(frame: frame)

        if let shadowView = self.shadowView {
            self.addSubview(shadowView)
        }
        if let nativeParamsView = self.nativeParamsView {
            self.addSubview(nativeParamsView)
        }
        if let backgroundNode = self.backgroundNode {
            self.addSubview(backgroundNode.view)
        }
        if let foregroundView = self.foregroundView {
            self.addSubview(foregroundView)
            foregroundView.mask = self.maskContainerView
        }
        self.addSubview(self.contentContainer)

        self.setupHighlightLayer()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let highlightLayer = CALayer()
    private let highlightMaskLayer = CAGradientLayer()
    private let borderHighlightLayer = CAShapeLayer()

    private func setupHighlightLayer() {
        self.highlightLayer.backgroundColor = UIColor.white.cgColor
        self.highlightLayer.compositingFilter = "plusLighter"
        self.highlightLayer.zPosition = CGFloat.greatestFiniteMagnitude
        self.highlightLayer.masksToBounds = true

        self.highlightMaskLayer.type = .radial
        self.highlightMaskLayer.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.25).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        self.highlightMaskLayer.locations = [0.0, 0.3, 1.0]
        self.highlightMaskLayer.bounds = CGRect(x: 0, y: 0, width: 400.0, height: 400.0)
        self.highlightMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.highlightMaskLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.highlightMaskLayer.endPoint = CGPoint(x: 1.0, y: 1.0)

        self.highlightLayer.mask = self.highlightMaskLayer
        self.highlightLayer.opacity = 0.0

        self.layer.addSublayer(self.highlightLayer)

        self.borderHighlightLayer.fillColor = nil
        self.borderHighlightLayer.strokeColor = UIColor.white.cgColor
        self.borderHighlightLayer.lineWidth = 1.0
        self.borderHighlightLayer.compositingFilter = "overlayBlendMode"
        self.borderHighlightLayer.zPosition = CGFloat.greatestFiniteMagnitude + 1

        let borderMask = CAGradientLayer()
        borderMask.type = .radial
        borderMask.colors = [
            UIColor.white.withAlphaComponent(0.9).cgColor,
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        borderMask.locations = [0.0, 0.4, 1.0]
        borderMask.bounds = CGRect(x: 0, y: 0, width: 600.0, height: 600.0)
        borderMask.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        borderMask.startPoint = CGPoint(x: 0.5, y: 0.5)
        borderMask.endPoint = CGPoint(x: 1.0, y: 1.0)

        self.borderHighlightLayer.mask = borderMask
        self.borderHighlightLayer.opacity = 0.0

        self.layer.addSublayer(self.borderHighlightLayer)
    }

    private var initialTouchPoint: CGPoint = .zero

    public func updateInitialTouchPoint(_ point: CGPoint) {
        self.initialTouchPoint = point
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.initialTouchPoint = point

        if let nativeView = self.nativeView {
            if let result = nativeView.hitTest(self.convert(point, to: nativeView), with: event) {
                return result
            }
        } else {
            if let result = self.contentContainer.hitTest(self.convert(point, to: self.contentContainer), with: event) {
                return result
            }
        }
        return nil
    }

    public func update(size: CGSize, cornerRadius: CGFloat, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRect(cornerRadius: cornerRadius), isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, transition: transition)
    }

    public func update(size: CGSize, shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, transition: ComponentTransition) {
        if let nativeView = self.nativeView, let nativeViewClippingContext = self.nativeViewClippingContext, (nativeView.bounds.size != size || nativeViewClippingContext.shape != shape) {

            nativeViewClippingContext.update(shape: shape, size: size, transition: transition)
            if transition.animation.isImmediate {
                nativeView.frame = CGRect(origin: CGPoint(), size: size)
            } else {
                let nativeFrame = CGRect(origin: CGPoint(), size: size)
                transition.setFrame(view: nativeView, frame: nativeFrame)
            }
        }
        if let backgroundNode = self.backgroundNode {
            backgroundNode.updateColor(color: .clear, forceKeepBlur: tintColor.color.alpha != 1.0, transition: transition.containedViewLayoutTransition)

            switch shape {
            case let .roundedRect(cornerRadius):
                backgroundNode.update(size: size, cornerRadius: cornerRadius, transition: transition.containedViewLayoutTransition)
            }
            transition.setFrame(view: backgroundNode.view, frame: CGRect(origin: CGPoint(), size: size))
        }

        let shadowInset: CGFloat = 32.0

        if let innerColor = tintColor.innerColor {
            let innerBackgroundFrame = CGRect(origin: CGPoint(), size: size).insetBy(dx: 3.0, dy: 3.0)
            let innerBackgroundRadius = min(innerBackgroundFrame.width, innerBackgroundFrame.height) * 0.5

            let innerBackgroundView: UIView
            var innerBackgroundTransition = transition
            var animateIn = false
            if let current = self.innerBackgroundView {
                innerBackgroundView = current
            } else {
                innerBackgroundView = UIView()
                innerBackgroundTransition = innerBackgroundTransition.withAnimation(.none)
                self.innerBackgroundView = innerBackgroundView
                self.contentView.insertSubview(innerBackgroundView, at: 0)

                innerBackgroundView.frame = innerBackgroundFrame
                innerBackgroundView.layer.cornerRadius = innerBackgroundRadius
                animateIn = true
            }

            innerBackgroundView.backgroundColor = innerColor
            innerBackgroundTransition.setFrame(view: innerBackgroundView, frame: innerBackgroundFrame)
            innerBackgroundTransition.setCornerRadius(layer: innerBackgroundView.layer, cornerRadius: innerBackgroundRadius)

            if animateIn {
                transition.animateAlpha(view: innerBackgroundView, from: 0.0, to: 1.0)
                transition.animateScale(view: innerBackgroundView, from: 0.001, to: 1.0)
            }
        } else if let innerBackgroundView = self.innerBackgroundView {
            self.innerBackgroundView = nil

            transition.setAlpha(view: innerBackgroundView, alpha: 0.0, completion: { [weak innerBackgroundView] _ in
                innerBackgroundView?.removeFromSuperview()
            })
            transition.setScale(view: innerBackgroundView, scale: 0.001)

            innerBackgroundView.removeFromSuperview()
        }

        let params = Params(shape: shape, isDark: isDark, tintColor: tintColor, isInteractive: isInteractive)
        if self.params != params {
            self.params = params

            let outerCornerRadius: CGFloat
            switch shape {
            case let .roundedRect(cornerRadius):
                outerCornerRadius = cornerRadius
            }

            if let shadowView = self.shadowView {
                let shadowInnerInset: CGFloat = 0.5
                shadowView.image = generateImage(CGSize(width: shadowInset * 2.0 + outerCornerRadius * 2.0, height: shadowInset * 2.0 + outerCornerRadius * 2.0), rotatedContext: { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))

                    context.setFillColor(UIColor.black.cgColor)
                    context.setShadow(offset: CGSize(width: 0.0, height: 1.0), blur: 40.0, color: UIColor(white: 0.0, alpha: 0.04).cgColor)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset + shadowInnerInset, y: shadowInset + shadowInnerInset), size: CGSize(width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0, height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0)))

                    context.setFillColor(UIColor.clear.cgColor)
                    context.setBlendMode(.copy)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset + shadowInnerInset, y: shadowInset + shadowInnerInset), size: CGSize(width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0, height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0)))
                })?.stretchableImage(withLeftCapWidth: Int(shadowInset + outerCornerRadius), topCapHeight: Int(shadowInset + outerCornerRadius))
            }

            if let foregroundView = self.foregroundView {
                foregroundView.image = GlassBackgroundView.generateLegacyGlassImage(size: CGSize(width: outerCornerRadius * 2.0, height: outerCornerRadius * 2.0), inset: shadowInset, isDark: isDark, fillColor: tintColor.color)
            } else {
                if let nativeParamsView = self.nativeParamsView, let nativeView = self.nativeView {
                    if #available(iOS 26.0, *) {
                        let glassEffect = UIGlassEffect(style: .regular)
                        switch tintColor.kind {
                        case .panel:
                            glassEffect.tintColor = UIColor(white: isDark ? 0.0 : 1.0, alpha: 0.1)
                        case .custom:
                            glassEffect.tintColor = tintColor.color
                        }
                        glassEffect.isInteractive = params.isInteractive

                        if transition.animation.isImmediate {
                            nativeView.effect = glassEffect
                        } else {
                            UIView.animate(withDuration: 0.2, animations: {
                                nativeView.effect = glassEffect
                            })
                        }

                        if isDark {
                            nativeParamsView.lumaMin = 0.0
                            nativeParamsView.lumaMax = 0.15
                        } else {
                            nativeParamsView.lumaMin = 0.6
                            nativeParamsView.lumaMax = 0.61
                        }
                    }
                }
            }
        }

        transition.setFrame(view: self.maskContainerView, frame: CGRect(origin: CGPoint(), size: CGSize(width: size.width + shadowInset * 2.0, height: size.height + shadowInset * 2.0)))
        transition.setFrame(view: self.maskContentView, frame: CGRect(origin: CGPoint(x: shadowInset, y: shadowInset), size: size))
        if let foregroundView = self.foregroundView {
            transition.setFrame(view: foregroundView, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        if let shadowView = self.shadowView {
            transition.setFrame(view: shadowView, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        transition.setFrame(view: self.contentContainer, frame: CGRect(origin: CGPoint(), size: size))
    }

    // MARK: - Elastic Interaction Logic

    private var displayLink: SharedDisplayLinkDriver.Link?

    private let stiffness: CGFloat = 350.0
    private let damping: CGFloat = 25.0
    private let mass: CGFloat = 1.0
    private let stretchSensitivity: CGFloat = 0.0025
    private let maxStretch: CGFloat = 1.15
    private let resistanceFactor: CGFloat = 0.05

    private let scaleStiffness: CGFloat = 400.0
    private let scaleDamping: CGFloat = 30.0
    private let activeScaleTarget: CGFloat = 1.05

    private var isInteracting: Bool = false
    private var position: CGPoint = .zero
    private var velocity: CGPoint = .zero
    private var targetPosition: CGPoint = .zero

    private var rawTranslation: CGPoint = .zero

    private var currentScale: CGFloat = 1.0
    private var scaleVelocity: CGFloat = 0.0

    public var elasticMovementEnabled: Bool = true

    public func beginElasticInteraction() {
        if !self.isInteracting {
            self.isInteracting = true
            self.velocity = .zero
            self.rawTranslation = .zero

            let fadeGlow = CABasicAnimation(keyPath: "opacity")
            fadeGlow.fromValue = self.highlightLayer.presentation()?.opacity ?? 0.0
            fadeGlow.toValue = 1.0
            fadeGlow.duration = 0.15
            fadeGlow.timingFunction = CAMediaTimingFunction(name: .easeOut)

            self.highlightLayer.opacity = 1.0
            self.highlightLayer.add(fadeGlow, forKey: "fadeIn")

            let fadeBorder = CABasicAnimation(keyPath: "opacity")
            fadeBorder.fromValue = self.borderHighlightLayer.presentation()?.opacity ?? 0.0
            fadeBorder.toValue = 1.0
            fadeBorder.duration = 0.12
            fadeBorder.timingFunction = CAMediaTimingFunction(name: .easeOut)

            self.borderHighlightLayer.opacity = 1.0
            self.borderHighlightLayer.add(fadeBorder, forKey: "fadeIn")

            self.startDisplayLink()
        }
    }

    public func updateElasticInteraction(translation: CGPoint) {
        self.rawTranslation = translation
        self.targetPosition = CGPoint(x: translation.x * self.resistanceFactor, y: translation.y * self.resistanceFactor)

        if self.isInteracting {
            self.position = self.targetPosition
        }
    }

    public func endElasticInteraction(velocity: CGPoint) {
        self.isInteracting = false
        self.targetPosition = .zero
        self.rawTranslation = .zero
        self.velocity = CGPoint(x: velocity.x * self.resistanceFactor, y: velocity.y * self.resistanceFactor)

        let fadeGlow = CABasicAnimation(keyPath: "opacity")
        fadeGlow.fromValue = self.highlightLayer.presentation()?.opacity ?? 1.0
        fadeGlow.toValue = 0.0
        fadeGlow.duration = 0.25
        fadeGlow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        self.highlightLayer.opacity = 0.0
        self.highlightLayer.add(fadeGlow, forKey: "fadeOut")

        let fadeBorder = CABasicAnimation(keyPath: "opacity")
        fadeBorder.fromValue = self.borderHighlightLayer.presentation()?.opacity ?? 1.0
        fadeBorder.toValue = 0.0
        fadeBorder.duration = 0.25
        fadeBorder.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        self.borderHighlightLayer.opacity = 0.0
        self.borderHighlightLayer.add(fadeBorder, forKey: "fadeOut")
    }

    private func startDisplayLink() {
        if self.displayLink == nil {
            self.displayLink = SharedDisplayLinkDriver.shared.add { [weak self] dt in
                self?.tick(dt: dt)
            }
        }
        self.displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.layer.transform = CATransform3DIdentity

        self.position = .zero
        self.velocity = .zero
        self.currentScale = 1.0
        self.scaleVelocity = 0.0
        self.rawTranslation = .zero
    }

    private func tick(dt: CGFloat) {
        let targetScale = self.isInteracting ? self.activeScaleTarget : 1.0
        let scaleForce = -self.scaleStiffness * (self.currentScale - targetScale) - self.scaleDamping * self.scaleVelocity
        let scaleAccel = scaleForce / self.mass

        if self.elasticMovementEnabled {
            self.scaleVelocity += scaleAccel * dt
            self.currentScale += self.scaleVelocity * dt
        } else {
            self.scaleVelocity = 0.0
            self.currentScale = 1.0
        }

        if !self.isInteracting || !self.elasticMovementEnabled {
            let forceX = -self.stiffness * self.position.x - self.damping * self.velocity.x
            let forceY = -self.stiffness * self.position.y - self.damping * self.velocity.y

            let ax = forceX / self.mass
            let ay = forceY / self.mass

            self.velocity.x += ax * dt
            self.velocity.y += ay * dt

            self.position.x += self.velocity.x * dt
            self.position.y += self.velocity.y * dt
        } else {
            self.position = self.targetPosition
        }

        let highlightOffsetX = self.initialTouchPoint.x + self.rawTranslation.x - self.position.x
        let highlightOffsetY = self.initialTouchPoint.y + self.rawTranslation.y - self.position.y

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.highlightMaskLayer.position = CGPoint(x: highlightOffsetX, y: highlightOffsetY)

        if let borderMask = self.borderHighlightLayer.mask as? CAGradientLayer {
            borderMask.position = CGPoint(x: highlightOffsetX, y: highlightOffsetY)
        }

        CATransaction.commit()

        let isPositionSettled = abs(self.position.x) < 0.1 && abs(self.position.y) < 0.1 && abs(self.velocity.x) < 1.0 && abs(self.velocity.y) < 1.0
        let isScaleSettled = abs(self.currentScale - 1.0) < 0.001 && abs(self.scaleVelocity) < 0.1

        if !self.isInteracting && isPositionSettled && isScaleSettled {
            self.stopDisplayLink()
            return
        }
        
        if self.elasticMovementEnabled {
            self.applyElasticTransform()
        } else {
            self.layer.transform = CATransform3DIdentity
        }
    }

    private func applyElasticTransform() {
        if !self.isInteracting && abs(self.position.x) < 0.1 && abs(self.position.y) < 0.1 && abs(self.currentScale - 1.0) < 0.001 {
            self.layer.transform = CATransform3DIdentity
            return
        }

        let rawStretchX = 1.0 + min(abs(self.position.x) * self.stretchSensitivity, self.maxStretch - 1.0)
        let rawStretchY = 1.0 + min(abs(self.position.y) * self.stretchSensitivity, self.maxStretch - 1.0)

        let squashFactorX = 1.0 / rawStretchY
        let squashFactorY = 1.0 / rawStretchX

        let finalStretchX = rawStretchX * squashFactorX
        let finalStretchY = rawStretchY * squashFactorY

        let combinedScaleX = finalStretchX * self.currentScale
        let combinedScaleY = finalStretchY * self.currentScale

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, self.position.x, self.position.y, 0)
        transform = CATransform3DScale(transform, combinedScaleX, combinedScaleY, 1)

        self.layer.transform = transform
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        self.highlightLayer.frame = self.bounds

        let cornerRadius: CGFloat
        if let params = self.params, case let .roundedRect(value) = params.shape {
            cornerRadius = value
        } else {
            cornerRadius = 0.0
        }

        self.highlightLayer.cornerRadius = cornerRadius

        if self.highlightLayer.mask == nil || self.highlightLayer.bounds != self.bounds {
            if let maskLayer = self.highlightLayer.mask {
                maskLayer.frame = self.bounds
            }
        }

        let borderPath = UIBezierPath(roundedRect: self.bounds.insetBy(dx: 1.5, dy: 1.5),
                                       cornerRadius: max(0, cornerRadius - 1.5))
        self.borderHighlightLayer.path = borderPath.cgPath
        self.borderHighlightLayer.frame = self.bounds

        if let borderMask = self.borderHighlightLayer.mask as? CAGradientLayer {
            borderMask.frame = self.bounds
        }

        if !self.isInteracting && self.displayLink == nil {
            self.highlightMaskLayer.position = self.initialTouchPoint
            if let borderMask = self.borderHighlightLayer.mask as? CAGradientLayer {
                borderMask.position = self.initialTouchPoint
            }
        }
    }
}

public final class GlassBackgroundContainerView: UIView {
    private final class ContentView: UIView { }

    private let legacyView: ContentView?
    private let nativeParamsView: EffectSettingsContainerView?
    private let nativeView: UIVisualEffectView?

    public var contentView: UIView {
        if let nativeView = self.nativeView {
            return nativeView.contentView
        } else {
            return self.legacyView!
        }
    }

    public override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = 7.0
            let nativeView = UIVisualEffectView(effect: effect)
            self.nativeView = nativeView

            let nativeParamsView = EffectSettingsContainerView(frame: CGRect())
            self.nativeParamsView = nativeParamsView
            nativeParamsView.addSubview(nativeView)

            self.legacyView = nil
        } else {
            self.nativeView = nil
            self.nativeParamsView = nil
            self.legacyView = ContentView()
        }

        super.init(frame: frame)

        if let nativeParamsView = self.nativeParamsView {
            self.addSubview(nativeParamsView)
        } else if let legacyView = self.legacyView {
            self.addSubview(legacyView)
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)

        if subview !== self.nativeParamsView && subview !== self.legacyView {
            assertionFailure()
        }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = self.contentView.hitTest(point, with: event) else {
            return nil
        }
        return result
    }

    public func update(size: CGSize, isDark: Bool, transition: ComponentTransition) {
        if let nativeParamsView = self.nativeParamsView, let nativeView = self.nativeView {
            nativeView.overrideUserInterfaceStyle = isDark ? .dark : .light

            if isDark {
                nativeParamsView.lumaMin = 0.0
                nativeParamsView.lumaMax = 0.15
            } else {
                nativeParamsView.lumaMin = 0.6
                nativeParamsView.lumaMax = 0.61
            }

            transition.setFrame(view: nativeView, frame: CGRect(origin: CGPoint(), size: size))
        } else if let legacyView = self.legacyView {
            transition.setFrame(view: legacyView, frame: CGRect(origin: CGPoint(), size: size))
        }
    }
}

private extension CGContext {
    func addBadgePath(in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.minY)
        scaleBy(x: rect.width / 78.0, y: rect.height / 78.0)

        // M 0 39
        move(to: CGPoint(x: 0, y: 39))

        // C 0 17.4609 17.4609 0 39 0
        addCurve(to: CGPoint(x: 39, y: 0),
                 control1: CGPoint(x: 0,       y: 17.4609),
                 control2: CGPoint(x: 17.4609, y: 0))

        // H 42
        addLine(to: CGPoint(x: 42, y: 0))

        // C 61.8823 0 78 16.1177 78 36
        addCurve(to: CGPoint(x: 78, y: 36),
                 control1: CGPoint(x: 61.8823, y: 0),
                 control2: CGPoint(x: 78,      y: 16.1177))

        // V 39
        addLine(to: CGPoint(x: 78, y: 39))

        // C 78 60.5391 60.5391 78 39 78
        addCurve(to: CGPoint(x: 39, y: 78),
                 control1: CGPoint(x: 78,      y: 60.5391),
                 control2: CGPoint(x: 60.5391, y: 78))

        // H 36
        addLine(to: CGPoint(x: 36, y: 78))

        // C 16.1177 78 0 61.8823 0 42
        addCurve(to: CGPoint(x: 0, y: 42),
                 control1: CGPoint(x: 16.1177, y: 78),
                 control2: CGPoint(x: 0,       y: 61.8823))

        // V 39 / Z
        addLine(to: CGPoint(x: 0, y: 39))
        closePath()

        restoreGState()
    }
}

public extension GlassBackgroundView {
    static func generateLegacyGlassImage(size: CGSize, inset: CGFloat, isDark: Bool, fillColor: UIColor) -> UIImage {
        var size = size
        if size == .zero {
            size = CGSize(width: 2.0, height: 2.0)
        }
        let innerSize = size
        size.width += inset * 2.0
        size.height += inset * 2.0

        return UIGraphicsImageRenderer(size: size).image { ctx in
            let context = ctx.cgContext

            context.clear(CGRect(origin: CGPoint(), size: size))

            let addShadow: (CGContext, Bool, CGPoint, CGFloat, CGFloat, UIColor, CGBlendMode) -> Void = { context, isOuter, position, blur, spread, shadowColor, blendMode in
                var blur = blur

                if isOuter {
                    blur += abs(spread)

                    context.beginTransparencyLayer(auxiliaryInfo: nil)
                    context.saveGState()
                    defer {
                        context.restoreGState()
                        context.endTransparencyLayer()
                    }

                    let spreadRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize).insetBy(dx: 0.25, dy: 0.25)
                    let spreadPath = UIBezierPath(
                        roundedRect: spreadRect,
                        cornerRadius: min(spreadRect.width, spreadRect.height) * 0.5
                    ).cgPath

                    context.setShadow(offset: CGSize(width: position.x, height: position.y), blur: blur, color: shadowColor.cgColor)
                    context.setFillColor(UIColor.black.withAlphaComponent(1.0).cgColor)
                    context.addPath(spreadPath)
                    context.fillPath()

                    let cleanRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize)
                    let cleanPath = UIBezierPath(
                        roundedRect: cleanRect,
                        cornerRadius: min(cleanRect.width, cleanRect.height) * 0.5
                    ).cgPath
                    context.setBlendMode(.copy)
                    context.setFillColor(UIColor.clear.cgColor)
                    context.addPath(cleanPath)
                    context.fillPath()
                    context.setBlendMode(.normal)
                } else {
                    let image = UIGraphicsImageRenderer(size: size).image(actions: { ctx in
                        let context = ctx.cgContext

                        context.clear(CGRect(origin: CGPoint(), size: size))
                        let spreadRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize).insetBy(dx: -spread - 0.33, dy: -spread - 0.33)

                        context.setShadow(offset: CGSize(width: position.x, height: position.y), blur: blur, color: shadowColor.cgColor)
                        context.setFillColor(shadowColor.cgColor)
                        let enclosingRect = spreadRect.insetBy(dx: -10000.0, dy: -10000.0)
                        context.addPath(UIBezierPath(rect: enclosingRect).cgPath)
                        context.addBadgePath(in: spreadRect)
                        context.fillPath(using: .evenOdd)
                    })

                    UIGraphicsPushContext(context)
                    image.draw(in: CGRect(origin: .zero, size: size), blendMode: blendMode, alpha: 1.0)
                    UIGraphicsPopContext()
                }
            }

            addShadow(context, true, CGPoint(), 10.0, 0.0, UIColor(white: 0.0, alpha: 0.06), .normal)
            addShadow(context, true, CGPoint(), 20.0, 0.0, UIColor(white: 0.0, alpha: 0.06), .normal)

            var a: CGFloat = 0.0
            var b: CGFloat = 0.0
            var s: CGFloat = 0.0
            fillColor.getHue(nil, saturation: &s, brightness: &b, alpha: &a)

            let innerImage: UIImage
            if size == CGSize(width: 40.0 + inset * 2.0, height: 40.0 + inset * 2.0), b >= 0.2 {
                innerImage = UIGraphicsImageRenderer(size: size).image { ctx in
                    let context = ctx.cgContext

                    context.setFillColor(fillColor.cgColor)
                    context.fill(CGRect(origin: CGPoint(), size: size))

                    if let image = UIImage(bundleImageName: "Item List/GlassEdge40x40") {
                        let imageInset = (image.size.width - 40.0) * 0.5

                        if s == 0.0 && abs(a - 0.7) < 0.1 && !isDark {
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .normal, alpha: 1.0)
                        } else if s <= 0.3 && !isDark {
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .normal, alpha: 0.7)
                        } else if b >= 0.2 {
                            let maxAlpha: CGFloat = isDark ? 0.7 : 0.8
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .overlay, alpha: max(0.5, min(1.0, maxAlpha * s)))
                        } else {
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .normal, alpha: 0.5)
                        }
                    }
                }
            } else {
                innerImage = UIGraphicsImageRenderer(size: size).image { ctx in
                    let context = ctx.cgContext

                    context.setFillColor(fillColor.cgColor)
                    context.fill(CGRect(origin: CGPoint(), size: size).insetBy(dx: inset, dy: inset).insetBy(dx: 0.1, dy: 0.1))

                    addShadow(context, true, CGPoint(x: 0.0, y: 0.0), 20.0, 0.0, UIColor(white: 0.0, alpha: 0.04), .normal)
                    addShadow(context, true, CGPoint(x: 0.0, y: 0.0), 5.0, 0.0, UIColor(white: 0.0, alpha: 0.04), .normal)

                    if s <= 0.3 && !isDark {
                        addShadow(context, false, CGPoint(x: 0.0, y: 0.0), 8.0, 0.0, UIColor(white: 0.0, alpha: 0.4), .overlay)

                        let edgeAlpha: CGFloat = max(0.8, min(1.0, a))

                        for _ in 0 ..< 2 {
                            addShadow(context, false, CGPoint(x: -0.64, y: -0.64), 0.8, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                            addShadow(context, false, CGPoint(x: 0.64, y: 0.64), 0.8, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                        }
                    } else if b >= 0.2 {
                        let edgeAlpha: CGFloat = max(0.2, min(isDark ? 0.5 : 0.7, a * a * a))

                        addShadow(context, false, CGPoint(x: -0.64, y: -0.64), 0.5, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .plusLighter)
                        addShadow(context, false, CGPoint(x: 0.64, y: 0.64), 0.5, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .plusLighter)
                    } else {
                        let edgeAlpha: CGFloat = max(0.4, min(isDark ? 0.5 : 0.7, a * a * a))

                        addShadow(context, false, CGPoint(x: -0.64, y: -0.64), 1.2, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                        addShadow(context, false, CGPoint(x: 0.64, y: 0.64), 1.2, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                    }
                }
            }

            context.addEllipse(in: CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize))
            context.clip()
            innerImage.draw(in: CGRect(origin: CGPoint(), size: size))
        }.stretchableImage(withLeftCapWidth: Int(size.width * 0.5), topCapHeight: Int(size.height * 0.5))
    }

    static func generateForegroundImage(size: CGSize, isDark: Bool, fillColor: UIColor) -> UIImage {
        var size = size
        if size == .zero {
            size = CGSize(width: 1.0, height: 1.0)
        }

        return generateImage(size, rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))

            let maxColor = UIColor(white: 1.0, alpha: isDark ? 0.2 : 0.9)
            let minColor = UIColor(white: 1.0, alpha: 0.0)

            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))

            let lineWidth: CGFloat = isDark ? 0.33 : 0.66

            context.saveGState()

            let darkShadeColor = UIColor(white: isDark ? 1.0 : 0.0, alpha: isDark ? 0.0 : 0.035)
            let lightShadeColor = UIColor(white: isDark ? 0.0 : 1.0, alpha: isDark ? 0.0 : 0.035)
            let innerShadowBlur: CGFloat = 24.0

            context.resetClip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.clip()
            context.addRect(CGRect(origin: CGPoint(), size: size).insetBy(dx: -100.0, dy: -100.0))
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor.black.cgColor)
            context.setShadow(offset: CGSize(width: 10.0, height: -10.0), blur: innerShadowBlur, color: darkShadeColor.cgColor)
            context.fillPath(using: .evenOdd)

            context.resetClip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.clip()
            context.addRect(CGRect(origin: CGPoint(), size: size).insetBy(dx: -100.0, dy: -100.0))
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor.black.cgColor)
            context.setShadow(offset: CGSize(width: -10.0, height: 10.0), blur: innerShadowBlur, color: lightShadeColor.cgColor)
            context.fillPath(using: .evenOdd)

            context.restoreGState()

            context.setLineWidth(lineWidth)

            context.addRect(CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width * 0.5, height: size.height)))
            context.clip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.replacePathWithStrokedPath()
            context.clip()

            do {
                var locations: [CGFloat] = [0.0, 0.5, 0.5 + 0.2, 1.0 - 0.1, 1.0]
                let colors: [CGColor] = [maxColor.cgColor, maxColor.cgColor, minColor.cgColor, minColor.cgColor, maxColor.cgColor]

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!

                context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
            }

            context.resetClip()
            context.addRect(CGRect(origin: CGPoint(x: size.width - size.width * 0.5, y: 0.0), size: CGSize(width: size.width * 0.5, height: size.height)))
            context.clip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.replacePathWithStrokedPath()
            context.clip()

            do {
                var locations: [CGFloat] = [0.0, 0.1, 0.5 - 0.2, 0.5, 1.0]
                let colors: [CGColor] = [maxColor.cgColor, minColor.cgColor, minColor.cgColor, maxColor.cgColor, maxColor.cgColor]

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!

                context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
            }
        })!.stretchableImage(withLeftCapWidth: Int(size.width * 0.5), topCapHeight: Int(size.height * 0.5))
    }
}

public final class GlassBackgroundComponent: Component {
    private let size: CGSize
    private let cornerRadius: CGFloat
    private let isDark: Bool
    private let tintColor: GlassBackgroundView.TintColor

    public init(size: CGSize, cornerRadius: CGFloat, isDark: Bool, tintColor: GlassBackgroundView.TintColor) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.isDark = isDark
        self.tintColor = tintColor
    }

    public static func == (lhs: GlassBackgroundComponent, rhs: GlassBackgroundComponent) -> Bool {
        if lhs.size != rhs.size {
            return false
        }
        if lhs.cornerRadius != rhs.cornerRadius {
            return false
        }
        if lhs.isDark != rhs.isDark {
            return false
        }
        if lhs.tintColor != rhs.tintColor {
            return false
        }
        return true
    }

    public final class View: GlassBackgroundView {
        func update(component: GlassBackgroundComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.update(size: component.size, cornerRadius: component.cornerRadius, isDark: component.isDark, tintColor: component.tintColor, transition: transition)

            return component.size
        }
    }

    public func makeView() -> View {
        return View()
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
