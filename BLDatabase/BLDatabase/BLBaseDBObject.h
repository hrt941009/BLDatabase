//
//  BLBaseDBObject.h
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>

#define BL_ARRAY_TYPE(BL_OBJECT_SUBCLASS) \
@protocol BL_OBJECT_SUBCLASS <NSObject>   \
@end

extern NSString * const BLDatabaseInsertKey;
extern NSString * const BLDatabaseUpdateKey;
extern NSString * const BLDatabaseDeleteKey;

extern NSString * const BLDatabaseChangedNotification;

@class BLDatabaseConnection;

@protocol BLBaseDBObject <NSObject>

@required

// db tableName
+ (NSString *)tableName;

// db pk
+ (NSString *)primaryKeyFieldName;

@optional

// 不需要存取db的字段
+ (NSArray *)ignoredFieldNames;

// 需要建立索引的db字段
+ (NSArray *)indexFieldNames;

// db字段默认值
+ (NSDictionary *)defaultValues;

// default is NO
+ (BOOL)usingFTS;

// using this when delete self also delete cascade objects
- (NSArray *)cascadeObjects;

- (BOOL)enableCachedInConnection;

- (void)didTouchedInConnection:(BLDatabaseConnection *)connection;

- (void)didInsertInConnection:(BLDatabaseConnection *)connection;

- (void)didUpdateInConnection:(BLDatabaseConnection *)connection;

- (void)didDeleteInConnection:(BLDatabaseConnection *)connection;

@end

typedef NS_ENUM(NSInteger, BLBaseDBObjectFieldType) {
    BLBaseDBObjectFieldTypeOther = 0,
    BLBaseDBObjectFieldTypeText,
    BLBaseDBObjectFieldTypeInteger,
    BLBaseDBObjectFieldTypeReal,
    BLBaseDBObjectFieldTypeBlob,
    BLBaseDBObjectFieldTypeDate,
    BLBaseDBObjectFieldTypeArray,
    BLBaseDBObjectFieldTypeRelationship
};

@interface BLBaseDBObjectFieldInfo : NSObject

@property (nonatomic, assign, readonly) BOOL isPrimaryKey;
@property (nonatomic, assign, readonly) BOOL isIndex;
@property (nonatomic, assign, readonly) BOOL isRelationship;
@property (nonatomic, strong, readonly) id defaultValue;

@property (nonatomic, copy, readonly) NSString *propertyName;
@property (nonatomic, strong, readonly) Class relationshipObjectClass;
@property (nonatomic, assign, readonly) BLBaseDBObjectFieldType type;
@property (nonatomic, copy, readonly) NSString *propertyTypeEncoding;

@end

@class BLBaseDBObjectFieldInfo, BLDatabaseConnection;

/**
 objc_msgSend()报错Too many arguments to function call ,expected 0,have3
 resolve: Build Setting--> Apple LLVM 6.0 - Preprocessing--> Enable Strict Checking of objc_msgSend Calls  改为 NO
 */

/**
 1. BLBaseDBObject的所有attribute都是immutable;
 2. BLDatabase支持的数据类型 (signed/unsigned)(bool, char, short, int, long, long long, float, double),
 NSNumber, NSString, NSDate, NSData;
 3. 关系对象类型BLBaseDBObject, NSArray<xxx>;
 */

@interface BLBaseDBObject : NSObject <BLBaseDBObject, NSCopying, NSCoding>

@property (nonatomic, weak, readonly) BLDatabaseConnection *connection;
@property (nonatomic, assign, readonly) int64_t rowid;
@property (nonatomic, copy, readonly) NSString *uniqueId;
@property (nonatomic, assign, readonly) BOOL isFault;
@property (nonatomic, strong, readonly) NSMutableSet *changedFieldNames;
@property (nonatomic, strong, readonly) NSMutableSet *preloadFieldNames;

// db所有字段
+ (NSArray *)databaseFieldNames;

+ (BLBaseDBObjectFieldInfo *)infoForFieldName:(NSString *)fieldName;

+ (NSString *)rowidFieldName;

+ (NSString *)uniqueIdFieldName;

- (NSString *)detailDescription;

- (id)copyWithExcludeProperties:(NSArray *)excludeProperties;

- (id)copyWithIncludeProperties:(NSArray *)includeProperties;

@end