#import "ZeusObjCGuard.h"

NSString *ZeusCatchObjCException(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @"no reason"];
    }
}
