import UIKit
import IOSurface
import MetalEngine
import MetalKit

private let kIOReturnSuccess: kern_return_t = 0

final class BackgroundCaptureManager {
    static let shared = BackgroundCaptureManager()

    private let device: MTLDevice
    private let blitQueue: MTLCommandQueue

    private(set) var currentTexture: MTLTexture?
    private var stableFrameTexture: MTLTexture?
    private var lastGoodTexture: MTLTexture?
    private var lastSurfaceID: UInt32 = 0

    private(set) var didUpdateThisFrame = false
    private var isFrozen = false
    private var frozenTexture: MTLTexture?

    private var shownViews: [(view: UIView, wasHidden: Bool)] = []
    private var hiddenViews: [(view: UIView, wasHidden: Bool)] = []

    private init() {
        self.device = MetalEngine.shared.device
        self.blitQueue = device.makeCommandQueue()!
    }

    // MARK: - View Filtering Logic

    func beginShowViews(_ views: [UIView]) {
        shownViews = views.map { ($0, $0.isHidden) }
        for v in views { v.isHidden = false }
    }

    func endShowViews() {
        for item in shownViews {
            item.view.isHidden = item.wasHidden
        }
        shownViews.removeAll()
    }

    func beginHidingViews(_ views: [UIView]) {
        hiddenViews = views.map { ($0, $0.isHidden) }
        for v in views { v.isHidden = true }
    }

    func endHidingViews() {
        for item in hiddenViews {
            item.view.isHidden = item.wasHidden
        }
        hiddenViews.removeAll()
    }

    // MARK: - Capture Pipeline

    func notifyLayout(window: UIWindow, captureRect: CGRect? = nil) {
        guard !isFrozen else { return }
        didUpdateThisFrame = false

        if let surface = fetchSurface(from: window) {
            if updateTexture(from: surface) {
                didUpdateThisFrame = true
                return
            }
        }

        if let surface = snapshotSurface(from: window) {
            if updateTexture(from: surface) {
                didUpdateThisFrame = true
                return
            }
        }

        renderFallback(window: window, rect: captureRect)
        didUpdateThisFrame = true
    }

    private func fetchSurface(from window: UIWindow) -> IOSurface? {
        if let context = window.layer.value(forKey: "context") as AnyObject?,
           context.responds(to: NSSelectorFromString("currentIOSurface")),
           let surface = context.perform(NSSelectorFromString("currentIOSurface"))?.takeUnretainedValue() as? IOSurface {
            return surface
        }
        return nil
    }

    private func snapshotSurface(from window: UIWindow) -> IOSurface? {
        guard let context = window.layer.value(forKey: "context") as AnyObject?,
              context.responds(to: NSSelectorFromString("createSnapshotOfType:")) else {
            return nil
        }
        return context.perform(NSSelectorFromString("createSnapshotOfType:"), with: 2)?.takeUnretainedValue() as? IOSurface
    }

    private func updateTexture(from surface: IOSurface) -> Bool {
        let newID = IOSurfaceGetID(surface)
        let width = Int(IOSurfaceGetWidth(surface))
        let height = Int(IOSurfaceGetHeight(surface))

        if currentTexture == nil || lastSurfaceID != newID || currentTexture?.width != width || currentTexture?.height != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = .shaderRead
            desc.storageMode = .shared

            guard let tex = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0) else {
                return false
            }
            currentTexture = tex
            lastGoodTexture = tex
            lastSurfaceID = newID
        }
        return true
    }

    private func renderFallback(window: UIWindow, rect: CGRect?) {
        let scale = window.screen.scale
        let captureRect = rect ?? window.bounds
        let pixelSize = CGSize(width: captureRect.width * scale, height: captureRect.height * scale)

        let props: [IOSurfacePropertyKey: Any] = [
            .width: Int(pixelSize.width),
            .height: Int(pixelSize.height),
            .pixelFormat: Int(kCVPixelFormatType_32BGRA),
            .bytesPerElement: 4
        ]

        guard let surface = IOSurface(properties: props) else { return }
        IOSurfaceLock(surface, [], nil)
        defer { IOSurfaceUnlock(surface, [], nil) }

        guard let ctx = CGContext(
            data: IOSurfaceGetBaseAddress(surface),
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: IOSurfaceGetBytesPerRow(surface),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        ctx.scaleBy(x: scale, y: scale)
        if let rect = rect {
            ctx.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        }

        window.layer.render(in: ctx)
        _ = updateTexture(from: surface)
    }

    // MARK: - Stable Texture Logic

    func currentStableTexture() -> MTLTexture? {
        if isFrozen { return frozenTexture }
        guard let src = currentTexture ?? lastGoodTexture else { return nil }

        if stableFrameTexture == nil ||
           stableFrameTexture?.width != src.width ||
           stableFrameTexture?.height != src.height {

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: src.pixelFormat,
                width: src.width,
                height: src.height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            stableFrameTexture = device.makeTexture(descriptor: desc)
        }

        if let dst = stableFrameTexture,
           let buffer = blitQueue.makeCommandBuffer(),
           let encoder = buffer.makeBlitCommandEncoder() {
            encoder.copy(from: src, to: dst)
            encoder.endEncoding()
            buffer.commit()
            return dst
        }

        return src
    }

    func freezeIfNeeded() {
        guard !isFrozen, let stable = currentStableTexture() else { return }
        frozenTexture = stable
        isFrozen = true
    }

    func unfreeze() {
        isFrozen = false
        frozenTexture = nil
    }
}
