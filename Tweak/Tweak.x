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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    });
}

// Hook NSURLSession 拦截网络请求
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    
    NSString *urlString = request.URL.absoluteString;
    
    // 检查是否是 VIP 歌曲 URL 请求
    if ([urlString containsString:@"song/enhance/player/url"] || 
        [urlString containsString:@"song/enhance/player/url/v1"]) {
        
        NSLog(@"[NCM-Unlock] Intercepting song URL request: %@", urlString);
        
        // 创建新的 completion handler 来替换响应
        void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }
            
            // 解析原始响应
            NSError *jsonError;
            NSMutableDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
            
            if (jsonError || !jsonResponse) {
                if (completionHandler) {
                    completionHandler(data, response, error);
                }
                return;
            }
            
            // 检查是否需要替换 URL
            NSArray *songs = jsonResponse[@"data"];
            if ([songs isKindOfClass:[NSArray class]] && songs.count > 0) {
                NSMutableDictionary *songData = [songs[0] mutableCopy];
                NSNumber *code = songData[@"code"];
                NSString *originalUrl = songData[@"url"];
                
                // 如果 code != 200 或 url 为空，说明需要 VIP 权限
                if ([code integerValue] != 200 || !originalUrl || [originalUrl isEqualToString:@""]) {
                    NSLog(@"[NCM-Unlock] Song requires VIP, attempting to get free URL");
                    
                    // 获取歌曲 ID
                    NSString *songId = [NSString stringWithFormat:@"%@", songData[@"id"]];
                    
                    // 使用解锁 API 获取免费 URL
                    [[NCMUnlockAPI sharedInstance] getSongUrl:songId completion:^(NSString *freeUrl, NSString *quality) {
                        if (freeUrl) {
                            // 替换 URL
                            songData[@"url"] = freeUrl;
                            songData[@"code"] = @200;
                            songData[@"br"] = @320000; // 320kbps
                            songData[@"type"] = @"mp3";
                            
                            NSMutableArray *newSongs = [NSMutableArray arrayWithArray:songs];
                            newSongs[0] = songData;
                            jsonResponse[@"data"] = newSongs;
                            
                            // 重新序列化
                            NSData *newData = [NSJSONSerialization dataWithJSONObject:jsonResponse options:0 error:nil];
                            
                            // 显示提示
                            if ([SettingsHelper sharedInstance].showToast) {
                                showToastMessage([NSString stringWithFormat:@"已替换为免费音源 (%@)", quality]);
                            }
                            
                            if (completionHandler) {
                                completionHandler(newData, response, nil);
                            }
                        } else {
                            if (completionHandler) {
                                completionHandler(data, response, error);
                            }
                        }
                    }];
                    return;
                }
            }
            
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        
        return %orig(request, newCompletionHandler);
    }
    
    return %orig;
}

%end

// 初始化
%ctor {
    %init;
    
    NSLog(@"[NCM-Unlock] Module loaded successfully");
    
    // 初始化设置
    [SettingsHelper sharedInstance];
    
    // 测试 Toast - 延迟2秒显示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showToastMessage(@"[NCM-Unlock] 模块已加载");
    });
}
