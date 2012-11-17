//
//  AppController.m
//  MetaZ
//
//  Created by Brian Olsen on 06/09/09.
//  Copyright 2009 Maven-Group. All rights reserved.
//

#import "AppController.h"
#import "UndoTableView.h"
#import "PosterView.h"
#import "MZMetaSearcher.h"
#import "MZWriteQueue.h"
#import "FakeSearchResult.h"
#import "SearchMeta.h"
#import "FilesTableView.h"
#import "Resources.h"
#import "MZMetaDataDocument.h"
#import "MZScriptingAdditions.h"

#define MaxShortDescription 256

@interface AppController ()

- (void)updateSearchMenu;
- (void)registerUndoName:(NSUndoManager *)manager;

@end


NSArray* MZUTIFilenameExtension(NSArray* utis)
{
    NSMutableArray* ret = [NSMutableArray arrayWithCapacity:utis.count];
    for(NSString* uti in utis)
    {
        NSDictionary* dict = (NSDictionary*)UTTypeCopyDeclaration((CFStringRef)uti);
        //[dict writeToFile:[NSString stringWithFormat:@"/Users/bro/Documents/Maven-Group/MetaZ/%@.plist", uti] atomically:NO];
        NSDictionary* tags = [dict objectForKey:(NSString*)kUTTypeTagSpecificationKey];
        NSArray* extensions = [tags objectForKey:(NSString*)kUTTagClassFilenameExtension];
        [ret addObjectsFromArray:extensions];
        [dict release];
    }
    return ret;
}


NSResponder* findResponder(NSWindow* window) {
    NSResponder* oldResponder =  [window firstResponder];
    if([oldResponder isKindOfClass:[NSTextView class]] && [window fieldEditor:NO forObject:nil] != nil)
    {
        NSResponder* delegate = (NSResponder*)[((NSTextView*)oldResponder) delegate];
        if([delegate isKindOfClass:[NSTextField class]])
            oldResponder = delegate;
    }
    return oldResponder;
}

NSDictionary* findBinding(NSWindow* window) {
    NSResponder* oldResponder = findResponder(window);
    NSDictionary* dict = [oldResponder infoForBinding:NSValueBinding];
    if(dict == nil)
        dict = [oldResponder infoForBinding:NSDataBinding];
    return dict;
}


@implementation AppController
@synthesize window;
@synthesize tabView;
@synthesize episodeFormatter;
@synthesize seasonFormatter;
@synthesize dateFormatter;
@synthesize purchaseDateFormatter;
@synthesize filesSegmentControl;
@synthesize filesController;
@synthesize undoController;
@synthesize resizeController;
@synthesize shortDescription;
@synthesize longDescription;
@synthesize imageView;
@synthesize searchIndicator;
@synthesize searchController;
@synthesize searchField;
@synthesize chapterEditor;
@synthesize remainingInShortDescription;
@synthesize picturesController;
@synthesize updater;
@synthesize loadingIndicator;

#pragma mark - initialization

+ (void)initialize
{
    if(self != [AppController class])
        return;

    NSArray* sendTypes = [NSArray arrayWithObjects:NSTIFFPboardType, nil];
    NSArray* returnTypes = [NSArray arrayWithObjects:NSTIFFPboardType, nil];
    [NSApp registerServicesMenuSendTypes:sendTypes
                    returnTypes:returnTypes];
}

- (id)init
{
    self = [super init];
    if(self)
    {
        remainingInShortDescription = MaxShortDescription;
        activeProfile = [[SearchProfile unknownTypeProfile] retain];
        [activeProfile addObserver:self forKeyPath:@"searchTerms" options:0 context:NULL];
    }
    return self;
}

-(void)awakeFromNib
{   
    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(finishedSearch:)
               name:MZSearchFinishedNotification
             object:nil];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(removedEdit:)
               name:MZMetaEditsDeallocating
             object:nil];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(startedLoading:)
               name:MZMetaLoaderStartedNotification
             object:nil];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(finishedLoading:)
               name:MZMetaLoaderFinishedNotification
             object:nil];

    [[MZPluginController sharedInstance] setDelegate:self];
    [[MZMetaSearcher sharedSearcher] setFakeResult:[FakeSearchResult resultWithController:filesController]];
    [self updateSearchMenu];

    undoManager = [[NSUndoManager alloc] init];

    [seasonFormatter setNilSymbol:@""];
    [episodeFormatter setNilSymbol:@""];
    [dateFormatter setLenient:YES];
    [purchaseDateFormatter setLenient:YES];
    [dateFormatter setDefaultDate:nil];
    [purchaseDateFormatter setDefaultDate:nil];
    
    [window setExcludedFromWindowsMenu:YES];

    [filesController addObserver:self
                      forKeyPath:@"selection.title"
                         options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld|NSKeyValueObservingOptionInitial
                         context:nil];
    [filesController addObserver:self
                      forKeyPath:@"selection.pure.videoType"
                         options:0
                         context:nil];
    [filesController addObserver:self
                      forKeyPath:@"selection.shortDescription"
                         options:0
                         context:nil];
    [updater setSendsSystemProfile:YES];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [activeProfile removeObserver:self forKeyPath:@"searchTerms"];
    [filesController removeObserver:self forKeyPath:@"selection.title"];
    [filesController removeObserver:self forKeyPath:@"selection.pure.videoType"];
    [window release];
    [tabView release];
    [episodeFormatter release];
    [seasonFormatter release];
    [dateFormatter release];
    [purchaseDateFormatter release];
    [filesSegmentControl release];
    [filesController release];
    [resizeController release];
    [undoController release];
    [shortDescription release];
    [longDescription release];
    [undoManager release];
    [imageView release];
    [imageEditController release];
    [prefController release];
    [presetsController release];
    [searchIndicator release];
    [searchController release];
    [searchField release];
    [activeProfile release];
    [chapterEditor release];
    [fileNameEditor release];
    [fileNameStorage release];
    [picturesController release];
    [updater release];
    [super dealloc];
}
#pragma mark - private

- (void)updateSearchMenu
{
    SearchProfile* profile;
    
    id videoType = [filesController protectedValueForKeyPath:@"selection.pure.videoType"];
    MZVideoType vt;
    MZTag* tag = [MZTag tagForIdentifier:MZVideoTypeTagIdent];
    [tag convertObject:videoType toValue:&vt];
    switch (vt) {
        case MZMovieVideoType:
            if([[activeProfile identifier] isEqual:@"movie"])
                profile = [[activeProfile retain] autorelease];
            else
                profile = [SearchProfile movieProfile];
            break;
        case MZTVShowVideoType:
            if([[activeProfile identifier] isEqual:@"tvShow"])
                profile = [[activeProfile retain] autorelease];
            else
                profile = [SearchProfile tvShowProfile];
            break;
        default:
            if([[activeProfile identifier] isEqual:@"unknown"])
                profile = [[activeProfile retain] autorelease];
            else
                profile = [SearchProfile unknownTypeProfile];
            break;
    }
    [activeProfile removeObserver:self forKeyPath:@"searchTerms"];
    [activeProfile release];
    activeProfile = [profile retain];
    [activeProfile setCheckObject:filesController withPrefix:@"selection.pure."];
    [activeProfile addObserver:self forKeyPath:@"searchTerms" options:0 context:NULL];

    NSMenu* menu = [[NSMenu alloc] initWithTitle:
        NSLocalizedString(@"Search terms", @"Search menu title")];
    [menu addItemWithTitle:[menu title] action:nil keyEquivalent:@""];
    NSInteger i = 0;
    for(NSString* tagId in [profile tags])
    {
        if(![tagId isEqual:MZVideoTypeTagIdent])
        {
            MZTag* tag = [MZTag tagForIdentifier:tagId];
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[tag localizedName]
                action:@selector(switchItem:) keyEquivalent:@""];
            [item setTarget:profile];
            [item setTag:i];
            [item setState:NSOnState];
            [item setIndentationLevel:1];
            [menu addItem:item];
            [item release];
        }
        i++;
    }
    id searchCell = [searchField cell];
    [searchCell setSearchMenuTemplate:menu];
    [menu release];
        
    NSString* prefix = @"selection.pure.";
    id mainValue = @"";
    if([profile mainTag])
    {
        mainValue = [filesController protectedValueForKeyPath:
            [prefix stringByAppendingString:[profile mainTag]]];
    
        if(mainValue == nil || mainValue == [NSNull null] || mainValue == NSMultipleValuesMarker ||
            mainValue == NSNoSelectionMarker || mainValue == NSNotApplicableMarker)
        {
            mainValue = @"";
        }
    }
    [searchField setStringValue:mainValue];

    if([[NSUserDefaults standardUserDefaults] boolForKey:@"autoSearch"])
    {
        //[[MZMetaSearcher sharedSearcher] clearResults];
        [self startSearch:searchField];
    }
}

- (void)registerUndoName:(NSUndoManager *)manager
{
    [manager setActionName:NSLocalizedString(@"Apply Search", @"Apply search undo name")];
    [manager registerUndoWithTarget:self 
                           selector:@selector(registerUndoName:)
                             object:manager];
}

#pragma mark - as observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if([keyPath isEqual:@"selection.title"] && object == filesController)
    {
        id value = [object valueForKeyPath:keyPath];
        if(value == NSMultipleValuesMarker ||
           value == NSNotApplicableMarker ||
           value == NSNoSelectionMarker ||
           value == [NSNull null] ||
           value == nil)
        {
            [window setTitle:@"MetaZ"];
        }
        else
        {
            [window setTitle:[NSString stringWithFormat:@"MetaZ - %@", value]];
        }

        if(value == NSNoSelectionMarker)
            [filesSegmentControl setEnabled:NO forSegment:1];
        else
            [filesSegmentControl setEnabled:YES forSegment:1];
    }
    if([keyPath isEqual:@"selection.pure.videoType"] && object == filesController)
    {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateSearchMenu) object:nil];
        [self performSelector:@selector(updateSearchMenu) withObject:nil afterDelay:0.001];
    }
    if([keyPath isEqual:@"selection.shortDescription"] && object == filesController)
    {
        NSInteger newRemain = 0;
        id length = [filesController valueForKeyPath:@"selection.shortDescription.length"];
        if([length respondsToSelector:@selector(integerValue)])
            newRemain = [length integerValue];
        [self willChangeValueForKey:@"remainingInShortDescription"];
        remainingInShortDescription = MaxShortDescription-newRemain;
        [self didChangeValueForKey:@"remainingInShortDescription"];
    }
    if([keyPath isEqual:@"searchTerms"] && object == activeProfile)
        [self startSearch:self];
}


#pragma mark - as MZPluginControllerDelegate

- (id<MetaData>)pluginController:(MZPluginController *)controller
        extraMetaDataForProvider:(id<MZDataProvider>)provider
                          loaded:(MetaLoaded*)loaded
{
    return [[[SearchMeta alloc] initWithProvider:loaded controller:searchController] autorelease];
}


#pragma mark - actions

- (IBAction)showAdvancedTab:(id)sender {
    [window makeKeyAndOrderFront:sender];
    [tabView selectTabViewItemWithIdentifier:@"advanced"];    
}

- (IBAction)showChapterTab:(id)sender {
    [window makeKeyAndOrderFront:sender];
    [tabView selectTabViewItemWithIdentifier:@"chapters"];    
}

- (IBAction)showInfoTab:(id)sender {
    [window makeKeyAndOrderFront:sender];
    [tabView selectTabViewItemWithIdentifier:@"info"];
}

- (IBAction)showSortTab:(id)sender {
    [window makeKeyAndOrderFront:sender];
    [tabView selectTabViewItemWithIdentifier:@"sorting"];
}

- (IBAction)showVideoTab:(id)sender {
    [window makeKeyAndOrderFront:sender];
    [tabView selectTabViewItemWithIdentifier:@"video"];    
}

- (IBAction)startSearch:(id)sender;
{
    NSResponder* oldResponder = findResponder(window);
    if([filesController commitEditing])
    {
        NSResponder* currentResponder =  findResponder(window);
        if(oldResponder != currentResponder)
            [window makeFirstResponder:oldResponder];
    }

    NSString* term = [[searchField stringValue] 
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    NSMutableDictionary* dict = [activeProfile searchTerms:term];
    //[dict setObject:term forKey:[activeProfile mainTag]];
    [searchIndicator startAnimation:searchField];
    [searchController setSortDescriptors:nil];
    searches++;
    MZLoggerInfo(@"Starting search %d", searches);
    [[MZMetaSearcher sharedSearcher] startSearchWithData:dict];
}

- (IBAction)segmentClicked:(id)sender {
    int clickedSegment = [sender selectedSegment];
    int clickedSegmentTag = [[sender cell] tagForSegment:clickedSegment];

    if(clickedSegmentTag == 0)
        [self openDocument:sender];
    else
        [filesController remove:sender];
}

- (IBAction)selectNextFile:(id)sender {
    NSResponder* oldResponder = findResponder(window);
    if([filesController commitEditing])
    {
        NSResponder* currentResponder =  findResponder(window);
        if(oldResponder != currentResponder)
            [window makeFirstResponder:oldResponder];
    }
    [filesController selectNext:sender];
}


- (IBAction)selectPreviousFile:(id)sender {
    NSResponder* oldResponder = findResponder(window);
    if([filesController commitEditing])
    {
        NSResponder* currentResponder =  findResponder(window);
        if(oldResponder != currentResponder)
            [window makeFirstResponder:oldResponder];
    }
    [filesController selectPrevious:sender];
}

- (IBAction)selectNextResult:(id)sender {
    NSResponder* oldResponder = findResponder(window);
    if([filesController commitEditing])
    {
        NSResponder* currentResponder =  findResponder(window);
        if(oldResponder != currentResponder)
            [window makeFirstResponder:oldResponder];
    }
    [searchController selectNext:sender];
}

- (IBAction)selectPreviousResult:(id)sender {
    NSResponder* oldResponder = findResponder(window);
    if([filesController commitEditing])
    {
        NSResponder* currentResponder =  findResponder(window);
        if(oldResponder != currentResponder)
            [window makeFirstResponder:oldResponder];
    }
    [searchController selectPrevious:sender];
}


- (IBAction)revertChanges:(id)sender {
    NSDictionary* dict = findBinding(window);
    if(dict == nil)
    {
        MZLoggerError(@"Could not find binding for revert.");
        return;
    }
    id observed = [dict objectForKey:NSObservedObjectKey];
    NSString* keyPath = [[dict objectForKey:NSObservedKeyPathKey] stringByAppendingString:@"Changed"];
    NSNumber* num = [observed valueForKeyPath:keyPath];
    num = [NSNumber numberWithBool:![num boolValue]];
    [observed setValue:num forKeyPath:keyPath];
}

- (IBAction)searchForImages:(id)sender
{
    NSString* title = [[filesController valueForKeyPath:@"selection.pure.title"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    id videoType = [filesController protectedValueForKeyPath:@"selection.pure.videoType"];
    MZVideoType vt;
    MZTag* tag = [MZTag tagForIdentifier:MZVideoTypeTagIdent];
    [tag convertObject:videoType toValue:&vt];
    
    NSString* query;
    switch (vt) {
        case MZTVShowVideoType:
        {
            NSString* show = [filesController valueForKeyPath:@"selection.pure.tvShow"];
            if([show isKindOfClass:[NSString class]])
            {
                show = [show stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                NSNumber* season = [filesController valueForKeyPath:@"selection.pure.tvSeason"];
                if([season isKindOfClass:[NSNumber class]])
                    query = [NSString stringWithFormat:@"\"%@\" season %d", show, [season integerValue]];
                else
                    query = [NSString stringWithFormat:@"\"%@\"", show];
                break;
            }
        }
        default:
            query = [NSString stringWithFormat:@"\"%@\"", title];
            break;
    }
    
    // Escape even the "reserved" characters for URLs 
    // as defined in http://www.ietf.org/rfc/rfc2396.txt
    CFStringRef encodedValue = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, 
                                                                       (CFStringRef)query,
                                                                       NULL, 
                                                                       (CFStringRef)@";/?:@&=+$,", 
                                                                        kCFStringEncodingUTF8);

    query = (NSString*)encodedValue;
    NSString* str = [NSString stringWithFormat:
        @"http://images.google.com/images?q=%@&gbv=2&svnum=10&safe=active&sa=G&imgsz=small%%7Cmedium%%7Clarge%%7Cxlarge",
        query];
    CFRelease(encodedValue);
    NSURL* url = [NSURL URLWithString:str];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)showImageEditor:(id)sender
{
    if(!imageEditController)
        imageEditController = [[ImageWindowController alloc] initWithImageView:imageView];
    [[NSNotificationCenter defaultCenter] 
                addObserver:self 
                 selector:@selector(imageEditorDidClose:)
                     name:NSWindowWillCloseNotification
                   object:[imageEditController window]];
    [imageEditController showWindow:self];
}

- (IBAction)showPreferences:(id)sender
{
    if(!prefController)
    {
        prefController = [[PreferencesWindowController alloc] init];
        [[NSNotificationCenter defaultCenter] 
                addObserver:self 
                 selector:@selector(preferencesDidClose:)
                     name:NSWindowWillCloseNotification
                   object:[prefController window]];
    }
    [prefController showWindow:self];
}

- (IBAction)openDocument:(id)sender {
    NSArray *fileTypes = [[MZMetaLoader sharedLoader] types];

    NSArray* extensions = MZUTIFilenameExtension(fileTypes);
    for(NSString* ext in extensions)
    {
        MZLoggerDebug(@"Found extention %@", ext);
    }
    
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setAllowsMultipleSelection:YES];
    [oPanel setCanChooseFiles:YES];
    [oPanel setCanChooseDirectories:NO];
    [oPanel beginSheetForDirectory: nil
                              file: nil
                             types: extensions
                    modalForWindow: window
                     modalDelegate: self
                    didEndSelector: @selector(openPanelDidEnd:returnCode:contextInfo:) 
                       contextInfo: nil];
}

- (IBAction)showPresets:(id)sender
{
    if(!presetsController)
    {
        presetsController = [[PresetsWindowController alloc] initWithController:filesController];
        [[NSNotificationCenter defaultCenter] 
                addObserver:self 
                 selector:@selector(presetsDidClose:)
                     name:NSWindowWillCloseNotification
                   object:[presetsController window]];
    }
    if(![[presetsController window] isVisible])
    {
        [[presetsController window] setFrameUsingName:@"presetsPanel"];
        [presetsController showWindow:self];
    }
    else
        [presetsController close];
}

- (IBAction)applySearchEntry:(id)sender
{
    id selection = [searchController valueForKeyPath:@"selection.self"];
    if(![selection isKindOfClass:[MZSearchResult class]])
        return;
    
    NSDictionary* result = [selection values];
    for(NSString* key in [result allKeys])
    {
        id value = [result objectForKey:key];
        if([value isKindOfClass:[MZRemoteData class]])
        {
            if(![value isLoaded])
                return;
        }
    }
    
    id picture = [picturesController valueForKeyPath:@"selection.self"];
    MZLoggerDebug(@"Picture is %@", picture);
    if([picture isKindOfClass:[MZRemoteData class]])
    {
        if(![picture isLoaded])
            return;
    }
    
    
    NSArray* edits = [filesController selectedObjects];
    for(MetaEdits* edit in edits)
    {
        [self registerUndoName:edit.undoManager];
    }

    for(MetaEdits* edit in edits)
    {
        NSArray* providedTags = [edit providedTags];
        for(MZTag* tag in providedTags)
        {
            if(![edit getterChangedForKey:[tag identifier]])
            {
                id value = [result objectForKey:[tag identifier]];
                if([[tag identifier] isEqual:MZChapterNamesTagIdent])
                {
                    if(value)
                    {
                        [chapterEditor setChapterNames:value];
                        [chapterEditor setChanged:[NSNumber numberWithBool:YES]];
                    }
                }
                else if([[tag identifier] isEqual:MZPictureTagIdent])
                {
                    if([picture isKindOfClass:[MZRemoteData class]])
                        picture = [picture data];
                    if(picture)
                        [edit setterValue:picture forKey:[tag identifier]];
                }
                else
                {
                    if([value isKindOfClass:[MZRemoteData class]])
                        value = [value data];
                    if(value)
                        [edit setterValue:value forKey:[tag identifier]];
                }

            }
        }
        [self registerUndoName:edit.undoManager];
    }
}

- (IBAction)showReleaseNotes:(id)sender
{
    NSURL* url = [NSURL URLWithString:@"http://griff.github.com/metaz/release-notes.html"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)showHomepage:(id)sender
{
    NSURL* url = [NSURL URLWithString:@"http://griff.github.com/metaz/"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)showIssues:(id)sender
{
    NSURL* url = [NSURL URLWithString:@"https://github.com/griff/metaz/issues"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)reportIssue:(id)sender
{
    NSURL* url = [NSURL URLWithString:@"https://github.com/griff/metaz/issues/new"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)viewLog:(id)sender
{
    NSFileManager *mgr = [NSFileManager manager];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    for(NSString* dir in paths)
    {
        NSString* path = [[dir 
            stringByAppendingPathComponent:@"Logs"] 
            stringByAppendingPathComponent:@"MetaZ.log"];
                
        if([mgr fileExistsAtPath:path])
        {
            [[NSWorkspace sharedWorkspace]
                       openFile:path
                withApplication:@"Console"
                  andDeactivate:YES];
            return;
        }
    }
}

- (IBAction)sendFeedback:(id)sender
{
}

#pragma mark - user interface validation

- (BOOL)validateUserInterfaceItem:(id < NSValidatedUserInterfaceItem >)anItem {
    SEL action = [anItem action];
    if(action == @selector(applySearchEntry:))
    {
        id selection = [searchController protectedValueForKeyPath:@"selection.self"];
        if(![selection isKindOfClass:[MZSearchResult class]])
            return NO;
        
        NSDictionary* values = [selection values];
        for(NSString* key in [values allKeys])
        {
            id value = [values objectForKey:key];
            if([value isKindOfClass:[MZRemoteData class]])
            {
                if(![value isLoaded])
                    return NO;
            }
        }
        if(presetsController && [[presetsController window] isKeyWindow])
            return NO;
        return YES;
    }
    if(action == @selector(selectNextFile:))
        return [filesController canSelectNext];
    if(action == @selector(selectPreviousFile:))
        return [filesController canSelectPrevious];
    if(action == @selector(revertChanges:))
    {
        NSDictionary* dict = findBinding(window);
        if([[filesController selectedObjects] count] >= 1 && dict != nil)
        {
            id observed = [dict objectForKey:NSObservedObjectKey];
            NSString* keyPath = [dict objectForKey:NSObservedKeyPathKey];
            BOOL changed = [[observed valueForKeyPath:[keyPath stringByAppendingString:@"Changed"]] boolValue];
            NSMenuItem* item = (NSMenuItem*)anItem;
            if(changed)
                [item setTitle:NSLocalizedString(@"Revert Changes", @"Revert changes menu item")];
            else
                [item setTitle:NSLocalizedString(@"Apply Changes", @"Apply changes menu item")];
            return YES;
        }
        else 
            return NO;
    }
    if(action == @selector(showImageEditor:))
    {
        id value = [filesController protectedValueForKeyPath:@"selection.picture"];
        return [value isKindOfClass:[NSData class]] || [value isKindOfClass:[MZRemoteData class]];
    }
    if(action == @selector(searchForImages:))
    {
        id videoType = [filesController protectedValueForKeyPath:@"selection.pure.videoType"];
        MZVideoType vt;
        MZTag* tag = [MZTag tagForIdentifier:MZVideoTypeTagIdent];
        [tag convertObject:videoType toValue:&vt];
        if(vt == MZTVShowVideoType)
        {
            id show = [filesController valueForKeyPath:@"selection.pure.tvShow"];
            if([show isKindOfClass:[NSString class]])
                return YES;
        }
        id title = [filesController valueForKeyPath:@"selection.pure.title"];
        return [title isKindOfClass:[NSString class]];
    }
    return YES;
}

#pragma mark - callbacks

- (void)finishedSearch:(NSNotification *)note
{
    searches--;
    MZLoggerDebug(@"Finished search %d", searches);
    if(searches <= 0)
        [searchIndicator stopAnimation:self];
}

- (void)startedLoading:(NSNotification *)note
{
    if(loadings == 0)
        [loadingIndicator setDoubleValue:0.0];
    loadings++;
    [loadingIndicator setMaxValue:loadings];
    [loadingIndicator setHidden:NO];
}

- (void)finishedLoading:(NSNotification *)note
{
    [loadingIndicator incrementBy:1.0];
    loadings--;
    if(loadings == 0)
        [loadingIndicator setHidden:YES];
}

- (void)imageEditorDidClose:(NSNotification *)note
{
    [[NSNotificationCenter defaultCenter] 
           removeObserver:self 
                     name:NSWindowWillCloseNotification
                   object:[note object]];
    [imageEditController release];
    imageEditController = nil;
}

- (void)preferencesDidClose:(NSNotification *)note
{
    [[NSNotificationCenter defaultCenter] 
           removeObserver:self 
                     name:NSWindowWillCloseNotification
                   object:[note object]];
    [prefController release];
    prefController = nil;
}

- (void)presetsDidClose:(NSNotification *)note
{
    [[note object] saveFrameUsingName:@"presetsPanel"];
}

- (void)removedEdit:(NSNotification *)note
{
    MetaEdits* other = [note object];
    [other.undoManager removeAllActionsWithTarget:self];
}

- (void)openPanelDidEnd:(NSOpenPanel *)oPanel returnCode:(int)returnCode  contextInfo:(void  *)contextInfo {
    if (returnCode == NSOKButton)
    {
        if([filesController commitEditing])
        {
            NSEnumerator* e = [[oPanel URLs] objectEnumerator];
            NSURL* url = nil;
            NSMutableArray* filenames = [NSMutableArray array];
            while ((url = [e nextObject]))
            {
                [filenames addObject: [url path]];
            }
            [[MZMetaLoader sharedLoader] loadFromFiles: filenames];
        }
    }
}

- (void)queueStatusChanged:(GTMKeyValueChangeNotification *)notification
{
    if([[MZWriteQueue sharedQueue] status] == QueueStopped)
    {
        [[notification object] gtm_removeObserver:self forKeyPath:[notification keyPath] selector:_cmd];
        [NSApp replyToApplicationShouldTerminate:YES];
    }
}

#pragma mark - as window delegate

- (NSSize)windowWillResize:(NSWindow *)aWindow toSize:(NSSize)proposedFrameSize {
    [[NSNotificationCenter defaultCenter] postNotificationName:MZNSWindowWillResizeNotification object:aWindow];
    return [resizeController windowWillResize:aWindow toSize:proposedFrameSize];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)aWindow {
    NSResponder* responder = [aWindow firstResponder];
    if(responder == shortDescription || 
        responder == longDescription ||
        [responder isKindOfClass:[UndoTableView class]] ||
        [responder isKindOfClass:[PosterView class]])
    {
        NSUndoManager * man = [undoController undoManager];
        if(man != nil)
            return man;
    }
    return undoManager;
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client
{
    if([client isKindOfClass:[FilesTableView class]])
    {
        if(!fileNameEditor)
        {
            fileNameStorage = [[MZFileNameTextStorage alloc] init];
            
            NSLayoutManager *layoutManager;
            layoutManager = [[NSLayoutManager alloc] init];
            [fileNameStorage addLayoutManager:layoutManager];
            [layoutManager release];

            NSTextContainer *container;
            container = [[NSTextContainer alloc]
                    initWithContainerSize:NSZeroSize];
            [layoutManager addTextContainer:container];
            [container release];

            fileNameEditor = [[NSTextView alloc]
                    initWithFrame:NSZeroRect textContainer:container];
            [fileNameEditor setFieldEditor:YES];
            [fileNameEditor setRichText:NO];
        }
        return fileNameEditor;
    }
    return nil;
}

#pragma mark - as text delegate
- (void)textDidChange:(NSNotification *)aNotification
{
    [self willChangeValueForKey:@"remainingInShortDescription"];
    remainingInShortDescription = MaxShortDescription-[[shortDescription string] length];
    [self didChangeValueForKey:@"remainingInShortDescription"];
}

#pragma mark - as application delegate

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    [window makeKeyAndOrderFront:sender];
    return [[MZMetaLoader sharedLoader] loadFromFile:filename];
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    [window makeKeyAndOrderFront:sender];
    if([[MZMetaLoader sharedLoader] loadFromFiles:filenames])
        [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    else
        [sender replyToOpenOrPrint:NSApplicationDelegateReplyCancel];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
    [NSApp setServicesProvider:self];
    
    // Load scriptability early to allow sdef open handler to override default AppKit handler.
    [NSScriptSuiteRegistry sharedScriptSuiteRegistry]; 
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    BOOL changed = NO;
    NSArray* arr = [[MZMetaLoader sharedLoader] files];
    int count = [arr count];
    for(int i=0; i<count && !changed; i++)
    {
        MetaEdits* edit = [arr objectAtIndex:i];
        changed = [edit changed];
    }
    
    int result = NSAlertDefaultReturn;
    if(changed)
    {
        result = NSRunCriticalAlertPanel(
            NSLocalizedString(@"Are you sure you want to quit MetaZ?", nil),
            @"%@",
            NSLocalizedString(@"Quit", nil), NSLocalizedString(@"Don't Quit", nil), nil,
            NSLocalizedString(@"You have files loaded with unsaved changes. Do you want to quit anyway?", nil));
    }
    else if([[MZWriteQueue sharedQueue] status] == QueueRunning)
    {
        result = NSRunCriticalAlertPanel(
            NSLocalizedString(@"Are you sure you want to quit MetaZ?", nil),
            NSLocalizedString(@"If you quit MetaZ your current jobs will be reloaded into your queue at next launch. Do you want to quit anyway?", nil),
            NSLocalizedString(@"Quit", nil), NSLocalizedString(@"Don't Quit", nil), nil, @"A movie" );
        
    }
    
    // Warn if items still in the queue
    else if([[[MZWriteQueue sharedQueue] pendingItems] count] > 0)
    {
        result = NSRunCriticalAlertPanel(
            NSLocalizedString(@"Are you sure you want to quit MetaZ?", nil),
            @"%@",
            NSLocalizedString(@"Quit", nil), NSLocalizedString(@"Don't Quit", nil), nil,
            NSLocalizedString(@"There are pending jobs in your queue. Do you want to quit anyway?",nil));
    }
    
    if( result == NSAlertDefaultReturn )
    {
        if([[MZWriteQueue sharedQueue] status] == QueueRunning || [[MZWriteQueue sharedQueue] status] == QueueStopping)
        {
            [[MZWriteQueue sharedQueue] gtm_addObserver:self forKeyPath:@"status" selector:@selector(queueStatusChanged:) userInfo:nil options:0];
            [[MZWriteQueue sharedQueue] stop];
            return NSTerminateLater;
        }
        return NSTerminateNow;
    }
    return NSTerminateCancel;
}

-(void)doiTunesMetadata:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
    NSDictionary* prop = [pboard propertyListForType:iTunesMetadataPboardType];
    if(!prop)
        prop = [pboard propertyListForType:iTunesPboardType]; 

    if(prop)
    {
        NSMutableArray* names = [NSMutableArray array];
        NSMutableArray* dataDicts = [NSMutableArray array];
        NSDictionary* tracks = [prop objectForKey:@"Tracks"];
        for(id track in [tracks allValues])
        {
            NSURL* location = [NSURL URLWithString:[track objectForKey:@"Location"]];
            [names addObject:[location path]];

            NSString* persistentId = [track objectForKey:@"Persistent ID"];
            NSDictionary* data = [NSDictionary dictionaryWithObject:persistentId forKey:MZiTunesPersistentIDTagIdent];
            [dataDicts addObject:data];
        }
        [[MZMetaLoader sharedLoader] loadFromFiles:names withMetaData:dataDicts];
    }
}

-(void)doiTunes:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
    NSString* path = [[NSBundle mainBundle] pathForResource:@"Return iTunes selected" ofType:@"scpt"];
    NSURL* url = [NSURL fileURLWithPath:path];
    NSDictionary* errDict = nil;
    NSAppleScript* script = [[[NSAppleScript alloc] initWithContentsOfURL:url error:&errDict] autorelease];
    if(errDict)
    {
        NSError* err = [NSError errorWithAppleScriptError:errDict];
        if(error)
            *error =  [err localizedDescription];
        GTMLoggerError(@"Error loading script %d %d", path, [err localizedDescription]);
        return;
    }
    if(script)
    {
        NSAppleEventDescriptor* ret = [script executeAndReturnError:&errDict];
        if(!ret)
        {
            NSError* err = [NSError errorWithAppleScriptError:errDict];
            if(error)
                *error = [err localizedDescription];
            GTMLoggerError(@"Error running script %d %d", path, [err localizedDescription]);
        }
        else
        {
            id obj = [ret objectValue];
            if([obj isKindOfClass:[NSArray class]])
            {
                NSMutableArray* names = [NSMutableArray array];
                NSMutableArray* dataDicts = nil;
                for(id o in obj)
                {
                    if([o isKindOfClass:[NSString class]])
                    {
                        [names addObject:o];
                    }
                    else if([o isKindOfClass:[NSDictionary class]])
                    {
                        [names addObject:[o objectForKey:@"mylocation"]];
                        if(!dataDicts)
                            dataDicts = [NSMutableArray array];
                        [dataDicts addObject:[NSDictionary dictionaryWithObject:[o objectForKey:@"myid"] forKey:MZiTunesPersistentIDTagIdent]];
                    }
                    else
                    {
                        NSString* err = [NSString stringWithFormat:@"Unsupported return type %@", o];
                        if(error)
                            *error = err;
                        else
                        GTMLoggerError(@"Selection array: %@", err);
                        return;
                    }
                }
                [[MZMetaLoader sharedLoader] loadFromFiles:names withMetaData:dataDicts];
            }
            else if([obj isKindOfClass:[NSString class]])
                [[MZMetaLoader sharedLoader] loadFromFile:obj];
            else if([obj isKindOfClass:[NSDictionary class]])
                [[MZMetaLoader sharedLoader] loadFromFile:[obj objectForKey:@"mylocation"]
                                             withMetaData:[NSDictionary dictionaryWithObject:[obj objectForKey:@"myid"]
                                                                                      forKey:MZiTunesPersistentIDTagIdent]];
            else {
                NSString* err = [NSString stringWithFormat:@"Unsupported return type %@", obj];
                if(error)
                    *error = err;
                else
                GTMLoggerError(@"Selection: %@", err);
            }
        }
    }
}

@end
