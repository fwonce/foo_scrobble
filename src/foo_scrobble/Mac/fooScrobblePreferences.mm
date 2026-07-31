#import "fooScrobblePreferences.h"
#import "stdafx.h"

#import "Authorizer.h"
#import "ScrobbleConfig.h"

using namespace foo_scrobble;

@interface fooScrobblePreferences ()
@property (nonatomic) NSButton* enableScrobblingCheckbox;
@property (nonatomic) NSButton* enableNowPlayingCheckbox;
@property (nonatomic) NSButton* submitOnlyInLibraryCheckbox;
@property (nonatomic) NSButton* submitDynamicSourcesCheckbox;
@property (nonatomic) NSTextField* statusLabel;
@property (nonatomic) NSButton* authButton;
@property (nonatomic) std::shared_ptr<Authorizer> currentAuth;
@end

@implementation fooScrobblePreferences

- (instancetype)init {
    self = [super init];
    return self;
}

- (void)loadView {
    NSView* root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 260)];

    CGFloat y = 230;
    CGFloat leftPad = 20;
    CGFloat rowHeight = 28;

    // Enable scrobbling
    self.enableScrobblingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftPad, y, 400, 20)];
    [self.enableScrobblingCheckbox setButtonType:NSButtonTypeSwitch];
    self.enableScrobblingCheckbox.title = @"Enable scrobbling";
    [self.enableScrobblingCheckbox setTarget:self];
    [self.enableScrobblingCheckbox setAction:@selector(onEnableScrobbling:)];
    [root addSubview:self.enableScrobblingCheckbox];
    y -= rowHeight;

    // Now playing
    self.enableNowPlayingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftPad, y, 400, 20)];
    [self.enableNowPlayingCheckbox setButtonType:NSButtonTypeSwitch];
    self.enableNowPlayingCheckbox.title = @"Send \"Now Playing\" notifications";
    [self.enableNowPlayingCheckbox setTarget:self];
    [self.enableNowPlayingCheckbox setAction:@selector(onEnableNowPlaying:)];
    [root addSubview:self.enableNowPlayingCheckbox];
    y -= rowHeight;

    // Only in library
    self.submitOnlyInLibraryCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftPad, y, 400, 20)];
    [self.submitOnlyInLibraryCheckbox setButtonType:NSButtonTypeSwitch];
    self.submitOnlyInLibraryCheckbox.title = @"Only scrobble tracks in media library";
    [self.submitOnlyInLibraryCheckbox setTarget:self];
    [self.submitOnlyInLibraryCheckbox setAction:@selector(onSubmitOnlyInLibrary:)];
    [root addSubview:self.submitOnlyInLibraryCheckbox];
    y -= rowHeight;

    // Dynamic sources
    self.submitDynamicSourcesCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftPad, y, 400, 20)];
    [self.submitDynamicSourcesCheckbox setButtonType:NSButtonTypeSwitch];
    self.submitDynamicSourcesCheckbox.title = @"Scrobble dynamic sources (streams/radio)";
    [self.submitDynamicSourcesCheckbox setTarget:self];
    [self.submitDynamicSourcesCheckbox setAction:@selector(onSubmitDynamicSources:)];
    [root addSubview:self.submitDynamicSourcesCheckbox];
    y -= rowHeight + 10;

    // Separator
    NSView* sep = [[NSView alloc] initWithFrame:NSMakeRect(leftPad, y + 10, 400, 1)];
    // Use a box for separator
    y -= 10;

    // Status label
    self.statusLabel = [NSTextField labelWithString:@"Not authorized"];
    self.statusLabel.frame = NSMakeRect(leftPad, y - 10, 400, 20);
    [root addSubview:self.statusLabel];
    y -= 30;

    // Auth button
    self.authButton = [NSButton buttonWithTitle:@"Authorize with Last.fm" target:self action:@selector(onAuthButton:)];
    self.authButton.frame = NSMakeRect(leftPad, y - 5, 200, 32);
    [root addSubview:self.authButton];

    [self loadSettings];
    self.view = root;
}

- (void)loadSettings {
    self.enableScrobblingCheckbox.state = Config.GetEnableScrobbling() ? NSControlStateValueOn : NSControlStateValueOff;
    self.enableNowPlayingCheckbox.state = Config.GetEnableNowPlaying() ? NSControlStateValueOn : NSControlStateValueOff;
    self.submitOnlyInLibraryCheckbox.state = Config.GetSubmitOnlyInLibrary() ? NSControlStateValueOn : NSControlStateValueOff;
    self.submitDynamicSourcesCheckbox.state = Config.GetSubmitDynamicSources() ? NSControlStateValueOn : NSControlStateValueOff;

    auto sessionKey = Config.GetSessionKey();
    if (sessionKey.get_length() > 0) {
        self.statusLabel.stringValue = @"Authorized ✓";
        self.authButton.title = @"Deauthorize";
    } else {
        self.statusLabel.stringValue = @"Not authorized";
        self.authButton.title = @"Authorize with Last.fm";
    }
}

- (IBAction)onEnableScrobbling:(NSButton*)sender {
    Config.SetEnableScrobbling(sender.state == NSControlStateValueOn);
}

- (IBAction)onEnableNowPlaying:(NSButton*)sender {
    Config.SetEnableNowPlaying(sender.state == NSControlStateValueOn);
}

- (IBAction)onSubmitOnlyInLibrary:(NSButton*)sender {
    Config.SetSubmitOnlyInLibrary(sender.state == NSControlStateValueOn);
}

- (IBAction)onSubmitDynamicSources:(NSButton*)sender {
    Config.SetSubmitDynamicSources(sender.state == NSControlStateValueOn);
}

- (IBAction)onAuthButton:(NSButton*)sender {
    auto sessionKey = Config.GetSessionKey();
    if (sessionKey.get_length() > 0) {
        // Already authorized → deauthorize
        Config.ResetSessionKey();
        ScrobbleConfigNotify::NotifyChanged();
        self.currentAuth = nil;
        [self loadSettings];
    } else if (self.currentAuth && self.authButton.tag == 1) {
        // We have a pending auth → complete it
        self.statusLabel.stringValue = @"Completing authorization...";
        self.authButton.enabled = NO;

        auto auth = self.currentAuth;
        auth->CompleteAuth([self, auth](Authorizer::State state) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (state == Authorizer::State::Authorized) {
                    Config.SetSessionKey(auth->GetSessionKey());
                    ScrobbleConfigNotify::NotifyChanged();
                    self.currentAuth = nil;
                    [self loadSettings];
                } else {
                    self.statusLabel.stringValue = @"Authorization failed";
                    self.authButton.enabled = YES;
                    self.currentAuth = nil;
                }
            });
        });
    } else {
        // Start new authorization
        self.statusLabel.stringValue = @"Requesting authorization...";
        self.authButton.enabled = NO;
        self.authButton.tag = 0;

        auto auth = std::make_shared<Authorizer>(sessionKey);
        self.currentAuth = auth;

        auth->RequestAuth([self, auth](Authorizer::State state) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (state == Authorizer::State::WaitingForApproval) {
                    self.statusLabel.stringValue = @"Please authorize in browser, then click Complete";
                    self.authButton.title = @"Complete Authorization";
                    self.authButton.enabled = YES;
                    self.authButton.tag = 1;
                } else if (state == Authorizer::State::Authorized) {
                    Config.SetSessionKey(auth->GetSessionKey());
                    ScrobbleConfigNotify::NotifyChanged();
                    self.currentAuth = nil;
                    [self loadSettings];
                } else {
                    self.statusLabel.stringValue = @"Authorization failed";
                    self.authButton.enabled = YES;
                    self.currentAuth = nil;
                }
            });
        });
    }
}

@end

namespace {

class preferences_page_scrobble : public preferences_page_v4 {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([fooScrobblePreferences new]);
    }

    const char* get_name() override { return "Last.fm Scrobbling"; }

    GUID get_guid() override {
        return GUID{0x3a7e9c21, 0x5f8b, 0x4d3a, {0x9c, 0x1e, 0x8f, 0x7d, 0x2b, 0x4a, 0x6c, 0x8e}};
    }

    GUID get_parent_guid() override { return guid_tools; }
};

FB2K_SERVICE_FACTORY(preferences_page_scrobble);

} // anonymous namespace
