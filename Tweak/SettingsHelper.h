#import <Foundation/Foundation.h>
#import "NCMUnlockAPI.h"

NS_ASSUME_NONNULL_BEGIN

@interface SettingsHelper : NSObject

+ (instancetype)sharedInstance;

/// 音质设置
@property (nonatomic, assign) NCMQuality audioQuality;

/// 是否显示 Toast 提示
@property (nonatomic, assign) BOOL showToast;

/// 获取当前音质名称
@property (nonatomic, readonly) NSString *qualityName;

@end

NS_ASSUME_NONNULL_END
