//
//  BLRelationshipTest.m
//  BLDatabase
//
//  Created by alibaba on 15/5/20.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "BLStoreManager.h"
#import "BLDatabase.h"
#import "BLDatabaseConnection.h"
#import "BLBaseDBObject+Common.h"
#import "BLAccount.h"

@interface BLRelationshipTest : XCTestCase

@end

@implementation BLRelationshipTest

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    
    BLDatabase *database = [[BLStoreManager shareInstance] database];
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    [database setSchemaVersion:1 withMigrationBlock:^(BLDatabaseConnection *databaseConnection, NSUInteger oldSchemaVersion) {
        //if (oldSchemaVersion == 0) {
            [BLAccount createTableAndIndexInDatabaseConnection:databaseConnection];
            return ;
        //}
    }];
    
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLAccount findObjectsInDatabaseConnection:connection];
        [connection deleteObjects:result];
        
        result = [BLAccount findObjectsInDatabaseConnection:connection];
        XCTAssert([result count] == 0);
    }];
    
    NSArray *result = [BLAccount findObjectsInDatabaseConnection:connection];
    XCTAssert([result count] == 0);
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
    
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLAccount findObjectsInDatabaseConnection:connection];
        [connection deleteObjects:result];
        
        result = [BLAccount findObjectsInDatabaseConnection:connection];
        XCTAssert([result count] == 0);
    }];
    
    NSArray *result = [BLAccount findObjectsInDatabaseConnection:connection];
    XCTAssert([result count] == 0);
}

- (void)testOneToOne
{
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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
    BLDatabaseConnection *connection = [[BLStoreManager shareInstance] connection];
    
    [connection performBlockAndWaitInTransaction:^(BOOL *rollback) {
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

@end
