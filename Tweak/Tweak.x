#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "NCMUnlockAPI.h"
#import "SettingsHelper.h"

// Helper: 显示 Toast
static void showToastMessage(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil 
                                                                       message:message 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        [rootVC presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    });
}

// 存储待处理的歌曲ID
static NSMutableDictionary *pendingSongRequests = [NSMutableDictionary new];

// Hook NSURLSession - 拦截所有请求
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSString *urlString = request.URL.absoluteString;
    
    // 记录所有网易云请求（调试用）
    if ([urlString containsString:@"music.163.com"] || [urlString containsString:@"netease"]) {
        NSLog(@"[NCM-Unlock] Request: %@", urlString);
    }
    
    // 拦截 eapi 歌曲请求
    if ([urlString containsString:@"eapi/song/enhance/player/url"] || 
        [urlString containsString:@"song/enhance/player/url/v1"]) {
        
        NSLog(@"[NCM-Unlock] Found song URL request: %@", urlString);
        showToastMessage(@"[NCM-Unlock] 拦截到歌曲URL请求");
        
        // 包装 completionHandler
        void (^newHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (completionHandler) {
                completionHandler(data, response, error);
            }
            
            // 响应是加密的，我们需要在解密后处理
            // 通过通知来触发后续处理
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showToastMessage(@"[NCM-Unlock] 收到歌曲URL响应（加密）");
            });
        };
        
        return %orig(request, newHandler);
    }
    
    return %orig;
}

%end

// Hook JSON 解析 - 监听解密后的数据
%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;
    
    // 检查是否是歌曲URL响应
    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)result;
        
        // 检查是否包含歌曲URL相关字段
        if (dict[@"data"] && [dict[@"data"] isKindOfClass:[NSArray class]]) {
            NSArray *dataArray = dict[@"data"];
            if (dataArray.count > 0) {
                NSDictionary *firstItem = dataArray[0];
                if (firstItem[@"url"] || firstItem[@"id"]) {
                    NSLog(@"[NCM-Unlock] Found song data: %@", dict);
                    showToastMessage([NSString stringWithFormat:@"[NCM-Unlock] 解析到歌曲数据: id=%@", firstItem[@"id"]]);
                    
                    // 检查是否需要替换
                    NSNumber *code = firstItem[@"code"];
                    NSString *url = firstItem[@"url"];
                    
                    if ([code integerValue] != 200 || !url || url.length == 0) {
                        showToastMessage(@"[NCM-Unlock] 歌曲需要VIP，尝试替换...");
                        
                        // 获取歌曲ID
                        NSString *songId = [NSString stringWithFormat:@"%@", firstItem[@"id"]];
                        
                        // 使用解锁API获取免费URL
                        [[NCMUnlockAPI sharedInstance] getSongUrl:songId completion:^(NSString *freeUrl, NSString *quality) {
                            if (freeUrl) {
                                showToastMessage([NSString stringWithFormat:@"[NCM-Unlock] 获取到免费URL: %@", quality]);
                                // 注意：这里无法直接修改已返回的数据
                                // 需要在更底层进行替换
                            } else {
                                showToastMessage(@"[NCM-Unlock] 未找到免费URL");
                            }
                        }];
                    }
                }
            }
        }
    }
    
    return result;
}

%end

// 初始化
%ctor {
    %init;
    
    NSLog(@"[NCM-Unlock] Module loaded successfully");
    showToastMessage(@"[NCM-Unlock] 模块已加载");
    
    // 初始化设置
    [SettingsHelper sharedInstance];
}
