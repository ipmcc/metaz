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
    return [super init];
}

-(void)dealloc {
    [filesBox release];
    [searchBox release];
    [tabView release];
    [splitView release];
    [super dealloc];
}

#pragma mark - as window delegate

#define FIRST_SUBVIEW  filesBox
#define SECOND_SUBVIEW tabView
#define THIRD_SUBVIEW  searchBox 

#define FIRST_SUBVIEW_WIDTH  ((id)FIRST_SUBVIEW  == (id)searchBox ? SEARCHBOX_WIDTH : ((id)FIRST_SUBVIEW  == (id)tabView ? TABVIEW_WIDTH : FILESBOX_WIDTH))
#define SECOND_SUBVIEW_WIDTH ((id)SECOND_SUBVIEW == (id)searchBox ? SEARCHBOX_WIDTH : ((id)SECOND_SUBVIEW == (id)tabView ? TABVIEW_WIDTH : FILESBOX_WIDTH))
#define THIRD_SUBVIEW_WIDTH  ((id)THIRD_SUBVIEW  == (id)searchBox ? SEARCHBOX_WIDTH : ((id)THIRD_SUBVIEW  == (id)tabView ? TABVIEW_WIDTH : FILESBOX_WIDTH))

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize {
    CGFloat divider = [splitView dividerThickness];
    CGFloat minwidth = [[splitView window] frame].size.width - [splitView frame].size.width;
    minwidth += SECOND_SUBVIEW_WIDTH+2*divider;
    if(![splitView isSubviewCollapsed:THIRD_SUBVIEW])
        minwidth += THIRD_SUBVIEW_WIDTH;
    if(![splitView isSubviewCollapsed:FIRST_SUBVIEW])
        minwidth += FIRST_SUBVIEW_WIDTH;
    if(minwidth> proposedFrameSize.width)
        proposedFrameSize.width = minwidth;
    return proposedFrameSize;
}

#pragma mark - as splitView delegate

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSSize newSize = [sender frame].size;
    if(![sender isEqual:splitView])
    {
        [sender adjustSubviews];
        return;
    }

    CGFloat widths[3]; 
    widths[0] = [FIRST_SUBVIEW frame].size.width;
    widths[1] = [SECOND_SUBVIEW frame].size.width;
    widths[2] = [THIRD_SUBVIEW frame].size.width;
    CGFloat mins[3]; 
    mins[0] = FIRST_SUBVIEW_WIDTH;
    mins[1] = SECOND_SUBVIEW_WIDTH;
    mins[2] = THIRD_SUBVIEW_WIDTH;
    int amounts[3];
    amounts[0] = [splitView isSubviewCollapsed:FIRST_SUBVIEW] ? 0 : 1;
    amounts[1] = 1;
    amounts[2] = [splitView isSubviewCollapsed:THIRD_SUBVIEW] ? 0 : 1;

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
    if(![splitView isSubviewCollapsed:FIRST_SUBVIEW]) newWidth+=widths[0];
    newWidth+=widths[1];
    if(![splitView isSubviewCollapsed:THIRD_SUBVIEW]) newWidth+=widths[2];
    if(newWidth != newSize.width)
        MZLoggerDebug(@"Bad sum");
    
    NSRect rect = [FIRST_SUBVIEW frame];
    rect.origin.x = 0;
    rect.origin.y = 0;
    rect.size.width = widths[0];
    rect.size.height = newSize.height;
    [FIRST_SUBVIEW setFrame:rect];
    [FIRST_SUBVIEW setNeedsDisplay:YES];
    
    rect = [SECOND_SUBVIEW frame];
    if([splitView isSubviewCollapsed:FIRST_SUBVIEW])
        rect.origin.x = divider;
    else
        rect.origin.x = widths[0] + divider;
    rect.origin.y = 0;
    rect.size.width = widths[1];
    rect.size.height = newSize.height;
    [SECOND_SUBVIEW setFrame:rect];
    [SECOND_SUBVIEW setNeedsDisplay:YES];

    rect = [THIRD_SUBVIEW frame];
    if([splitView isSubviewCollapsed:FIRST_SUBVIEW])
        rect.origin.x = widths[1] + 2*divider;
    else
        rect.origin.x = widths[0] + widths[1] + 2*divider;
    rect.origin.y = 0;
    rect.size.width = widths[2];
    rect.size.height = newSize.height;
    [THIRD_SUBVIEW setFrame:rect];
    [THIRD_SUBVIEW setNeedsDisplay:YES];
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset {
    if(![sender isEqual:splitView])
    {
        return 30;
    }
    if ([[sender subviews] objectAtIndex: offset] == FIRST_SUBVIEW)
        return FIRST_SUBVIEW_WIDTH;
    if ([[sender subviews] objectAtIndex: offset] == SECOND_SUBVIEW)
    {
        CGFloat ret = SECOND_SUBVIEW_WIDTH+[sender dividerThickness];
        if(![sender isSubviewCollapsed:FIRST_SUBVIEW])
        {
            CGFloat widthF = [FIRST_SUBVIEW frame].size.width;
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
    if ([[sender subviews] objectAtIndex: offset] == SECOND_SUBVIEW)
    {
        return splitW - THIRD_SUBVIEW_WIDTH;
    }
    if ([[sender subviews] objectAtIndex: offset] == FIRST_SUBVIEW)
    {
        CGFloat ret = splitW - (SECOND_SUBVIEW_WIDTH+2*[sender dividerThickness]);
        if(![sender isSubviewCollapsed:THIRD_SUBVIEW])
            ret -= [THIRD_SUBVIEW frame].size.width;
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
    if(dividerIndex==0 && [FIRST_SUBVIEW isEqual:subview])
    {
        if([sender isSubviewCollapsed:FIRST_SUBVIEW]) // Are we uncolapsing FIRST_SUBVIEW
        {
            CGFloat width = [FIRST_SUBVIEW frame].size.width;
            CGFloat widthT = [SECOND_SUBVIEW frame].size.width;
            if(widthT-width < SECOND_SUBVIEW_WIDTH) // We need to adjust divider 1 if proposed width of SECOND_SUBVIEW is to small
            {
                CGFloat widthS = SECOND_SUBVIEW_WIDTH+width+divider;
                CGFloat maxPr = [self splitView:sender constrainMaxCoordinate:[sender maxPossiblePositionOfDividerAtIndex:1] ofSubviewAt:1];
                if(widthS>maxPr) // If proposed position for divider 1 is larger than allowed max, hide THIRD_SUBVIEW
                {
                    [THIRD_SUBVIEW setHidden:YES];
                    [sender adjustSubviews];
                    CGFloat widthSplit = [sender frame].size.width;
                    if(widthS > widthSplit) // If proposed width for FIRST_SUBVIEW leaves no room for min width of SECOND_SUBVIEW
                        width -= (widthS-widthSplit); // Reduce proposed width so that SECOND_SUBVIEW is exactly min width
                }
                else
                    [sender setPosition:widthS ofDividerAtIndex:1];
            }
            if(width<FIRST_SUBVIEW_WIDTH) // If proposed width of FIRST_SUBVIEW is smaller than min do nothing
            {
                return YES;
            }
            [sender setPosition:width ofDividerAtIndex:0];
            [sender adjustSubviews];
            return NO;
        }
        return YES;
    }
    else if([THIRD_SUBVIEW isEqual:subview])
    {
        if([sender isSubviewCollapsed:THIRD_SUBVIEW]) // Are we uncolapsing THIRD_SUBVIEW
        {
            CGFloat width = [THIRD_SUBVIEW frame].size.width;
            CGFloat widthT = [SECOND_SUBVIEW frame].size.width;
            if(widthT-width < SECOND_SUBVIEW_WIDTH) // We need to adjust divider 0 if proposed width of SECOND_SUBVIEW is to small
            {
                CGFloat widthSplit = [sender frame].size.width;
                CGFloat widthS = widthSplit-width-divider-SECOND_SUBVIEW_WIDTH;
                CGFloat minPr = [self splitView:sender constrainMinCoordinate:[sender minPossiblePositionOfDividerAtIndex:0] ofSubviewAt:0];
                if(widthS < minPr) // If proposed position for divider 0 is smaller than allowed min, hide FIRST_SUBVIEW
                {
                    [FIRST_SUBVIEW setHidden:YES];
                    [sender adjustSubviews];
                    if(widthS < 0) // If proposed width for THIRD_SUBVIEW leaves no room for min width of SECOND_SUBVIEW
                        width += widthS; // Reduce proposed width so that SECOND_SUBVIEW is exactly min width
                }
                else
                    [sender setPosition:widthS ofDividerAtIndex:0];
            }
            if(width < THIRD_SUBVIEW_WIDTH) // If proposed width of THIRD_SUBVIEW is smaller than min do nothing
                return YES;

            [sender setPosition:width ofDividerAtIndex:1];
            [sender adjustSubviews];
            return NO;
        }
        return YES;
    }
    return NO;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview {
    return ![sender isEqual:splitView] || [FIRST_SUBVIEW isEqual:subview] || [THIRD_SUBVIEW isEqual:subview];
}

@end
