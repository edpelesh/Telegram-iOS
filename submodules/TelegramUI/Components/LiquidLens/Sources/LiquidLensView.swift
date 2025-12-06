import Foundation
import UIKit
import Display
import ComponentFlow
import GlassBackgroundComponent
import simd

private final class RestingBackgroundView: UIVisualEffectView {
    var isDark: Bool?

    static func colorMatrix(isDark: Bool) -> [Float32] {
        if isDark {
            return [1.082, -0.113, -0.011, 0.0, 0.135, -0.034, 1.003, -0.011, 0.0, 0.135, -0.034, -0.113, 1.105, 0.0, 0.135, 0.0, 0.0, 0.0, 1.0, 0.0]
        } else {
            return [1.185, -0.05, -0.005, 0.0, -0.2, -0.015, 1.15, -0.005, 0.0, -0.2, -0.015, -0.05, 1.195, 0.0, -0.2, 0.0, 0.0, 0.0, 1.0, 0.0]
        }
    }

    init() {
        let effect = UIBlurEffect(style: .light)
        super.init(effect: effect)
        
        for subview in self.subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        
        self.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isDark: Bool) {
        if self.isDark == isDark {
            return
        }
        self.isDark = isDark
        
        if let sublayer = self.layer.sublayers?[0], let _ = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            
            if let classValue = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol {
                let makeSelector = NSSelectorFromString("filterWithName:")
                let filter = classValue.perform(makeSelector, with: "colorMatrix").takeUnretainedValue() as? NSObject
                
                if let filter {
                    var matrix: [Float32] = RestingBackgroundView.colorMatrix(isDark: isDark)
                    filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: "inputColorMatrix")
                    sublayer.filters = [filter]
                    sublayer.setValue(1.0, forKey: "scale")
                }
            }
        }
    }
}

public final class LiquidLensView: UIView {
    public var onDragInteraction: ((CGFloat, CGFloat, CGFloat, Bool) -> Void)?
    
    private struct Params: Equatable {
        var size: CGSize
        var selectionX: CGFloat
        var selectionWidth: CGFloat
        var isDark: Bool
        var isLifted: Bool

        init(size: CGSize, selectionX: CGFloat, selectionWidth: CGFloat, isDark: Bool, isLifted: Bool) {
            self.size = size
            self.selectionX = selectionX
            self.selectionWidth = selectionWidth
            self.isLifted = isLifted
            self.isDark = isDark
        }
    }

    private struct LensParams: Equatable {
        var baseFrame: CGRect
        var isLifted: Bool

        init(baseFrame: CGRect, isLifted: Bool) {
            self.baseFrame = baseFrame
            self.isLifted = isLifted
        }
    }

    private let containerView: UIView
    private let backgroundContainerContainer: UIView
    private let backgroundContainer: GlassBackgroundContainerView
    private let backgroundView: GlassBackgroundView
    private let liftedBackgroundView: GlassBackgroundView
    private var lensView: UIView?
    private let liftedContainerView: UIView
    public let contentView: UIView
    private let restingBackgroundView: RestingBackgroundView
    
    private var legacySelectionView: GlassBackgroundView.ContentImageView?
    private var legacyContentMaskView: UIView?
    private var legacyContentMaskBlobView: UIImageView?
    private var legacyLiftedContentBlobMaskView: UIImageView?
    
    private var interactionUpdateTimer: ConstantDisplayLinkAnimator?
    private var lastGestureVelocity: SIMD2<Float> = SIMD2<Float>(0, 0)
    public private(set) var lastKnobPosition: SIMD2<Float>?
    public private(set) var isInteracting: Bool = false

    public var selectedContentView: UIView {
        return self.liftedContainerView
    }

    private var params: Params?
    private var appliedLensParams: LensParams?
    private var isApplyingLensParams: Bool = false
    private var pendingLensParams: LensParams?

    private var liftedDisplayLink: SharedDisplayLinkDriver.Link?

    public var selectionX: CGFloat? {
        return self.params?.selectionX
    }

    public var selectionWidth: CGFloat? {
        return self.params?.selectionWidth
    }

    public func beginElasticInteraction(at point: CGPoint) {
        if #available(iOS 26.0, *) {
            return
        }
        let localPoint = self.convert(point, to: self.backgroundView)
        self.backgroundView.updateInitialTouchPoint(localPoint)
        self.backgroundView.beginElasticInteraction()
    }

    public func updateElasticInteraction(translation: CGPoint) {
        if #available(iOS 26.0, *) {
            return
        }
        self.backgroundView.updateElasticInteraction(translation: translation)
    }

    public func endElasticInteraction(velocity: CGPoint) {
        if #available(iOS 26.0, *) {
            return
        }
        self.backgroundView.endElasticInteraction(velocity: velocity)
    }
    
    public func updateGestureVelocity(_ velocity: SIMD2<Float>) {
        self.lastGestureVelocity = velocity
    }
    
    public func getKnobCenterPosition() -> SIMD2<Float>? {
        return self.lastKnobPosition
    }
    
    public func getCurrentLensFrame() -> CGRect? {
        guard let params = self.params else { return nil }
        return CGRect(
            origin: CGPoint(x: max(0.0, min(params.selectionX, params.size.width - params.selectionWidth)), y: 0.0),
            size: CGSize(width: params.selectionWidth, height: params.size.height)
        )
    }
    
    public func setInteractionState(_ interacting: Bool) {
        self.isInteracting = interacting
        
        let targetScale: CGFloat = interacting ? 1.05 : 1.0
        
        UIView.animate(withDuration: 0.25,
                       delay: 0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.5,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.backgroundView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
            self.contentView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
        }, completion: nil)
    }
    
    public func updateKnobPosition(_ position: SIMD2<Float>) {
        self.lastKnobPosition = position
    }
    
    public func updateTouchPositionRelativeToKnob(_ position: SIMD2<Float>) {
        if let params = self.params {
            let horizontalDelta = CGFloat(position.x)
            onDragInteraction?(horizontalDelta, params.size.width, params.size.height, isInteracting)
        }
    }
    public func getViewsToIgnore() -> [UIView] {
        var views: [UIView] = []
        if self.liftedBackgroundView.superview != nil {
            views.append(self.liftedBackgroundView)
        }
        return views
    }
    
    public func getViewsToHide() -> [UIView] {
        var views: [UIView] = []
        if let legacyContentMaskView = self.legacyContentMaskView {
            views.append(legacyContentMaskView)
        }
        views.append(self.backgroundView)
        return views
    }
    
    override public init(frame: CGRect) {
        self.containerView = UIView()

        self.backgroundContainerContainer = UIView()
        self.backgroundContainer = GlassBackgroundContainerView()

        self.backgroundView = GlassBackgroundView()
        self.liftedBackgroundView = GlassBackgroundView()

        self.contentView = UIView()
        self.contentView.clipsToBounds = false

        self.liftedContainerView = UIView()
        self.liftedContainerView.clipsToBounds = false

        self.restingBackgroundView = RestingBackgroundView()

        super.init(frame: frame)
        self.clipsToBounds = false

        if #available(iOS 26.0, *) {
            self.backgroundContainer.contentView.addSubview(self.backgroundView)
            self.backgroundView.contentView.addSubview(self.containerView)
            self.containerView.isUserInteractionEnabled = false

            if let viewClass = NSClassFromString("_UILiquidLensView") as AnyObject as? NSObjectProtocol {
                let allocSelector = NSSelectorFromString("alloc")
                let initSelector = NSSelectorFromString("initWithRestingBackground:")
                let objcAlloc = viewClass.perform(allocSelector).takeUnretainedValue()
                let instance = objcAlloc.perform(initSelector, with: UIView()).takeUnretainedValue()
                self.lensView = instance as? UIView
            }
        } else {
            self.addSubview(self.liftedBackgroundView)
            self.liftedBackgroundView.isUserInteractionEnabled = false
            self.liftedBackgroundView.isHidden = true

            self.addSubview(self.backgroundView)
            self.addSubview(self.containerView)
            self.containerView.isUserInteractionEnabled = false
            
            self.backgroundView.elasticMovementEnabled = false
        }

        self.backgroundContainerContainer.addSubview(self.backgroundContainer)
        self.addSubview(self.backgroundContainerContainer)

        if let lensView = self.lensView {
            self.backgroundContainer.layer.zPosition = 1

            self.liftedContainerView.addSubview(self.restingBackgroundView)

            self.containerView.addSubview(self.liftedContainerView)
            self.containerView.addSubview(lensView)
            self.containerView.addSubview(self.contentView)

            lensView.layer.zPosition = 16.0
            lensView.perform(NSSelectorFromString("setLiftedContainerView:"), with: self.backgroundContainer.contentView)
            lensView.perform(NSSelectorFromString("setLiftedContentView:"), with: self.liftedContainerView)
            lensView.perform(NSSelectorFromString("setOverridePunchoutView:"), with: self.contentView)
            
            do {
                let selector = NSSelectorFromString("setLiftedContentMode:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setStyle:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setWarpsContentBelow:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, true)
                }
            }
            
            lensView.setValue(UIColor(white: 0.0, alpha: 0.1), forKey: "restingBackgroundColor")
        } else {
            let legacySelectionView = GlassBackgroundView.ContentImageView()
            self.legacySelectionView = legacySelectionView
            self.backgroundView.contentView.insertSubview(legacySelectionView, at: 0)

            let legacyContentMaskView = UIView()
            legacyContentMaskView.backgroundColor = .white
            self.legacyContentMaskView = legacyContentMaskView
            self.contentView.mask = legacyContentMaskView
            
            if let filter = CALayer.luminanceToAlpha() {
                legacyContentMaskView.layer.filters = [filter]
            }
            
            let legacyContentMaskBlobView = UIImageView()
            self.legacyContentMaskBlobView = legacyContentMaskBlobView
            legacyContentMaskView.addSubview(legacyContentMaskBlobView)
            
            self.containerView.addSubview(self.contentView)
            
            let legacyLiftedContentBlobMaskView = UIImageView()
            self.legacyLiftedContentBlobMaskView = legacyLiftedContentBlobMaskView
            self.liftedContainerView.mask = legacyLiftedContentBlobMaskView
            
            self.containerView.addSubview(self.liftedContainerView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: CGSize, selectionX: CGFloat, selectionWidth: CGFloat, isDark: Bool, isLifted: Bool, transition: ComponentTransition) {
        let params = Params(size: size, selectionX: selectionX, selectionWidth: selectionWidth, isDark: isDark, isLifted: isLifted)
        if self.params == params {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func update(transition: ComponentTransition) {
        guard let params = self.params else {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func updateLens(params: LensParams, animated: Bool) {
        guard let lensView = self.lensView else {
            return
        }

        if self.isApplyingLensParams {
            self.pendingLensParams = params
            return
        }
        self.isApplyingLensParams = true
        let previousParams = self.appliedLensParams

        let transition: ComponentTransition = animated ? .easeInOut(duration: 0.3) : .immediate

        if previousParams?.isLifted != params.isLifted {
            let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
            var shouldScheduleUpdate = false
            var didProcessUpdate = false
            self.pendingLensParams = params
            if let lensView = self.lensView, let method = lensView.method(for: selector) {
                typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, AnyObject?) -> Void
                let function = unsafeBitCast(method, to: ObjCMethod.self)
                function(lensView, selector, params.isLifted, !transition.animation.isImmediate, { [weak self] in
                    guard let self else {
                        return
                    }
                    let liftedInset: CGFloat = params.isLifted ? 4.0 : -4.0
                    lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                    didProcessUpdate = true
                    if shouldScheduleUpdate {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, let pendingLensParams = self.pendingLensParams else {
                                return
                            }
                            self.isApplyingLensParams = false
                            self.pendingLensParams = nil
                            self.updateLens(params: pendingLensParams, animated: !transition.animation.isImmediate)
                        }
                    }
                }, nil)
            }
            if didProcessUpdate {
                transition.animateView {
                    lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
                }
                self.pendingLensParams = nil
                self.isApplyingLensParams = false
            } else {
                shouldScheduleUpdate = true
            }
        } else {
            if !animated || transition.animation.isImmediate {
               lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width - 8.0, height: params.baseFrame.height - 8.0))
               lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
            } else {
                transition.animateView {
                    let liftedInset: CGFloat = params.isLifted ? 4.0 : -4.0
                    lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                    lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
                }
            }
            self.isApplyingLensParams = false
        }
    }

    private func updateLiftedLensPosition() {
        guard let lensView = self.lensView else {
            return
        }
        guard let params = self.params else {
            return
        }
        let baseLensFrame = CGRect(origin: CGPoint(x: max(0.0, min(params.selectionX, params.size.width - params.selectionWidth)), y: 0.0), size: CGSize(width: params.selectionWidth, height: params.size.height))
        lensView.center = CGPoint(x: baseLensFrame.midX, y: baseLensFrame.midY)
        
        if let legacyContentMaskBlobView = self.legacyContentMaskBlobView,
           let legacyLiftedContentBlobMaskView = self.legacyLiftedContentBlobMaskView,
           let legacySelectionView = self.legacySelectionView {
            let lensFrame = baseLensFrame.insetBy(dx: 4.0, dy: 4.0)
            let effectiveLensFrame = lensFrame.insetBy(dx: params.isLifted ? -2.0 : 0.0, dy: params.isLifted ? -2.0 : 0.0)
            
            legacyContentMaskBlobView.frame = effectiveLensFrame
            legacyLiftedContentBlobMaskView.frame = effectiveLensFrame
            legacySelectionView.frame = effectiveLensFrame
        }
    }

    private func update(params: Params, transition: ComponentTransition) {
        let isFirstTime = self.params == nil
        let transition: ComponentTransition = isFirstTime ? .immediate : transition

        self.params = params

        transition.setFrame(view: self.containerView, frame: CGRect(origin: CGPoint(), size: params.size))
        transition.setFrame(view: self.backgroundContainerContainer, frame: CGRect(origin: CGPoint(), size: params.size))

        transition.setFrame(view: self.backgroundContainer, frame: CGRect(origin: CGPoint(), size: params.size))
        self.backgroundContainer.update(size: params.size, isDark: params.isDark, transition: transition)
        
        if transition.animation.isImmediate {
            self.backgroundView.bounds = CGRect(origin: CGPoint(), size: params.size)
            self.backgroundView.center = CGPoint(x: params.size.width / 2.0, y: params.size.height / 2.0)
        } else {
            transition.animateView {
                self.backgroundView.bounds = CGRect(origin: CGPoint(), size: params.size)
                self.backgroundView.center = CGPoint(x: params.size.width / 2.0, y: params.size.height / 2.0)
            }
        }
        self.backgroundView.update(size: params.size, cornerRadius: params.size.height * 0.5, isDark: params.isDark, tintColor: GlassBackgroundView.TintColor.init(kind: .panel, color: UIColor(white: params.isDark ? 0.0 : 1.0, alpha: 0.6)), isInteractive: true, transition: transition)

        let liftedSizeBackgroundSize = CGSize(width: params.size.width - 10.0, height: params.size.height - 10.0)
        transition.setFrame(view: self.liftedBackgroundView, frame: CGRect(origin: CGPoint(x: 5.0, y: 5.0), size: liftedSizeBackgroundSize))
        self.liftedBackgroundView.update(size: liftedSizeBackgroundSize, cornerRadius: liftedSizeBackgroundSize.height * 0.5, isDark: params.isDark, tintColor: GlassBackgroundView.TintColor.init(kind: .panel, color: UIColor(white: params.isDark ? 0.0 : 1.0, alpha: 1.0)), isInteractive: true, transition: transition)

        if transition.animation.isImmediate {
            self.contentView.bounds = CGRect(origin: CGPoint(), size: params.size)
            self.contentView.center = CGPoint(x: params.size.width / 2.0, y: params.size.height / 2.0)
        } else {
            transition.animateView {
                self.contentView.bounds = CGRect(origin: CGPoint(), size: params.size)
                self.contentView.center = CGPoint(x: params.size.width / 2.0, y: params.size.height / 2.0)
            }
        }
        transition.setFrame(view: self.liftedContainerView, frame: CGRect(origin: CGPoint(), size: params.size))

        let baseLensFrame = CGRect(origin: CGPoint(x: max(0.0, min(params.selectionX, params.size.width - params.selectionWidth)), y: 0.0), size: CGSize(width: params.selectionWidth, height: params.size.height))
        self.updateLens(params: LensParams(baseFrame: baseLensFrame, isLifted: params.isLifted), animated: !transition.animation.isImmediate)
        
        if params.isLifted, let lensView = self.lensView {
            lensView.center = CGPoint(x: baseLensFrame.midX, y: baseLensFrame.midY)
        }
        
        if let legacyContentMaskView = self.legacyContentMaskView {
            transition.setFrame(view: legacyContentMaskView, frame: CGRect(origin: CGPoint(), size: params.size))
        }
        if let legacyContentMaskBlobView = self.legacyContentMaskBlobView, let legacyLiftedContentBlobMaskView = self.legacyLiftedContentBlobMaskView, let legacySelectionView = self.legacySelectionView {
            let lensFrame = baseLensFrame.insetBy(dx: 4.0, dy: 4.0)
            let effectiveLensFrame = lensFrame.insetBy(dx: params.isLifted ? -2.0 : 0.0, dy: params.isLifted ? -2.0 : 0.0)
            
            if legacyContentMaskBlobView.image?.size.height != lensFrame.height {
                legacyContentMaskBlobView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .black)
                legacyLiftedContentBlobMaskView.image = legacyContentMaskBlobView.image
                legacySelectionView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .white)?.withRenderingMode(.alwaysTemplate)
            }

            legacySelectionView.tintColor = UIColor(white: params.isDark ? 1.0 : 0.0, alpha: params.isDark ? 0.1 : 0.075)
            transition.setFrame(view: legacySelectionView, frame: effectiveLensFrame)

            let shouldShowLegacy = !params.isLifted

            transition.setAlpha(view: legacyContentMaskBlobView, alpha: shouldShowLegacy ? 1.0 : 0.0)
            transition.setAlpha(view: legacyLiftedContentBlobMaskView, alpha: shouldShowLegacy ? 1.0 : 1.0)
            transition.setAlpha(view: legacySelectionView, alpha: shouldShowLegacy ? 1.0 : 0.0)
            
            if shouldShowLegacy {
                ComponentTransition.immediate.setFrame(view: legacyContentMaskBlobView, frame: effectiveLensFrame)
                ComponentTransition.immediate.setFrame(view: legacyLiftedContentBlobMaskView, frame: effectiveLensFrame)
                legacySelectionView.tintColor = UIColor(white: params.isDark ? 1.0 : 0.0, alpha: params.isDark ? 0.1 : 0.075)
                ComponentTransition.immediate.setFrame(view: legacySelectionView, frame: effectiveLensFrame)
            } else {
                transition.setFrame(view: legacyLiftedContentBlobMaskView, frame: effectiveLensFrame)
                transition.setFrame(view: legacyContentMaskBlobView, frame: effectiveLensFrame)
                transition.setFrame(view: legacySelectionView, frame: effectiveLensFrame)
            }
        }
        
        transition.setFrame(view: self.restingBackgroundView, frame: CGRect(origin: CGPoint(), size: params.size))
        self.restingBackgroundView.update(isDark: params.isDark)
        transition.setAlpha(view: self.restingBackgroundView, alpha: params.isLifted ? 0.0 : 1.0)
        
        if params.isLifted {
            if self.liftedDisplayLink == nil {
                self.liftedDisplayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateLiftedLensPosition()
                })
            }
        } else if let liftedDisplayLink = self.liftedDisplayLink {
            self.liftedDisplayLink = nil
            liftedDisplayLink.invalidate()
        }
    }
}
