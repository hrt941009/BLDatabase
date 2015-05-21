//
//  BLFindDataTests.m
//  BLDatabase
//
//  Created by alibaba on 15/5/19.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "BLStoreManager.h"
#import "BLDatabase.h"
#import "BLDatabaseConnection.h"
#import "BLBaseDBObject+Common.h"
#import "BLTestObject.h"

@interface BLDiskDatabaseTests : XCTestCase

@end

@implementation BLDiskDatabaseTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    
    BLDatabase *database = [[BLStoreManager shareInstance] database];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    [database setSchemaVersion:1 withMigrationBlock:^(BLDatabaseConnection *databaseConnection, NSUInteger oldSchemaVersion) {
        //if (oldSchemaVersion == 0) {
            [BLTestObject createTableAndIndexInDatabaseConnection:databaseConnection];
            return ;
        //}
    }];
    
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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
    
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    int count = 100;
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    int count = 100;
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    int count = 100;
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    int count = 1;
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 20;
            object.name = @"alibaba";
            [connection insertObject:object];
        }
        
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection where:nil];
        XCTAssertTrue(testObject.isFault);
        NSMutableSet *targetFieldNames = [NSMutableSet setWithObjects:@"objectID", @"rowid", nil];
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
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    int count = 1;
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 20;
            object.name = @"alibaba";
            [connection insertObject:object];
        }
        
        BLTestObject *testObject = [BLTestObject findFirstObjectInDatabaseConnection:connection where:nil];
        XCTAssertTrue(testObject.isFault);
        testObject.name = @"alibaba1";
        testObject.groupName = @"alibaba1";
        XCTAssertFalse(testObject.isFault);
        
        NSMutableSet *targetFieldNames = [NSMutableSet setWithObjects:@"name", @"groupName", nil];
        XCTAssertEqualObjects(testObject.changedFieldNames, targetFieldNames);
    }];
}

@end
