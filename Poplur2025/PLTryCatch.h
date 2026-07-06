#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Objective-C exceptions into a Swift-catchable result.
/// GLTFSceneKit can raise NSException while decoding malformed GLB data, which
/// Swift's do/try/catch cannot intercept directly.
@interface PLTryCatch : NSObject

+ (BOOL)runCatchingException:(void (^)(void))block error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
