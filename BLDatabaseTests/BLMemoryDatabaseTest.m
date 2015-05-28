//
//  BLMemoryDatabaseTest.m
//  BLDatabase
//
//  Created by alibaba on 15/5/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "BLStoreManager.h"
#import "BLDatabase.h"
#import "BLDatabaseConnection.h"
#import "BLBaseDBObject+Common.h"
#import "BLTestObject.h"
#import "BLAccount.h"

@interface BLMemoryDatabaseTest : XCTestCase

@end

@implementation BLMemoryDatabaseTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    [database setSchemaVersion:1 withMigrationBlock:^(BLDatabaseConnection *databaseConnection, NSUInteger oldSchemaVersion) {
        [BLTestObject createTableAndIndexIfNeededInDatabaseConnection:databaseConnection];
        [BLAccount createTableAndIndexIfNeededInDatabaseConnection:databaseConnection];
    }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
        [connection deleteObjects:result];
        
        result = [BLTestObject findObjectsInDatabaseConnection:connection];
        XCTAssert([result count] == 0);
    }];
    
    NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
    XCTAssert([result count] == 0);
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
    
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
        [connection deleteObjects:result];
        
        result = [BLTestObject findObjectsInDatabaseConnection:connection];
        XCTAssert([result count] == 0);
    }];
    
    NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
    XCTAssert([result count] == 0);
}

- (void)testInsert {
    // This is an example of a functional test case.
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    int count = 100;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            [connection insertObject:object];
        }
        
        NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
        XCTAssert([result count] == count);
    }];
    
    NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
    XCTAssert([result count] == count);
}

- (void)testFindWithSql {
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    int count = 100;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 20;
            object.name = @"alibaba";
            [connection insertObject:object];
        }
        
        NSArray *result1 = [BLTestObject findObjectsInDatabaseConnection:connection];
        NSArray *result2 = [BLTestObject findObjectsInDatabaseConnection:connection where:@"age = ? AND name = ?", @(20), @"alibaba"];
        
        XCTAssert([result1 count] >= [result2 count]);
        XCTAssert([result2 count] == count);
        
        u_int64_t length = 20;
        NSArray *result3 = [BLTestObject findObjectsInDatabaseConnection:connection
                                                                 orderBy:nil
                                                                  length:length
                                                                  offset:0
                                                                   where:@"age = ? AND name = ?", @(20), @"alibaba"];
        XCTAssert([result3 count] == length);
    }];
}

- (void)testFindWithPredicate {
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    int count = 100;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 20;
            object.name = @"alibaba";
            [connection insertObject:object];
        }
        
        NSArray *result1 = [BLTestObject findObjectsInDatabaseConnection:connection];
        NSArray *result2 = [BLTestObject findObjectsInDatabaseConnection:connection predicate:[NSPredicate predicateWithFormat:@"age = %d AND name = %@", 20, @"alibaba"]];
        
        XCTAssert([result1 count] >= [result2 count]);
        XCTAssert([result2 count] == count);
        
        u_int64_t length = 20;
        NSArray *result3 = [BLTestObject findObjectsInDatabaseConnection:connection
                                                               predicate:[NSPredicate predicateWithFormat:@"age = %d AND name = %@", 20, @"alibaba"]
                                                                sortTerm:nil
                                                                  length:length
                                                                  offset:0];
        XCTAssert([result3 count] == length);
    }];
}

- (void)testFault
{
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    int count = 1;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 20;
            object.name = @"alibaba";
            [connection insertObject:object];
        }
        
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection fieldNames:@[@"name"] where:nil];
        XCTAssertTrue(testObject.isFault);
        NSMutableSet *targetFieldNames = [NSMutableSet setWithObjects:@"objectID", @"rowid", @"name", nil];
        XCTAssertEqualObjects(testObject.preloadFieldNames, targetFieldNames);
        
        __unused NSString *groupName = testObject.groupName;
        XCTAssertFalse(testObject.isFault);
        XCTAssertEqual(testObject.age, 20);
        XCTAssertEqualObjects(testObject.name, @"alibaba");
        XCTAssertEqualObjects(testObject.groupName, nil);
    }];
}

- (void)testChangedFieldNames
{
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    int count = 1;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 20;
            object.name = @"alibaba";
            [connection insertObject:object];
        }
        
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection fieldNames:@[@"name"] where:nil];
        XCTAssertTrue(testObject.isFault);
        testObject.name = @"alibaba1";
        testObject.groupName = @"alibaba1";
        XCTAssertFalse(testObject.isFault);
        
        NSMutableSet *targetFieldNames = [NSMutableSet setWithObjects:@"name", @"groupName", nil];
        XCTAssertEqualObjects(testObject.changedFieldNames, targetFieldNames);
    }];
}

- (void)testOneToOne
{
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLAccount *account = [BLAccount new];
        NSString *objectID = account.objectID;
        BLAccount *account1 = [BLAccount new];
        NSString *objectID1 = account1.objectID;
        account.relationship = account1;
        account1.relationship = account;
        [connection insertObjects:@[account, account1]];
        
        BLAccount *targeAccount = [BLAccount findFirstObjectInDatabaseConnection:connection valueForObjectID:objectID];
        BLAccount *targeAccount1 = [BLAccount findFirstObjectInDatabaseConnection:connection valueForObjectID:objectID1];
        XCTAssertEqualObjects(targeAccount.relationship.objectID, objectID1);
        XCTAssertEqualObjects(targeAccount1.relationship.objectID, objectID);
    }];
}

- (void)testOneToMany
{
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLAccount *account = [BLAccount new];
        NSString *objectID = account.objectID;
        
        BLAccount *account1 = [BLAccount new];
        NSString *objectID1 = account1.objectID;
        
        BLAccount *account2 = [BLAccount new];
        NSString *objectID2 = account2.objectID;
        
        account.relationships = (NSArray<BLAccount> *)@[account1, account2];
        [connection insertObjects:@[account, account1, account2]];
        
        BLAccount *targeAccount = [BLAccount findFirstObjectInDatabaseConnection:connection valueForObjectID:objectID];
        NSArray *objectIDs = @[objectID1, objectID2];
        XCTAssertEqualObjects(targeAccount.relationshipsUUIDs, objectIDs);
    }];
}

- (void)testNotification
{
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    NSInteger insert = 50;
    NSInteger update = 50;
    NSInteger delete = 50;
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < update + delete; i++) {
            BLTestObject *testObject = [BLTestObject new];
            testObject.age = 20;
            testObject.name = @"alibaba";
            testObject.groupName = @"aliyun";
            [connection insertObject:testObject];
        }
    }];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:BLDatabaseChangedNotification
                                                                    object:database
                                                                     queue:[NSOperationQueue currentQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    NSDictionary *userInfo = note.userInfo;
                                                                    NSArray *insertObjects = userInfo[BLDatabaseInsertKey];
                                                                    NSArray *updateObjects = userInfo[BLDatabaseUpdateKey];
                                                                    NSArray *deleteObjects = userInfo[BLDatabaseDeleteKey];
                                                                    XCTAssertTrue([insertObjects count] == insert);
                                                                    XCTAssertTrue([updateObjects count] == insert);
                                                                    XCTAssertTrue([deleteObjects count] == insert);
                                                                }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLTestObject findObjectsInDatabaseConnection:connection];
        XCTAssertTrue([result count] == update + delete);
        
        NSArray *updateObjects = [result subarrayWithRange:NSMakeRange(0, update)];
        NSArray *deleteObjects = [result subarrayWithRange:NSMakeRange(update, delete)];
        
        for (BLTestObject *object in updateObjects) {
            object.name = @"alibaba1";
            [connection updateObject:object];
        }
        [connection deleteObjects: deleteObjects];
        
        for (int i = 0; i < insert; i++) {
            BLTestObject *testObject = [BLTestObject new];
            testObject.age = 20;
            testObject.name = @"alibaba";
            testObject.groupName = @"aliyun";
            [connection insertObject:testObject];
        }
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:BLDatabaseChangedNotification object:database];
}

- (void)testMergeInsertUpdateNotification
{
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:BLDatabaseChangedNotification
                                                                    object:database
                                                                     queue:[NSOperationQueue currentQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    NSDictionary *userInfo = note.userInfo;
                                                                    NSArray *insertObjects = userInfo[BLDatabaseInsertKey];
                                                                    NSArray *updateObjects = userInfo[BLDatabaseUpdateKey];
                                                                    NSArray *deleteObjects = userInfo[BLDatabaseDeleteKey];
                                                                    XCTAssertTrue([insertObjects count] == 1);
                                                                    XCTAssertTrue([updateObjects count] == 0);
                                                                    XCTAssertTrue([deleteObjects count] == 0);
                                                                }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject new];
        testObject.age = 20;
        testObject.name = @"alibaba";
        testObject.groupName = @"aliyun";
        [connection insertObject:testObject];
        
        testObject.name = @"alibaba1";
        [connection updateObject:testObject];
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:BLDatabaseChangedNotification object:database];
}

- (void)testMergeInsertDeleteNotification
{
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:BLDatabaseChangedNotification
                                                                    object:database
                                                                     queue:[NSOperationQueue currentQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    XCTAssertTrue(true);
                                                                }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject new];
        testObject.age = 20;
        testObject.name = @"alibaba";
        testObject.groupName = @"aliyun";
        [connection insertObject:testObject];
        
        [connection deleteObject:testObject];
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:BLDatabaseChangedNotification object:database];
}

- (void)testMergeUpdateUpdateNotification
{
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    __block NSString *objectID = nil;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject new];
        testObject.age = 20;
        testObject.name = @"alibaba";
        testObject.groupName = @"aliyun";
        objectID = testObject.objectID;
        [connection insertObject:testObject];
    }];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:BLDatabaseChangedNotification
                                                                    object:database
                                                                     queue:[NSOperationQueue currentQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    NSDictionary *userInfo = note.userInfo;
                                                                    NSArray *insertObjects = userInfo[BLDatabaseInsertKey];
                                                                    NSArray *updateObjects = userInfo[BLDatabaseUpdateKey];
                                                                    NSArray *deleteObjects = userInfo[BLDatabaseDeleteKey];
                                                                    XCTAssertTrue([insertObjects count] == 0);
                                                                    XCTAssertTrue([updateObjects count] == 1);
                                                                    XCTAssertTrue([deleteObjects count] == 0);
                                                                }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection where:nil];
        testObject.age = 20;
        [connection updateObject:testObject];
        
        testObject.age = 20;
        [connection updateObject:testObject];
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:BLDatabaseChangedNotification object:database];
}

- (void)testMergeUpdateDeleteNotification
{
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    __block NSString *objectID = nil;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject new];
        testObject.age = 20;
        testObject.name = @"alibaba";
        testObject.groupName = @"aliyun";
        objectID = testObject.objectID;
        [connection insertObject:testObject];
    }];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:BLDatabaseChangedNotification
                                                                    object:database
                                                                     queue:[NSOperationQueue currentQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    NSDictionary *userInfo = note.userInfo;
                                                                    NSArray *insertObjects = userInfo[BLDatabaseInsertKey];
                                                                    NSArray *updateObjects = userInfo[BLDatabaseUpdateKey];
                                                                    NSArray *deleteObjects = userInfo[BLDatabaseDeleteKey];
                                                                    XCTAssertTrue([insertObjects count] == 0);
                                                                    XCTAssertTrue([updateObjects count] == 0);
                                                                    XCTAssertTrue([deleteObjects count] == 1);
                                                                }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection where:nil];
        testObject.age = 20;
        [connection updateObject:testObject];
        
        [connection deleteObject:testObject];
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:BLDatabaseChangedNotification object:database];
}

- (void)testMergeDeleteInsertNotification
{
    BLDatabase *database = [[BLStoreManager shareInstance] mDatabase];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] mConnection];
    
    __block NSString *objectID = nil;
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject new];
        testObject.age = 20;
        testObject.name = @"alibaba";
        testObject.groupName = @"aliyun";
        objectID = testObject.objectID;
        [connection insertObject:testObject];
    }];
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:BLDatabaseChangedNotification
                                                                    object:database
                                                                     queue:[NSOperationQueue currentQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    NSDictionary *userInfo = note.userInfo;
                                                                    NSArray *insertObjects = userInfo[BLDatabaseInsertKey];
                                                                    NSArray *updateObjects = userInfo[BLDatabaseUpdateKey];
                                                                    NSArray *deleteObjects = userInfo[BLDatabaseDeleteKey];
                                                                    XCTAssertTrue([insertObjects count] == 0);
                                                                    XCTAssertTrue([updateObjects count] == 1);
                                                                    XCTAssertTrue([deleteObjects count] == 0);
                                                                }];
    
    [connection performReadWriteBlockAndWaitInTransaction:^(BOOL *rollback) {
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection where:nil];
        [connection deleteObject:testObject];
        
        [connection insertObject:testObject];
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:BLDatabaseChangedNotification object:database];
}

@end
