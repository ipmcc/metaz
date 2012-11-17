#import "ResizeController.h"

#define SEARCHBOX_WIDTH 100.0
#define TABVIEW_WIDTH 363.0
#define FILESBOX_WIDTH 150.0

@implementation ResizeController
@synthesize filesBox;
@synthesize searchBox;
@synthesize tabView;
@synthesize splitView;

#pragma mark - initialization

- (id)init
{
    if ((self = [super init]))
    {
        // Read once at init time... changing this at runtime would likely be disastrous.
        searchBoxFirst = [[NSUserDefaults standardUserDefaults] boolForKey: @"searchBoxFirst"];
    }
    return self;
}

-(void)dealloc {
    [filesBox release];
    [searchBox release];
    [tabView release];
    [splitView release];
    [super dealloc];
}

- (NSBox*)leftSubview
{
    return searchBoxFirst ? searchBox : filesBox;
}

- (NSTabView*)middleSubview
{
    return [self tabView];
}

- (NSBox*)rightSubview
{
    return searchBoxFirst ? filesBox : searchBox;
}

- (CGFloat)leftSubviewWidth
{
    return searchBoxFirst ? SEARCHBOX_WIDTH : FILESBOX_WIDTH;
}

- (CGFloat)middleSubviewWidth
{
    return TABVIEW_WIDTH;
}

- (CGFloat)rightSubviewWidth
{
    return searchBoxFirst ? FILESBOX_WIDTH : SEARCHBOX_WIDTH;
}

- (void)awakeFromNib
{    
    NSArray* correctOrder = [NSArray arrayWithObjects: [self leftSubview], [self middleSubview], [self rightSubview], nil];
    if (![correctOrder isEqualToArray: [splitView subviews]])
    {
        // remove them...
        [splitView setSubviews: nil];

        // swap frames
        CGRect temp = [filesBox frame];
        [filesBox setFrame: [searchBox frame]];
        [searchBox setFrame: temp];
        
        // put them back right
        [splitView setSubviews: correctOrder];
    }
}

#pragma mark - as window delegate

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize {
    
    const CGFloat minSplitViewWidth = [self leftSubviewWidth] + [self middleSubviewWidth] + [self rightSubviewWidth] + 2 * [splitView dividerThickness];
    const CGFloat margin = CGRectGetMinX([splitView frame]);
    
    proposedFrameSize.width = MAX(proposedFrameSize.width, minSplitViewWidth + margin * 2.0);

    return proposedFrameSize;
}

#pragma mark - as splitView delegate

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
    if(![sender isEqual:splitView])
    {
        [sender adjustSubviews];
        return;
    }
    
    const CGFloat mins[] = { [self leftSubviewWidth], [self middleSubviewWidth], [self rightSubviewWidth] };
    
    NSArray *subviews = [sender subviews];
    
	CGFloat delta = [sender bounds].size.width - oldSize.width;
	
    for(NSUInteger i = 0; i < 3; ++i)
    {
		NSView* view = [[sender subviews] objectAtIndex:i];
		NSSize size = [view frame].size;
		CGFloat minLengthValue = mins[i];
		
        size.height = sender.bounds.size.height;
        if (delta > 0 || size.width + delta >= mins[i])
        {
            size.width += delta;
            delta = 0;
        }
        else if (delta < 0)
        {
            delta += size.width - mins[i];
            size.width = minLengthValue;
        }
		
		[view setFrameSize: size];
	}
	
	
	CGFloat offset = 0;
	CGFloat dividerThickness = [sender dividerThickness];
	for (NSView *subview in subviews)
	{
		NSRect viewFrame = subview.frame;
		NSPoint viewOrigin = viewFrame.origin;
		viewOrigin.x = offset;
		[subview setFrameOrigin:viewOrigin];
        [subview setNeedsDisplay: YES];

		offset += viewFrame.size.width + dividerThickness;
	}
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
    if (sender == splitView)
    {
        const CGFloat mins[] = { [self leftSubviewWidth], [self middleSubviewWidth], [self rightSubviewWidth] };
        proposedMin = CGRectGetMinX([[[sender subviews] objectAtIndex: offset] frame]) + mins[offset];
    }
    else
    {
        proposedMin = 30;
    }
    
    return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
    if (sender == splitView)
    {
        const CGFloat mins[] = { [self leftSubviewWidth], [self middleSubviewWidth], [self rightSubviewWidth] };
        NSView *thisView = [[sender subviews] objectAtIndex:offset];
        NSView *nextView = [[sender subviews] objectAtIndex:offset + 1];
        proposedMax = CGRectGetMaxX([thisView frame]) + [nextView frame].size.width - mins[offset+1];
    }
    else
    {
        proposedMax -= 30;
    }
    
    return proposedMax;
}

- (BOOL)splitView:(NSSplitView *)sender shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex
{
    if(sender == splitView && [self middleSubview] == subview)
    {
        return NO;
    }
    
    return YES;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
    return sender != splitView || [self leftSubview] == subview || [self rightSubview] == subview;
}

@end

#if 0

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSSize newSize = [sender frame].size;
    if(![sender isEqual:splitView])
    {
        [sender adjustSubviews];
        return;
    }
    
    CGFloat widths[3];
    widths[0] = [searchBox frame].size.width;
    widths[1] = [tabView frame].size.width;
    widths[2] = [filesBox frame].size.width;
    CGFloat mins[3];
    mins[0] = SEARCHBOX_WIDTH;
    mins[1] = TABVIEW_WIDTH;
    mins[2] = FILESBOX_WIDTH;
    int amounts[3];
    amounts[0] = [splitView isSubviewCollapsed:searchBox] ? 0 : 1;
    amounts[1] = 1;
    amounts[2] = [splitView isSubviewCollapsed:filesBox] ? 0 : 1;
    
    CGFloat divider = [splitView dividerThickness];
    CGFloat minWidth = 2*divider;
    for(int i=0; i<3; i++) if(amounts[i] > 0) minWidth+=mins[i];
        
        if(newSize.width<minWidth)
        {
            [splitView adjustSubviews];
            return;
        }
    
    CGFloat oldWidth = 2*divider;
    for(int i=0; i<3; i++) if(amounts[i] > 0) oldWidth+=widths[i];
        //CGFloat amount = oldWidth - newSize.width;
        
        CGFloat w = newSize.width-2*divider;
        
        int count = 0;
        for(int i=0; i<3; i++) count+=amounts[i];
            CGFloat step = floor(w/count);
            for(int i=0; i<3; i++) {
                if(amounts[i]>0)
                {
                    widths[i] = amounts[i]*step;
                    if(widths[i]<mins[i])
                    {
                        widths[i] = mins[i];
                        w -= mins[i];
                        count -= amounts[i];
                        amounts[i] = 0;
                        if(count>0)
                            step = floor(w/count);
                        i=-1;
                    }
                }
            }
    for(int i=0; i<3; i++) if(amounts[i]>0) w-=widths[i];
        
        if(count==0)
            MZLoggerDebug(@"Bad Count");
            
            if(w>3.0)
                MZLoggerDebug(@"More width");
                
                int idx=0;
                while(w>0)
                {
                    for(; idx<3 && amounts[idx]==0; idx = (idx+1) % count);
                    widths[idx] += 1;
                    w -= 1;
                }
    
    if(w>0)
        MZLoggerDebug(@"More width");
        
        CGFloat newWidth = 2*divider;
        if(![splitView isSubviewCollapsed:searchBox]) newWidth+=widths[0];
            newWidth+=widths[1];
            if(![splitView isSubviewCollapsed:filesBox]) newWidth+=widths[2];
                if(newWidth != newSize.width)
                    MZLoggerDebug(@"Bad sum");
                    
                    NSRect rect = [searchBox frame];
                    rect.origin.x = 0;
                    rect.origin.y = 0;
                    rect.size.width = widths[0];
                    rect.size.height = newSize.height;
                    [searchBox setFrame:rect];
    [searchBox setNeedsDisplay:YES];
    
    rect = [tabView frame];
    if([splitView isSubviewCollapsed:searchBox])
        rect.origin.x = divider;
        else
            rect.origin.x = widths[0] + divider;
            rect.origin.y = 0;
            rect.size.width = widths[1];
            rect.size.height = newSize.height;
            [tabView setFrame:rect];
    [tabView setNeedsDisplay:YES];
    
    rect = [filesBox frame];
    if([splitView isSubviewCollapsed:searchBox])
        rect.origin.x = widths[1] + 2*divider;
        else
            rect.origin.x = widths[0] + widths[1] + 2*divider;
            rect.origin.y = 0;
            rect.size.width = widths[2];
            rect.size.height = newSize.height;
            [filesBox setFrame:rect];
    [filesBox setNeedsDisplay:YES];
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset {
    if(![sender isEqual:splitView])
    {
        return 30;
    }
    if(offset==0)
        return SEARCHBOX_WIDTH;
    if(offset==1)
    {
        CGFloat ret = TABVIEW_WIDTH+[sender dividerThickness];
        if(![sender isSubviewCollapsed:searchBox])
        {
            CGFloat widthF = [searchBox frame].size.width;
            ret += widthF;
        }
        return ret;
    }
    return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset {
    if(![sender isEqual:splitView])
    {
        return proposedMax-30;
    }
    
    CGFloat splitW = [sender frame].size.width;
    if(offset==1)
    {
        return splitW - FILESBOX_WIDTH;
    }
    if(offset==0)
    {
        CGFloat ret = splitW - (TABVIEW_WIDTH+2*[sender dividerThickness]);
        if(![sender isSubviewCollapsed:filesBox])
            ret -= [filesBox frame].size.width;
        return ret;
    }
    return proposedMax;
}

- (BOOL)splitView:(NSSplitView *)sender shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex {
    if(![sender isEqual:splitView])
    {
        return YES;
    }
    
    CGFloat divider = [sender dividerThickness];
    if(dividerIndex==0 && [searchBox isEqual:subview])
    {
        if([sender isSubviewCollapsed:searchBox]) // Are we uncolapsing searchBox
        {
            CGFloat width = [searchBox frame].size.width;
            CGFloat widthT = [tabView frame].size.width;
            if(widthT-width < TABVIEW_WIDTH) // We need to adjust divider 1 if proposed width of tabView is to small
            {
                CGFloat widthS = TABVIEW_WIDTH+width+divider;
                CGFloat maxPr = [self splitView:sender constrainMaxCoordinate:[sender maxPossiblePositionOfDividerAtIndex:1] ofSubviewAt:1];
                if(widthS>maxPr) // If proposed position for divider 1 is larger than allowed max, hide filesBox
                {
                    [filesBox setHidden:YES];
                    [sender adjustSubviews];
                    CGFloat widthSplit = [sender frame].size.width;
                    if(widthS > widthSplit) // If proposed width for searchBox leaves no room for min width of tabView
                        width -= (widthS-widthSplit); // Reduce proposed width so that tabView is exactly min width
                }
                else
                    [sender setPosition:widthS ofDividerAtIndex:1];
            }
            if(width<SEARCHBOX_WIDTH) // If proposed width of searchBox is smaller than min do nothing
            {
                return YES;
            }
            [sender setPosition:width ofDividerAtIndex:0];
            [sender adjustSubviews];
            return NO;
        }
        return YES;
    }
    else if([filesBox isEqual:subview])
    {
        if([sender isSubviewCollapsed:filesBox]) // Are we uncolapsing filesBox
        {
            CGFloat width = [filesBox frame].size.width;
            CGFloat widthT = [tabView frame].size.width;
            if(widthT-width < TABVIEW_WIDTH) // We need to adjust divider 0 if proposed width of tabView is to small
            {
                CGFloat widthSplit = [sender frame].size.width;
                CGFloat widthS = widthSplit-width-divider-TABVIEW_WIDTH;
                CGFloat minPr = [self splitView:sender constrainMinCoordinate:[sender minPossiblePositionOfDividerAtIndex:0] ofSubviewAt:0];
                if(widthS < minPr) // If proposed position for divider 0 is smaller than allowed min, hide searchBox
                {
                    [searchBox setHidden:YES];
                    [sender adjustSubviews];
                    if(widthS < 0) // If proposed width for filesBox leaves no room for min width of tabView
                        width += widthS; // Reduce proposed width so that tabView is exactly min width
                }
                else
                    [sender setPosition:widthS ofDividerAtIndex:0];
            }
            if(width < FILESBOX_WIDTH) // If proposed width of filesBox is smaller than min do nothing
                return YES;
            
            [sender setPosition:width ofDividerAtIndex:1];
            [sender adjustSubviews];
            return NO;
        }
        return YES;
    }
    return NO;
}

#endif