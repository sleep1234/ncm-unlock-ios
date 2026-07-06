#import "SettingsHelper.h"

static NSString *const kAudioQualityKey = @"NCMUnlock_AudioQuality";
static NSString *const kShowToastKey = @"NCMUnlock_ShowToast";

@implementation SettingsHelper {
    NSUserDefaults *_defaults;
}

+ (instancetype)sharedInstance {
    static SettingsHelper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SettingsHelper alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [NSUserDefaults standardUserDefaults];
        [self loadSettings];
    }
    return self;
}

- (void)loadSettings {
    _audioQuality = [_defaults integerForKey:kAudioQualityKey];
    _showToast = [_defaults boolForKey:kShowToastKey];
    
    // 默认值
    if (!_showToast && ![_defaults objectForKey:kShowToastKey]) {
        _showToast = YES;
    }
}

- (void)setAudioQuality:(NCMQuality)audioQuality {
    _audioQuality = audioQuality;
    [_defaults setInteger:audioQuality forKey:kAudioQualityKey];
    [_defaults synchronize];
    
    // 同步到解锁 API
    [NCMUnlockAPI sharedInstance].audioQuality = audioQuality;
}

- (void)setShowToast:(BOOL)showToast {
    _showToast = showToast;
    [_defaults setBool:showToast forKey:kShowToastKey];
    [_defaults synchronize];
}

- (NSString *)qualityName {
    switch (_audioQuality) {
        case NCMQualityStandard: return @"标准 128kbps";
        case NCMQualityHigher: return @"较高 192kbps";
        case NCMQualityExhigh: return @"极高 320kbps";
        case NCMQualityLossless: return @"无损 FLAC";
        default: return @"极高 320kbps";
    }
}

@end
