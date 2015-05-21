#import "BLNull.h"


@implementation BLNull

static BLNull *singleton;

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		singleton = [[BLNull alloc] init];
	}
}

+ (id)null
{
	return singleton;
}

- (id)init
{
	NSAssert(singleton == nil, @"Must use singleton via [YapNull null]");
	
	#ifdef NS_BLOCK_ASSERTIONS
	if (singleton != nil) return nil;
	#endif
	
	self = [super init];
	return self;
}

@end
