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
    return tabView;
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
        [splitView setSubviews: [NSArray array]];

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

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize {
    
    if(![sender isEqual:splitView])
    {
        [sender adjustSubviews];
        return;
    }
    
    const CGFloat mins[] = { [self leftSubviewWidth], [self middleSubviewWidth], [self rightSubviewWidth] };
    const CGFloat dividerThickness = [sender dividerThickness];

    NSArray *subviews = [sender subviews];
    
	CGFloat delta = [sender bounds].size.width - [searchBox frame].size.width - [tabView frame].size.width -
                    [filesBox frame].size.width - 2.0 * dividerThickness;
	
    for(NSUInteger i = 0; i < 3; ++i)
    {
		NSView* view = [[sender subviews] objectAtIndex:i];
		NSSize size = NSMakeSize([view frame].size.width, [sender bounds].size.height);
		
        if (delta > 0 || size.width + delta >= mins[i])
        {
            size.width += delta;
            delta = 0;
        }
        else if (delta < 0)
        {
            delta += size.width - mins[i];
            size.width = mins[i];
        }
		
		[view setFrameSize: size];
	}
		
	CGFloat offset = 0;
	for (NSView *subview in subviews)
	{
		NSRect viewFrame = [subview frame];
		[subview setFrameOrigin:NSMakePoint(offset, viewFrame.origin.y)];
        [subview setNeedsDisplay: YES];

		offset += viewFrame.size.width + dividerThickness;
	}
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset {
    
    if (sender != splitView)
    {
        proposedMin = 30;
    }
    else
    {
        const CGFloat mins[] = { [self leftSubviewWidth], [self middleSubviewWidth], [self rightSubviewWidth] };
        proposedMin = CGRectGetMinX([[[sender subviews] objectAtIndex: offset] frame]) + mins[offset];
    }

    return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset {
    
    if (sender != splitView)
    {
        proposedMax -= 30;
    }
    else
    {
        const CGFloat mins[] = { [self leftSubviewWidth], [self middleSubviewWidth], [self rightSubviewWidth] };
        NSView *thisView = [[sender subviews] objectAtIndex:offset];
        NSView *nextView = [[sender subviews] objectAtIndex:offset + 1];
        proposedMax = CGRectGetMaxX([thisView frame]) + [nextView frame].size.width - mins[offset+1];
    }

    return proposedMax;
}

- (BOOL)splitView:(NSSplitView *)sender shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex {
    
    if(sender == splitView && [self middleSubview] == subview)
    {
        return NO;
    }
    
    return YES;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview {

    return sender != splitView || [self leftSubview] == subview || [self rightSubview] == subview;
}

@end
