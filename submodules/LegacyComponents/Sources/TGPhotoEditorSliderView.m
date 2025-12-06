#import <LegacyComponents/TGPhotoEditorSliderView.h>

#import "LegacyComponentsInternal.h"

#import <LegacyComponents/TGPhotoEditorInterfaceAssets.h>

const CGFloat TGPhotoEditorSliderViewLineSize = 3.0f;
const CGFloat TGPhotoEditorSliderViewMargin = 15.0f;
const CGFloat TGPhotoEditorSliderViewInternalMargin = 7.0f;
const CGFloat TGPhotoEditorSliderViewGlassKnobInset = 10.0f;

@interface TGPhotoEditorSliderView () <UIGestureRecognizerDelegate>
{
    CGFloat _knobTouchStart;
    CGFloat _knobTouchCenterStart;
    CGFloat _knobDragCenter;
    NSInteger _lastFeedbackPosition;
    CFTimeInterval _lastDisplayUpdateTime;
    
    UIPanGestureRecognizer *_panGestureRecognizer;
    UITapGestureRecognizer *_tapGestureRecognizer;
    UITapGestureRecognizer *_edgeTapGestureRecognizer;
    UITapGestureRecognizer *_doubleTapGestureRecognizer;
    UILongPressGestureRecognizer *_longPressGestureRecognizer;
    
    UIColor *_backColor;
    UIColor *_trackColor;
    UIColor *_startColor;
    
    bool _startHidden;
    bool _useGlass;
    
    UISelectionFeedbackGenerator *_feedbackGenerator;
}
@end

@implementation TGPhotoEditorSliderView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        _minimumValue = 0.0f;
        _maximumValue = 1.0f;
        _startValue = 0.0f;
        _value = _startValue;
        _dotSize = 10.5f;
        _minimumUndottedValue = -1;
        _markPositions = true;
        _useGlass = false;
        _lastFeedbackPosition = -1;
        _lastDisplayUpdateTime = 0.0;
        
        _lineSize = TGPhotoEditorSliderViewLineSize;
        _knobPadding = TGPhotoEditorSliderViewInternalMargin;
        
        _backColor = [TGPhotoEditorInterfaceAssets sliderBackColor];
        _trackColor = [TGPhotoEditorInterfaceAssets sliderTrackColor];
        _startColor = [TGPhotoEditorInterfaceAssets sliderTrackColor];
        
        static UIImage *knobViewImage = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^
        {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(21.0f, 21.0f), false, 0.0f);
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSetShadowWithColor(context, CGSizeMake(0, 0.5f), 1.5f, [UIColor colorWithWhite:0.0f alpha:0.5f].CGColor);
            CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
            CGContextFillEllipseInRect(context, CGRectMake(2.0f, 2.0f, 17.0f, 17.0f));
            knobViewImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        });
        
        _knobView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _knobView.image = knobViewImage;
        [self addSubview:_knobView];
        
        _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panGestureRecognizer.enabled = false;
        _panGestureRecognizer.delegate = self;
        [self addGestureRecognizer:_panGestureRecognizer];
        
        _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        _tapGestureRecognizer.enabled = false;
        [self addGestureRecognizer:_tapGestureRecognizer];
        
        _edgeTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgeTap:)];
        _edgeTapGestureRecognizer.enabled = false;
        [self addGestureRecognizer:_edgeTapGestureRecognizer];
        
        _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [self addGestureRecognizer:_doubleTapGestureRecognizer];
        
        _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        _longPressGestureRecognizer.minimumPressDuration = 0.0;
        _longPressGestureRecognizer.allowableMovement = CGFLOAT_MAX;
        _longPressGestureRecognizer.enabled = false;
        [self addGestureRecognizer:_longPressGestureRecognizer];
        
        if (iosMajorVersion() >= 10)
            _feedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
    }
    return self;
}

#pragma mark -

- (void)setPositionsCount:(NSInteger)positionsCount
{
    _positionsCount = positionsCount;
    _tapGestureRecognizer.enabled = !_disableSnapToPositions && _positionsCount > 1 && !_useGlass;
    _doubleTapGestureRecognizer.enabled = !_tapGestureRecognizer.enabled && !_useGlass;
}

- (void)setUseGlass:(bool)useGlass
{
    _useGlass = useGlass;
    
    if (_useGlass) {
        _tapGestureRecognizer.enabled = false;
        _doubleTapGestureRecognizer.enabled = false;
        _edgeTapGestureRecognizer.enabled = false;
        _longPressGestureRecognizer.enabled = true;
        _panGestureRecognizer.enabled = false;
    }
}

- (void)drawRectangle:(CGRect)rect cornerRadius:(CGFloat)cornerRadius context:(CGContextRef)context
{
    if (cornerRadius > FLT_EPSILON)
    {
        CGContextAddPath(context, [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius].CGPath);
        CGContextClosePath(context);
        CGContextFillPath(context);
    }
    else
    {
        CGContextFillRect(context, rect);
    }
}

- (void)drawRect:(CGRect)__unused rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGFloat margin = TGPhotoEditorSliderViewInternalMargin;
    CGFloat knobInset = _useGlass ? TGPhotoEditorSliderViewGlassKnobInset : 0.0f;
    CGFloat trackExtend = _useGlass ? 8.0f : 0.0f;
    
    CGFloat visualMargin = _positionsCount > 1 ? margin : 2.0f;
    CGFloat baseTotalLength = self.frame.size.width - margin * 2;
    CGFloat totalLength = MAX(0.0f, baseTotalLength - knobInset * 2.0f);
    CGFloat visualTotalLength = self.frame.size.width - 2 * (_positionsCount > 1 ? margin : visualMargin);
    
    CGFloat trackMargin = visualMargin;
    CGFloat trackTotalLength = visualTotalLength;
    if (_useGlass) {
        trackMargin = MAX(0.0f, trackMargin - trackExtend);
        trackTotalLength = visualTotalLength + trackExtend * 2.0f;
    }
    
    CGFloat sideLength = self.frame.size.height;
    bool vertical = false;
    if (self.frame.size.width < self.frame.size.height)
    {
        baseTotalLength = self.frame.size.height - margin * 2;
        totalLength = MAX(0.0f, baseTotalLength - knobInset * 2.0f);
        visualTotalLength = self.frame.size.height - 2 * (_positionsCount > 1 ? margin : visualMargin);
        
        trackMargin = visualMargin;
        trackTotalLength = visualTotalLength;
        if (_useGlass) {
            trackMargin = MAX(0.0f, trackMargin - trackExtend);
            trackTotalLength = visualTotalLength + trackExtend * 2.0f;
        }
        sideLength = self.frame.size.width;
        vertical = true;
    }
    
    CGFloat knobBias = (_useGlass && !_knobView.highlighted && _value >= _maximumValue - 0.0001f) ? 1.0f : 0.0f;
    BOOL useDragCenter = _knobView.highlighted && (_useGlass || self.positionsCount < 2);
    CGFloat knobPosition = _knobPadding + knobInset + (useDragCenter ? _knobDragCenter : [self centerPositionForValue:_value totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical]);
    knobPosition = MAX(_knobPadding + knobInset, MIN(knobPosition + knobBias, _knobPadding + knobInset + totalLength + knobBias));
    
    CGFloat lowerBoundPosition = _knobPadding + knobInset + [self centerPositionForValue:_lowerBoundValue totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical];
    
    CGFloat viewWidth = vertical ? self.frame.size.height : self.frame.size.width;
    CGFloat maxTrackTotalLength = viewWidth - trackMargin;
    CGFloat effectiveTrackTotalLength = MIN(trackTotalLength, maxTrackTotalLength);
    
    CGFloat startPosition = trackMargin + effectiveTrackTotalLength / (_maximumValue - _minimumValue) * (ABS(_minimumValue) + _startValue);
    if (vertical)
        startPosition = 2 * trackMargin + effectiveTrackTotalLength - startPosition;
    
    CGFloat endPosition = trackMargin + effectiveTrackTotalLength / (_maximumValue - _minimumValue) * (ABS(_minimumValue) + _maximumValue);
    if (vertical)
        endPosition = 2 * trackMargin + effectiveTrackTotalLength - endPosition;
    
    CGFloat origin = startPosition;
    CGFloat track = knobPosition - startPosition;
    if (track < 0)
    {
        track = fabs(track);
        origin -= track;
    }
    
    if (_useGlass) {
        const CGFloat remapZone = 10.0f;
        
        CGFloat knobMinPosition = _knobPadding + knobInset;
        CGFloat knobMaxPosition = _knobPadding + knobInset + totalLength;
        
        CGFloat distanceFromKnobMin = knobPosition - knobMinPosition;
        CGFloat distanceFromKnobMax = knobMaxPosition - knobPosition;
        
        CGFloat boundaryKnobPosStart = knobMinPosition + remapZone;
        CGFloat boundaryKnobPosEnd = knobMaxPosition - remapZone;
        CGFloat normalTrackAtBoundaryStart = boundaryKnobPosStart - startPosition;
        CGFloat normalTrackAtBoundaryEnd = boundaryKnobPosEnd - startPosition;
        if (normalTrackAtBoundaryStart < 0) {
            normalTrackAtBoundaryStart = fabs(normalTrackAtBoundaryStart);
        }
        if (normalTrackAtBoundaryEnd < 0) {
            normalTrackAtBoundaryEnd = fabs(normalTrackAtBoundaryEnd);
        }
        
        CGFloat maxTrackWidth = endPosition - startPosition;
        if (maxTrackWidth < 0) {
            maxTrackWidth = fabs(maxTrackWidth);
        }
        normalTrackAtBoundaryStart = MIN(normalTrackAtBoundaryStart, maxTrackWidth);
        normalTrackAtBoundaryEnd = MIN(normalTrackAtBoundaryEnd, maxTrackWidth);
        
        if (distanceFromKnobMin <= 0) {
            track = 0.0f;
            origin = startPosition;
        }
        else if (distanceFromKnobMax <= 0) {
            track = endPosition - startPosition;
            if (track < 0) {
                track = fabs(track);
            }
            origin = startPosition;
        }
        else if (distanceFromKnobMin <= remapZone) {
            CGFloat normalizedPos = distanceFromKnobMin / remapZone;
            CGFloat acceleratedPos = normalizedPos * normalizedPos * (3.0f - 2.0f * normalizedPos);
            track = acceleratedPos * normalTrackAtBoundaryStart;
            origin = startPosition;
        }
        else if (distanceFromKnobMax <= remapZone) {
            CGFloat normalizedPos = 1.0f - (distanceFromKnobMax / remapZone);
            CGFloat acceleratedPos = normalizedPos * normalizedPos * (3.0f - 2.0f * normalizedPos);
            CGFloat trackRange = maxTrackWidth - normalTrackAtBoundaryEnd;
            if (trackRange > 0) {
                track = normalTrackAtBoundaryEnd + (acceleratedPos * trackRange);
            } else {
                track = maxTrackWidth;
            }
            origin = startPosition;
        }
    }
    
    CGRect backFrame = CGRectMake(trackMargin, (sideLength - _lineSize) / 2, effectiveTrackTotalLength, _lineSize);
    
    if (_useGlass) {
        CGFloat maxTrackWidth = endPosition - startPosition;
        if (maxTrackWidth < 0) {
            maxTrackWidth = fabs(maxTrackWidth);
        }
        track = MIN(track, maxTrackWidth);
        if (origin + track > endPosition) {
            track = MAX(0, endPosition - origin);
        }
    }
    
    CGRect trackFrame = CGRectMake(origin, (sideLength - _lineSize) / 2, track, _lineSize);
    CGRect startFrame = CGRectMake(startPosition - 4 / 2, (sideLength - 12) / 2, 4, 12);
    CGRect endFrame = CGRectMake(endPosition - 4 / 2, (sideLength - 12) / 2, 4, 12);
    CGRect knobFrame = CGRectMake(knobPosition - _knobView.image.size.width / 2, (sideLength - _knobView.image.size.height) / 2, _knobView.image.size.width, _knobView.image.size.height);
    if (vertical)
    {
        backFrame = CGRectMake(backFrame.origin.y, backFrame.origin.x, backFrame.size.height, backFrame.size.width);
        trackFrame = CGRectMake(trackFrame.origin.y, trackFrame.origin.x, trackFrame.size.height, trackFrame.size.width);
        startFrame = CGRectMake(startFrame.origin.y, startFrame.origin.x, startFrame.size.height, startFrame.size.width);
        endFrame = CGRectMake(endFrame.origin.y, endFrame.origin.x, endFrame.size.height, endFrame.size.width);
        knobFrame = CGRectMake(knobFrame.origin.y, knobFrame.origin.x, knobFrame.size.width, knobFrame.size.height);
    }
    
    if (_markValue > FLT_EPSILON)
    {
        CGContextSetFillColorWithColor(context, _backColor.CGColor);
        [self drawRectangle:backFrame cornerRadius:0.0f context:context];
    }
    
    if (_bordered)
    {
        CGContextSetFillColorWithColor(context, UIColorRGBA(0x000000, 0.6f).CGColor);
        [self drawRectangle:CGRectInset(backFrame, -1.0f, -1.0f) cornerRadius:self.trackCornerRadius * 2.0f context:context];
        if (!_startHidden)
            [self drawRectangle:CGRectInset(startFrame, -1.0f, -1.0f) cornerRadius:self.trackCornerRadius * 2.0f context:context];
        
        CGContextSetBlendMode(context, kCGBlendModeCopy);
    }

    for (int passIndex = 0; passIndex < 2; passIndex++) {
        CGContextSaveGState(context);
        CGContextResetClip(context);
        
        UIColor *passBackColor = _backColor;
        UIColor *passTrackColor = _trackColor;
        
        if (passIndex == 0) {
            if (_lowerBoundValue > 0.0f && _lowerBoundTrackColor != nil) {
                CGContextBeginPath(context);
                CGContextAddRect(context, CGRectMake(0.0, 0.0, lowerBoundPosition, rect.size.height));
                CGContextClip(context);
                
                CGFloat trackAlpha = 0.0f;
                [_trackColor getRed:nil green:nil blue:nil alpha:&trackAlpha];
                
                passTrackColor = _lowerBoundTrackColor;
            }
        } else {
            if (_lowerBoundValue > 0.0f && _lowerBoundTrackColor != nil && lowerBoundPosition < rect.size.width) {
                CGContextBeginPath(context);
                CGContextAddRect(context, CGRectMake(lowerBoundPosition, 0.0, rect.size.width - lowerBoundPosition, rect.size.height));
                CGContextClip(context);
            } else {
                CGContextRestoreGState(context);
                break;
            }
        }
        
        CGContextSetFillColorWithColor(context, passBackColor.CGColor);
        [self drawRectangle:backFrame cornerRadius:self.trackCornerRadius context:context];
        
        CGContextSetBlendMode(context, kCGBlendModeNormal);
        
        CGContextSetFillColorWithColor(context, passTrackColor.CGColor);
        [self drawRectangle:trackFrame cornerRadius:self.trackCornerRadius context:context];
        
        if (!_startHidden || self.displayEdges)
        {
            bool highlighted = CGRectGetMidX(startFrame) < CGRectGetMaxX(trackFrame);
            if (vertical)
                highlighted = CGRectGetMidY(startFrame) > CGRectGetMinY(trackFrame);
            highlighted = highlighted && self.displayEdges;
            
            CGContextSetFillColorWithColor(context, highlighted ? passTrackColor.CGColor : _startColor.CGColor);
            [self drawRectangle:startFrame cornerRadius:self.trackCornerRadius context:context];
        }
        
        if (self.displayEdges) {
            CGContextSetFillColorWithColor(context, passBackColor.CGColor);
            [self drawRectangle:endFrame cornerRadius:self.trackCornerRadius context:context];
        }
        
        if (_bordered)
        {
            CGContextSetFillColorWithColor(context, UIColorRGBA(0x000000, 0.6f).CGColor);
            CGContextFillEllipseInRect(context, CGRectInset(knobFrame, 1.0f, 1.0f));
        }
        
        if (_useGlass && self.useLinesForPositions && self.positionsCount > 1)
        {
            CGFloat dotRadius = 2.0f;
            CGFloat knobTotalLength = (vertical ? self.frame.size.height : self.frame.size.width) - margin * 2;
            knobTotalLength = MAX(0.0f, knobTotalLength - knobInset * 2.0f);
            
            for (NSInteger i = 0; i < self.positionsCount; i++)
            {
                if (!self.markPositions) {
                    if (i != 0 && i != self.positionsCount - 1) {
                        continue;
                    }
                }
                
                CGFloat dotX = _knobPadding + knobInset + knobTotalLength / (self.positionsCount - 1) * i;
                CGFloat dotY = (sideLength - _lineSize) / 2 + _lineSize / 2.0f + 8.0f;
                if (vertical) {
                    CGFloat temp = dotX;
                    dotX = dotY;
                    dotY = temp;
                }
                
                CGRect dotRect = CGRectMake(dotX - dotRadius, dotY - dotRadius, dotRadius * 2.0f, dotRadius * 2.0f);
                CGContextSetFillColorWithColor(context, passBackColor.CGColor);
                CGContextFillEllipseInRect(context, dotRect);
            }
        } else if (self.positionsCount > 1)
        {
            for (NSInteger i = 0; i < self.positionsCount; i++)
            {
                if (!self.markPositions) {
                    if (i != 0 && i != self.positionsCount - 1) {
                        continue;
                    }
                }
                
                if (self.useLinesForPositions) {
                    CGSize lineSize = CGSizeMake(4.0, 12.0);
                    CGRect lineRect = CGRectMake(margin - lineSize.width / 2.0f + totalLength / (self.positionsCount - 1) * i, (sideLength - lineSize.height) / 2, lineSize.width, lineSize.height);
                    if (vertical)
                        lineRect = CGRectMake(lineRect.origin.y, lineRect.origin.x, lineRect.size.height, lineRect.size.width);
                    
                    bool highlighted = CGRectGetMidX(lineRect) < CGRectGetMaxX(trackFrame);
                    if (vertical)
                        highlighted = CGRectGetMidY(lineRect) > CGRectGetMinY(trackFrame);
                    
                    CGContextSetFillColorWithColor(context, highlighted ? passTrackColor.CGColor : passBackColor.CGColor);
                    [self drawRectangle:lineRect cornerRadius:self.trackCornerRadius context:context];
                } else {
                    if ([self.backgroundColor isEqual:[UIColor clearColor]])
                    {
                        CGContextSetBlendMode(context, kCGBlendModeClear);
                        CGContextSetFillColorWithColor(context, [UIColor clearColor].CGColor);
                    }
                    else
                    {
                        CGContextSetFillColorWithColor(context, self.backgroundColor.CGColor);
                    }
                    
                    CGFloat inset = 1.5f;
                    CGFloat outerSize = _dotSize + inset * 2.0f;
                    CGRect dotRect = CGRectMake(margin - outerSize / 2.0f + totalLength / (self.positionsCount - 1) * i, (sideLength - outerSize) / 2, outerSize, outerSize);
                    if (vertical)
                        dotRect = CGRectMake(dotRect.origin.y, dotRect.origin.x, dotRect.size.height, dotRect.size.width);
                    
                    CGContextFillEllipseInRect(context, dotRect);
                    
                    dotRect = CGRectInset(dotRect, inset, inset);
                    
                    CGContextSetBlendMode(context, kCGBlendModeNormal);
                    bool highlighted = CGRectGetMidX(dotRect) < CGRectGetMaxX(trackFrame);
                    if (vertical)
                        highlighted = CGRectGetMidY(dotRect) > CGRectGetMinY(trackFrame);
                    
                    CGContextSetFillColorWithColor(context, highlighted ? passTrackColor.CGColor : passBackColor.CGColor);
                    CGContextFillEllipseInRect(context, dotRect);
                }
            }
        }
        
        CGContextRestoreGState(context);
    }
}

#pragma mark -

- (void)setLineSize:(CGFloat)lineSize
{
    _lineSize = lineSize;
    [self setNeedsLayout];
}

- (UIColor *)backColor
{
    return _backColor;
}

- (void)setBackColor:(UIColor *)backColor
{
    _backColor = backColor;
    [self setNeedsDisplay];
}

- (UIColor *)trackColor
{
    return _trackColor;
}

- (void)setTrackColor:(UIColor *)trackColor
{
    if (_trackColor == nil || ![_trackColor isEqual:trackColor]) {
        _trackColor = trackColor;
        [self setNeedsDisplay];
    }
}

- (UIColor *)startColor
{
    return _startColor;
}

- (void)setStartColor:(UIColor *)startColor
{
    _startColor = startColor;
    [self setNeedsDisplay];
}

- (UIImage *)knobImage
{
    return _knobView.image;
}

- (void)setKnobImage:(UIImage *)knobImage
{
    _knobView.image = knobImage;
    [self setNeedsLayout];
}

- (void)setBordered:(bool)bordered
{
    _bordered = bordered;
    [self setNeedsDisplay];
}

- (void)setMinimumUndottedValue:(int)minimumUndottedValue {
    if (_minimumUndottedValue != minimumUndottedValue) {
        _minimumUndottedValue = minimumUndottedValue;
        [self setNeedsDisplay];
    }
}

#pragma mark - Properties

- (BOOL)isTracking
{
    return _knobView.highlighted;
}

- (void)setValue:(CGFloat)value
{
    [self setValue:value animated:NO];
}

- (void)setValue:(CGFloat)value animated:(BOOL)__unused animated
{
    if (_lowerBoundValue > FLT_EPSILON) {
        _value = MIN(MAX(_lowerBoundValue, MAX(value, _minimumValue)), _maximumValue);
    } else {
        _value = MIN(MAX(value, _minimumValue), _maximumValue);
    }
    [self setNeedsLayout];
}

- (void)setStartValue:(CGFloat)startValue
{
    _startValue = startValue;
    if (ABS(_startValue - _minimumValue) < FLT_EPSILON)
        _startHidden = true;

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)setDotSize:(CGFloat)dotSize
{
    _dotSize = dotSize;
    [self setNeedsDisplay];
}

- (void)layoutSubviews
{
    if (CGRectIsEmpty(self.frame))
        return;
    
    CGFloat margin = TGPhotoEditorSliderViewInternalMargin;
    CGFloat knobInset = _useGlass ? TGPhotoEditorSliderViewGlassKnobInset : 0.0f;
    CGFloat totalLength = self.frame.size.width - margin * 2;
    totalLength = MAX(0.0f, totalLength - knobInset * 2.0f);
    CGFloat sideLength = self.frame.size.height;
    bool vertical = false;
    if (self.frame.size.width < self.frame.size.height)
    {
        totalLength = self.frame.size.height - margin * 2;
        totalLength = MAX(0.0f, totalLength - knobInset * 2.0f);
        sideLength = self.frame.size.width;
        vertical = true;
    }
    
    CGFloat knobBias = (_useGlass && !_knobView.highlighted && _value >= _maximumValue - 0.0001f) ? 1.0f : 0.0f;
    BOOL useDragCenter = _knobView.highlighted && (_useGlass || self.positionsCount < 2);
    CGFloat knobPosition = _knobPadding + knobInset + (useDragCenter ? _knobDragCenter : [self centerPositionForValue:_value totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical]);
    knobPosition = MAX(_knobPadding + knobInset, MIN(knobPosition + knobBias, _knobPadding + knobInset + totalLength + knobBias));
    
    CGRect knobViewFrame = CGRectMake(knobPosition - _knobView.image.size.width / 2, (sideLength - _knobView.image.size.height) / 2, _knobView.image.size.width, _knobView.image.size.height);
    
    if (self.frame.size.width > self.frame.size.height)
        _knobView.frame = knobViewFrame;
    else
        _knobView.frame = CGRectMake(knobViewFrame.origin.y, knobViewFrame.origin.x, knobViewFrame.size.width, knobViewFrame.size.height);
    
    [self setNeedsDisplay];
}

#pragma mark -

- (CGFloat)centerPositionForValue:(CGFloat)value totalLength:(CGFloat)totalLength knobSize:(CGFloat)knobSize vertical:(bool)vertical
{
    if (_minimumValue < 0)
    {
        CGFloat knob = knobSize;
        if (fabs(_minimumValue) > 1.0 && (NSInteger)value == 0) {
            return totalLength / 2;
        } else if (fabs(value) < 0.01)
        {
            return totalLength / 2;
        }
        else
        {
            CGFloat edgeValue = (value > 0 ? _maximumValue : _minimumValue);
            if ((value < 0 && vertical) || (value > 0 && !vertical))
                return ((totalLength + knob) / 2) + ((totalLength - knob) / 2) * ABS(value / edgeValue);
            else
                return ((totalLength - knob) / 2) * ABS((edgeValue - _value) / edgeValue);
        }
    }

    CGFloat position = totalLength / (_maximumValue - _minimumValue) * (ABS(_minimumValue) + value);
    if (vertical)
        position = totalLength - position;
    
    return position;
}

- (CGFloat)valueForCenterPosition:(CGFloat)position totalLength:(CGFloat)totalLength knobSize:(CGFloat)knobSize vertical:(bool)vertical
{
    CGFloat value = 0;
    if (_minimumValue < 0)
    {
        CGFloat knob = knobSize;
        if (position < (totalLength - knob) / 2)
        {
            CGFloat edgeValue = _minimumValue;
            if (vertical)
            {
                edgeValue = _maximumValue;
                position *= -1;
            }

            value = edgeValue + position / ((totalLength - knob) / 2) * ABS(edgeValue);
        }
        else if (position >= (totalLength - knob) / 2 && position <= (totalLength + knob) / 2)
        {
            value = 0;
        }
        else if (position > (totalLength + knob) / 2)
        {
            CGFloat edgeValue = (vertical ? _minimumValue : _maximumValue);
            value = (position - ((totalLength + knob) / 2)) / ((totalLength - knob) / 2) * edgeValue;
        }
    }
    else
    {
        value = _minimumValue + (!vertical ? position : (totalLength - position)) / totalLength * (_maximumValue - _minimumValue);
    }
    
    return MIN(MAX(value, _minimumValue), _maximumValue);
}

- (void)setEnablePanHandling:(bool)enablePanHandling {
    _enablePanHandling = enablePanHandling;
    if (!_useGlass) {
        _panGestureRecognizer.enabled = enablePanHandling;
    }
}

#pragma mark - Touch Handling

- (void)handlePan:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [self handleBeginTracking:[gestureRecognizer locationInView:self]];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateChanged) {
        [self handleContinueTracking:[gestureRecognizer locationInView:self]];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self handleEndTracking];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateCancelled) {
        [self handleCancelTracking];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)gestureRecognizer
{
    CGPoint touchLocation = [gestureRecognizer locationInView:self];
    CGFloat totalLength = self.frame.size.width;
    CGFloat location = touchLocation.x;
    
    if (self.frame.size.width < self.frame.size.height)
    {
        totalLength = self.frame.size.height;
        location = touchLocation.y;
    }
    
    CGFloat position = ((location / totalLength) * (self.positionsCount - 1));
    CGFloat previousPosition = MAX(0, floor(position));
    CGFloat nextPosition = MIN(self.positionsCount - 1, ceil(position));
    
    bool changed = false;
    if (fabs(position - previousPosition) < 0.3f)
    {
        [self setValue:previousPosition];
        changed = true;
    }
    else if (fabs(position - nextPosition) < 0.3f)
    {
        [self setValue:nextPosition];
        changed = true;
    }
    
    if (changed)
    {
        if (self.interactionBegan != nil)
            self.interactionBegan();
        
        [self setNeedsLayout];
        [self sendActionsForControlEvents:UIControlEventValueChanged];
        
        if (self.interactionEnded != nil)
            self.interactionEnded();
        
        [_feedbackGenerator selectionChanged];
        [_feedbackGenerator prepare];
    }
}

- (void)setEnableEdgeTap:(bool)enableEdgeTap {
    _enableEdgeTap = enableEdgeTap;
    _edgeTapGestureRecognizer.enabled = enableEdgeTap && !_useGlass;
}

- (void)handleEdgeTap:(UITapGestureRecognizer *)gestureRecognizer {
    bool changed = false;
    
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        CGPoint touchLocation = [gestureRecognizer locationInView:self];
        CGFloat edgeWidth = 16.0f;
        if (touchLocation.x < edgeWidth || touchLocation.x > self.bounds.size.width - edgeWidth) {
            CGRect knobRect = CGRectInset(self.knobView.frame, -8.0, -8.0);
            if (!CGRectContainsPoint(knobRect, touchLocation)) {
                if (touchLocation.x < edgeWidth) {
                    [self setValue:_minimumValue];
                } else {
                    [self setValue:_maximumValue];
                }
                changed = true;
            }
        }
    }
    
    if (changed)
    {
        if (self.interactionBegan != nil)
            self.interactionBegan();
        
        [self setNeedsLayout];
        [self sendActionsForControlEvents:UIControlEventValueChanged];
        
        if (self.interactionEnded != nil)
            self.interactionEnded();
        
        [_feedbackGenerator selectionChanged];
        [_feedbackGenerator prepare];
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)__unused gestureRecognizer
{
    if (self.reset != nil)
        self.reset();
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (!_useGlass) {
        return;
    }
    
    CGPoint touchLocation = [gestureRecognizer locationInView:self];
    
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGRect knobHitRect = CGRectInset(_knobView.frame, -30.0, -30.0);
        if (CGRectContainsPoint(knobHitRect, touchLocation)) {
            [self handleBeginTracking:touchLocation];
            _knobStartedDragging = true;
            
            if (self.interactionBegan != nil)
                self.interactionBegan();
        }
    } else if (gestureRecognizer.state == UIGestureRecognizerStateChanged) {
        [self handleContinueTracking:touchLocation];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded ||
               gestureRecognizer.state == UIGestureRecognizerStateCancelled) {
        [self handleEndTracking];
    }
}

- (void)maybeCancelParentViewScrolling:(UIView *)parentView depth:(int32_t)depth
{
    if (depth > 5)
        return;
    
    if ([parentView isKindOfClass:[UIScrollView class]])
    {
        ((UIScrollView *)parentView).scrollEnabled = false;
        ((UIScrollView *)parentView).scrollEnabled = true;
    }
    else if (parentView.superview != nil)
    {
        [self maybeCancelParentViewScrolling:parentView.superview depth:depth++];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _panGestureRecognizer) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:gestureRecognizer.view];
        return ABS(velocity.x) > ABS(velocity.y);
    }
    
    if (gestureRecognizer == _longPressGestureRecognizer && _useGlass) {
        CGPoint touchLocation = [gestureRecognizer locationInView:self];
        CGRect knobHitRect = CGRectInset(_knobView.frame, -35.0, -35.0);
        return CGRectContainsPoint(knobHitRect, touchLocation);
    }
    
    return true;
}


- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)__unused event
{
    if (!_enablePanHandling && !_useGlass) {
        CGPoint touchLocation = [touch locationInView:self];
        [self handleBeginTracking:touchLocation];
    }
    return !_useGlass;
}

- (void)handleBeginTracking:(CGPoint)touchLocation {
    _lastFeedbackPosition = -1;
    
    _knobView.highlighted = true;
    
    CGFloat knobInset = _useGlass ? TGPhotoEditorSliderViewGlassKnobInset : 0.0f;
    bool vertical = self.frame.size.width < self.frame.size.height;
    CGFloat margin = TGPhotoEditorSliderViewInternalMargin;
    CGFloat totalLength = (vertical ? self.frame.size.height : self.frame.size.width) - margin * 2;
    totalLength = MAX(0.0f, totalLength - knobInset * 2.0f);
    
    if (self.frame.size.width > self.frame.size.height)
    {
        _knobTouchStart = touchLocation.x;
        if (_useGlass) {
            _knobTouchCenterStart = [self centerPositionForValue:_value totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical];
            _knobDragCenter = _knobTouchCenterStart;
        } else {
            _knobTouchCenterStart = _knobView.center.x;
            _knobDragCenter = touchLocation.x;
        }
    }
    else
    {
        _knobTouchStart = touchLocation.y;
        if (_useGlass) {
            _knobTouchCenterStart = [self centerPositionForValue:_value totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical];
            _knobDragCenter = _knobTouchCenterStart;
        } else {
            _knobTouchCenterStart = _knobView.center.y;
            _knobDragCenter = touchLocation.y;
        }
    }
    
    _knobStartedDragging = false;
    
    [_feedbackGenerator prepare];
    
    [self maybeCancelParentViewScrolling:self.superview depth:0];
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)__unused event
{
    if (!_enablePanHandling && !_useGlass) {
        CGPoint touchLocation = [touch locationInView:self];
        [self handleContinueTracking:touchLocation];
    }
    return !_useGlass;
}

- (BOOL)handleContinueTracking:(CGPoint)touchLocation
{
    CGFloat knobInset = _useGlass ? TGPhotoEditorSliderViewGlassKnobInset : 0.0f;
    
    CGFloat totalLength = self.frame.size.width;
    bool vertical = false;
    CGFloat currentTouchPos = touchLocation.x;
    
    if (self.frame.size.width > self.frame.size.height)
    {
        vertical = false;
        currentTouchPos = touchLocation.x;
    }
    else
    {
        vertical = true;
        totalLength = self.frame.size.height;
        currentTouchPos = touchLocation.y;
    }
    
    if (fabs(currentTouchPos - _knobTouchStart) > 1.0f && !_knobStartedDragging)
    {
        _knobStartedDragging = true;
        
        if (self.interactionBegan != nil)
            self.interactionBegan();
    }
    
    totalLength -= (_knobPadding + knobInset) * 2;
    
    if (_useGlass) {
        CGFloat touchDelta = currentTouchPos - _knobTouchStart;
        _knobDragCenter = _knobTouchCenterStart + touchDelta;
    } else {
        _knobDragCenter = _knobTouchCenterStart - _knobTouchStart - (_knobPadding + knobInset);
        _knobDragCenter += currentTouchPos;
    }
    
    CGFloat previousValue = self.value;
    if (self.positionsCount > 1 && !self.disableSnapToPositions && !(_useGlass && self.positionsCount > 1))
    {
        NSInteger position = (NSInteger)round((_knobDragCenter / totalLength) * (self.positionsCount - 1));
        
        if (_lowerBoundValue > 0.0f) {
            position = MAX(position, (NSInteger)_lowerBoundValue);
        }
        
        _knobDragCenter = position * totalLength / (self.positionsCount - 1);
    } else {
        if (_lowerBoundValue > 0.0f) {
            _knobDragCenter = MAX(_knobDragCenter, _lowerBoundValue * totalLength);
        }
    }
    _knobDragCenter = MAX(0.0f, MIN(_knobDragCenter, totalLength));
    
    if (!(_useGlass && self.positionsCount > 1)) {
        [self setValue:[self valueForCenterPosition:_knobDragCenter totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical]];
        if (previousValue != self.value && !self.disableSnapToPositions && (self.positionsCount > 1 || self.value == self.minimumValue || self.value == self.maximumValue || (self.minimumValue != self.startValue && self.value == self.startValue)))
        {
            [_feedbackGenerator selectionChanged];
            [_feedbackGenerator prepare];
        }
    } else {
        CGFloat newValue = [self valueForCenterPosition:_knobDragCenter totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical];
        if (_lowerBoundValue > FLT_EPSILON) {
            _value = MIN(MAX(_lowerBoundValue, MAX(newValue, _minimumValue)), _maximumValue);
        } else {
            _value = MIN(MAX(newValue, _minimumValue), _maximumValue);
        }
    }
    
    if (_useGlass && self.positionsCount > 1) {
        CGFloat margin = TGPhotoEditorSliderViewInternalMargin;
        CGFloat knobInset = TGPhotoEditorSliderViewGlassKnobInset;
        CGFloat totalLength = (vertical ? self.frame.size.height : self.frame.size.width) - margin * 2;
        totalLength = MAX(0.0f, totalLength - knobInset * 2.0f);
        CGFloat sideLength = vertical ? self.frame.size.width : self.frame.size.height;
        
        CGFloat knobPosition = _knobPadding + knobInset + _knobDragCenter;
        knobPosition = MAX(_knobPadding + knobInset, MIN(knobPosition, _knobPadding + knobInset + totalLength));
        
        CGRect knobViewFrame = CGRectMake(knobPosition - _knobView.image.size.width / 2, (sideLength - _knobView.image.size.height) / 2, _knobView.image.size.width, _knobView.image.size.height);
        
        if (vertical) {
            _knobView.frame = CGRectMake(knobViewFrame.origin.y, knobViewFrame.origin.x, knobViewFrame.size.width, knobViewFrame.size.height);
        } else {
            _knobView.frame = knobViewFrame;
        }
        
        CFTimeInterval now = CACurrentMediaTime();
        CFTimeInterval minDisplayInterval = 1.0 / 60.0; // 60 FPS
        if (now - _lastDisplayUpdateTime >= minDisplayInterval) {
            [self setNeedsDisplay];
            _lastDisplayUpdateTime = now;
        }
    } else {
        [self setNeedsLayout];
    }
    
    if (!_limitValueChangedToLatestState) {
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    
    return true;
}

- (void)endTrackingWithTouch:(UITouch *)__unused touch withEvent:(UIEvent *)__unused event
{
    if (!_enablePanHandling && !_useGlass) {
        [self handleEndTracking];
    }
}

- (void)handleEndTracking
{
    _knobView.highlighted = false;
    
    if (_useGlass && self.positionsCount > 1 && !self.disableSnapToPositions) {
        CGFloat knobInset = TGPhotoEditorSliderViewGlassKnobInset;
        bool vertical = self.frame.size.width < self.frame.size.height;
        CGFloat margin = TGPhotoEditorSliderViewInternalMargin;
        CGFloat totalLength = (vertical ? self.frame.size.height : self.frame.size.width) - margin * 2;
        totalLength = MAX(0.0f, totalLength - knobInset * 2.0f);
        
        NSInteger position = (NSInteger)round((_knobDragCenter / totalLength) * (self.positionsCount - 1));
        
        if (_lowerBoundValue > 0.0f) {
            position = MAX(position, (NSInteger)_lowerBoundValue);
        }
        
        CGFloat targetDragCenter = position * totalLength / (self.positionsCount - 1);
        
        if (position != _lastFeedbackPosition) {
            [_feedbackGenerator selectionChanged];
            _lastFeedbackPosition = position;
        }

        CGFloat snappedValue = [self valueForCenterPosition:targetDragCenter totalLength:totalLength knobSize:_knobView.image.size.width vertical:vertical];
        [self setValue:snappedValue];
        
        _knobDragCenter = targetDragCenter;
    }
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    
    if (self.interactionEnded != nil)
        self.interactionEnded();
}

- (void)setLastFeedbackPosition:(NSInteger)position
{
    _lastFeedbackPosition = position;
}

- (void)cancelTrackingWithEvent:(UIEvent *)__unused event
{
    if (!_enablePanHandling && !_useGlass) {
        [self handleCancelTracking];
    }
}

- (void)handleCancelTracking
{
    _knobView.highlighted = false;
    
    [self setNeedsLayout];
    
    if (self.interactionEnded != nil)
        self.interactionEnded();
}

- (void)increase {
    self.value = MIN(self.maximumValue, self.value + 1);
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsLayout];
}

- (void)increaseBy:(CGFloat)delta {
    self.value = MIN(self.maximumValue, self.value + delta);
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsLayout];
}

- (void)decrease {
    self.value = MAX(self.minimumValue, self.value - 1);
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsLayout];
}

- (void)decreaseBy:(CGFloat)delta {
    self.value = MAX(self.minimumValue, self.value - delta);
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    [self setNeedsLayout];
}

@end
