#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NCMQuality) {
    NCMQualityStandard = 0,  // 128kbps
    NCMQualityHigher = 1,    // 192kbps
    NCMQualityExhigh = 2,    // 320kbps
    NCMQualityLossless = 3   // FLAC
};

@interface NCMUnlockAPI : NSObject

+ (instancetype)sharedInstance;

/// 获取歌曲免费 URL
/// @param songId 歌曲 ID
/// @param completion 完成回调 (免费URL, 音质描述)
- (void)getSongUrl:(NSString *)songId completion:(void (^)(NSString * _Nullable url, NSString * _Nullable quality))completion;

/// 获取当前音质设置
@property (nonatomic, assign) NCMQuality audioQuality;

@end

NS_ASSUME_NONNULL_END
