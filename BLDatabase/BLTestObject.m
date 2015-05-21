//
//  BLTestObject.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/29.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLTestObject.h"
#import "FMDatabase.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation BLTestObject

+ (void)load
{
//    Method m1;
//    Method m2;
//    
//    m1 = class_getInstanceMethod(self, @selector(swizzleAge));
//    m2 = class_getInstanceMethod(self, @selector(age));
//    
//    class_addMethod(self, @selector(oldAge), method_getImplementation(m2), method_getTypeEncoding(m2));
//    
//    method_exchangeImplementations(m1, m2);
//    
//    m1 = class_getInstanceMethod(self, @selector(swizzleSetAge:));
//    m2 = class_getInstanceMethod(self, @selector(setAge:));
//    
//    method_exchangeImplementations(m1, m2);
}


//- (id)swizzleAge
//{
//    //self.navigationController.transitionInProgress = NO;
//    //[self safeViewDidAppear:animated];
//    int i = 2;
//    objc_msgSend();
//    NSLog(@"%@", NSStringFromSelector(_cmd));
//    return [self performSelector:@selector(oldAge)];
//    
//}

- (void)swizzleSetAge:(void *)para
{
    [self performSelector:@selector(swizzleSetAge:) withObject:(__bridge id)para];
}

+ (void)openedDB:(FMDatabase *)db schemaVersion:(int)schemaVersion upgradeSchemaVersion:(int)upgradeSchemaVersion
{
    while (schemaVersion < upgradeSchemaVersion) {
        if (schemaVersion == 0) {
            if (! [db executeUpdate:
                   @"CREATE TABLE BLTestObject ("
                   @"    uuid         TEXT NOT NULL PRIMARY KEY,"
                   @"    groupName    TEXT,"
                   @"    name         TEXT,"
                   @"    age          INTEGER"
                   @");"
                   ]) {
                NSLog(@"create table error");
            }
        }
        
        schemaVersion++;
    }
}

//- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
//{
//    NSString *sel = NSStringFromSelector(selector);
//    if ([sel rangeOfString:@"set"].location == 0) {
//        return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
//    } else {
//        return [NSMethodSignature signatureWithObjCTypes:"@@:"];
//    }
//}
//
//- (void)forwardInvocation:(NSInvocation *)invocation
//{
////    NSString *key = NSStringFromSelector([invocation selector]);
////    if ([key rangeOfString:@"set"].location == 0) {
////        key = [[key substringWithRange:NSMakeRange(3, [key length]-4)] lowercaseString];
////        NSString *obj;
////        [invocation getArgument:&obj atIndex:2];
////        [data setObject:obj forKey:key];
////    } else {
////        NSString *obj = [data objectForKey:key];
////        [invocation setReturnValue:&obj];
////    }
//}

@end
