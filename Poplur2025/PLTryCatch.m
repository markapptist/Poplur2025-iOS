#import "PLTryCatch.h"

@implementation PLTryCatch

+ (BOOL)runCatchingException:(void (^)(void))block error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLTryCatch"
                                          code:-1
                                      userInfo:@{
                                          NSLocalizedDescriptionKey: exception.reason ?: @"Unknown exception",
                                          @"exceptionName": exception.name
                                      }];
        }
        return NO;
    }
}

@end
