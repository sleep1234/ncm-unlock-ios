#import "NCMUnlockAPI.h"

// 稳定音源
static NSString *const kNeteaseSource = @"netease";
static NSString *const kJooxSource = @"joox";
static NSString *const kBilibiliSource = @"bilibili";

// 音质映射
static NSDictionary *qualityMap;

@implementation NCMUnlockAPI {
    NSURLSession *_session;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedInstance {
    static NCMUnlockAPI *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NCMUnlockAPI alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sharedSession];
        _queue = dispatch_queue_create("com.ncm-unlock.api", DISPATCH_QUEUE_SERIAL);
        
        qualityMap = @{
            @(NCMQualityStandard): @"128k",
            @(NCMQualityHigher): @"192k",
            @(NCMQualityExhigh): @"320k",
            @(NCMQualityLossless): @"flac"
        };
    }
    return self;
}

- (void)getSongUrl:(NSString *)songId completion:(void (^)(NSString * _Nullable url, NSString * _Nullable quality))completion {
    if (!songId || songId.length == 0) {
        completion(nil, nil);
        return;
    }
    
    dispatch_async(_queue, ^{
        // 尝试多个音源
        [self tryNeteaseSource:songId completion:completion];
    });
}

- (void)tryNeteaseSource:(NSString *)songId completion:(void (^)(NSString * _Nullable url, NSString * _Nullable quality))completion {
    // 使用网易云官方 API 获取歌曲 URL
    
    // 构建请求 URL
    NSString *urlString = [NSString stringWithFormat:@"https://music.163.com/api/song/enhance/player/url?id=%@&ids=[%@]&br=%@", 
                          songId, songId, [self getBitrate]];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // 设置请求头
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://music.163.com" forHTTPHeaderField:@"Referer"];
    [request setValue:@"__csrf=" forHTTPHeaderField:@"Cookie"];
    
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[NCM-Unlock] Netease source failed: %@", error.localizedDescription);
            [self tryJooxSource:songId completion:completion];
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            [self tryJooxSource:songId completion:completion];
            return;
        }
        
        NSArray *songs = json[@"data"];
        if ([songs isKindOfClass:[NSArray class]] && songs.count > 0) {
            NSDictionary *songData = songs[0];
            NSString *url = songData[@"url"];
            NSNumber *code = songData[@"code"];
            
            if ([code integerValue] == 200 && url && ![url isEqualToString:@""]) {
                NSLog(@"[NCM-Unlock] Got URL from Netease: %@", url);
                completion(url, @"网易云");
                return;
            }
        }
        
        [self tryJooxSource:songId completion:completion];
    }];
    
    [task resume];
}

- (void)tryJooxSource:(NSString *)songId completion:(void (^)(NSString * _Nullable url, NSString * _Nullable quality))completion {
    // Joox 音源（需要代理服务器）
    // 这里可以接入 UnblockNeteaseMusic 的 API
    NSLog(@"[NCM-Unlock] Trying Joox source for song: %@", songId);
    
    // 暂时跳过，直接尝试 Bilibili
    [self tryBilibiliSource:songId completion:completion];
}

- (void)tryBilibiliSource:(NSString *)songId completion:(void (^)(NSString * _Nullable url, NSString * _Nullable quality))completion {
    // Bilibili 音源
    NSLog(@"[NCM-Unlock] Trying Bilibili source for song: %@", songId);
    
    // 搜索歌曲
    NSString *searchUrl = [NSString stringWithFormat:@"https://api.bilibili.com/audio/music-service-c/web/song/info?sid=%@", songId];
    
    NSURL *url = [NSURL URLWithString:searchUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://www.bilibili.com" forHTTPHeaderField:@"Referer"];
    
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, nil);
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            completion(nil, nil);
            return;
        }
        
        NSDictionary *dataDict = json[@"data"];
        if (dataDict) {
            NSString *audioUrl = dataDict[@"play_url"];
            if (audioUrl && ![audioUrl isEqualToString:@""]) {
                NSLog(@"[NCM-Unlock] Got URL from Bilibili: %@", audioUrl);
                completion(audioUrl, @"Bilibili");
                return;
            }
        }
        
        completion(nil, nil);
    }];
    
    [task resume];
}

- (NSString *)getBitrate {
    switch (_audioQuality) {
        case NCMQualityStandard: return @"128000";
        case NCMQualityHigher: return @"192000";
        case NCMQualityExhigh: return @"320000";
        case NCMQualityLossless: return @"999000";
        default: return @"320000";
    }
}

@end
