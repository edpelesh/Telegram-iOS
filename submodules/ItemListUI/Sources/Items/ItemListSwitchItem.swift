import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import SwitchNode
import AppBundle
import ComponentFlow
import LiquidGlassEffect

public enum ItemListSwitchItemNodeType {
    case regular
    case icon
}

public class ItemListSwitchItem: ListViewItem, ItemListItem {
    public enum TextColor {
        case primary
        case accent
    }
    
    let presentationData: ItemListPresentationData
    let systemStyle: ItemListSystemStyle
    let icon: UIImage?
    let title: String
    let text: String?
    let textColor: TextColor
    let titleBadgeComponent: AnyComponent<Empty>?
    let value: Bool
    let type: ItemListSwitchItemNodeType
    let enableInteractiveChanges: Bool
    let enabled: Bool
    let displayLocked: Bool
    let disableLeadingInset: Bool
    let maximumNumberOfLines: Int
    let noCorners: Bool
    public let sectionId: ItemListSectionId
    let style: ItemListStyle
    let updated: (Bool) -> Void
    let activatedWhileDisabled: () -> Void
    let action: (() -> Void)?
    public let tag: ItemListItemTag?
    
    public init(presentationData: ItemListPresentationData, systemStyle: ItemListSystemStyle = .legacy, icon: UIImage? = nil, title: String, text: String? = nil, textColor: TextColor = .primary, titleBadgeComponent: AnyComponent<Empty>? = nil, value: Bool, type: ItemListSwitchItemNodeType = .regular, enableInteractiveChanges: Bool = true, enabled: Bool = true, displayLocked: Bool = false, disableLeadingInset: Bool = false, maximumNumberOfLines: Int = 1, noCorners: Bool = false, sectionId: ItemListSectionId, style: ItemListStyle, updated: @escaping (Bool) -> Void, activatedWhileDisabled: @escaping () -> Void = {}, action: (() -> Void)? = nil, tag: ItemListItemTag? = nil) {
        self.presentationData = presentationData
        self.systemStyle = systemStyle
        self.icon = icon
        self.title = title
        self.text = text
        self.textColor = textColor
        self.titleBadgeComponent = titleBadgeComponent
        self.value = value
        self.type = type
        self.enableInteractiveChanges = enableInteractiveChanges
        self.enabled = enabled
        self.displayLocked = displayLocked
        self.disableLeadingInset = disableLeadingInset
        self.maximumNumberOfLines = maximumNumberOfLines
        self.noCorners = noCorners
        self.sectionId = sectionId
        self.style = style
        self.updated = updated
        self.activatedWhileDisabled = activatedWhileDisabled
        self.action = action
        self.tag = tag
    }
    
    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListSwitchItemNode(type: self.type)
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply(false) })
                })
            }
        }
    }
    
    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ItemListSwitchItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            var animated = true
                            if case .None = animation {
                                animated = false
                            }
                            apply(animated)
                        })
                    }
                }
            }
        }
    }
    
    public var selectable: Bool {
        return self.action != nil && self.enabled
    }
    
    public func selected(listView: ListView){
        listView.clearHighlightAnimated(true)
        if self.enabled {
            self.action?()
        }
    }
}

protocol ItemListSwitchNodeImpl {
    var frameColor: UIColor { get set }
    var contentColor: UIColor { get set }
    var handleColor: UIColor { get set }
    var positiveContentColor: UIColor { get set }
    var negativeContentColor: UIColor { get set }
    
    var isOn: Bool { get }
    func setOn(_ value: Bool, animated: Bool)
}

extension SwitchNode: ItemListSwitchNodeImpl {
    var positiveContentColor: UIColor {
        get {
            return .white
        } set(value) {
            
        }
    }
    var negativeContentColor: UIColor {
        get {
            return .white
        } set(value) {
            
        }
    }
}

extension IconSwitchNode: ItemListSwitchNodeImpl {
}

public class ItemListSwitchItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let iconNode: ASImageNode
    private let titleNode: TextNode
    private var textNode: TextNode?
    private var switchNode: ASDisplayNode & ItemListSwitchNodeImpl
    private let switchGestureNode: ASDisplayNode
    private var disabledOverlayNode: ASDisplayNode?
    
    private var titleBadgeComponentView: ComponentView<Empty>?
    
    private var lockedIconNode: ASImageNode?
    
    private let activateArea: AccessibilityAreaNode
    
    private var item: ItemListSwitchItem?
    
    private var glassKnob: LiquidGlassKnobView?
    private var interactionUpdateTimer: ConstantDisplayLinkAnimator?
    private var lastGestureVelocity: SIMD2<Float> = SIMD2<Float>(0, 0)
    private var lastKnobPosition: SIMD2<Float>?
    private var isInteracting: Bool = false
    private var backgroundPillView: UIView?
    
    public var tag: ItemListItemTag? {
        return self.item?.tag
    }
    
    public init(type: ItemListSwitchItemNodeType) {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.backgroundColor = .white
        
        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.iconNode = ASImageNode()
        self.iconNode.isLayerBacked = true
        self.iconNode.displaysAsynchronously = false
        
        self.titleNode = TextNode()
        self.titleNode.anchorPoint = CGPoint()
        self.titleNode.isUserInteractionEnabled = false
        
        switch type {
            case .regular:
                self.switchNode = SwitchNode()
            case .icon:
                self.switchNode = IconSwitchNode()
                self.switchNode.clipsToBounds = false
        }
        
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        
        self.switchGestureNode = ASDisplayNode()
        
        self.activateArea = AccessibilityAreaNode()
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.switchNode)
        self.addSubnode(self.switchGestureNode)
        self.addSubnode(self.activateArea)
        
        self.activateArea.activate = { [weak self] in
            guard let strongSelf = self, let item = strongSelf.item, item.enabled else {
                return false
            }
            let value = !strongSelf.switchNode.isOn
            if item.enableInteractiveChanges {
                strongSelf.switchNode.setOn(value, animated: true)
            }
            item.updated(value)
            return true
        }
    }
    
    override public func didLoad() {
        super.didLoad()
        
        if let control = self.switchNode.view as? UIControl {
            control.addTarget(self, action: #selector(self.switchValueChanged(_:)), for: .valueChanged)
            control.addTarget(self, action: #selector(self.switchTouchDown), for: .touchDown)
            control.addTarget(self, action: #selector(self.switchTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        self.switchGestureNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
        
        if #available(iOS 26.0, *) { } else {
            if let switchNode = self.switchNode as? SwitchNode {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let switchView = self.switchNode.view as? UIControl {
                        self.setupGlassKnob(switchView: switchView, switchNode: switchNode)
                    }
                }
            }
        }
    }
    
    private func setupGlassKnob(switchView: UIControl, switchNode: SwitchNode) {
        guard self.glassKnob == nil else { return }
        
        if let knobView = switchNode.knobView {
            knobView.isHidden = true
        }
        
        var knobFrame = switchView.bounds
        knobFrame.size.height += 10.0
        knobFrame.size.width += 30.0
        knobFrame.origin.y -= 5.0
        knobFrame.origin.x -= 15.0
        
        if #available(iOS 26.0, *) { } else {
            let pillWidthScale: CGFloat = 0.9
            let pillHeightScale: CGFloat = 0.7
            let pillWidth = switchView.bounds.width * pillWidthScale
            let pillHeight = switchView.bounds.height * pillHeightScale
            let pillX = switchView.bounds.midX - pillWidth / 2
            let pillY = switchView.bounds.midY - pillHeight / 2
            
            let pillFrame = switchView.convert(CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight), to: self.view)
            let backgroundPillView = UIView(frame: pillFrame)
            backgroundPillView.isUserInteractionEnabled = false
            
            if let switchNode = self.switchNode as? SwitchNode {
                let backgroundColor = switchNode.isOn ? switchNode.contentColor : switchNode.frameColor
                backgroundPillView.backgroundColor = backgroundColor
                backgroundPillView.layer.cornerRadius = pillHeight / 2
                self.view.insertSubview(backgroundPillView, belowSubview: switchNode.view)
                self.backgroundPillView = backgroundPillView
                
                switchView.addTarget(self, action: #selector(switchValueChangedForPill(_:)), for: UIControl.Event.valueChanged)
            }
        }
        
        var viewsToHide: [UIView] = []
        if let switchView = switchNode.view as? UIControl {
            viewsToHide.append(switchView)
        }
        if let knobView = switchNode.knobView {
            viewsToHide.append(knobView)
        }
        
        let glassKnob = LiquidGlassKnobView(frame: knobFrame, viewsToHide: viewsToHide, disableVerticalStretch: true)
        glassKnob.isUserInteractionEnabled = false
        glassKnob.clipsToBounds = false
        glassKnob.shadowScale = 0.3
        glassKnob.thickness = 8.0
        glassKnob.useExpandedBounds = true
        switchView.addSubview(glassKnob)
        self.glassKnob = glassKnob
        
        self.disableClippingOnParentViews(for: glassKnob)
        
        switchNode.interactionBegan = { [weak self] in
            guard let self = self else { return }
            self.glassKnob?.setInteractionState(true)
            self.lastGestureVelocity = SIMD2<Float>(0, 0)
            self.isInteracting = true
            
            if let knobView = switchNode.knobView, let glassKnob = self.glassKnob {
                switchView.layoutIfNeeded()
                
                let knobCenterInSwitch = knobView.center
                let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSwitch, from: switchView)
                let lockedPosition = SIMD2<Float>(Float(round(knobCenterInGlassKnob.x)), Float(round(knobCenterInGlassKnob.y)))
                self.lastKnobPosition = lockedPosition
                glassKnob.updateKnobPosition(lockedPosition)
            }
            
            self.startInteractionTracking()
        }
        
        switchNode.interactionEnded = { [weak self] in
            guard let self = self else { return }
            self.stopInteractionTracking()
            self.glassKnob?.setInteractionState(false)
            self.glassKnob?.updateTouchPosition(nil, velocity: self.lastGestureVelocity)
            self.lastGestureVelocity = SIMD2<Float>(0, 0)
            self.isInteracting = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                self?.updateKnobPosition(force: true)
            }
        }
        
        self.updateKnobPosition()
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
        guard let switchNode = self.switchNode as? SwitchNode,
              let glassKnob = self.glassKnob,
              let knobView = switchNode.knobView,
              let switchView = switchNode.view as? UIControl else {
            return
        }
        
        guard switchView.bounds.width > 0 && switchView.bounds.height > 0 else {
            return
        }
        
        if isInteracting && !force {
            return
        }
        
        switchView.layoutIfNeeded()
        
        let knobCenterInSwitch = knobView.center
        let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSwitch, from: switchView)
        
        let quantizedX = round(knobCenterInGlassKnob.x)
        let quantizedY = round(knobCenterInGlassKnob.y)
        let newPosition = SIMD2<Float>(Float(quantizedX), Float(quantizedY))
        
        if let lastPosition = lastKnobPosition {
            let threshold: Float = 0.5
            if abs(newPosition.x - lastPosition.x) < threshold && 
               abs(newPosition.y - lastPosition.y) < threshold {
                return
            }
        }
        
        lastKnobPosition = newPosition
        glassKnob.updateKnobPosition(newPosition)
    }
    
    private func updateInteractionState() {
        guard let switchNode = self.switchNode as? SwitchNode,
              let glassKnob = self.glassKnob,
              let knobView = switchNode.knobView,
              let switchView = switchNode.view as? UIControl else {
            return
        }

        let knobCenterInSwitch = knobView.center
        let knobCenterInGlassKnob = glassKnob.convert(knobCenterInSwitch, from: switchView)
        
        let quantizedX = round(knobCenterInGlassKnob.x)
        let quantizedY = round(knobCenterInGlassKnob.y)
        let currentPosition = SIMD2<Float>(Float(quantizedX), Float(quantizedY))
        
        if isInteracting {
            if lastKnobPosition == nil || 
               abs(currentPosition.x - lastKnobPosition!.x) > 0.5 || 
               abs(currentPosition.y - lastKnobPosition!.y) > 0.5 {
                lastKnobPosition = currentPosition
                glassKnob.updateKnobPosition(currentPosition)
            }
        }
        
        if let gestureRecognizers = switchView.gestureRecognizers {
            for gestureRecognizer in gestureRecognizers {
                var touchLocation: CGPoint?
                var gestureVel = CGPoint.zero
                
                if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                    if panGesture.state == .began || panGesture.state == .changed {
                        touchLocation = panGesture.location(in: switchView)
                        gestureVel = panGesture.velocity(in: switchView)
                    }
                }
                
                if let touchLocation = touchLocation {
                    let velocityInGlassKnob = glassKnob.convert(CGPoint(x: gestureVel.x, y: gestureVel.y), from: switchView)
                    let gestureVelocity = SIMD2<Float>(Float(velocityInGlassKnob.x), Float(velocityInGlassKnob.y))
                    lastGestureVelocity = gestureVelocity
                    
                    let touchLocationInGlassKnob = glassKnob.convert(touchLocation, from: switchView)
                    let touchRelativeToKnob = SIMD2<Float>(
                        Float(touchLocationInGlassKnob.x - CGFloat(currentPosition.x)),
                        Float(touchLocationInGlassKnob.y - CGFloat(currentPosition.y))
                    )
                    
                    glassKnob.updateTouchPosition(touchRelativeToKnob, velocity: gestureVelocity)
                    break
                }
            }
        }
    }
    
    @objc private func switchTouchDown() {
        self.startInteractionTracking()
        self.glassKnob?.setInteractionState(true)
    }
    
    @objc private func switchTouchUp() {
        self.glassKnob?.setInteractionState(false)
        self.glassKnob?.updateTouchPosition(nil, velocity: lastGestureVelocity)
        self.lastGestureVelocity = SIMD2<Float>(0, 0)
    }
    
    private func adjustSwitchTrackHeight(switchView: UISwitch) {
        guard let firstSubview = switchView.subviews.first else { return }
        
        var trackView: UIView?
        if #available(iOS 13.0, *) {
            if let trackContainer = firstSubview.subviews.first {
                trackView = trackContainer
            }
        } else {
            trackView = firstSubview
        }
        
        guard let trackView = trackView else { return }
        
        let targetHeight: CGFloat = 22.0
        var trackFrame = trackView.frame
        let originalHeight = trackFrame.height
        if abs(originalHeight - targetHeight) > 0.5 {
            let heightDiff = originalHeight - targetHeight
            trackFrame.size.height = targetHeight
            trackFrame.origin.y += heightDiff / 2.0
            trackView.frame = trackFrame
        }
    }
    
    func asyncLayout() -> (_ item: ItemListSwitchItem, _ params: ListViewItemLayoutParams, _ insets: ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeTextLayout = TextNode.asyncLayout(self.textNode)
        
        let currentItem = self.item
        var currentDisabledOverlayNode = self.disabledOverlayNode
        
        return { item, params, neighbors in
            var contentSize: CGSize
            var insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = item.systemStyle == .glass ? 16.0 : 0.0
            
            let itemBackgroundColor: UIColor
            let itemSeparatorColor: UIColor
            
            let titleFont = Font.regular(item.presentationData.fontSize.itemListBaseFontSize)
            let textFont = Font.regular(item.presentationData.fontSize.itemListBaseFontSize * 14.0 / 17.0)
            
            var updatedTheme: PresentationTheme?
            if currentItem?.presentationData.theme !== item.presentationData.theme {
                updatedTheme = item.presentationData.theme
            }
            
            var updatedValue = false
            if currentItem?.value != item.value {
                updatedValue = true
            }
            
            var updateIcon = false
            if currentItem?.icon != item.icon {
                updateIcon = true
            }
            
            switch item.style {
            case .plain:
                itemBackgroundColor = item.presentationData.theme.list.plainBackgroundColor
                itemSeparatorColor = item.presentationData.theme.list.itemPlainSeparatorColor
                contentSize = CGSize(width: params.width, height: 44.0)
                insets = itemListNeighborsPlainInsets(neighbors)
            case .blocks:
                itemBackgroundColor = item.presentationData.theme.list.itemBlocksBackgroundColor
                itemSeparatorColor = item.presentationData.theme.list.itemBlocksSeparatorColor
                contentSize = CGSize(width: params.width, height: 44.0)
                insets = itemListNeighborsGroupedInsets(neighbors, params)
            }
            
            
            
            var topInset: CGFloat
            if item.text != nil {
                topInset = 9.0
            } else {
                topInset = 11.0
            }
            if case .glass = item.systemStyle {
                contentSize.height = 52.0
                topInset += 4.0
            }
            
            var leftInset = 16.0 + params.leftInset
            if let _ = item.icon {
                leftInset += 43.0
            }
            
            if item.disableLeadingInset {
                insets.top = 0.0
                insets.bottom = 0.0
            }
            
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.title, font: titleFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: item.maximumNumberOfLines, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - params.rightInset - 64.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            contentSize.height = max(contentSize.height, titleLayout.size.height + topInset * 2.0)
            
            var textLayoutAndApply: (TextNodeLayout, () -> TextNode)?
            
            if let text = item.text {
                let textColor: UIColor
                switch item.textColor {
                case .primary:
                    textColor = item.presentationData.theme.list.itemSecondaryTextColor
                case .accent:
                    textColor = item.presentationData.theme.list.itemAccentColor
                }
                let (textLayout, textApply) = makeTextLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: text, font: textFont, textColor: textColor), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - params.rightInset - 84.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
                contentSize.height += -1.0 + textLayout.size.height
                textLayoutAndApply = (textLayout, textApply)
            }
            
            if !item.enabled {
                if currentDisabledOverlayNode == nil {
                    currentDisabledOverlayNode = ASDisplayNode()
                }
            } else {
                currentDisabledOverlayNode = nil
            }
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (ListViewItemNodeLayout(contentSize: contentSize, insets: insets), { [weak self] animated in
                if let strongSelf = self {
                    let transition: ContainedViewLayoutTransition
                    if animated {
                        transition = ContainedViewLayoutTransition.animated(duration: 0.4, curve: .spring)
                    } else {
                        transition = .immediate
                    }
                    
                    strongSelf.item = item
                    
                    strongSelf.activateArea.frame = CGRect(origin: CGPoint(x: params.leftInset, y: 0.0), size: CGSize(width: params.width - params.leftInset - params.rightInset, height: layout.contentSize.height))
                    
                    strongSelf.activateArea.accessibilityLabel = item.title
                    strongSelf.activateArea.accessibilityValue = item.value ? item.presentationData.strings.VoiceOver_Common_On : item.presentationData.strings.VoiceOver_Common_Off
                    strongSelf.activateArea.accessibilityHint = item.presentationData.strings.VoiceOver_Common_SwitchHint
                    var accessibilityTraits = UIAccessibilityTraits()
                    if item.enabled {
                    } else {
                        accessibilityTraits.insert(.notEnabled)
                    }
                    strongSelf.activateArea.accessibilityTraits = accessibilityTraits
                    
                    if let icon = item.icon {
                        var iconTransition = transition
                        if strongSelf.iconNode.supernode == nil {
                            iconTransition = .immediate
                            strongSelf.addSubnode(strongSelf.iconNode)
                        }
                        if updateIcon {
                            strongSelf.iconNode.image = icon
                        }
                        let iconY: CGFloat
                        if item.text == nil {
                            iconY = floor((layout.contentSize.height - icon.size.height) / 2.0)
                        } else {
                            iconY = max(0.0, floor(topInset + titleLayout.size.height + 1.0 - icon.size.height * 0.5))
                        }
                        iconTransition.updateFrame(node: strongSelf.iconNode, frame: CGRect(origin: CGPoint(x: params.leftInset + floor((leftInset - params.leftInset - icon.size.width) / 2.0), y: iconY), size: icon.size))
                    } else if strongSelf.iconNode.supernode != nil {
                        strongSelf.iconNode.image = nil
                        strongSelf.iconNode.removeFromSupernode()
                    }
                    
                    if let currentDisabledOverlayNode = currentDisabledOverlayNode {
                        if currentDisabledOverlayNode != strongSelf.disabledOverlayNode {
                            strongSelf.disabledOverlayNode = currentDisabledOverlayNode
                            strongSelf.insertSubnode(currentDisabledOverlayNode, belowSubnode: strongSelf.switchGestureNode)
                            currentDisabledOverlayNode.alpha = 0.0
                            transition.updateAlpha(node: currentDisabledOverlayNode, alpha: 1.0)
                            currentDisabledOverlayNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: layout.contentSize.width, height: layout.contentSize.height - separatorHeight))
                        } else {
                            transition.updateFrame(node: currentDisabledOverlayNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: layout.contentSize.width, height: layout.contentSize.height - separatorHeight)))
                        }
                        currentDisabledOverlayNode.backgroundColor = itemBackgroundColor.withAlphaComponent(0.6)
                    } else if let disabledOverlayNode = strongSelf.disabledOverlayNode {
                        transition.updateAlpha(node: disabledOverlayNode, alpha: 0.0, completion: { [weak disabledOverlayNode] _ in
                            disabledOverlayNode?.removeFromSupernode()
                        })
                        strongSelf.disabledOverlayNode = nil
                    }
                    
                    if let _ = updatedTheme {
                        strongSelf.topStripeNode.backgroundColor = itemSeparatorColor
                        strongSelf.bottomStripeNode.backgroundColor = itemSeparatorColor
                        strongSelf.backgroundNode.backgroundColor = itemBackgroundColor
                        
                        strongSelf.switchNode.frameColor = item.presentationData.theme.list.itemSwitchColors.frameColor
                        strongSelf.switchNode.contentColor = item.presentationData.theme.list.itemAccentColor
                        strongSelf.switchNode.handleColor = item.presentationData.theme.list.itemSwitchColors.handleColor
                        strongSelf.switchNode.positiveContentColor = item.presentationData.theme.list.itemSwitchColors.positiveColor
                        strongSelf.switchNode.negativeContentColor = item.presentationData.theme.list.itemSwitchColors.negativeColor
                        
                        strongSelf.highlightedBackgroundNode.backgroundColor = item.presentationData.theme.list.itemHighlightedBackgroundColor
                    }
                    
                    let _ = titleApply()
                    
                    switch item.style {
                        case .plain:
                            if strongSelf.backgroundNode.supernode != nil {
                                strongSelf.backgroundNode.removeFromSupernode()
                            }
                            if strongSelf.topStripeNode.supernode != nil {
                                strongSelf.topStripeNode.removeFromSupernode()
                            }
                            if strongSelf.bottomStripeNode.supernode == nil {
                                strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 0)
                            }
                            if strongSelf.maskNode.supernode != nil {
                                strongSelf.maskNode.removeFromSupernode()
                            }
                            transition.updateFrame(node: strongSelf.bottomStripeNode, frame: CGRect(origin: CGPoint(x: leftInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - leftInset, height: separatorHeight)))
                        case .blocks:
                            if strongSelf.backgroundNode.supernode == nil {
                                strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                            }
                            if strongSelf.topStripeNode.supernode == nil {
                                strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                            }
                            if strongSelf.bottomStripeNode.supernode == nil {
                                strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                            }
                            if strongSelf.maskNode.supernode == nil {
                                strongSelf.insertSubnode(strongSelf.maskNode, aboveSubnode: strongSelf.switchGestureNode)
                            }
                            
                            let hasCorners = itemListHasRoundedBlockLayout(params) && !item.noCorners
                            var hasTopCorners = false
                            var hasBottomCorners = false
                            switch neighbors.top {
                                case .sameSection(false):
                                    strongSelf.topStripeNode.isHidden = true
                                default:
                                    hasTopCorners = true
                                    strongSelf.topStripeNode.isHidden = hasCorners
                            }
                            let bottomStripeInset: CGFloat
                            switch neighbors.bottom {
                                case .sameSection(false):
                                    bottomStripeInset = leftInset
                                    strongSelf.bottomStripeNode.isHidden = false
                                default:
                                    bottomStripeInset = 0.0
                                    hasBottomCorners = true
                                    strongSelf.bottomStripeNode.isHidden = hasCorners
                            }
                            
                            strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.presentationData.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil
                            
                            transition.updateFrame(node: strongSelf.backgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight))))
                            transition.updateFrame(node: strongSelf.maskNode, frame: strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0))
                            transition.updateFrame(node: strongSelf.topStripeNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight)))
                            transition.updateFrame(node: strongSelf.bottomStripeNode, frame: CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: layoutSize.width - params.rightInset - bottomStripeInset - separatorRightInset, height: separatorHeight)))
                    }
                    
                    let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: topInset), size: titleLayout.size)
                    transition.updatePosition(node: strongSelf.titleNode, position: titleFrame.origin)
                    strongSelf.titleNode.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
                    
                    if let (textLayout, textApply) = textLayoutAndApply {
                        let textNode = textApply()
                        if strongSelf.textNode !== textNode {
                            strongSelf.textNode?.removeFromSupernode()
                            strongSelf.textNode = textNode
                            textNode.isUserInteractionEnabled = false
                            strongSelf.addSubnode(textNode)
                            
                            if transition.isAnimated {
                                textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                            }
                        }
                        textNode.frame = CGRect(origin: CGPoint(x: leftInset, y: strongSelf.titleNode.frame.maxY + 2.0), size: textLayout.size)
                    } else if let textNode = strongSelf.textNode {
                        strongSelf.textNode = nil
                        if transition.isAnimated {
                            textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak textNode] _ in
                                textNode?.removeFromSupernode()
                            })
                        } else {
                            textNode.removeFromSupernode()
                        }
                    }
                    
                    if let switchView = strongSelf.switchNode.view as? UIControl {
                        if strongSelf.switchNode.bounds.size.width.isZero {
                            switchView.sizeToFit()
                        }
                        let switchSize = switchView.bounds.size
                        let switchFrame = CGRect(origin: CGPoint(x: params.width - params.rightInset - switchSize.width - 15.0, y: floor((contentSize.height - switchSize.height) / 2.0)), size: switchSize)
                        
                        transition.updateFrame(node: strongSelf.switchNode, frame: switchFrame)
                        strongSelf.switchGestureNode.frame = strongSelf.switchNode.frame
                        
                        if let backgroundPill = strongSelf.backgroundPillView {
                            let pillWidthScale: CGFloat = 0.9
                            let pillHeightScale: CGFloat = 0.7
                            let pillWidth = switchSize.width * pillWidthScale
                            let pillHeight = switchSize.height * pillHeightScale
                            let pillX = switchFrame.midX - pillWidth / 2
                            let pillY = switchFrame.midY - pillHeight / 2
                            backgroundPill.frame = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
                            backgroundPill.layer.cornerRadius = pillHeight / 2
                        }
                        
                        var currentValue = false
                        if #available(iOS 26.0, *) {
                            if let uiSwitch = switchView as? UISwitch {
                                currentValue = uiSwitch.isOn
                                if currentValue != item.value {
                                    uiSwitch.setOn(item.value, animated: animated)
                                }
                            }
                        } else {
                            currentValue = (strongSelf.switchNode as? SwitchNode)?.isOn ?? false
                            if currentValue != item.value {
                                (strongSelf.switchNode as? SwitchNode)?.setOn(item.value, animated: animated)
                            }
                        }
                        switchView.isUserInteractionEnabled = item.enableInteractiveChanges
                        
                        if #available(iOS 26.0, *) { } else {
                            if let glassKnob = strongSelf.glassKnob {
                                var knobFrame = switchView.bounds
                                knobFrame.size.height += 10.0
                                knobFrame.size.width += 30.0
                                knobFrame.origin.y -= 5.0
                                knobFrame.origin.x -= 15.0
                                glassKnob.frame = knobFrame
                                
                                DispatchQueue.main.async {
                                    strongSelf.updateKnobPosition(force: true)
                                    glassKnob.setNeedsDisplay()
                                }
                            } else if let switchNode = strongSelf.switchNode as? SwitchNode {
                                strongSelf.setupGlassKnob(switchView: switchView, switchNode: switchNode)
                            }
                            
                            DispatchQueue.main.async {
                                if let knobView = (strongSelf.switchNode as? SwitchNode)?.knobView {
                                    knobView.isHidden = true
                                }
                            }
                        }
                    }
                    strongSelf.switchGestureNode.isHidden = item.enableInteractiveChanges && item.enabled
                    
                    if item.displayLocked {
                        var lockedIconTransition = transition
                        var updateLockedIconImage = false
                        if let _ = updatedTheme {
                            updateLockedIconImage = true
                        }
                        if updatedValue {
                            updateLockedIconImage = true
                        }
                        
                        let lockedIconNode: ASImageNode
                        if let current = strongSelf.lockedIconNode {
                            lockedIconNode = current
                        } else {
                            lockedIconTransition = .immediate
                            updateLockedIconImage = true
                            lockedIconNode = ASImageNode()
                            strongSelf.lockedIconNode = lockedIconNode
                            strongSelf.insertSubnode(lockedIconNode, aboveSubnode: strongSelf.switchNode)
                        }
                        
                        if updateLockedIconImage, let image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/TextLockIcon"), color: item.value ? item.presentationData.theme.list.itemSwitchColors.positiveColor : item.presentationData.theme.list.itemSecondaryTextColor) {
                            lockedIconNode.image = image
                        }
                        
                        let switchFrame = strongSelf.switchNode.frame
                        
                        if let icon = lockedIconNode.image {
                            let iconOrigin: CGPoint
                            switch item.systemStyle {
                            case .glass:
                                iconOrigin = CGPoint(x: item.value ? switchFrame.maxX - icon.size.width - 16.0 + UIScreenPixel : switchFrame.minX + 16.0 - UIScreenPixel, y: switchFrame.minY + 8.0)
                            case .legacy:
                                iconOrigin = CGPoint(x: item.value ? switchFrame.maxX - icon.size.width - 11.0 : switchFrame.minX + 11.0, y: switchFrame.minY + 9.0)
                            }
                            lockedIconTransition.updateFrame(node: lockedIconNode, frame: CGRect(origin: iconOrigin, size: icon.size))
                        }
                    } else if let lockedIconNode = strongSelf.lockedIconNode {
                        strongSelf.lockedIconNode = nil
                        lockedIconNode.removeFromSupernode()
                    }
                    
                    if let component = item.titleBadgeComponent {
                        let componentView: ComponentView<Empty>
                        if let current = strongSelf.titleBadgeComponentView {
                            componentView = current
                        } else {
                            componentView = ComponentView<Empty>()
                            strongSelf.titleBadgeComponentView = componentView
                        }
                        
                        let badgeSize = componentView.update(
                            transition: .immediate,
                            component: component,
                            environment: {},
                            containerSize: contentSize
                        )
                        if let view = componentView.view {
                            var titleBadgeTransition = transition
                            if view.superview == nil {
                                titleBadgeTransition = .immediate
                                strongSelf.view.addSubview(view)
                            }
                            titleBadgeTransition.updateFrame(view: view, frame: CGRect(origin: CGPoint(x: strongSelf.titleNode.frame.maxX + 7.0, y: floor((contentSize.height - badgeSize.height) / 2.0)), size: badgeSize))
                        }
                    } else if let componentView = strongSelf.titleBadgeComponentView {
                        strongSelf.titleBadgeComponentView = nil
                        componentView.view?.removeFromSuperview()
                    }
                    
                    transition.updateFrame(node: strongSelf.highlightedBackgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: params.width, height: layoutSize.height + UIScreenPixel + UIScreenPixel)))
                }
            })
        }
    }
    
    override public func accessibilityActivate() -> Bool {
        guard let item = self.item else {
            return false
        }
        if !item.enabled {
            return false
        }
        if let switchNode = self.switchNode as? IconSwitchNode {
            switchNode.isOn = !switchNode.isOn
            item.updated(switchNode.isOn)
        } else if let switchNode = self.switchNode as? SwitchNode {
            switchNode.isOn = !switchNode.isOn
            item.updated(switchNode.isOn)
        }
        return true
    }
    
    override public func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        
        if highlighted {
            self.highlightedBackgroundNode.alpha = 1.0
            if self.highlightedBackgroundNode.supernode == nil {
                var anchorNode: ASDisplayNode?
                if self.bottomStripeNode.supernode != nil {
                    anchorNode = self.bottomStripeNode
                } else if self.topStripeNode.supernode != nil {
                    anchorNode = self.topStripeNode
                } else if self.backgroundNode.supernode != nil {
                    anchorNode = self.backgroundNode
                }
                if let anchorNode = anchorNode {
                    self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: anchorNode)
                } else {
                    self.addSubnode(self.highlightedBackgroundNode)
                }
            }
        } else {
            if self.highlightedBackgroundNode.supernode != nil {
                if animated {
                    self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0.0, duration: 0.4, completion: { [weak self] completed in
                        if let strongSelf = self {
                            if completed {
                                strongSelf.highlightedBackgroundNode.removeFromSupernode()
                            }
                        }
                    })
                    self.highlightedBackgroundNode.alpha = 0.0
                } else {
                    self.highlightedBackgroundNode.removeFromSupernode()
                }
            }
        }
    }
    
    override public func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.allowsGroupOpacity = true
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4, completion: { [weak self] _ in
            self?.layer.allowsGroupOpacity = false
        })
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.allowsGroupOpacity = true
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
    @objc private func switchValueChanged(_ switchView: UIControl) {
        if let item = self.item {
            var value = false
            if #available(iOS 26.0, *) {
                if let uiSwitch = switchView as? UISwitch {
                    value = uiSwitch.isOn
                }
            } else {
                value = (self.switchNode as? SwitchNode)?.isOn ?? false
            }
            item.updated(value)
        }
    }
    
    @objc private func switchValueChangedForPill(_ switchView: UIControl) {
        if #available(iOS 26.0, *) {
            return
        }
        
        guard let backgroundPill = self.backgroundPillView,
              let switchNode = self.switchNode as? SwitchNode else {
            return
        }
        
        let backgroundColor = switchNode.isOn ? switchNode.contentColor : switchNode.frameColor
        
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            backgroundPill.backgroundColor = backgroundColor
        })
    }
    
    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if let item = self.item, let switchView = self.switchNode.view as? UIControl, case .ended = recognizer.state {
            if item.enabled && !item.displayLocked {
                var value = false
                if #available(iOS 26.0, *) {
                    if let uiSwitch = switchView as? UISwitch {
                        value = uiSwitch.isOn
                    }
                } else {
                    value = (self.switchNode as? SwitchNode)?.isOn ?? false
                }
                item.updated(!value)
            } else {
                item.activatedWhileDisabled()
            }
        }
    }
    
    // MARK: - Clipping Handling

    private var parentViewsWithClippingDisabled: [(view: UIView, originalClipsToBounds: Bool, originalMasksToBounds: Bool)] = []
    
    private func disableClippingOnParentViews(for glassKnob: UIView) {
        restoreClippingOnParentViews()
        
        var currentView: UIView? = glassKnob.superview
        let knobFrameInGlassKnob = glassKnob.bounds
        
        while let view = currentView, !(view is UIWindow) {
            let knobFrameInView = glassKnob.convert(knobFrameInGlassKnob, to: view)
            let extendsBeyondBounds = !view.bounds.contains(knobFrameInView)
            
            if (view.clipsToBounds || view.layer.masksToBounds) && extendsBeyondBounds {
                parentViewsWithClippingDisabled.append((
                    view: view,
                    originalClipsToBounds: view.clipsToBounds,
                    originalMasksToBounds: view.layer.masksToBounds
                ))
                
                view.clipsToBounds = false
                view.layer.masksToBounds = false
            }
            
            currentView = view.superview
        }
    }
    
    private func restoreClippingOnParentViews() {
        for (view, originalClipsToBounds, originalMasksToBounds) in parentViewsWithClippingDisabled {
            view.clipsToBounds = originalClipsToBounds
            view.layer.masksToBounds = originalMasksToBounds
        }
        parentViewsWithClippingDisabled.removeAll()
    }
}
