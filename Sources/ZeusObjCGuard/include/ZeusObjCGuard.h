#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns nil, or "name: reason" of the Objective-C exception it raised.
/// Some Apple frameworks (AVFAudio's connect/setFormat, error -10868) report a bad device or format
/// by raising an exception, which Swift cannot catch and which would end the process.
/// Use only around a single framework call whose failure leaves nothing half-done that matters.
FOUNDATION_EXPORT NSString *_Nullable ZeusCatchObjCException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
