#import "HBBalanceView.h"
#include <stdlib.h>
#include <math.h>

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
typedef CGFloat HBGraphFloat;
#else
typedef float HBGraphFloat;
#endif
static BOOL HVIsDark(void) {
    NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return text && [text brightnessComponent] > 0.5;
}
static NSColor *HVCurve(BOOL dark) { return [NSColor colorWithCalibratedRed:dark ? 0.455 : 0.278 green:dark ? 0.714 : 0.494 blue:dark ? 0.933 : 0.722 alpha:1]; }
static NSColor *HVRed(BOOL dark) { return [NSColor colorWithCalibratedRed:dark ? 1 : 0.78 green:dark ? 0.48 : 0.16 blue:dark ? 0.48 : 0.18 alpha:1]; }
static void HVText(NSString *text, NSRect rect, NSColor *color, BOOL right) {
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:10], NSFontAttributeName, color, NSForegroundColorAttributeName, nil];
    NSSize size = [text sizeWithAttributes:attributes];
    [NSGraphicsContext saveGraphicsState]; [NSBezierPath clipRect:rect];
    [text drawAtPoint:NSMakePoint(right ? NSMaxX(rect) - size.width : rect.origin.x, rect.origin.y) withAttributes:attributes];
    [NSGraphicsContext restoreGraphicsState];
}

@implementation HBBalanceView
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSRect)plotRect { NSRect bounds = [self bounds]; return NSMakeRect(112, 48, MAX(1, bounds.size.width - 132), MAX(1, bounds.size.height - 76)); }
- (void)invalidate {
    [_image release]; _image = nil; free(_samples); _samples = NULL; _sampleCount = 0; _hoverDate = 0; _dragging = NO; [self setNeedsDisplay:YES];
}
- (void)setHistory:(HBBalanceHistory *)history wallet:(HBWallet *)wallet range:(HBHistoryRange)range overdraft:(NSDecimalNumber *)overdraft {
    [history retain]; [_history release]; _history = history; [wallet retain]; [_wallet release]; _wallet = wallet;
    [overdraft retain]; [_overdraft release]; _overdraft = overdraft; _range = range; [self invalidate];
}
- (void)setRange:(HBHistoryRange)range { _range = HBHistoryClamp(range, _history); [self invalidate]; }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self invalidate]; }
- (double)xForDate:(int)date { NSRect plot = [self plotRect]; return plot.origin.x + (date - _range.start) * plot.size.width / (_range.end - _range.start); }
- (double)yForBalance:(double)balance { NSRect plot = [self plotRect]; return plot.origin.y + (balance - _minimum) * plot.size.height / (_maximum - _minimum); }
- (int)dateAtPoint:(NSPoint)point {
    NSRect plot = [self plotRect]; double ratio = MAX(0, MIN(1, (point.x - plot.origin.x) / plot.size.width));
    return _range.start + (int)floor(ratio * (_range.end - _range.start) + 0.5);
}
- (void)drawSegmentFrom:(int)start to:(int)end forecast:(BOOL)forecast dark:(BOOL)dark {
    if (start >= end) return;
    double y = [self yForBalance:[[_history balanceAt:start] doubleValue]], x = [self xForDate:start];
    NSBezierPath *line = [NSBezierPath bezierPath]; [line moveToPoint:NSMakePoint(x, y)]; unsigned int i;
    for (i = 0; i < _sampleCount; i++) if (_samples[i].date > start && _samples[i].date <= end) {
        x = [self xForDate:_samples[i].date]; [line lineToPoint:NSMakePoint(x, y)];
        y = [self yForBalance:_samples[i].balance]; [line lineToPoint:NSMakePoint(x, y)];
    }
    [line lineToPoint:NSMakePoint([self xForDate:end], y)];
    NSBezierPath *area = [[line copy] autorelease]; double zero = [self yForBalance:0];
    [area lineToPoint:NSMakePoint([self xForDate:end], zero)]; [area lineToPoint:NSMakePoint([self xForDate:start], zero)]; [area closePath];
    [[HVCurve(dark) colorWithAlphaComponent:forecast ? (dark ? 0.12 : 0.09) : (dark ? 0.22 : 0.18)] set]; [area fill];
    [HVCurve(dark) set]; [line setLineWidth:2];
    if (forecast) { HBGraphFloat dash[] = {6, 4}; [line setLineDash:dash count:2 phase:0]; }
    [line stroke];
}
- (void)drawBase:(BOOL)dark {
    NSRect bounds = [self bounds], plot = [self plotRect];
    NSColor *surface = dark ? [NSColor colorWithCalibratedWhite:0.10 alpha:1] : [NSColor whiteColor];
    NSColor *grid = [NSColor colorWithCalibratedWhite:dark ? 0.28 : 0.85 alpha:1], *text = [NSColor controlTextColor];
    [surface set]; NSRectFill(bounds);
    if (!_history) { HVText(@"Aucune donnee a afficher.", NSMakeRect(20, bounds.size.height / 2, bounds.size.width - 40, 24), text, NO); return; }
    _samples = [_history copyPointsFrom:_range.start to:_range.end limit:(unsigned int)MAX(16, plot.size.width * 2) count:&_sampleCount];
    if (!_samples) { HVText(@"Memoire insuffisante.", NSMakeRect(20, bounds.size.height / 2, 300, 24), text, NO); return; }
    _minimum = _maximum = 0; unsigned int i;
    for (i = 0; i < _sampleCount; i++) { _minimum = MIN(_minimum, _samples[i].balance); _maximum = MAX(_maximum, _samples[i].balance); }
    if (_overdraft) _minimum = MIN(_minimum, [_overdraft doubleValue]);
    double padding = MAX((_maximum - _minimum) * 0.08, 0.01); _minimum -= padding; _maximum += padding;
    NSDictionary *account = [[_history accounts] objectAtIndex:0];
    for (i = 0; i < 6; i++) {
        double amount = _minimum + (_maximum - _minimum) * i / 5, y = [self yForBalance:amount];
        NSBezierPath *line = [NSBezierPath bezierPath]; [line moveToPoint:NSMakePoint(plot.origin.x, y)]; [line lineToPoint:NSMakePoint(NSMaxX(plot), y)];
        [grid set]; [line stroke];
        NSString *value = [_wallet formatAmount:[NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.12g", amount]] account:account];
        HVText(value, NSMakeRect(4, y - 7, 100, 18), text, YES);
    }
    unsigned int divisions = plot.size.width < 500 ? 3 : 5;
    for (i = 0; i <= divisions; i++) {
        int date = _range.start + (int)((double)i * (_range.end - _range.start) / divisions); double x = [self xForDate:date];
        NSBezierPath *line = [NSBezierPath bezierPath]; [line moveToPoint:NSMakePoint(x, plot.origin.y)]; [line lineToPoint:NSMakePoint(x, NSMaxY(plot))];
        [grid set]; [line stroke];
        NSString *label = [HBDateFromOrdinal(date) descriptionWithCalendarFormat:_range.end - _range.start > 730 ? @"%m/%Y" : @"%d/%m/%Y"];
        HVText(label, NSMakeRect(MAX(plot.origin.x - 20, MIN(x - 34, bounds.size.width - 72)), 26, 72, 18), text, NO);
    }
    [NSGraphicsContext saveGraphicsState]; [NSBezierPath clipRect:plot];
    [self drawSegmentFrom:_range.start to:MIN(_range.end, [_history today]) forecast:NO dark:dark];
    [self drawSegmentFrom:MAX(_range.start, [_history today]) to:_range.end forecast:YES dark:dark];
    NSBezierPath *zero = [NSBezierPath bezierPath]; [zero moveToPoint:NSMakePoint(plot.origin.x, [self yForBalance:0])];
    [zero lineToPoint:NSMakePoint(NSMaxX(plot), [self yForBalance:0])]; [grid set]; [zero stroke];
    if (_overdraft) {
        double y = [self yForBalance:[_overdraft doubleValue]]; NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(plot.origin.x, y)]; [line lineToPoint:NSMakePoint(NSMaxX(plot), y)];
        HBGraphFloat dash[] = {5, 3}; [line setLineDash:dash count:2 phase:0]; [line setLineWidth:1.5]; [HVRed(dark) set]; [line stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
    if ([_history today] >= _range.start && [_history today] <= _range.end) {
        double x = [self xForDate:[_history today]]; NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(x, plot.origin.y)]; [line lineToPoint:NSMakePoint(x, NSMaxY(plot))];
        HBGraphFloat dash[] = {2, 3}; [line setLineDash:dash count:2 phase:0]; [grid set]; [line stroke];
        HVText(@"Aujourd'hui", NSMakeRect(MAX(plot.origin.x, MIN(x + 4, NSMaxX(plot) - 72)), NSMaxY(plot) + 6, 72, 18), text, NO);
    }
}
- (void)drawRect:(NSRect)rect {
    BOOL dark = HVIsDark();
    if (!_image || dark != _cachedDark) {
        [_image release]; _image = nil; free(_samples); _samples = NULL;
        _image = [[NSImage alloc] initWithSize:[self bounds].size]; _cachedDark = dark;
        [_image lockFocus]; [self drawBase:dark]; [_image unlockFocus];
    }
    [_image drawAtPoint:NSZeroPoint fromRect:[self bounds] operation:NSCompositeCopy fraction:1];
    NSRect plot = [self plotRect];
    if (_dragging) { NSRect selection = NSMakeRect([self xForDate:MIN(_dragStart, _dragDate)], plot.origin.y, fabs([self xForDate:_dragDate] - [self xForDate:_dragStart]), plot.size.height);
        [[HVCurve(dark) colorWithAlphaComponent:0.12] set]; NSRectFill(selection); }
    if (_history && _hoverDate) {
        double x = [self xForDate:_hoverDate], y = [self yForBalance:[[_history balanceAt:_hoverDate] doubleValue]];
        NSBezierPath *line = [NSBezierPath bezierPath]; [line moveToPoint:NSMakePoint(x, plot.origin.y)]; [line lineToPoint:NSMakePoint(x, NSMaxY(plot))];
        [HVCurve(dark) set]; [line stroke]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 3, y - 3, 6, 6)] fill];
        NSString *label = [NSString stringWithFormat:@"%@ | %@ : %@", [HBDateFromOrdinal(_hoverDate) descriptionWithCalendarFormat:@"%d/%m/%Y"],
            _hoverDate > [_history today] ? @"Solde previsionnel" : @"Solde", [_wallet formatAmount:[_history balanceAt:_hoverDate] account:[[_history accounts] objectAtIndex:0]]];
        HVText(label, NSMakeRect(plot.origin.x, 4, plot.size.width, 18), [NSColor controlTextColor], NO);
    }
}
- (void)mouseMoved:(NSEvent *)event {
    if (!_history) return; NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    int date = NSPointInRect(point, [self plotRect]) ? [self dateAtPoint:point] : 0;
    if (date != _hoverDate) { _hoverDate = date; [self setNeedsDisplay:YES]; }
}
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    if (!_history || !NSPointInRect(point, [self plotRect])) return;
    [[self window] makeFirstResponder:self]; _dragging = YES; _hoverDate = _dragStart = _dragDate = [self dateAtPoint:point]; [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)event { if (_dragging) { _hoverDate = _dragDate = [self dateAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]; [self setNeedsDisplay:YES]; } }
- (void)mouseUp:(NSEvent *)event {
    if (!_dragging) return; _dragging = NO;
    if (_dragStart != _dragDate) [_delegate balanceView:self selectFrom:MIN(_dragStart, _dragDate) to:MAX(_dragStart, _dragDate)];
    [self setNeedsDisplay:YES];
}
- (void)scrollWheel:(NSEvent *)event {
    if (!_history || [event deltaY] == 0) return;
    if ([event modifierFlags] & NSAlternateKeyMask) [_delegate balanceView:self zoom:[event deltaY] > 0 ? 0.8 : 1.25];
    else [_delegate balanceView:self shift:[event deltaY] > 0 ? -1 : 1];
}
- (void)dealloc { [_history release]; [_wallet release]; [_overdraft release]; [_image release]; free(_samples); [super dealloc]; }
@end
