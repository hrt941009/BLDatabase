//
//  BLFetchedResultsController.h
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/29.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BLFetchRequest.h"

@class BLDatabaseConnection;

@protocol BLFetchedResultsControllerDelegate;

@interface BLFetchedResultsController : NSObject

@property (nonatomic, strong, readonly) BLFetchRequest *request;
@property (nonatomic, copy, readonly) NSString *groupByKeyPath;
@property (nonatomic, assign, readonly) BOOL groupAscending;
@property (nonatomic, strong, readonly) Class objectClass;
@property (nonatomic, weak, readonly) BLDatabaseConnection *connection;
@property (nonatomic, weak) id<BLFetchedResultsControllerDelegate> delegate;

- (instancetype)initWithFetchRequest:(BLFetchRequest *)request
                      groupByKeyPath:(NSString *)groupByKeyPath
                      groupAscending:(BOOL)groupAscending
                         objectClass:(Class)objectClass
                inConnection:(BLDatabaseConnection *)connection;

- (void)performFetch;

- (NSIndexPath *)indexPathWithObject:(id)object;

- (id)objectAtIndexPath:(NSIndexPath *)indexPath;

- (NSUInteger)numberOfSections;

- (NSUInteger)numberOfRowsInSection:(NSUInteger)section;

- (NSString *)titleInSection:(NSUInteger)section;

- (NSArray *)sectionIndexTitles;

- (NSArray *)fetchedObjects;

- (NSUInteger)numberOfFetchedObjects;

@end

typedef NS_ENUM(NSUInteger, BLFetchedResultsChangeType) {
    BLFetchedResultsChangeInsert = 1,
    BLFetchedResultsChangeDelete = 2,
    BLFetchedResultsChangeUpdate = 3
};

@protocol BLFetchedResultsControllerDelegate <NSObject>

@optional

- (void)controller:(BLFetchedResultsController *)controller
didChangeWithIndexSet:(NSIndexSet *)indexSet
     forChangeType:(BLFetchedResultsChangeType)type;

- (void)controller:(BLFetchedResultsController *)controller
didChangeWithIndexPaths:(NSArray *)indexPaths
     forChangeType:(BLFetchedResultsChangeType)type;

- (void)controllerWillChangeContent:(BLFetchedResultsController *)controller;

- (void)controllerDidChangeContent:(BLFetchedResultsController *)controller;

@end
