//
//  BLBaseDBObject.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLBaseDBObject.h"
#import "BLDatabaseConnection.h"
#import "BLDatabaseConnection+Private.h"
#import "FMDB.h"
#import "FMResultSet.h"
#import "BLDatabaseConfig.h"
#import "BLDatabaseUtil.h"
#import "BLDBChangedObject.h"
#import "BLDBCache.h"
#import "BLDatabase.h"
#import "BLDatabase+Private.h"
#import "BLNull.h"

#import <objc/runtime.h>
#import <objc/message.h>

NSString * const BLDatabaseInsertKey = @"BLDatabaseInsertKey";
NSString * const BLDatabaseUpdateKey = @"BLDatabaseUpdateKey";
NSString * const BLDatabaseDeleteKey = @"BLDatabaseDeleteKey";

NSString * const BLDatabaseChangedNotification = @"BLBaseDBObjectChangedNotification";

static dispatch_queue_t globalQueue = nil;
static NSMutableDictionary *g_database_fieldInfo = NULL;
static NSMutableDictionary *g_propertyName_fieldInfo = nil;
static NSMutableDictionary *g_setterName_fieldInfo = nil;
static NSMutableDictionary *g_getterName_fieldInfo = nil;

@interface BLBaseDBObjectFieldInfo ()
{
@public
    SEL         oldGetter;
    SEL         oldSetter;
}

@property (nonatomic, assign) BOOL isPrimaryKey;
@property (nonatomic, assign) BOOL isIndex;
@property (nonatomic, assign) BOOL isRelationship;
@property (nonatomic, strong) id defaultValue;

@property (nonatomic, copy) NSString *propertyName;
@property (nonatomic, strong) Class relationshipObjectClass;
@property (nonatomic, assign) BLBaseDBObjectFieldType type;
@property (nonatomic, copy) NSString *propertyTypeEncoding;

@end

@interface BLBaseDBObject ()
{
    __weak      NSDictionary *fieldInfoForSetters;
    __weak      NSDictionary *fieldInfoForGetters;
    __weak      NSDictionary *fieldInfoForDatabase;
}

@property (nonatomic, weak) BLDatabaseConnection *connection;

@property (nonatomic, assign) int64_t rowid;
@property (nonatomic, copy) NSString *uniqueId;
@property (nonatomic, assign) BOOL isFault;

@property (nonatomic, assign) BOOL enableFullLoadIfFault;
@property (nonatomic, strong) NSMutableSet *changedFieldNames;
@property (nonatomic, strong) NSMutableSet *preloadFieldNames;

@end

@implementation BLBaseDBObjectFieldInfo

@end

@implementation BLBaseDBObject

#pragma mark - global queue

+ (dispatch_queue_t)globalQueue
{
    static dispatch_once_t once_t;
    dispatch_once(&once_t, ^{
        globalQueue = dispatch_queue_create("com.base_db_object.global", DISPATCH_QUEUE_SERIAL);
    });
    
    return globalQueue;
}

#pragma mark - init

+ (void)initialize
{
    dispatch_sync([self globalQueue], ^{
        Class cls = [self class];
        __unused NSString *className = NSStringFromClass(cls);
        BLLogDebug(@"class Name = %@", className);
        if (g_propertyName_fieldInfo[className]) {
            return ;
        }
        
        if (!g_database_fieldInfo) {
            g_database_fieldInfo = [NSMutableDictionary dictionary];
        }
        if (!g_propertyName_fieldInfo) {
            g_propertyName_fieldInfo = [NSMutableDictionary dictionary];
        }
        if (!g_setterName_fieldInfo) {
            g_setterName_fieldInfo = [NSMutableDictionary dictionary];
        }
        if (!g_getterName_fieldInfo) {
            g_getterName_fieldInfo = [NSMutableDictionary dictionary];
        }
        
        NSMutableDictionary *databaseInfo = [NSMutableDictionary dictionary];
        NSMutableDictionary *propertyNameInfo = [NSMutableDictionary dictionary];
        NSMutableDictionary *getterNameInfo = [NSMutableDictionary dictionary];
        NSMutableDictionary *setterNameInfo = [NSMutableDictionary dictionary];
        
        NSDictionary *defaultValues = [self defaultValues];
        NSArray *indexFieldNames = [self indexFieldNames];
        
        unsigned int outCount, i;
        objc_property_t *properties = class_copyPropertyList(cls, &outCount);
        
        for(i = 0; i < outCount; i++) {
            objc_property_t property = properties[i];
            const char *propName = property_getName(property);
            NSString *propertyName = [NSString stringWithCString:propName
                                                        encoding:[NSString defaultCStringEncoding]];
            if ([[self ignoredFieldNames] containsObject:propertyName]) {
                continue;
            }
            
            char *ivar = property_copyAttributeValue(property, "V");
            if (ivar) {
                //check if ivar has KVC-compliant name
                __autoreleasing NSString *ivarName = @(ivar);
                if ([ivarName isEqualToString:propertyName] || [ivarName isEqualToString:[@"_" stringByAppendingString:propertyName]]) {
                    //no setter, but setValue:forKey: will still work
                    BLLogDebug(@"propertyName = %@", propertyName);
                    
                    BLBaseDBObjectFieldInfo *info = [BLBaseDBObjectFieldInfo new];
                    info.defaultValue = defaultValues[propertyName];
                    info.isIndex  = [indexFieldNames containsObject:propertyName];
                    info.isPrimaryKey = [[self primaryKeyFieldName] isEqualToString:propertyName];
                    info.propertyName = propertyName;
                    
                    Method hookGetter = nil;
                    Method hookSetter = nil;
                    
                    char *typeEncoding = property_copyAttributeValue(property, "T");
                    switch (typeEncoding[0]) {
                        case '@': {
                            static const char arrayPrefix[] = "@\"NSArray<";
                            static const int arrayPrefixLen = sizeof(arrayPrefix) - 1;
                            
                            if (strcmp(typeEncoding, "@\"NSString\"") == 0) {
                                info.type = BLBaseDBObjectFieldTypeText;
                                hookGetter = class_getInstanceMethod(self, @selector(hookGetterForObjcType));
                                hookSetter = class_getInstanceMethod(self, @selector(hookSetterForObjcType:));
                            } else if (strcmp(typeEncoding, "@\"NSDate\"") == 0) {
                                info.type = BLBaseDBObjectFieldTypeDate;
                                hookGetter = class_getInstanceMethod(self, @selector(hookGetterForObjcType));
                                hookSetter = class_getInstanceMethod(self, @selector(hookSetterForObjcType:));
                            } else if (strcmp(typeEncoding, "@\"NSData\"") == 0) {
                                info.type = BLBaseDBObjectFieldTypeBlob;
                                hookGetter = class_getInstanceMethod(self, @selector(hookGetterForObjcType));
                                hookSetter = class_getInstanceMethod(self, @selector(hookSetterForObjcType:));
                            } else if (strcmp(typeEncoding, "@\"NSArray\"") == 0) {
                                // 关系对象id列表
                                info.type = BLBaseDBObjectFieldTypeArray;
                                hookGetter = class_getInstanceMethod(self, @selector(hookGetterForObjcType));
                                hookSetter = class_getInstanceMethod(self, @selector(hookSetterForObjcType:));
                            } else if (strncmp(typeEncoding, arrayPrefix, arrayPrefixLen) == 0) {
                                // get object class from type string - @"NSArray<objectClassName>"
                                // 一对多关系对象
                                info.type = BLBaseDBObjectFieldTypeRelationship;
                                info.isRelationship = YES;
                                NSString *objectClassName = [[NSString alloc] initWithBytes:typeEncoding + arrayPrefixLen
                                                                                     length:strlen(typeEncoding + arrayPrefixLen) - 2 // drop trailing >"
                                                                                   encoding:NSUTF8StringEncoding];
                                
                                Class propertyClass = NSClassFromString(objectClassName);
                                info.relationshipObjectClass = propertyClass;
                                
                                // UT测试不通过，具体原因还没找到
                                Class baseClass = NSClassFromString(NSStringFromClass([BLBaseDBObject class]));
                                if (![propertyClass isSubclassOfClass:baseClass]) {
                                    BLLogError(@"unsupport type for BLDatabase, propertyName is %@", propertyName);
                                    assert(false);
                                }
                                hookGetter = class_getInstanceMethod(self, @selector(hookGetterForRelationships));
                                hookSetter = class_getInstanceMethod(self, @selector(hookSetterForRelationships:));
                            } else if (strlen(typeEncoding) >= 3) {
                                // 一对一关系对象
                                info.type = BLBaseDBObjectFieldTypeRelationship;
                                info.isRelationship = YES;
                                
                                Class propertyClass = nil;
                                char *className = strndup(typeEncoding + 2, strlen(typeEncoding) - 3);
                                __autoreleasing NSString *name = @(className);
                                NSRange range = [name rangeOfString:@"<"];
                                if (range.location != NSNotFound) {
                                    name = [name substringToIndex:range.location];
                                }
                                propertyClass = NSClassFromString(name) ? : [NSObject class];
                                info.relationshipObjectClass = propertyClass;
                                free(className);
                                
                                // UT测试不通过，具体原因还没找到
                                Class baseClass = NSClassFromString(NSStringFromClass([BLBaseDBObject class]));
                                if (![propertyClass isSubclassOfClass:baseClass]) {
                                    BLLogError(@"unsupport type for BLDatabase, propertyName is %@", propertyName);
                                    assert(false);
                                }
                                
                                hookGetter = class_getInstanceMethod(self, @selector(hookGetterForRelationship));
                                hookSetter = class_getInstanceMethod(self, @selector(hookSetterForRelationship:));
                            }
                            
                            break;
                        }
                        case 'c': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForCharType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForCharType:));
                            break;
                        }
                        case 'i': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForIntType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForIntType:));
                            break;
                        }
                        case 's': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForShortType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForShortType:));
                            break;
                        }
                        case 'l': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForLongType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForLongType:));
                            break;
                        }
                        case 'q': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForLongLongType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForLongLongType:));
                            break;
                        }
                        case 'C': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForUnsignedCharType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForUnsignedCharType:));
                            break;
                        }
                        case 'I': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForUnsignedIntType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForUnsignedIntType:));
                            break;
                        }
                        case 'S': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForUnsignedShortType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForUnsignedShortType:));
                            break;
                        }
                        case 'L': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForUnsignedLongType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForUnsignedLongType:));
                            break;
                        }
                        case 'Q': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForUnsignedLongLongType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForUnsignedLongLongType:));
                            break;
                        }
                        case 'f': {
                            info.type = BLBaseDBObjectFieldTypeReal;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForFloatType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForFloatType:));
                            break;
                        }
                        case 'd': {
                            info.type = BLBaseDBObjectFieldTypeReal;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForDoubleType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForDoubleType:));
                            break;
                        }
                        case 'B': {
                            info.type = BLBaseDBObjectFieldTypeInteger;
                            hookGetter = class_getInstanceMethod(self, @selector(hookGetterForBoolType));
                            hookSetter = class_getInstanceMethod(self, @selector(hookSetterForBoolType:));
                            break;
                        }
                        default: {
                            BLLogError(@"unsupport type for BLDatabase, propertyName is %@", propertyName);
                            assert(false);
                            break;
                        }
                    }
                    free(typeEncoding);
                    
                    NSArray *propertyAttributes = [[NSString stringWithCString:property_getAttributes(property) encoding:NSASCIIStringEncoding]componentsSeparatedByString:@","];
                    NSString *getterName = propertyName;
                    NSString *setterName = [@"set" stringByAppendingFormat:@"%@:", [self firstLetterToUpperWithString:propertyName]];
                    for (NSString *attributes in propertyAttributes) {
                        if ([attributes hasPrefix:@"G"]) {
                            getterName = [attributes substringFromIndex:1];
                        } else if ([attributes hasPrefix:@"S"]) {
                            setterName = [attributes substringFromIndex:1];
                        }
                    }
                    
                    if (!info.isRelationship) {
                        [databaseInfo setValue:info forKey:propertyName];
                    }
                    [propertyNameInfo setValue:info forKey:propertyName];
                    [getterNameInfo setValue:info forKey:getterName];
                    [setterNameInfo setValue:info forKey:setterName];
                    
                    if (hookGetter && hookSetter) {
                        NSString *oldGetterName = [@"old" stringByAppendingString:[self firstLetterToUpperWithString:getterName]];
                        Method currentGetter = class_getInstanceMethod(self, NSSelectorFromString(getterName));
                        //Method hookGetter = class_getInstanceMethod(self, @selector(hookGetter));
                        
                        SEL oldGetter = NSSelectorFromString(oldGetterName);
                        info->oldGetter = oldGetter;
                        BOOL success = class_addMethod(self, oldGetter, method_getImplementation(currentGetter), method_getTypeEncoding(currentGetter));
                        if (!success) {
                            BLLogError(@"add method failed");
                            assert(false);
                        }
                        method_setImplementation(currentGetter, method_getImplementation(hookGetter));
                        
                        NSString *oldSetterName = [@"old" stringByAppendingString:[self firstLetterToUpperWithString:setterName]];
                        Method currentSetter = class_getInstanceMethod(self, NSSelectorFromString(setterName));
                        //Method hookSetter = class_getInstanceMethod(self, @selector(hookSetter:));
                        
                        SEL oldSetter = NSSelectorFromString(oldSetterName);
                        info->oldSetter = oldSetter;
                        success = class_addMethod(self, oldSetter, method_getImplementation(currentSetter), method_getTypeEncoding(currentSetter));
                        if (!success) {
                            BLLogError(@"add method failed");
                            assert(false);
                        }
                        method_setImplementation(currentSetter, method_getImplementation(hookSetter));
                    }
                }
            }
            free(ivar);
        }
        free(properties);
        
        // 添加父类的字段
        cls = [self superclass];
        while (cls != [NSObject class]) {
            NSString *className = NSStringFromClass(cls);
            [databaseInfo addEntriesFromDictionary:g_database_fieldInfo[className]];
            cls = [cls superclass];
        }
        
        cls = [self superclass];
        while (cls != [NSObject class]) {
            NSString *className = NSStringFromClass(cls);
            [propertyNameInfo addEntriesFromDictionary:g_propertyName_fieldInfo[className]];
            cls = [cls superclass];
        }
        
        cls = [self superclass];
        while (cls != [NSObject class]) {
            NSString *className = NSStringFromClass(cls);
            [getterNameInfo addEntriesFromDictionary:g_getterName_fieldInfo[className]];
            cls = [cls superclass];
        }
        
        cls = [self superclass];
        while (cls != [NSObject class]) {
            NSString *className = NSStringFromClass(cls);
            [setterNameInfo addEntriesFromDictionary:g_setterName_fieldInfo[className]];
            cls = [cls superclass];
        }
        
        [g_database_fieldInfo setValue:databaseInfo forKey:className];
        [g_propertyName_fieldInfo setValue:propertyNameInfo forKey:className];
        [g_getterName_fieldInfo setValue:getterNameInfo forKey:className];
        [g_setterName_fieldInfo setValue:setterNameInfo forKey:className];
    });
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // not call setter
        _uniqueId = [[NSUUID UUID] UUIDString];
        _changedFieldNames = [NSMutableSet set];
        _preloadFieldNames = [NSMutableSet set];
        _enableFullLoadIfFault = YES;
    }
    
    return self;
}

#pragma mark - public

+ (NSString *)rowidFieldName
{
    return @"rowid";
}

+ (NSString *)uniqueIdFieldName
{
    return @"uniqueId";
}

/*
 - (NSString *)valueForPrimaryKeyFieldName
 {
 NSString *primaryKeyFieldName = [[self class] primaryKeyFieldName];
 if (primaryKeyFieldName) {
 NSString *value = [self valueForKey:primaryKeyFieldName];
 
 return value;
 } else {
 return nil;
 }
 }
 */

- (NSString *)detailDescription
{
    NSMutableString *description = [NSMutableString string];
    NSMutableArray *codeableProperties = [NSMutableArray array];
    Class cls = [self class];
    while (cls != [NSObject class]) {
        [codeableProperties addObjectsFromArray:[cls codeablePropertiesWithClass:cls]];
        cls = [cls superclass];
    }
    
    for (NSString *key in codeableProperties) {
        [description appendFormat:@"%@ = %@\n", key, [self valueForKey:key]];
    }
    
    return description;
}

#pragma mark - codeable Properties

+ (NSArray *)codeablePropertiesWithClass:(Class)cls
{
    NSMutableArray *codeableProperties = [NSMutableArray array];
    
    unsigned int propertyCount;
    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
    for (unsigned int i = 0; i < propertyCount; i++) {
        //get property
        objc_property_t property = properties[i];
        const char *propertyName = property_getName(property);
        NSString *key = @(propertyName);
        char *ivar = property_copyAttributeValue(property, "V");
        if (ivar) {
            //check if ivar has KVC-compliant name
            __autoreleasing NSString *ivarName = @(ivar);
            if ([ivarName isEqualToString:key] || [ivarName isEqualToString:[@"_" stringByAppendingString:key]]) {
                //no setter, but setValue:forKey: will still work
                [codeableProperties addObject:key];
            }
            free(ivar);
        }
    }
    free(properties);
    
    return codeableProperties;
}

#pragma mark - database field names

+ (NSArray *)databaseFieldNames
{
    NSString *className = NSStringFromClass([self class]);
    
    return [g_database_fieldInfo[className] allKeys];
}

+ (BLBaseDBObjectFieldInfo *)infoForFieldName:(NSString *)fieldName
{
    NSString *className = NSStringFromClass([self class]);
    
    return g_database_fieldInfo[className][fieldName];
}

#pragma mark - hook getter

- (id)hookGetterForRelationship
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    if (!fieldInfo.propertyName) {
        BLLogError(@"propertyName is nil for seletorName = %@", seletorName);
        assert(false);
    }
    
    // 找个关系对象对应的id字段名
    NSString *reflectionPropertyName = [[self class] reflectionNameToOneWithPropertyName:fieldInfo.propertyName];
    
    // 通过对象对应的id值去db查找
    __block id object = nil;
    void (^block)(void) = ^(void) {
        object = [fieldInfo.relationshipObjectClass findFirstObjectInConnection:_connection
                                                                       uniqueId:[self valueForKey:reflectionPropertyName]];
    };
    
    if ([_connection isInWriteQueue]) {
        block();
    } else {
        [_connection performReadBlockAndWait:^{
            block();
        }];
    }
    
    return object;
}

- (id)hookGetterForRelationships
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    if (!fieldInfo.propertyName) {
        BLLogError(@"propertyName is nil for selectorName = %@", seletorName);
        assert(false);
    }
    
    // 找个关系对象对应的id字段名
    NSString *reflectionPropertyName = [[self class] reflectionNameToManyWithPropertyName:fieldInfo.propertyName];
    
    NSMutableArray *objects = [NSMutableArray array];
    NSArray *values = [self valueForKey:reflectionPropertyName];
    for (NSString *value in values) {
        // 通过对象对应的id值去db查找
        __block id object = nil;
        void (^block)(void) = ^(void) {
            object = [fieldInfo.relationshipObjectClass findFirstObjectInConnection:_connection
                                                                           uniqueId:value];
        };
        
        if ([_connection isInWriteQueue]) {
            block();
        } else {
            [_connection performReadBlockAndWait:^{
                block();
            }];
        }
        
        if (object) {
            [objects addObject:object];
        }
    }
    
    if ([objects count] > 0) {
        return [objects copy];
    } else {
        return nil;
    }
}

- (void)loadFaultIfNeededWithGetSelectorName:(NSString *)seletorName
                                   fieldInfo:(BLBaseDBObjectFieldInfo *)fieldInfo
{
    if (self.enableFullLoadIfFault && self.isFault) {
        if (!fieldInfo.propertyName) {
            BLLogError(@"propertyName is nil for seletorName = %@", seletorName);
            assert(false);
        }
        
        // fault对象且当前访问的属性不是预加载属性 则从db读取数据
        if (![self.preloadFieldNames containsObject:fieldInfo.propertyName]) {
            [self loadFaultInConnection:_connection];
        }
    }
}

- (id)hookGetterForObjcType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return objc_msgSend(self, fieldInfo->oldGetter);
}

- (int)hookGetterForIntType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((int (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (short)hookGetterForShortType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((short (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (long)hookGetterForLongType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((long (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (long long)hookGetterForLongLongType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((long long (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (char)hookGetterForCharType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((char (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (unsigned char)hookGetterForUnsignedCharType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((unsigned char (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (unsigned int)hookGetterForUnsignedIntType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((unsigned int (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (unsigned short)hookGetterForUnsignedShortType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((unsigned short (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (unsigned long)hookGetterForUnsignedLongType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((unsigned long (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (unsigned long long)hookGetterForUnsignedLongLongType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((unsigned long long (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (float)hookGetterForFloatType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((float (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (double)hookGetterForDoubleType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((double (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

- (bool)hookGetterForBoolType
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForGetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForGetters = g_getterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForGetters[seletorName];
    [self loadFaultIfNeededWithGetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"getter %@", seletorName);
    
    return ((bool (*)(id, SEL))objc_msgSend)(self, fieldInfo->oldGetter);
}

#pragma mark - hook setter

- (void)hookSetterForRelationship:(id)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    if (!fieldInfo.propertyName) {
        BLLogError(@"propertyName is nil for seletorName = %@", seletorName);
        assert(false);
    }
    
    // 找个关系对象对应的id字段名
    NSString *reflectionPropertyName = [[self class] reflectionNameToOneWithPropertyName:fieldInfo.propertyName];
    
    // 给对应的id字段赋值
    [self setValue:[value uniqueId] forKey:reflectionPropertyName];
}

- (void)hookSetterForRelationships:(id)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    if (!fieldInfo.propertyName) {
        BLLogError(@"propertyName is nil for seletorName = %@", seletorName);
        assert(false);
    }
    
    // 找个关系对象对应的id字段名
    NSString *reflectionPropertyName = [[self class] reflectionNameToManyWithPropertyName:fieldInfo.propertyName];
    
    // 给对应的id字段赋值
    NSMutableOrderedSet *values = [NSMutableOrderedSet orderedSet];
    for (id temp in value) {
        [values addObject:[temp uniqueId]];
    }
    
    if ([values count] > 0) {
        [self setValue:[values array] forKey:reflectionPropertyName];
    }
}

- (void)loadFaultIfNeededWithSetSelectorName:(NSString *)seletorName
                                   fieldInfo:(BLBaseDBObjectFieldInfo *)fieldInfo
{
    if (!fieldInfo.propertyName) {
        BLLogError(@"propertyName is nil for seletorName = %@", seletorName);
        assert(false);
    }
    
    if (self.enableFullLoadIfFault && self.isFault) {
        // fault对象且当前访问的属性不是预加载属性 则从db读取数据
        [self loadFaultInConnection:_connection];
    }
    
    if (!self.isFault && self.enableFullLoadIfFault) {
        [_changedFieldNames addObject:fieldInfo.propertyName];
    }
}

- (void)hookSetterForObjcType:(id)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, id) = (void (*)(id, SEL, id)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForIntType:(int)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, int) = (void (*)(id, SEL, int)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForShortType:(short)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, short) = (void (*)(id, SEL, short)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForLongType:(long)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, long) = (void (*)(id, SEL, long)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForLongLongType:(long long)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, long long) = (void (*)(id, SEL, long long)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForCharType:(char)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, char) = (void (*)(id, SEL, char)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForUnsignedCharType:(unsigned char)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, unsigned char) = (void (*)(id, SEL, unsigned char)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForUnsignedIntType:(unsigned int)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, unsigned int) = (void (*)(id, SEL, unsigned int)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForUnsignedShortType:(unsigned short)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, unsigned short) = (void (*)(id, SEL, unsigned short)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForUnsignedLongType:(unsigned long)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, unsigned long) = (void (*)(id, SEL, unsigned long)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForUnsignedLongLongType:(unsigned long long)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, unsigned long long) = (void (*)(id, SEL, unsigned long long)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForFloatType:(float)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, float) = (void (*)(id, SEL, float)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForDoubleType:(double)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, double) = (void (*)(id, SEL, double)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

- (void)hookSetterForBoolType:(BOOL)value
{
    NSString *seletorName = NSStringFromSelector(_cmd);
    if (!self->fieldInfoForSetters) {
        NSString *className = NSStringFromClass([self class]);
        self->fieldInfoForSetters = g_setterName_fieldInfo[className];
    }
    BLBaseDBObjectFieldInfo *fieldInfo = self->fieldInfoForSetters[seletorName];
    [self loadFaultIfNeededWithSetSelectorName:seletorName fieldInfo:fieldInfo];
    
    //BLLogDebug(@"setter %@", seletorName);
    
    // 兼容arm64
    void (*action)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL)) objc_msgSend;
    action(self, fieldInfo->oldSetter, value);
    //objc_msgSend(self, fieldInfo->oldSetter, value);
}

#pragma mark - protocol NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    id copyObject = [[self class] new];
    
    NSMutableArray *codeableProperties = [NSMutableArray array];
    Class cls = [self class];
    while (cls != [NSObject class]) {
        [codeableProperties addObjectsFromArray:[[self class] codeablePropertiesWithClass:cls]];
        cls = [cls superclass];
    }
    
    for (NSString *propertyName in codeableProperties) {
        BLBaseDBObjectFieldInfo *info = g_propertyName_fieldInfo[propertyName];
        if (info.isRelationship) {
            continue;
        }
        
        id value = [self valueForKey:propertyName];
        [copyObject setValue:value forKey:propertyName];
    }
    
    return copyObject;
}

#pragma mark - copy

- (id)copyWithExcludeProperties:(NSArray *)excludeProperties
{
    id copyObject = [[self class] new];
    
    NSMutableArray *codeableProperties = [NSMutableArray array];
    Class cls = [self class];
    while (cls != [NSObject class]) {
        [codeableProperties addObjectsFromArray:[[self class] codeablePropertiesWithClass:cls]];
        cls = [cls superclass];
    }
    
    for (NSString *propertyName in codeableProperties) {
        if ([excludeProperties containsObject:propertyName]) {
            continue;
        } else {
            BLBaseDBObjectFieldInfo *info = g_propertyName_fieldInfo[propertyName];
            if (info.isRelationship) {
                continue;
            }
        }
        
        id value = [self valueForKey:propertyName];
        [copyObject setValue:value forKey:propertyName];
    }
    
    return copyObject;
}

- (id)copyWithIncludeProperties:(NSArray *)includeProperties
{
    id copyObject = [[self class] new];
    
    NSMutableArray *codeableProperties = [NSMutableArray array];
    Class cls = [self class];
    while (cls != [NSObject class]) {
        [codeableProperties addObjectsFromArray:[[self class] codeablePropertiesWithClass:cls]];
        cls = [cls superclass];
    }
    
    for (NSString *propertyName in codeableProperties) {
        if ([includeProperties containsObject:propertyName]) {
            BLBaseDBObjectFieldInfo *info = g_propertyName_fieldInfo[propertyName];
            if (info.isRelationship) {
                continue;
            }
            
            id value = [self valueForKey:propertyName];
            [copyObject setValue:value forKey:propertyName];
        }
    }
    
    return copyObject;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        NSMutableArray *codeableProperties = [NSMutableArray array];
        Class cls = [self class];
        while (cls != [NSObject class]) {
            [codeableProperties addObjectsFromArray:[[self class] codeablePropertiesWithClass:cls]];
            cls = [cls superclass];
        }
        
        for (NSString *propertyName in codeableProperties) {
            BLBaseDBObjectFieldInfo *info = g_propertyName_fieldInfo[propertyName];
            if (info.isRelationship) {
                continue;
            }
            
            id object = [aDecoder decodeObjectForKey:propertyName];
            if (object) {
                [self setValue:object forKey:propertyName];
            }
        }
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    NSMutableArray *codeableProperties = [NSMutableArray array];
    Class cls = [self class];
    while (cls != [NSObject class]) {
        [codeableProperties addObjectsFromArray:[[self class] codeablePropertiesWithClass:cls]];
        cls = [cls superclass];
    }
    
    for (NSString *propertyName in codeableProperties) {
        BLBaseDBObjectFieldInfo *info = g_propertyName_fieldInfo[propertyName];
        if (info.isRelationship) {
            continue;
        }
        
        id object = [self valueForKey:propertyName];
        if (object) {
            [aCoder encodeObject:object forKey:propertyName];
        }
    }
}

#pragma mark - protocol BLBaseDBObject

// db tableName
+ (NSString *)tableName
{
    return NSStringFromClass(self);
}

+ (NSString *)primaryKeyFieldName
{
    return nil;
}

+ (NSArray *)ignoredFieldNames
{
    return @[@"connection",
             @"rowid",
             @"isFault",
             @"enableFullLoadIfFault",
             @"changedFieldNames",
             @"preloadFieldNames"];
}

+ (NSArray *)indexFieldNames
{
    return nil;
}

// db默认值
+ (NSDictionary *)defaultValues
{
    return nil;
}

+ (BOOL)usingFTS
{
    return NO;
}

- (NSArray *)cascadeObjects
{
    return nil;
}

- (BOOL)enableCachedInConnection
{
    return YES;
}

- (BOOL)shouldTouchedInConnection:(BLDatabaseConnection *)connection
{
    return YES;
}

- (BOOL)shouldInsertInConnection:(BLDatabaseConnection *)connection
{
    return YES;
}

- (BOOL)shouldUpdateInConnection:(BLDatabaseConnection *)connection
{
    return YES;
}

- (BOOL)shouldDeleteInConnection:(BLDatabaseConnection *)connection
{
    return YES;
}

#pragma mark -

+ (void)createTableAndIndexIfNeededInConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    NSString *sql = [self createTableSql];
    BLLogDebug(@"sql = %@", sql);
    BOOL success = [connection.fmdb executeUpdate:sql];
    if (!success) {
        BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
        assert(false);
    }
    
    NSString *className = NSStringFromClass([self class]);
    NSDictionary *database_fieldInfo = g_database_fieldInfo[className];
    NSArray *fieldNames = [database_fieldInfo allKeys];
    NSMutableArray *indexColumnNames = [NSMutableArray array];
    NSUInteger count = [fieldNames count];
    for (int i = 0; i < count; i++) {
        NSString *fieldName = fieldNames[i];
        BLBaseDBObjectFieldInfo *fieldInfo = database_fieldInfo[fieldName];
        if (fieldInfo.isIndex) {
            [indexColumnNames addObject:fieldInfo.propertyName];
        }
    }
    [self createIndexWithColumnNames:indexColumnNames inConnection:connection];
}

+ (void)addColumnName:(NSString *)columnName
         inConnection:(BLDatabaseConnection *)connection
{
    [self addColumnNameAndValues:@{columnName:[BLNull null]} inConnection:connection];
}

+ (void)addColumnNames:(NSArray *)columnNames
          inConnection:(BLDatabaseConnection *)connection
{
    NSMutableDictionary *columnNameAndValues = [NSMutableDictionary dictionary];
    for (NSString *columnName in columnNames) {
        [columnNameAndValues setObject:[BLNull null] forKey:columnName];
    }
    
    [self addColumnNameAndValues:columnNameAndValues inConnection:connection];
}

+ (void)addColumnName:(NSString *)columnName
         defaultValue:(id)defaultValue
         inConnection:(BLDatabaseConnection *)connection
{
    [self addColumnNameAndValues:@{columnName:defaultValue} inConnection:connection];
}

+ (void)addColumnNameAndValues:(NSDictionary *)columnNameAndValues
                  inConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    NSMutableString *sql = [NSMutableString stringWithFormat:@"ALTER TABLE %@\n ADD ", [self tableName]];
    NSString *className = NSStringFromClass([self class]);
    NSDictionary *database_fieldInfo = g_database_fieldInfo[className];
    NSArray *columnNames = [columnNameAndValues allKeys];
    NSUInteger count = [columnNames count];
    
    for (int i = 0; i < count; i++) {
        NSString *columnName = columnNames[i];
        BLBaseDBObjectFieldInfo *fieldInfo = database_fieldInfo[columnName];
        assert(fieldInfo != nil);
        
        NSString *typeString = [self typeStringWithFieldType:fieldInfo.type];
        [sql appendFormat:@"%@ %@", columnName, typeString];
        
        id defaultValue = [self defaultValueWithObject:columnNameAndValues[columnName]];
        if (defaultValue) {
            [sql appendFormat:@" DEFAULT %@", defaultValue];
        }
        
        if (i + 1 != count) {
            [sql appendString:@","];
        }
        [sql appendString:@"\n"];
    }
    [sql appendString:@"GO"];
    
    BOOL success = [connection.fmdb executeUpdate:sql];
    if (!success) {
        BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
        assert(false);
    }
}

+ (void)deleteColumnName:(NSString *)columnName
            inConnection:(BLDatabaseConnection *)connection
{
    [self deleteColumnNames:@[columnName] inConnection:connection];
}

+ (void)deleteColumnNames:(NSArray *)columnNames
             inConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    if ([columnNames count] < 1) {
        return;
    }
    
    NSString *className = NSStringFromClass([self class]);
    NSArray *fieldNames = g_database_fieldInfo[className];
    NSMutableSet *fieldNamesSet = [NSMutableSet setWithArray:fieldNames];
    [fieldNamesSet minusSet:[NSSet setWithArray:columnNames]];
    NSString *linkColumnNames = [[fieldNamesSet allObjects] componentsJoinedByString:@", "];
    NSString *backupTableName = [NSString stringWithFormat:@"%@_backup", [self tableName]];
    
    NSMutableString *sql = [NSMutableString stringWithFormat:@"ALERT TABLE %@ RENAME TO %@;", [self tableName], backupTableName];
    [sql appendFormat:@"%@;", [self createTableSql]];
    [sql appendFormat:@"INSERT INTO %@(%@) select %@ from %@;", [self tableName], linkColumnNames, linkColumnNames, backupTableName];
    [sql appendFormat:@"DROP TABLE %@;", backupTableName];
    BLLogDebug(@"sql = %@", sql);
    BOOL success = [connection.fmdb executeUpdate:sql];
    if (!success) {
        BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
        assert(false);
    }
}

+ (void)createIndexWithColumnName:(NSString *)columnName
                     inConnection:(BLDatabaseConnection *)connection
{
    [self createIndexWithColumnNames:@[columnName] inConnection:connection];
}

+ (void)createIndexWithColumnNames:(NSArray *)columnNames
                      inConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    for (NSString *columnName in columnNames) {
        NSString *sql = [NSString stringWithFormat:@"CREATE UNIQUE INDEX IF NOT EXISTS %@ ON %@ (%@)", [self indexNameWithColumnName:columnName], [self tableName], columnName];
        BLLogDebug(@"sql = %@", sql);
        BOOL success = [connection.fmdb executeUpdate:sql];
        if (!success) {
            BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
            assert(false);
        }
    }
}

+ (void)createUnionIndexWithColumnNames:(NSArray *)columnNames
                           inConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    NSString *sql = [NSString stringWithFormat:@"CREATE UNIQUE INDEX IF NOT EXISTS %@ ON %@ (%@)", [self indexNameWithColumnNames:columnNames], [self tableName], [columnNames componentsJoinedByString:@","]];
    BLLogDebug(@"sql = %@", sql);
    BOOL success = [connection.fmdb executeUpdate:sql];
    if (!success) {
        BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
        assert(false);
    }
}

+ (void)dropIndexWithColumnName:(NSString *)columnName
                   inConnection:(BLDatabaseConnection *)connection
{
    [self dropIndexWithColumnNames:@[columnName] inConnection:connection];
}

+ (void)dropIndexWithColumnNames:(NSArray *)columnNames
                    inConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    for (NSString *columnName in columnNames) {
        NSString *sql = [NSString stringWithFormat:@"DROP INDEX IF NOT EXISTS %@", [self indexNameWithColumnName:columnName]];
        BLLogDebug(@"sql = %@", sql);
        BOOL success = [connection.fmdb executeUpdate:sql];
        if (!success) {
            BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
            assert(false);
        }
    }
}

+ (void)dropUnionIndexWithColumnNames:(NSArray *)columnNames
                         inConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    NSString *sql = [NSString stringWithFormat:@"DROP INDEX IF NOT EXISTS %@", [self indexNameWithColumnNames:columnNames]];
    BLLogDebug(@"sql = %@", sql);
    BOOL success = [connection.fmdb executeUpdate:sql];
    if (!success) {
        BLLogError(@"code = %d, message = %@", [connection.fmdb lastErrorCode], [connection.fmdb lastErrorMessage]);
        assert(false);
    }
}

#pragma mark - find count

+ (int64_t)numberOfObjectsInConnection:(BLDatabaseConnection *)connection
{
    return [self numberOfObjectsInConnection:connection where:nil];
}

+ (int64_t)numberOfObjectsInConnection:(BLDatabaseConnection *)connection
                                 where:(NSString *)where, ...
{
    va_list args;
    va_start(args, where);
    int64_t count = [self numberOfObjectsInConnection:connection
                                                where:where
                                               vaList:args];
    va_end(args);
    
    return count;
}

+ (int64_t)numberOfObjectsInConnection:(BLDatabaseConnection *)connection
                                 where:(NSString *)where
                                vaList:(va_list)args
{
    [connection validateRead];
    int64_t count = 0;
    FMResultSet *resultSet = [connection.fmdb executeQuery:[self countQueryWithWhere:where] withVAList:args];
    if ([resultSet next]) {
        count = [resultSet longLongIntForColumnIndex:0];
    }
    [resultSet close];
    
    return count;
}

#pragma mark - find object with sql

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                            rowid:(int64_t)rowid
{
    NSString *where = [NSString stringWithFormat:@"rowid = ?"];
    id object = [self findFirstObjectInConnection:connection
                                          orderBy:nil
                                            where:where, rowid];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                         uniqueId:(NSString *)uniqueId
{
    NSString *where = [NSString stringWithFormat:@"uniqueId = ?"];
    id object = [self findFirstObjectInConnection:connection
                                          orderBy:nil
                                            where:where, uniqueId];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
               valueForPrimaryKey:(NSString *)value
{
    NSString *primaryKeyFieldName = [self primaryKeyFieldName];
    if (primaryKeyFieldName) {
        NSString *where = [NSString stringWithFormat:@"%@ = ?", primaryKeyFieldName];
        id object = [self findFirstObjectInConnection:connection
                                              orderBy:nil
                                                where:where, value];
        
        return object;
    } else {
        return nil;
    }
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                            where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    id object = [self findFirstObjectInConnection:connection
                                          orderBy:nil
                                            where:where
                                           vaList:args];
    va_end(args);
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                          orderBy:(NSString *)orderBy
                            where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    id object = [self findFirstObjectInConnection:connection
                                          orderBy:orderBy
                                            where:where
                                           vaList:args];
    va_end(args);
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                          orderBy:(NSString *)orderBy
                            where:(NSString *)where
                           vaList:(va_list)args
{
    NSArray *fieldNames = nil;
    id object = [self findFirstObjectInConnection:connection
                                       fieldNames:fieldNames
                                          orderBy:orderBy
                                            where:where
                                           vaList:args];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                            rowid:(int64_t)rowid
{
    NSString *where = [NSString stringWithFormat:@"rowid = ?"];
    id object = [self findFirstObjectInConnection:connection
                                       fieldNames:fieldNames
                                          orderBy:nil
                                            where:where, rowid];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                         uniqueId:(NSString *)uniqueId
{
    NSString *where = [NSString stringWithFormat:@"uniqueId = ?"];
    id object = [self findFirstObjectInConnection:connection
                                       fieldNames:fieldNames
                                          orderBy:nil
                                            where:where, uniqueId];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                valueOfPrimaryKey:(NSString *)value
{
    NSString *where = [NSString stringWithFormat:@"%@ = ?", [self primaryKeyFieldName]];
    id object = [self findFirstObjectInConnection:connection
                                       fieldNames:fieldNames
                                          orderBy:nil
                                            where:where, value];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                            where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    id object = [self findFirstObjectInConnection:connection
                                       fieldNames:fieldNames
                                          orderBy:nil
                                            where:where
                                           vaList:args];
    va_end(args);
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                          orderBy:(NSString *)orderBy
                            where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:orderBy
                                             length:1
                                             offset:0
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return [result firstObject];
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                       fieldNames:(NSArray *)fieldNames
                          orderBy:(NSString *)orderBy
                            where:(NSString *)where
                           vaList:(va_list)args
{
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:orderBy
                                             length:1
                                             offset:0
                                              where:where
                                             vaList:args];
    
    return [result firstObject];
}

#pragma mark - find objects with sql

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
{
    NSArray *result = [self findObjectsInConnection:connection
                                            orderBy:nil
                                             length:0
                                             offset:0
                                              where:nil
                                             vaList:nil];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy
{
    NSArray *result = [self findObjectsInConnection:connection
                                            orderBy:orderBy
                                             length:0
                                             offset:0
                                              where:nil
                                             vaList:nil];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                               where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                            orderBy:nil
                                             length:0
                                             offset:0
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy
                               where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                            orderBy:orderBy
                                             length:0
                                             offset:0
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
                               where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                            orderBy:orderBy
                                             length:length
                                             offset:offset
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                             orderBy:(NSString *)orderBy
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
                               where:(NSString *)where
                              vaList:(va_list)args
{
    NSMutableArray *fieldNames = nil;
    /*
     NSMutableArray *fieldNames = [NSMutableArray arrayWithObjects:[self rowidFieldName], [self uniqueIdFieldName], nil];
     */
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:orderBy
                                             length:length
                                             offset:offset
                                              where:where
                                             vaList:args];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
{
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:nil
                                             length:0
                                             offset:0
                                              where:nil
                                             vaList:nil];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy
{
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:orderBy
                                             length:0
                                             offset:0
                                              where:nil
                                             vaList:nil];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                               where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:nil
                                             length:0
                                             offset:0
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy
                               where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:orderBy
                                             length:0
                                             offset:0
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
                               where:(NSString *)where, ...
{
    va_list(args);
    va_start(args, where);
    NSArray *result = [self findObjectsInConnection:connection
                                         fieldNames:fieldNames
                                            orderBy:orderBy
                                             length:length
                                             offset:offset
                                              where:where
                                             vaList:args];
    va_end(args);
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                          fieldNames:(NSArray *)fieldNames
                             orderBy:(NSString *)orderBy
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
                               where:(NSString *)where
                              vaList:(va_list)args
{
    [connection validateRead];
    BOOL isFault = NO;
    if ([fieldNames count] < 1) {
        fieldNames = [self databaseFieldNames];
    } else {
        NSString *uniqueIdFieldName = [self uniqueIdFieldName];
        if (uniqueIdFieldName && ![fieldNames containsObject:uniqueIdFieldName]) {
            fieldNames = [fieldNames arrayByAddingObject:uniqueIdFieldName];
        }
        isFault = [self isFaultWithFieldNames:fieldNames];
    }
    
    NSString *rowidFieldName = [self rowidFieldName];
    if (![fieldNames containsObject:rowidFieldName]) {
        fieldNames = [fieldNames arrayByAddingObject:rowidFieldName];
    }
    
    __block NSInteger uniqueIdIndex = NSNotFound;
    [fieldNames enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([[self uniqueIdFieldName] isEqualToString:obj]) {
            uniqueIdIndex = idx;
            *stop = YES;
        }
    }];
    assert(uniqueIdIndex != NSNotFound);
    
    NSString *query = [self queryWithFieldNames:fieldNames where:where orderBy:orderBy length:length offset:offset];
    FMResultSet *resultSet = [connection.fmdb executeQuery:query withVAList:args];
    NSString *className = NSStringFromClass([self class]);
    NSDictionary *fieldInfo = g_database_fieldInfo[className];
    NSArray *objects = [self objectsWithResultSet:resultSet
                                       fieldNames:fieldNames
                                    uniqueIdIndex:uniqueIdIndex
                                          isFault:isFault
                                        fieldInfo:fieldInfo
                                     inConnection:connection];
    [resultSet close];
    
    return objects;
}

#pragma mark - find object with predicate

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
{
    id object = [self findFirstObjectInConnection:connection
                                        predicate:predicate
                                  sortDescriptors:nil];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                         sortTerm:(NSString *)sortTerm
{
    id object = [self findFirstObjectInConnection:connection
                                        predicate:predicate
                                  sortDescriptors:[self sortDescriptorsWithSortTerm:sortTerm]];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                  sortDescriptors:(NSArray *)sortDescriptors
{
    NSArray *fieldNames = nil;
    id object = [self findFirstObjectInConnection:connection
                                        predicate:predicate
                                       fieldNames:fieldNames
                                  sortDescriptors:sortDescriptors];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                       fieldNames:(NSArray *)fieldNames
{
    id object = [self findFirstObjectInConnection:connection
                                        predicate:predicate
                                       fieldNames:fieldNames
                                  sortDescriptors:nil];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                       fieldNames:(NSArray *)fieldNames
                         sortTerm:(NSString *)sortTerm
{
    id object = [self findFirstObjectInConnection:connection
                                        predicate:predicate
                                       fieldNames:fieldNames
                                  sortDescriptors:[self sortDescriptorsWithSortTerm:sortTerm]];
    
    return object;
}

+ (id)findFirstObjectInConnection:(BLDatabaseConnection *)connection
                        predicate:(NSPredicate *)predicate
                       fieldNames:(NSArray *)fieldNames
                  sortDescriptors:(NSArray *)sortDescriptors
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                         fieldNames:fieldNames
                                    sortDescriptors:sortDescriptors
                                             length:1
                                             offset:0];
    
    return [result firstObject];
}

#pragma mark - find objects with predicate

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                    sortDescriptors:nil
                                             length:0
                                             offset:0];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                            sortTerm:(NSString *)sortTerm
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                    sortDescriptors:[self sortDescriptorsWithSortTerm:sortTerm]
                                             length:0
                                             offset:0];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                     sortDescriptors:(NSArray *)sortDescriptors
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                    sortDescriptors:sortDescriptors
                                             length:0
                                             offset:0];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                            sortTerm:(NSString *)sortTerm
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                    sortDescriptors:[self sortDescriptorsWithSortTerm:sortTerm]
                                             length:length
                                             offset:offset];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                     sortDescriptors:(NSArray *)sortDescriptors
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
{
    NSArray *fieldNames = nil;
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                         fieldNames:fieldNames
                                    sortDescriptors:sortDescriptors
                                             length:length
                                             offset:offset];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                         fieldNames:fieldNames
                                    sortDescriptors:nil
                                             length:0
                                             offset:0];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                            sortTerm:(NSString *)sortTerm
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                         fieldNames:fieldNames
                                    sortDescriptors:[self sortDescriptorsWithSortTerm:sortTerm]
                                             length:0
                                             offset:0];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                     sortDescriptors:(NSArray *)sortDescriptors
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                         fieldNames:fieldNames
                                    sortDescriptors:sortDescriptors
                                             length:0
                                             offset:0];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                            sortTerm:(NSString *)sortTerm
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
{
    NSArray *result = [self findObjectsInConnection:connection
                                          predicate:predicate
                                         fieldNames:fieldNames
                                    sortDescriptors:[self sortDescriptorsWithSortTerm:sortTerm]
                                             length:length
                                             offset:offset];
    
    return result;
}

+ (NSArray *)findObjectsInConnection:(BLDatabaseConnection *)connection
                           predicate:(NSPredicate *)predicate
                          fieldNames:(NSArray *)fieldNames
                     sortDescriptors:(NSArray *)sortDescriptors
                              length:(u_int64_t)length
                              offset:(u_int64_t)offset
{
    NSArray *objects = [self findObjectsInConnection:connection fieldNames:fieldNames];
    objects = [objects filteredArrayUsingPredicate:predicate];
    objects = [objects sortedArrayUsingDescriptors:sortDescriptors];
    if (offset > 0 || length > 0) {
        if (offset >= [objects count]) {
            objects = nil;
        } else {
            length = MIN(length, [objects count] - offset);
            NSRange range = NSMakeRange((NSUInteger)offset, (NSUInteger)length);
            objects = [objects subarrayWithRange:range];
        }
    }
    
    return objects;
}

#pragma mark - touched object

- (void)touchedInConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    if ([self shouldTouchedInConnection:connection]) {
        NSError *error = nil;
        BOOL isExist = [self isExistInConnection:connection];
        
        if (isExist) {
            BLDBChangedObject *changedObject = [BLDBChangedObject new];
            changedObject.uniqueId = self.uniqueId;
            changedObject.tableName = [[self class] tableName];
            changedObject.objectClass = [self class];
            changedObject.changedFiledNames = nil;
            changedObject.type = BLDBChangedObjectUpdate;
            
            [connection.changedObjects addObject:changedObject];
        } else {
            BLLogWarn(@"object not in database, touched object is invalidate");
            error = BLDatabaseError(@"object not in database, touched object is invalidate");
        }
        
        if ([self respondsToSelector:@selector(didTouchedInConnection:withError:)]) {
            [self didTouchedInConnection:connection withError:error];
        }
    }
}

#pragma mark - save/delete

- (void)insertOrUpdateInConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    BOOL isExist = [self isExistInConnection:connection];
    if (isExist) {
        [self updateInConnection:connection];
    } else {
        [self insertInConnection:connection];
    }
}

- (void)insertInConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    if ([self shouldInsertInConnection:connection]) {
        NSError *error = nil;
        NSArray *fieldNames = [[self class] databaseFieldNames];
        NSString *sql = [self insertSqlWithFieldNames:fieldNames];
        
        BOOL success = [connection.fmdb executeUpdate:sql withArgumentsInArray:[self valuesInFieldNames:fieldNames]];
        if (!success) {
            BLLogError(@"code = %d, message = %@", connection.fmdb.lastErrorCode, connection.fmdb.lastErrorMessage);
            error = connection.fmdb.lastError;
        } else {
            // 更新db字段
            self.connection = connection;
            
            // 更新rowid字段
            self.rowid = connection.fmdb.lastInsertRowId;
            
            BLDBChangedObject *changedObject = [BLDBChangedObject new];
            changedObject.uniqueId = self.uniqueId;
            changedObject.tableName = [[self class] tableName];
            changedObject.objectClass = [self class];
            changedObject.changedFiledNames = nil;
            changedObject.type = BLDBChangedObjectInsert;
            
            [connection.changedObjects addObject:changedObject];
        }
        
        if ([self respondsToSelector:@selector(didInsertInConnection:withError:)]) {
            [self didInsertInConnection:connection withError:error];
        }
    }
}

- (void)updateInConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    if ([self shouldUpdateInConnection:connection]) {
        NSError *error = nil;
        NSString *sql = nil;
        NSMutableSet *allSet = [NSMutableSet setWithArray:[[self class] databaseFieldNames]];
        [allSet intersectSet:self.changedFieldNames];
        NSArray *fieldNames = [allSet allObjects];
        
        if ([fieldNames count] >= 1) {
            sql = [self updateSqlWithFieldNames:fieldNames];
        } else {
            BLLogWarn(@"object has no changes, should not update");
            error = BLDatabaseError(@"object has no changes, should not update");
        }
        
        if (sql) {
            BOOL success = [connection.fmdb executeUpdate:sql withArgumentsInArray:[self valuesInFieldNames:fieldNames]];
            if (!success) {
                BLLogError(@"code = %d, message = %@", connection.fmdb.lastErrorCode, connection.fmdb.lastErrorMessage);
                error = connection.fmdb.lastError;
            } else {
                // 更新db字段
                self.connection = connection;
                
                // 清空改变的properties
                [self.changedFieldNames removeAllObjects];
                
                //NSString *cacheKey = [[self class] cacheKeyWithUniqueId:[self uniqueId]];
                //[[self class] removeWithKey:cacheKey inCachedObjects:connection.cachedObjects];
                
                BLDBChangedObject *changedObject = [BLDBChangedObject new];
                changedObject.uniqueId = self.uniqueId;
                changedObject.tableName = [[self class] tableName];
                changedObject.objectClass = [self class];
                changedObject.changedFiledNames = fieldNames;
                changedObject.type = BLDBChangedObjectUpdate;
                
                [connection.changedObjects addObject:changedObject];
            }
        }
        
        if ([self respondsToSelector:@selector(didUpdateInConnection:withError:)]) {
            [self didUpdateInConnection:connection withError:error];
        }
    }
}

- (void)deleteInConnection:(BLDatabaseConnection *)connection
{
    [connection validateReadWriteInTransaction];
    if ([self shouldDeleteInConnection:connection]) {
        NSError *error = nil;
        NSString *sql = [self deleteSql];
        BOOL success = [connection.fmdb executeUpdate:sql];
        if (!success) {
            BLLogError(@"code = %d, messaeg = %@", connection.fmdb.lastErrorCode, connection.fmdb.lastErrorMessage);
            error = connection.fmdb.lastError;
        } else {
            // 更新db字段
            self.connection = connection;
            
            //NSString *cacheKey = [[self class] cacheKeyWithUniqueId:[self uniqueId]];
            //[[self class] removeWithKey:cacheKey inCachedObjects:connection.cachedObjects];
            
            BLDBChangedObject *changedObject = [BLDBChangedObject new];
            changedObject.uniqueId = self.uniqueId;
            changedObject.tableName = [[self class] tableName];
            changedObject.objectClass = [self class];
            changedObject.changedFiledNames = nil;
            changedObject.type = BLDBChangedObjectDelete;
            
            [connection.changedObjects addObject:changedObject];
        }
        
        if ([self respondsToSelector:@selector(didDeleteInConnection:withError:)]) {
            [self didDeleteInConnection:connection withError:error];
        }
    }
}

#pragma mark - begin end notification

+ (void)commitChangedNotificationInConnection:(BLDatabaseConnection *)connection
{
    NSMutableArray *changedObjects = connection.changedObjects;
    
    NSMutableArray *insertObjects = [NSMutableArray array];
    NSMutableArray *updateObjects = [NSMutableArray array];
    NSMutableArray *deleteObjects = [NSMutableArray array];
    NSMutableDictionary *changedObjectsMapping = [NSMutableDictionary dictionary];
    NSMutableArray *indexesToRemove = [NSMutableArray array];
    
    NSInteger index = 0;
    for (BLDBChangedObject *changedObject in changedObjects) {
        NSString *uniqueId = [changedObject uniqueId];
        NSDictionary *info = [changedObjectsMapping valueForKey:uniqueId];
        NSInteger oldIndex = [info[@"index"] integerValue];
        BLDBChangedObjectType oldType = [info[@"type"] integerValue];
        
        if (info) {
            switch (changedObject.type) {
                case BLDBChangedObjectInsert:
                    NSAssert(oldType == BLDBChangedObjectDelete, @"before should be delete when current opration is insert");
                    // delete --> insert merge to update
                    [indexesToRemove addObject:@(oldIndex)];
                    
                    changedObject.type = BLDBChangedObjectUpdate;
                    changedObject.changedFiledNames = nil;
                    info = @{@"index":@(index),@"type":@(BLDBChangedObjectUpdate)};
                    [changedObjectsMapping setValue:info forKey:uniqueId];
                    break;
                case BLDBChangedObjectDelete:
                    NSAssert(oldType != BLDBChangedObjectDelete, @"before should not be delete when current opration is delete");
                    if (oldType == BLDBChangedObjectInsert) {
                        // insert --> delete merge to none
                        [indexesToRemove addObject:@(oldIndex)];
                        [indexesToRemove addObject:@(index)];
                        
                        [changedObjectsMapping removeObjectForKey:uniqueId];
                    } else {
                        // update --> delele merge to delete
                        [indexesToRemove addObject:@(oldIndex)];
                        
                        info = @{@"index":@(index),@"type":@(BLDBChangedObjectDelete)};
                        [changedObjectsMapping setValue:info forKey:uniqueId];
                    }
                    break;
                case BLDBChangedObjectUpdate:
                    NSAssert(oldType != BLDBChangedObjectDelete, @"before should not be delete when current opration is update");
                    if (oldType == BLDBChangedObjectInsert) {
                        // insert --> update merge to insert
                        [indexesToRemove addObject:@(oldIndex)];
                        
                        changedObject.type = BLDBChangedObjectInsert;
                        changedObject.changedFiledNames = nil;
                        info = @{@"index":@(index),@"type":@(BLDBChangedObjectInsert)};
                        [changedObjectsMapping setValue:info forKey:uniqueId];
                    } else {
                        // update --> update merge to update
                        [indexesToRemove addObject:@(oldIndex)];
                        BLDBChangedObject *oldChangedObject = changedObjects[oldIndex];
                        NSMutableOrderedSet *orderedSet = [NSMutableOrderedSet orderedSet];
                        if (oldChangedObject.changedFiledNames) {
                            [orderedSet addObjectsFromArray:oldChangedObject.changedFiledNames];
                        }
                        if (changedObject.changedFiledNames) {
                            [orderedSet addObjectsFromArray:changedObject.changedFiledNames];
                        }
                        changedObject.changedFiledNames = [orderedSet array];
                        info = @{@"index":@(index),@"type":@(BLDBChangedObjectUpdate)};
                        [changedObjectsMapping setValue:info forKey:uniqueId];
                    }
                    break;
                default:
                    break;
            }
        } else {
            info = @{@"index":@(index),@"type":@(changedObject.type)};
            [changedObjectsMapping setValue:info forKey:uniqueId];
        }
        
        index++;
    }
    
    [indexesToRemove sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];
    index = 0;
    NSInteger index1 = 0;
    for (BLDBChangedObject *changedObject in changedObjects) {
        if (index1 < [indexesToRemove count]) {
            NSInteger indexToRemove = [indexesToRemove[index1] integerValue];
            if (index == indexToRemove) {
                index1++;
                index++;
                continue;
            }
        }
        
        switch (changedObject.type) {
            case BLDBChangedObjectInsert:
                [insertObjects addObject:changedObject];
                break;
            case BLDBChangedObjectDelete:
                [deleteObjects addObject:changedObject];
                break;
            case BLDBChangedObjectUpdate:
                [updateObjects addObject:changedObject];
                break;
            default:
                break;
        }
        
        index++;
    }
    
    if ([insertObjects count] > 0 || [updateObjects count] > 0 || [deleteObjects count] > 0) {
        NSDictionary *userInfo = @{BLDatabaseInsertKey:insertObjects,
                                   BLDatabaseUpdateKey:updateObjects,
                                   BLDatabaseDeleteKey:deleteObjects};
        
        NSNotification *notification = [NSNotification notificationWithName:BLDatabaseChangedNotification
                                                                     object:connection.database
                                                                   userInfo:userInfo];
        
        for (BLDatabaseConnection *tempConnection in connection.database.connections) {
            [tempConnection refreshWithInsertObjects:insertObjects
                                       updateObjects:updateObjects
                                       deleteObjects:deleteObjects];
        }
        
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
    
    [connection.changedObjects removeAllObjects];
}

+ (void)rollbackChangedNotificationInConnection:(BLDatabaseConnection *)connection
{
    [connection.changedObjects removeAllObjects];
}

#pragma mark - load fault

- (void)loadFaultInConnection:(BLDatabaseConnection *)connection
{
    [connection validateRead];
    void(^block)(void) = ^(void) {
        if (self.isFault) {
            NSMutableSet *databaseFieldNames = [NSMutableSet setWithArray:[[self class] databaseFieldNames]];
            [databaseFieldNames minusSet:[self preloadFieldNames]];
            
            NSArray *fieldNames = [databaseFieldNames allObjects];
            NSString *uniqueIdFieldName = [[self class] uniqueIdFieldName];
            
            int *fieldTypes = (int *)malloc([fieldNames count] * sizeof(int));
            if (!self->fieldInfoForDatabase) {
                NSString *className = NSStringFromClass([self class]);
                self->fieldInfoForDatabase = g_database_fieldInfo[className];
            }
            [fieldNames enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                BLBaseDBObjectFieldInfo *info = self->fieldInfoForDatabase[obj];
                fieldTypes[idx] = info.type;
            }];
            
            NSString *sql = [[self class] queryWithFieldNames:fieldNames
                                                        where:[NSString stringWithFormat:@"%@ = ?", uniqueIdFieldName]
                                                      orderBy:nil
                                                       length:1
                                                       offset:0];
            FMResultSet *resultSet = [connection.fmdb executeQuery:sql, [self uniqueId]];
            
            if ([resultSet next]) {
                NSString *cacheKey = [[self class] cacheKeyWithUniqueId:self.uniqueId];
                NSMutableDictionary *resultDictionary = [[self class] dictionaryWithKey:cacheKey inCachedObjects:connection.cachedObjects];
                
                self.enableFullLoadIfFault = NO;
                
                sqlite3_stmt *statement = [[resultSet statement] statement];
                NSUInteger num_cols = (NSUInteger)sqlite3_data_count(statement);
                if (num_cols > 0) {
                    int columnCount = sqlite3_column_count(statement);
                    int columnIdx = 0;
                    for (columnIdx = 0; columnIdx < columnCount; columnIdx++) {
                        NSString *columnName = fieldNames[columnIdx];
                        id objectValue = [resultSet objectForColumnIndex:columnIdx];
                        
                        if (objectValue && objectValue != [NSNull null]) {
                            BLBaseDBObjectFieldType fieldType = fieldTypes[columnIdx];
                            if (fieldType == BLBaseDBObjectFieldTypeDate) {
                                objectValue = [NSDate dateWithTimeIntervalSince1970:[objectValue doubleValue]];
                            } else if (fieldType == BLBaseDBObjectFieldTypeArray) {
                                objectValue = [objectValue componentsSeparatedByString:@","];
                            }
                        }
                        
                        objectValue = objectValue != [NSNull null] ? objectValue : nil;
                        [self setValue:objectValue forKey:columnName];
                        
                        if (resultDictionary) {
                            [resultDictionary setValue:objectValue forKey:columnName];
                        }
                    }
                }
                
                self.enableFullLoadIfFault = YES;
            }
            
            self.isFault = NO;
            
            [resultSet close];
        }
    };
    
    if ([_connection isInWriteQueue]) {
        block();
    } else {
        [_connection performReadBlockAndWait:^{
            block();
        }];
    }
}

#pragma mark - cache

+ (void)setDictionary:(NSMutableDictionary *)dictionary withKey:(NSString *)key inCachedObjects:(BLDBCache *)cachedObjects
{
    if (dictionary) {
        [cachedObjects setObject:dictionary forKey:key];
    }
}

+ (void)removeWithKey:(NSString *)key inCachedObjects:(BLDBCache *)cachedObjects
{
    [cachedObjects removeObjectForKey:key];
}

+ (NSMutableDictionary *)dictionaryWithKey:(NSString *)key inCachedObjects:(BLDBCache *)cachedObjects
{
    return [cachedObjects objectForKey:key];
}

+ (NSString *)cacheKeyWithUniqueId:(NSString *)uniqueId
{
    return uniqueId;
}

/*
 + (NSString *)cacheKeyWithRowid:(int64_t)rowid
 {
 return [self cacheKeyWithTableName:[self tableName] withRowid:rowid];
 }
 
 + (NSString *)cacheKeyWithTableName:(NSString *)tableName withRowid:(int64_t)rowid
 {
 char *buffer;
 asprintf(&buffer, "%s-%lld", [tableName UTF8String], rowid);
 NSString *value = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
 free(buffer);
 
 return value;
 }
 */

#pragma mark - check

+ (BOOL)isValidObject:(id)object
{
    return [object isKindOfClass:[BLBaseDBObject class]];
}

#pragma mark - sql util

+ (NSString *)createTableSql
{
    NSString *className = NSStringFromClass([self class]);
    NSDictionary *database_fieldInfo = g_database_fieldInfo[className];
    NSArray *fieldNames = [database_fieldInfo allKeys];
    NSMutableString *sql = [NSMutableString string];
    
    [sql appendFormat:@"CREATE TABLE IF NOT EXISTS %@ %@ (\n", [self tableName], [self usingFTS] ? @"USING fts4" : @""];
    NSUInteger count = [fieldNames count];
    for (int i = 0; i < count; i++) {
        NSString *fieldName = fieldNames[i];
        [sql appendString:fieldName];
        
        BLBaseDBObjectFieldInfo *fieldInfo = database_fieldInfo[fieldName];
        
        BOOL isPK = NO;
        if ([fieldName isEqualToString:[[self class] primaryKeyFieldName]]) {
            isPK = YES;
        }
        
        id defaultValue = [[self class] defaultValues][fieldName];
        NSString *typeString = [self typeStringWithFieldType:fieldInfo.type];
        [sql appendString:typeString];
        if (isPK) {
            [sql appendString:@" PRIMARY KEY"];
        }
        
        id targetDefaultValue = [self defaultValueWithObject:defaultValue];
        if (targetDefaultValue) {
            [sql appendFormat:@" DEFAULT %@", targetDefaultValue];
        }
        
        if (i + 1 != count) {
            [sql appendString:@","];
        }
        [sql appendString:@"\n"];
    }
    [sql appendString:@")"];
    
    return sql;
}

+ (NSString *)countQueryWithWhere:(NSString *)where
{
    NSMutableString *sql = [NSMutableString string];
    if (where.length > 0) {
        [sql appendFormat:@"SELECT COUNT(*) FROM %@ WHERE %@", [self tableName], where];
    } else {
        [sql appendFormat:@"SELECT COUNT(*) FROM %@", [self tableName]];
    }
    BLLogDebug(@"sql = %@", sql);
    
    return sql;
}

+ (NSString *)queryWithFieldNames:(NSArray *)fieldNames
                            where:(NSString *)where
                          orderBy:(NSString *)orderBy
                           length:(u_int64_t)length
                           offset:(u_int64_t)offset
{
    NSMutableString *sql = [NSMutableString string];
    if ([fieldNames count] > 0) {
        [sql appendFormat:@"SELECT %@ FROM %@", [fieldNames componentsJoinedByString:@", "], [self tableName]];
    } else {
        [sql appendFormat:@"SELECT rowid, * FROM %@", [self tableName]];
    }
    
    if (where.length > 0) {
        [sql appendFormat:@" WHERE %@", where];
    } else {
        [sql appendString:@" WHERE 1=1"];
    }
    
    if (orderBy.length > 0) {
        [sql appendFormat:@" ORDER BY %@", orderBy];
    }
    if (length > 0) {
        [sql appendFormat:@" LIMIT %tu", length];
    }
    if (offset > 0) {
        [sql appendFormat:@" OFFSET %tu", offset];
    }
    BLLogDebug(@"sql = %@", sql);
    
    return sql;
}

- (NSString *)insertSqlWithFieldNames:(NSArray *)fieldNames
{
    NSMutableString *sql = [NSMutableString string];
    NSString *tableName = [[self class] tableName];
    NSMutableString *subString = [NSMutableString string];
    NSUInteger count = [fieldNames count];
    for (int i = 0; i < count; i++) {
        [subString appendFormat:@"%@", i != count - 1 ? @"?," : @"?"];
    }
    [sql appendFormat:@"INSERT INTO %@ (%@) VALUES (%@)", tableName, [fieldNames componentsJoinedByString:@","], subString];
    BLLogDebug(@"sql = %@", sql);
    
    return sql;
}

- (NSString *)updateSqlWithFieldNames:(NSArray *)fieldNames
{
    NSMutableString *sql = [NSMutableString string];
    NSString *tableName = [[self class] tableName];
    NSMutableString *subString = [NSMutableString string];
    NSUInteger count = [fieldNames count];
    for (int i = 0; i < count; i++) {
        [subString appendFormat:@"%@=?%@", fieldNames[i], i != count - 1 ? @"," : @""];
    }
    
    [sql appendFormat:@"UPDATE %@ SET %@ WHERE %@ = '%@'", tableName, subString, [[self class] uniqueIdFieldName], [self uniqueId]];
    BLLogDebug(@"sql = %@", sql);
    
    return sql;
}

- (NSString *)deleteSql
{
    NSMutableString *sql = [NSMutableString string];
    NSString *tableName = [[self class] tableName];
    
    [sql appendFormat:@"DELETE FROM %@ WHERE %@ = '%@'", tableName, [[self class] uniqueIdFieldName], [self uniqueId]];
    BLLogDebug(@"sql = %@", sql);
    
    return sql;
}

+ (NSString *)typeStringWithFieldType:(BLBaseDBObjectFieldType)type
{
    NSString *typeString = @"";
    switch (type) {
        case BLBaseDBObjectFieldTypeInteger:
            typeString = @" INTEGER";
            break;
        case BLBaseDBObjectFieldTypeReal:
            typeString = @" REAL";
            break;
        case BLBaseDBObjectFieldTypeBlob:
            typeString = @" BLOB";
            break;
        case BLBaseDBObjectFieldTypeDate:
            typeString = @" REAL";
            break;
        case BLBaseDBObjectFieldTypeText:
            typeString = @" TEXT";
            break;
        case BLBaseDBObjectFieldTypeArray:
            typeString = @" TEXT";
            break;
        default:
            BLLogError(@"unsupport type for %zd", type);
            assert(false);
            break;
    }
    
    return typeString;
}

+ (id)defaultValueWithObject:(id)object
{
    if (!object || object == [BLNull null]) {
        return nil;
    } else if ([object isEqual:[NSNull null]]) {
        return @"NULL";
    }
    
    return object;
}

+ (NSString *)indexNameWithColumnName:(NSString *)columnName
{
    NSString *indexName = [NSString stringWithFormat:@"%@_%@_index", [self tableName], columnName];
    
    return indexName;
}

+ (NSString *)indexNameWithColumnNames:(NSArray *)columnNames
{
    NSString *indexName = [NSString stringWithFormat:@"%@_%@_index", [self tableName], [columnNames componentsJoinedByString:@"_"]];
    
    return indexName;
}

#pragma mark - FMResultSet to object

+ (BOOL)isFaultWithFieldNames:(NSArray *)fieldNames
{
    if ([fieldNames count] == [[self databaseFieldNames] count] && [fieldNames isEqualToArray:[self databaseFieldNames]]) {
        return NO;
    }
    
    return YES;
}

- (NSArray *)valuesInFieldNames:(NSArray *)fieldNames
{
    NSMutableArray *values = [NSMutableArray array];
    
    for (NSString *fieldName in fieldNames) {
        id value = [self valueForKey:fieldName];
        NSString *className = NSStringFromClass([self class]);
        BLBaseDBObjectFieldInfo *info = g_database_fieldInfo[className][fieldName];
        if (!info) {
            BLLogError(@"info is nil for fieldName = %@", fieldName);
            assert(false);
        }
        
        if (value) {
            if (info.type == BLBaseDBObjectFieldTypeDate) {
                value = [NSNumber numberWithDouble:[value timeIntervalSince1970]];
            } else if (info.type == BLBaseDBObjectFieldTypeArray) {
                value = [value componentsJoinedByString:@","];
            }
            [values addObject:value];
        } else {
            [values addObject:[NSNull null]];
        }
    }
    
    return values;
}

+ (NSArray *)objectsWithResultSet:(FMResultSet *)resultSet
                       fieldNames:(NSArray *)fieldNames
                    uniqueIdIndex:(NSInteger)uniqueIdIndex
                          isFault:(BOOL)isFault
                        fieldInfo:(NSDictionary *)fieldInfo
                     inConnection:(BLDatabaseConnection *)connection
{
    NSMutableArray *objects = [NSMutableArray array];
    int *fieldTypes = (int *)malloc([fieldNames count] * sizeof(int));
    //NSString *className = NSStringFromClass([self class]);
    //NSDictionary *fieldInfo = g_database_fieldInfo[className];
    [fieldNames enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        BLBaseDBObjectFieldInfo *info = fieldInfo[obj];
        fieldTypes[idx] = info.type;
    }];
    
    while ([resultSet next]) {
        sqlite3_stmt *statement = [[resultSet statement] statement];
        NSString *uniqueId = [resultSet stringForColumnIndex:(int)uniqueIdIndex];
        NSString *cacheKey = [self cacheKeyWithUniqueId:uniqueId];
        NSMutableDictionary *resultDictionary = [self dictionaryWithKey:cacheKey inCachedObjects:connection.cachedObjects];
        BOOL hasCache = YES;
        
        if (!resultDictionary) {
            hasCache = NO;
            resultDictionary = [NSMutableDictionary dictionary];
        }
        
        if (!hasCache || [resultDictionary[@"isFault"] boolValue]) {
            NSMutableSet *preloadFieldNames = [NSMutableSet setWithArray:[resultDictionary allKeys]];
            NSUInteger num_cols = (NSUInteger)sqlite3_data_count(statement);
            if (num_cols > 0) {
                int columnCount = sqlite3_column_count(statement);
                int columnIdx = 0;
                for (columnIdx = 0; columnIdx < columnCount; columnIdx++) {
                    NSString *columnName = fieldNames[columnIdx];
                    
                    if ([preloadFieldNames containsObject:columnName]) {
                        continue;
                    }
                    
                    id objectValue = [resultSet objectForColumnIndex:columnIdx];
                    if (objectValue && objectValue != [NSNull null]) {
                        BLBaseDBObjectFieldType fieldType = fieldTypes[columnIdx];
                        if (fieldType == BLBaseDBObjectFieldTypeDate) {
                            objectValue = [NSDate dateWithTimeIntervalSince1970:[objectValue doubleValue]];
                        } else if (fieldType == BLBaseDBObjectFieldTypeArray) {
                            objectValue = [objectValue componentsSeparatedByString:@","];
                        }
                    }
                    
                    [resultDictionary setValue:objectValue forKey:columnName];
                }
            }
        }
        
        BLBaseDBObject *object = [self new];
        object.connection = connection;
        object.enableFullLoadIfFault = NO;
        
        for (NSString *key in resultDictionary) {
            id value = resultDictionary[key];
            if (value == [NSNull null]) {
                value = nil;
            }
            [object setValue:value forKey:key];
        }
        
        
        object.enableFullLoadIfFault = YES;
        object.isFault = isFault;
        if (isFault) {
            object.preloadFieldNames = [NSMutableSet setWithArray:[resultDictionary allKeys]];
        }
        
        if (!hasCache && [object enableCachedInConnection]) {
            [self setDictionary:resultDictionary withKey:cacheKey inCachedObjects:connection.cachedObjects];
        }
        [objects addObject:object];
    }
    
    free(fieldTypes);
    
    return objects;
}

#pragma mark - sort util

+ (NSArray *)sortDescriptorsWithSortTerm:(NSString *)sortTerm
{
    NSMutableArray *sortDescriptors = [NSMutableArray array];
    NSArray *sortKeys = [sortTerm componentsSeparatedByString:@","];
    for (__strong NSString *sortKey in sortKeys) {
        BOOL ascending = NO;
        NSArray *sortComponents = [sortKey componentsSeparatedByString:@":"];
        if (sortComponents.count > 1) {
            NSNumber *customAscending = sortComponents.lastObject;
            ascending = customAscending.boolValue;
            sortKey = sortComponents[0];
        }
        
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:sortKey ascending:ascending];
        [sortDescriptors addObject:sortDescriptor];
    }
    
    return sortDescriptors;
}

#pragma mark - util

+ (NSString *)firstLetterToUpperWithString:(NSString *)string
{
    NSString *newString = [string stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                          withString:[[string substringToIndex:1] uppercaseString]];
    
    return newString;
}

+ (NSString *)reflectionNameToOneWithPropertyName:(NSString *)propertyName
{
    char *buffer;
    asprintf(&buffer, "%sId", [propertyName UTF8String]);
    NSString *value = [NSString stringWithUTF8String:buffer];
    free(buffer);
    
    return value;
}

+ (NSString *)reflectionNameToManyWithPropertyName:(NSString *)propertyName
{
    char *buffer;
    asprintf(&buffer, "%sIds", [propertyName UTF8String]);
    NSString *value = [NSString stringWithUTF8String:buffer];
    free(buffer);
    
    return value;
}

- (BOOL)isExistInConnection:(BLDatabaseConnection *)connection
{
    BOOL isExist = NO;
    NSString *uniqueIdFieldName = [[self class] uniqueIdFieldName];
    
    int64_t count = [[self class] numberOfObjectsInConnection:connection
                                                        where:[NSString stringWithFormat:@"%@ = ?", uniqueIdFieldName], [self uniqueId]];
    isExist = count >= 1 ? YES : NO;
    
    return isExist;
}

@end
