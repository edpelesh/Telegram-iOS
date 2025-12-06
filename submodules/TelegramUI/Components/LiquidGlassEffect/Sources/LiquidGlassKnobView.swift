import MetalEngine
import MetalKit
import simd
import IOSurface
import UIKit
import Display
import LegacyComponents

private let kIOReturnSuccess: kern_return_t = 0

private final class BundleMarker: NSObject { }

private var metalLibraryValue: MTLLibrary?
func metalLibrary(device: MTLDevice) -> MTLLibrary? {
    if let metalLibraryValue { return metalLibraryValue }

    let mainBundle = Bundle(for: BundleMarker.self)
    guard let path = mainBundle.path(forResource: "LiquidGlassMetalSourcesBundle", ofType: "bundle"),
          let bundle = Bundle(path: path),
          let library = try? device.makeDefaultLibrary(bundle: bundle) else {
        return nil
    }

    metalLibraryValue = library
    return library
}

struct Uniforms {
    var modelViewProjection: matrix_float4x4
    var captureRect: SIMD4<Float>
    var knobCenter: SIMD2<Float>
    var time: Float
    var lastTime: Float
    var refractionStrength: Float
    var interactionProgress: Float
    var viewportSize: SIMD2<Float>
    var knobPosition: SIMD2<Float>
    var knobViewOrigin: SIMD2<Float>
    var backgroundSize: SIMD2<Float>
    var parentViewSize: SIMD2<Float>
    var parentViewSizePoints: SIMD2<Float>
    var pillSize: SIMD2<Float>
    var pillRadius: Float
    var touchPosition: SIMD2<Float>
    var touchVelocity: SIMD2<Float>
    var currentElongation: Float
    var currentSquash: Float
    var shadowScale: Float
    var thickness: Float
}

final public class LiquidGlassKnobView: MTKView {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?

    private var backgroundTexture: MTLTexture?
    private weak var sourceWindow: UIWindow?
    private var currentCaptureRect: CGRect = .zero
    private var lastContainerViewFrame: CGRect = .zero

    private var preferredFPS: Int = 120
    private var displayLink: ConstantDisplayLinkAnimator?
    private var isDrawing = false

    private var startTime: CFTimeInterval = 0.0
    private var lastTime: CFTimeInterval = 0.0
    private var isSetup = false
    private var pendingCleanup = false
    private var parentViewSize = SIMD2<Float>(0, 0)
    private var parentViewSizePoints = SIMD2<Float>(0, 0)
    private var knobPosition: SIMD2<Float> = SIMD2<Float>(0, 0)
    private var knobPositionInitialized: Bool = false

    private var targetInteractionProgress: Float = 0.0
    private var currentInteractionProgress: Float = 0.0
    private var animationStartTime: CFTimeInterval = 0.0
    private var animationStartValue: Float = 0.0
    private var isAnimating: Bool = false

    private var touchPosition: SIMD2<Float> = SIMD2<Float>(0, 0)
    private var touchVelocity: SIMD2<Float> = SIMD2<Float>(0, 0)

    private var offsetValue: SIMD2<Float> = SIMD2<Float>(0, 0)
    private var offsetVelocity: SIMD2<Float> = SIMD2<Float>(0, 0)
    private var idleFrames: Int = 0

    private var lastNotifiedPosition: Int? = nil
    private var thresholdFeedbackGenerator: UISelectionFeedbackGenerator?

    public var shadowScale: Float = 1.0
    public var thickness: Float = 12.0
    public let disableVerticalStretch: Bool

    public var pillSmallSize: SIMD2<Float> = SIMD2<Float>(35.0, 22.0)
    public var pillLargeSize: SIMD2<Float> = SIMD2<Float>(54.0, 36.0)

    public var useExpandedBounds: Bool = false
    public var expansionX: CGFloat = 60.0
    public var expansionY: CGFloat = 40.0
    public var lensSize: CGSize? = nil

    private var additionalViewsToIgnore: NSHashTable<UIView> = NSHashTable<UIView>.weakObjects()
    private var additionalViewsToHide: NSHashTable<UIView> = NSHashTable<UIView>.weakObjects()

    // MARK: - Init
    public init(frame: CGRect, preferredFPS: Int = 120, viewsToIgnore: [UIView] = [], viewsToHide: [UIView] = [], disableVerticalStretch: Bool = false) {
        self.disableVerticalStretch = disableVerticalStretch
        super.init(frame: frame, device: MetalEngine.shared.device)
        self.preferredFPS = max(1, min(120, preferredFPS))
        for view in viewsToIgnore {
            self.additionalViewsToIgnore.add(view)
        }
        for view in viewsToHide {
            self.additionalViewsToHide.add(view)
        }
        setup()
    }

    required init(coder: NSCoder) {
        self.disableVerticalStretch = false
        super.init(coder: coder)
        setup()
    }

    deinit {
        cleanupDisplayLink()
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            let hasActiveAnimations = isAnimating || length(offsetVelocity) > 0.001 || length(offsetValue) > 0.01
            if hasActiveAnimations {
                pendingCleanup = true
            } else {
                cleanupDisplayLink()
            }
        } else {
            pendingCleanup = false
            resumeDisplayLinkIfNeeded()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        sourceWindow = self.window
        if self.window == nil {
            let hasActiveAnimations = isAnimating || length(offsetVelocity) > 0.001 || length(offsetValue) > 0.01
            if hasActiveAnimations && !pendingCleanup {
                pendingCleanup = true
            } else if !hasActiveAnimations {
                cleanupDisplayLink()
            }
        } else {
            pendingCleanup = false
            resumeDisplayLinkIfNeeded()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if useExpandedBounds {
            let expandedSize = CGSize(
                width: self.bounds.width + expansionX,
                height: self.bounds.height + expansionY
            )
            let scale = self.contentScaleFactor
            self.drawableSize = CGSize(
                width: expandedSize.width * scale,
                height: expandedSize.height * scale
            )
        }

        updateParentViewSize()

        if currentInteractionProgress < 0.01 {
            if let sliderView = self.superview as? TGPhotoEditorSliderView {
                let knobCenterInSlider = sliderView.knobView.center
                let knobCenterInGlassKnob = self.convert(knobCenterInSlider, from: sliderView)
                let quantizedX = round(knobCenterInGlassKnob.x)
                let quantizedY = round(knobCenterInGlassKnob.y)
                self.updateKnobPosition(SIMD2<Float>(Float(quantizedX), Float(quantizedY)))
            }
        }
    }

    public func setInteractionState(_ isActive: Bool) {
        let newTarget: Float = isActive ? 1.0 : 0.0
        if abs(targetInteractionProgress - newTarget) > 0.01 {
            targetInteractionProgress = newTarget
            animationStartValue = currentInteractionProgress
            isAnimating = true
            animationStartTime = CACurrentMediaTime()
        }
        idleFrames = 0
        setupDisplayLink()
        displayLink?.isPaused = false
    }

    public func updateTouchPosition(_ position: SIMD2<Float>?, velocity: SIMD2<Float>? = nil) {
        touchPosition = position ?? SIMD2<Float>(0, 0)

        if let velocity = velocity {
            touchVelocity = SIMD2<Float>(velocity.x * 0.8, 0)
            setupDisplayLink()
            displayLink?.isPaused = false
        }
        idleFrames = 0
        resumeDisplayLinkIfNeeded()
    }

    public func updateKnobPosition(_ position: SIMD2<Float>) {
        knobPosition = position
        knobPositionInitialized = true
    }

    // MARK: - Setup
    private func setup() {
        guard !isSetup else { return }
        isSetup = true

        let device = MetalEngine.shared.device
        self.device = device
        self.framebufferOnly = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.enableSetNeedsDisplay = true
        self.isPaused = true
        self.clipsToBounds = false

        commandQueue = device.makeCommandQueue()
        setupPipeline(device: device)
        createPillGeometry(device: device)

        startTime = CACurrentMediaTime()
        setupDisplayLink()
    }

    private func setupPipeline(device: MTLDevice) {
        guard let library = metalLibrary(device: device),
              let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "sliderKnobFragment") else {
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        let ca = pipelineDescriptor.colorAttachments[0]!
        ca.isBlendingEnabled = true
        ca.rgbBlendOperation = .add
        ca.alphaBlendOperation = .add
        ca.sourceRGBBlendFactor = .sourceAlpha
        ca.sourceAlphaBlendFactor = .one
        ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch { }
    }

    private func createPillGeometry(device: MTLDevice) {
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 0.0,
             1.0, -1.0, 1.0, 0.0,
            -1.0,  1.0, 0.0, 1.0,
             1.0,  1.0, 1.0, 1.0
        ]
        let indices: [UInt16] = [0, 1, 2, 1, 3, 2]

        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<Float>.size,
                                         options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices,
                                        length: indices.count * MemoryLayout<UInt16>.size,
                                        options: .storageModeShared)
    }

    // MARK: - DisplayLink
    private func cleanupDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func setupDisplayLink() {
        guard self.window != nil else { return }
        if displayLink == nil {
            let link = ConstantDisplayLinkAnimator { [weak self] in
                self?.tick()
            }
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    private func pauseDisplayLinkIfIdle() {
        guard let displayLink else { return }

        let hasTouch = length(touchPosition) > 0.01
        let hasVelocity = length(touchVelocity) > 0.01
        let hasSpringEnergy = length(offsetVelocity) > 0.01
        let hasSpringDisplacement = length(offsetValue) > 0.01
        let isAnimatingState = isAnimating || abs(currentInteractionProgress - targetInteractionProgress) > 0.01

        let shouldStayActive = hasTouch || isAnimatingState || hasVelocity || hasSpringEnergy || hasSpringDisplacement

        displayLink.isPaused = !shouldStayActive
    }

    private func resumeDisplayLinkIfNeeded() {
        setupDisplayLink()
    }

    private func tick() {
        guard !self.isDrawing else { return }
        self.isDrawing = true
        defer { self.isDrawing = false }

        if let window = self.sourceWindow {
            let isStretching = length(offsetValue) > 0.1 || length(touchPosition) > 1.0
            let shouldCapture = currentInteractionProgress > 0.01 || isStretching

            if shouldCapture {
                BackgroundCaptureManager.shared.unfreeze()

                var viewsToIgnore: [UIView] = [self]
                viewsToIgnore.append(contentsOf: additionalViewsToIgnore.allObjects)
                BackgroundCaptureManager.shared.beginShowViews(viewsToIgnore)

                var viewsToHide: [UIView] = [self]
                viewsToHide.append(contentsOf: additionalViewsToHide.allObjects)
                BackgroundCaptureManager.shared.beginHidingViews(viewsToHide)

                let knobFrameInWindow = self.convert(self.bounds, to: window)

                if knobFrameInWindow != lastContainerViewFrame {
                    lastContainerViewFrame = knobFrameInWindow
                    currentCaptureRect = CGRect(
                        x: 0,
                        y: knobFrameInWindow.minY - 30.0,
                        width: window.bounds.width,
                        height: knobFrameInWindow.height + 60.0
                    ).intersection(window.bounds)
                }

                BackgroundCaptureManager.shared.notifyLayout(window: window, captureRect: currentCaptureRect)
                BackgroundCaptureManager.shared.endShowViews()
                BackgroundCaptureManager.shared.endHidingViews()
                backgroundTexture = BackgroundCaptureManager.shared.currentStableTexture()
            } else {
                backgroundTexture = nil
            }

            self.updateParentViewSize()
        }

        self.updateAnimation()
        self.setNeedsDisplay()

        let springEnergy = length(offsetVelocity)
        let springDisplacement = length(offsetValue)
        let shouldStayActive = length(touchPosition) > 0.0 || isAnimating || springEnergy > 0.005 || springDisplacement > 0.005 || length(touchVelocity) > 0.005

        if shouldStayActive {
            idleFrames = 0
        } else {
            idleFrames += 1
            if idleFrames > 5 {
                pauseDisplayLinkIfIdle()
                if pendingCleanup {
                    cleanupDisplayLink()
                    pendingCleanup = false
                }
            }
        }
    }

    private func updateParentViewSize() {
        guard let window = self.window else { return }
        let bounds = window.bounds
        let scale = window.screen.scale
        parentViewSizePoints = SIMD2(Float(bounds.width), Float(bounds.height))
        parentViewSize = SIMD2(Float(bounds.width * scale), Float(bounds.height * scale))
    }

    private func updateAnimation() {
        guard isAnimating else { return }

        let currentTime = CACurrentMediaTime()
        let elapsed = Float(currentTime - animationStartTime)

        let response: Float = 0.35
        let dampingFraction: Float = 0.7
        let omega: Float = 2.0 * Float.pi / response
        let zeta: Float = dampingFraction
        let beta: Float = 0.714

        let change: Float = targetInteractionProgress - animationStartValue

        var progress: Float = 0.0
        let expTerm = exp(-zeta * omega * elapsed)
        let cosTerm = cos(beta * omega * elapsed)
        let sinTerm = sin(beta * omega * elapsed)
        progress = 1.0 - expTerm * (cosTerm + (zeta / beta) * sinTerm)

        currentInteractionProgress = animationStartValue + change * progress
        let overshootTolerance: Float = 0.15
        if targetInteractionProgress > animationStartValue {
            currentInteractionProgress = min(max(currentInteractionProgress, 0.0), 1.0 + overshootTolerance)
        } else {
            currentInteractionProgress = min(max(currentInteractionProgress, -overshootTolerance), 1.0)
        }

        if abs(currentInteractionProgress - targetInteractionProgress) < 0.003 {
            currentInteractionProgress = targetInteractionProgress
            isAnimating = false
        }
    }

    public override func draw(_ rect: CGRect) {
        autoreleasepool {
            guard let drawable = currentDrawable,
                  let pipeline = pipelineState,
                  let cmdQ = commandQueue,
                  let vbuf = vertexBuffer else {
                return
            }
            guard let cmdBuf = cmdQ.makeCommandBuffer() else { return }

            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = drawable.texture
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.colorAttachments[0].storeAction = .store

            guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vbuf, offset: 0, index: 0)

            let viewportSize: CGSize = self.bounds.size
            let backgroundSize = backgroundTexture != nil ? SIMD2<Float>(Float(backgroundTexture!.width), Float(backgroundTexture!.height)) : SIMD2<Float>(0,0)

            let overshootProgress = Float(min(max(currentInteractionProgress, -0.15), 1.15))
            var basePillSize = SIMD2<Float>(
                pillSmallSize.x + (pillLargeSize.x - pillSmallSize.x) * overshootProgress,
                pillSmallSize.y + (pillLargeSize.y - pillSmallSize.y) * overshootProgress
            )

            let currentTime = CACurrentMediaTime()
            let time = Float(currentTime - startTime)
            let lastTimeValue = lastTime > 0 ? Float(lastTime - startTime) : time
            lastTime = currentTime
            let deltaTime = max(0.0001, time - lastTimeValue)

            let resistance: Float = 120.0
            let maxGrowth: Float = 0.3
            let leanFactorX: Float = 0.1
            let leanFactorY: Float = 0.05
            
            let velocityGain: Float = 0.02
            let velocityX = touchVelocity.x * velocityGain
            
            touchVelocity *= 0.95

            let rawTargetY = touchPosition.y * leanFactorY
            let clampedTargetY = max(-2.0, min(2.0, rawTargetY))
            
            let rawTargetX = touchPosition.x * leanFactorX + velocityX
            let clampedTargetX: Float
            
            if disableVerticalStretch {
                clampedTargetX = max(-3.0, min(3.0, rawTargetX))
            } else {
                let softLimitThreshold: Float = 15.0
                let softLimitRange: Float = 25.0
                let absRawX = abs(rawTargetX)
                
                if absRawX > softLimitThreshold {
                    let excess = absRawX - softLimitThreshold
                    let limitedExcess = (excess * softLimitRange) / (softLimitRange + excess)
                    let signX: Float = rawTargetX >= 0 ? 1.0 : -1.0
                    clampedTargetX = signX * (softLimitThreshold + limitedExcess)
                } else {
                    clampedTargetX = rawTargetX
                }
            }
            
            let targetOffset = SIMD2<Float>(
                clampedTargetX,
                disableVerticalStretch ? 0.0 : clampedTargetY
            )

            func springStep(value: inout Float, velocity: inout Float, target: Float) {
                let response: Float = 0.25
                let dampingRatio: Float = 0.5
                let omega = 2.0 * .pi / response
                let f = 1.0 + 2.0 * deltaTime * dampingRatio * omega
                let oo = omega * omega
                let detInv = 1.0 / (f + deltaTime * deltaTime * oo)
                let newValue = (f * value + deltaTime * velocity + deltaTime * deltaTime * oo * target) * detInv
                let newVelocity = (velocity + deltaTime * oo * (target - value)) * detInv
                value = newValue
                velocity = newVelocity
            }

            var ox = offsetValue.x, oy = offsetValue.y
            var vx = offsetVelocity.x, vy = offsetVelocity.y
            springStep(value: &ox, velocity: &vx, target: targetOffset.x)
            springStep(value: &oy, velocity: &vy, target: targetOffset.y)
            offsetValue = SIMD2<Float>(ox, oy)
            offsetVelocity = SIMD2<Float>(vx, vy)
            
            if length(touchPosition) < 0.001 && length(offsetVelocity) < 0.1 && length(offsetValue) < 0.1 {
                 offsetVelocity *= 0.8
                 offsetValue *= 0.8
                 
                 if length(offsetVelocity) < 0.005 && length(offsetValue) < 0.005 {
                     offsetVelocity = SIMD2<Float>(0, 0)
                     offsetValue = SIMD2<Float>(0, 0)
                 }
            }

            let stretchX = atan((offsetValue.x / leanFactorX) / resistance) * maxGrowth
            let stretchY = atan((offsetValue.y / leanFactorY) / resistance) * maxGrowth

            let scaleX = 1.0 + abs(stretchX) - (abs(stretchY) * 0.3)
            let scaleY = 1.0 + abs(stretchY) - (abs(stretchX) * 0.3)

            basePillSize.x *= scaleX
            basePillSize.y *= scaleY

            let pillRadius = basePillSize.y * 0.5

            let currentKnobPosition: SIMD2<Float> = knobPositionInitialized ? knobPosition : SIMD2<Float>(Float(viewportSize.width / 2.0), Float(viewportSize.height / 2.0))

            let finalKnobCenter = currentKnobPosition + offsetValue

            let knobViewOriginInWindow: SIMD2<Float>
            if let window = self.window {
                let originInWindow = self.convert(CGPoint.zero, to: window)
                knobViewOriginInWindow = SIMD2(Float(originInWindow.x), Float(originInWindow.y))
            } else {
                knobViewOriginInWindow = SIMD2<Float>(0, 0)
            }

            if length(touchPosition) > 0.0, let sliderView = self.superview as? TGPhotoEditorSliderView, sliderView.positionsCount > 1 {
                let minValue = Float(sliderView.minimumValue)
                let maxValue = Float(sliderView.maximumValue)
                if maxValue > minValue {
                    let normalizedValue = (Float(sliderView.value) - minValue) / (maxValue - minValue)
                    let positionsCount = Float(sliderView.positionsCount)
                    let positionIndex = round(normalizedValue * (positionsCount - 1.0))
                    let currentPosition = Int(positionIndex)
                    let exactPosition = positionIndex / (positionsCount - 1.0)
                    if abs(normalizedValue - exactPosition) < 0.05 && currentPosition != lastNotifiedPosition {
                        if thresholdFeedbackGenerator == nil {
                            thresholdFeedbackGenerator = UISelectionFeedbackGenerator()
                        }
                        thresholdFeedbackGenerator?.prepare()
                        thresholdFeedbackGenerator?.selectionChanged()
                        lastNotifiedPosition = currentPosition
                        sliderView.setLastFeedbackPosition(currentPosition)
                    }
                }
            } else if length(touchPosition) == 0 {
                lastNotifiedPosition = nil
                thresholdFeedbackGenerator = nil
            }

            var uniforms = Uniforms(
                modelViewProjection: matrix_identity_float4x4,
                captureRect: SIMD4<Float>(Float(currentCaptureRect.origin.x), Float(currentCaptureRect.origin.y), Float(currentCaptureRect.width), Float(currentCaptureRect.height)),
                knobCenter: finalKnobCenter,
                time: time,
                lastTime: lastTimeValue,
                refractionStrength: 1.0,
                interactionProgress: currentInteractionProgress,
                viewportSize: SIMD2(Float(viewportSize.width), Float(viewportSize.height)),
                knobPosition: currentKnobPosition,
                knobViewOrigin: knobViewOriginInWindow,
                backgroundSize: backgroundSize,
                parentViewSize: parentViewSize,
                parentViewSizePoints: parentViewSizePoints,
                pillSize: basePillSize,
                pillRadius: pillRadius,
                touchPosition: touchPosition,
                touchVelocity: touchVelocity,
                currentElongation: 0.0,
                currentSquash: 0.0,
                shadowScale: shadowScale,
                thickness: thickness
            )

            let uniformsSize = MemoryLayout<Uniforms>.stride
            encoder.setVertexBytes(&uniforms, length: uniformsSize, index: 1)
            encoder.setFragmentBytes(&uniforms, length: uniformsSize, index: 0)

            if let bg = backgroundTexture {
                encoder.setFragmentTexture(bg, index: 0)
            }

            if let ibuf = indexBuffer {
                let indexCount = ibuf.length / MemoryLayout<UInt16>.size
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: ibuf, indexBufferOffset: 0)
            }
            encoder.endEncoding()

            cmdBuf.present(drawable)
            cmdBuf.commit()
        }
    }
}
