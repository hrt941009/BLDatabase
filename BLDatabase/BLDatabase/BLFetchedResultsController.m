//
//  BLFetchedResultsController.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/29.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "BLFetchedResultsController.h"
#import "BLFetchRequest.h"
#import "BLBaseDBObject.h"
#import "BLBaseDBObject+Private.h"
#import <UIKit/UIKit.h>
#import "BLDatabaseConfig.h"
#import "BLBaseDBObject+Common.h"
#import "BLDBChangedObject.h"
#import "BLDatabaseConnection.h"

#define sync_block_mainThread(block)   if([NSThread isMainThread]) { \
block(); \
} else { \
dispatch_sync(dispatch_get_main_queue(), block); \
}\

#define async_block_mainThread(block)   if([NSThread isMainThread]) { \
block(); \
} else { \
dispatch_async(dispatch_get_main_queue(), block); \
}\

#pragma mark - BLFetchedResultsSectionInfo

@interface BLFetchedResultsSectionInfo : NSObject <NSCopying>

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger offset;
@property (nonatomic, assign) NSInteger length;

@end

@implementation BLFetchedResultsSectionInfo

- (id)copyWithZone:(NSZone *)zone
{
    BLFetchedResultsSectionInfo *copy = [[self class] allocWithZone:zone];
    copy.name = self.name;
    copy.offset = self.offset;
    copy.length = self.length;
    return copy;
}

@end

#pragma mark - BLFetchedResultsController

@interface BLFetchedResultsController ()

@property (nonatomic, strong) BLFetchRequest *request;
@property (nonatomic, copy) NSString *groupByKeyPath;
@property (nonatomic, assign) BOOL groupAscending;
@property (nonatomic, strong) Class objectClass;
@property (nonatomic, weak) BLDatabaseConnection *connection;
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, assign) BOOL hasGroup;

@property (nonatomic, strong) NSSortDescriptor *groupSortDescriptor;
@property (nonatomic, strong) NSArray *sortDescriptorsInGroup;
@property (nonatomic, strong) NSArray *allSortDescriptors;

@property (nonatomic, strong) NSMutableArray *sections;
@property (nonatomic, strong) NSMutableDictionary *indexPathMapping;
@property (nonatomic, strong) NSMutableArray *sortedObjects;

@property (nonatomic, assign) int64_t fetchedId;

@end

@implementation BLFetchedResultsController

- (instancetype)initWithFetchRequest:(BLFetchRequest *)request
                      groupByKeyPath:(NSString *)groupByKeyPath
                      groupAscending:(BOOL)groupAscending
                         objectClass:(Class)objectClass
                inConnection:(BLDatabaseConnection *)connection
{
    if (![objectClass isSubclassOfClass:[BLBaseDBObject class]] || !connection) {
        NSAssert(false, @"objectClass must be subclass of BLBaseDBObject, database must not be nil");
        return nil;
    }
    
    self = [super init];
    if (self) {
        self.request = request;
        self.groupByKeyPath = groupByKeyPath;
        self.groupAscending = groupAscending;
        self.objectClass = objectClass;
        self.connection = connection;
        self.indexPathMapping = [NSMutableDictionary dictionary];
        self.sections = [NSMutableArray array];
        self.sortedObjects = [NSMutableArray array];
        self.hasGroup = self.groupByKeyPath != nil;
        if (self.hasGroup) {
            self.groupSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:self.groupByKeyPath ascending:self.groupAscending];
        }
        
        [self addDatabaseObserver];
    }
    
    return self;
}

- (void)performFetch
{
    NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
    // sql 查询
    __block NSArray *objects = nil;
    [self.connection performReadBlockAndWait:^{
        objects = [self.objectClass findObjectsInConnection:self.connection
                                                 fieldNames:self.request.fieldNames
                                                      where:self.request.sqlAfterWhere];
    }];
    
    NSTimeInterval time2 = [[NSDate date] timeIntervalSince1970];
    BLLogInfo(@"find from db time duration = %lf", time2 - time1);
    
    NSArray *sortDescriptors = nil;
    if (self.request.sortDescriptors) {
        sortDescriptors = self.request.sortDescriptors;
    } else {
        sortDescriptors = [[self class] sortDescriptorsWithSortTerm:self.request.sortTerm];
    }
    
    NSMutableArray *newSortDescriptors = [NSMutableArray array];
    if (sortDescriptors) {
        [newSortDescriptors addObjectsFromArray:sortDescriptors];
    }
    
    BOOL hasRowidSort = NO;
    NSString *rowidFieldName = [self.objectClass rowidFieldName];
    for (NSSortDescriptor *sortDescriptor in newSortDescriptors) {
        if ([sortDescriptor.key isEqualToString:rowidFieldName]) {
            hasRowidSort = YES;
            break;
        }
    }
    if (!hasRowidSort) {
        [newSortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:rowidFieldName ascending:NO]];
    }
    self.sortDescriptorsInGroup = newSortDescriptors;
    
    NSMutableArray *allSortDescriptors = [NSMutableArray array];
    if (self.hasGroup) {
        [allSortDescriptors addObject:self.groupSortDescriptor];
    }
    [allSortDescriptors addObjectsFromArray:newSortDescriptors];
    self.allSortDescriptors = [allSortDescriptors copy];
    
    // sort
    NSArray *sortedObjects = [objects sortedArrayUsingDescriptors:self.allSortDescriptors];
    NSTimeInterval time3 = [[NSDate date] timeIntervalSince1970];
    BLLogInfo(@"sort time duration = %lf", time3 - time2);
    
    // filter
    NSArray *evaluativeObjects = [self evaluativeObjectsWithObjects:sortedObjects];
    NSTimeInterval time4 = [[NSDate date] timeIntervalSince1970];
    BLLogInfo(@"filter time duration = %lf", time4 - time3);
    
    // sections
    [self generateSectionsWithObjects:evaluativeObjects];
    self.sortedObjects = [NSMutableArray arrayWithArray:evaluativeObjects];
    _fetchedId++;
    BLLogInfo(@"perform fetch time duration = %lf, count = %tu", [[NSDate date] timeIntervalSince1970] - time1, [self.sortedObjects count]);
}

- (void)performFetchWithCompleteBlock:(void(^)(void))completeBlock
{
    [self.connection performReadBlock:^{
        NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
        // sql 查询
        NSArray *objects = [self.objectClass findObjectsInConnection:self.connection
                                                 fieldNames:self.request.fieldNames
                                                      where:self.request.sqlAfterWhere];
        async_block_mainThread(^{
            NSTimeInterval time2 = [[NSDate date] timeIntervalSince1970];
            BLLogInfo(@"find from db time duration = %lf", time2 - time1);
            
            NSArray *sortDescriptors = nil;
            if (self.request.sortDescriptors) {
                sortDescriptors = self.request.sortDescriptors;
            } else {
                sortDescriptors = [[self class] sortDescriptorsWithSortTerm:self.request.sortTerm];
            }
            
            NSMutableArray *newSortDescriptors = [NSMutableArray array];
            if (sortDescriptors) {
                [newSortDescriptors addObjectsFromArray:sortDescriptors];
            }
            
            BOOL hasRowidSort = NO;
            NSString *rowidFieldName = [self.objectClass rowidFieldName];
            for (NSSortDescriptor *sortDescriptor in newSortDescriptors) {
                if ([sortDescriptor.key isEqualToString:rowidFieldName]) {
                    hasRowidSort = YES;
                    break;
                }
            }
            if (!hasRowidSort) {
                [newSortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:rowidFieldName ascending:NO]];
            }
            self.sortDescriptorsInGroup = newSortDescriptors;
            
            NSMutableArray *allSortDescriptors = [NSMutableArray array];
            if (self.hasGroup) {
                [allSortDescriptors addObject:self.groupSortDescriptor];
            }
            [allSortDescriptors addObjectsFromArray:newSortDescriptors];
            self.allSortDescriptors = [allSortDescriptors copy];
            
            // sort
            NSArray *sortedObjects = [objects sortedArrayUsingDescriptors:self.allSortDescriptors];
            NSTimeInterval time3 = [[NSDate date] timeIntervalSince1970];
            BLLogInfo(@"sort time duration = %lf", time3 - time2);
            
            // filter
            NSArray *evaluativeObjects = [self evaluativeObjectsWithObjects:sortedObjects];
            NSTimeInterval time4 = [[NSDate date] timeIntervalSince1970];
            BLLogInfo(@"filter time duration = %lf", time4 - time3);
            
            // sections
            [self generateSectionsWithObjects:evaluativeObjects];
            self.sortedObjects = [NSMutableArray arrayWithArray:evaluativeObjects];
            _fetchedId++;
            BLLogInfo(@"perform fetch time duration = %lf, count = %tu", [[NSDate date] timeIntervalSince1970] - time1, [self.sortedObjects count]);
            
            if (completeBlock) {
                completeBlock();
            }
        });
    }];
}

/*
- (BOOL)performFetch:(NSError **)error
{
    BLLogInfo(@"begin perform fetch");
    NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
    // sql 查询
    NSArray *objects = [self.objectClass findObjectsInDatabase:self.database
                                                    fieldNames:self.request.fieldNames
                                                         where:self.request.filterWhere];
    
    BLLogInfo(@"find from db time duration = %lf", [[NSDate date] timeIntervalSince1970] - time1);
    
    BOOL hasRowidSort = NO;
    NSMutableArray *newSortDescriptors = [NSMutableArray arrayWithArray:self.request.sortDescriptors];
    for (NSSortDescriptor *sortDescriptor in newSortDescriptors) {
        if ([sortDescriptor.key isEqualToString:@"rowid"]) {
            hasRowidSort = YES;
            break;
        }
    }
    if (!hasRowidSort) {
        [newSortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"rowid" ascending:NO]];
    }
    self.request.sortDescriptors = newSortDescriptors;
    
    // sort
    NSMutableArray *sortDescriptors = [NSMutableArray array];
    if (self.groupSortDescriptor) {
        [sortDescriptors addObject:self.groupSortDescriptor];
    }
    if (self.request.sortDescriptors) {
        [sortDescriptors addObjectsFromArray:self.request.sortDescriptors];
    }
    
    // sort
    objects = [objects sortedArrayUsingDescriptors:sortDescriptors];
    BLLogInfo(@"sort time duration = %lf", [[NSDate date] timeIntervalSince1970] - time1);
    
    // filter
    NSArray *evaluativeObjects = [self evaluativeObjectsWithObjects:objects];
    
    BLLogInfo(@"filter time duration = %lf", [[NSDate date] timeIntervalSince1970] - time1);
    
    // sections
    [self generateSectionsWithObjects:evaluativeObjects];
    self.sortedObjects = [NSMutableArray arrayWithArray:evaluativeObjects];
    BLLogInfo(@"end perform fetch");
    BLLogInfo(@"perform fetch time duration = %lf, count = %ld", [[NSDate date] timeIntervalSince1970] - time1, [self.sortedObjects count]);
    
    return YES;
}
 */

- (void)dealloc
{
    [self removeDatabaseObserver];
}

#pragma mark - observer

- (void)addDatabaseObserver
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleDatabaseChangedNotification:)
                                                 name:BLDatabaseChangedNotification
                                               object:self.connection.database];
}

- (void)removeDatabaseObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleDatabaseChangedWithInsertObjects:(NSMutableArray *)insertObjects
                                 updateObjects:(NSMutableArray *)updateObjects
                                 deleteObjects:(NSMutableArray *)deleteObjects
{
    NSMutableArray *copySections = [[NSMutableArray alloc] initWithArray:self.sections copyItems:YES];
    NSMutableArray *copySortObjects = [[NSMutableArray alloc] initWithArray:self.sortedObjects];
    
    // 建立mapping
    NSMutableDictionary *indexPathMapping = [NSMutableDictionary dictionary];
    NSMutableArray *indexPaths = [NSMutableArray array];
    for (id object in updateObjects) {
        NSIndexPath *indexPath = [self.indexPathMapping valueForKey:[self keyWithUniqueId:[object uniqueId]]];
        [indexPaths addObject:indexPath];
        
        [indexPathMapping setObject:object forKey:[self keyWithIndexPath:indexPath]];
    }
    
    for (id object in deleteObjects) {
        NSIndexPath *indexPath = [self.indexPathMapping valueForKey:[self keyWithUniqueId:[object uniqueId]]];
        [indexPaths addObject:indexPath];
    }
    
    [indexPaths sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"section" ascending:YES],
                                       [NSSortDescriptor sortDescriptorWithKey:@"row" ascending:YES]]];
    
    NSInteger preSection = 0;
    NSInteger allDeleteCount = 0;
    NSInteger deleteCountInSection = 0;
    NSMutableArray *indexesToRemove = [NSMutableArray array];
    
    BLLogDebug(@"remove update objects");
    for (NSIndexPath *indexPath in indexPaths) {
        if (!indexPathMapping[[self keyWithIndexPath:indexPath]]) {
            // 非update object跳过
            continue;
        }
        
        NSInteger currentSection = indexPath.section;
        if (preSection < currentSection) {
            deleteCountInSection = 0;
            
            for (NSInteger index = preSection + 1; index <= currentSection; index++) {
                BLFetchedResultsSectionInfo *sectionInfo = copySections[index];
                sectionInfo.offset -= allDeleteCount;
            }
        }
        
        preSection = currentSection;
        BLFetchedResultsSectionInfo *currentSectionInfo = copySections[currentSection];
        currentSectionInfo.length--;
        
        // 更新要删除对象的index
        NSInteger indexToRemove = currentSectionInfo.offset + indexPath.row + allDeleteCount - deleteCountInSection;
        [indexesToRemove addObject:@(indexToRemove)];
        
        allDeleteCount++;
        deleteCountInSection++;
    }
    
    // 更新后续section的offset
    for (NSInteger index = preSection + 1; index < [copySections count]; index++) {
        BLFetchedResultsSectionInfo *sectionInfo = copySections[index];
        sectionInfo.offset -= allDeleteCount;
    }
    
    // 更新数据源
    NSMutableArray *tempSortedObjects = [NSMutableArray array];
    NSInteger index = 0;
    NSInteger index1 = 0;
    for (id object in copySortObjects) {
        if (index1 < [indexesToRemove count]) {
            NSInteger indexToRemove = [indexesToRemove[index1] integerValue];
            
            if (index == indexToRemove) {
                index1++;
                index++;
                continue;
            }
        }
        [tempSortedObjects addObject:object];
        index++;
    }
    copySortObjects = tempSortedObjects;
    
    BLLogDebug(@"deal update & delete objects");
    NSMutableArray *reloadIndexPaths = [NSMutableArray array];
    NSMutableArray *deleteIndexPaths = [NSMutableArray array];
    NSMutableArray *newCopySections = [[NSMutableArray alloc] initWithArray:copySections copyItems:YES];
    
    preSection = 0;
    NSInteger allChangedCount = 0;
    NSInteger insertCountInSection = 0;
    deleteCountInSection = 0;
    NSMutableArray *indexesToAdd = [NSMutableArray array];
    NSMutableArray *objectsToAdd = [NSMutableArray array];
    [indexesToRemove removeAllObjects];
    
    for (NSIndexPath *indexPath in indexPaths) {
        NSInteger currentSection = indexPath.section;
        if (preSection < currentSection) {
            deleteCountInSection = 0;
            insertCountInSection = 0;
            
            for (NSInteger index = preSection + 1; index <= currentSection; index++) {
                BLFetchedResultsSectionInfo *sectionInfo = copySections[index];
                sectionInfo.offset += allChangedCount;
            }
        }
        
        preSection = currentSection;
        id object = indexPathMapping[[self keyWithIndexPath:indexPath]];
        if (object) {
            BOOL foundSection = NO;
            NSUInteger section = [self sectionWithObject:object
                                                sections:newCopySections
                                                 isFound:&foundSection];
            
            if (foundSection && section == currentSection) {
                BOOL foundRow = NO;
                NSUInteger row = [self rowWithObject:object
                                           inSection:section
                                            sections:newCopySections
                                       sortedObjects:copySortObjects
                                             isFound:&foundRow];
                
                if (row + deleteCountInSection + insertCountInSection == indexPath.row) {
                    // // update object for reload
                    BLFetchedResultsSectionInfo *sectionInfo = copySections[section];
                    sectionInfo.length++;
                    
                    [indexesToAdd addObject:@([self.sections[indexPath.section] offset] + indexPath.row)];
                    [objectsToAdd addObject:object];
                    [reloadIndexPaths addObject:indexPath];
                    
                    allChangedCount++;
                    insertCountInSection++;
                } else {
                    // update object for insert & delete
                    [deleteIndexPaths addObject:indexPath];
                    [insertObjects addObject:object];
                    [indexesToRemove addObject:@([self.sections[indexPath.section] offset] + indexPath.row)];
                    
                    deleteCountInSection++;
                }
            } else {
                // update object for insert & delete
                [deleteIndexPaths addObject:indexPath];
                [insertObjects addObject:object];
                [indexesToRemove addObject:@([self.sections[indexPath.section] offset] + indexPath.row)];
                
                deleteCountInSection++;
            }
        } else {
            // delete object for delete
            BLFetchedResultsSectionInfo *sectionInfo = copySections[currentSection];
            sectionInfo.length--;
            //[deleteIndexPaths addObject:@(sectionInfo.offset + indexPath.row - deleteCountInSection)];
            //[copySortObjects removeObjectAtIndex:sectionInfo.offset + indexPath.row - deleteCountInSection];
            [deleteIndexPaths addObject:indexPath];
            [indexesToRemove addObject:@([self.sections[indexPath.section] offset] + indexPath.row)];
            
            allChangedCount--;
            deleteCountInSection++;
        }
    }
    
    for (NSInteger index = preSection + 1; index < [copySections count]; index++) {
        BLFetchedResultsSectionInfo *sectionInfo = copySections[index];
        sectionInfo.offset += allChangedCount;
    }
    
    // 更新数据源
    tempSortedObjects = [NSMutableArray array];
    index = 0;
    index1 = 0;
    NSInteger index2 = 0;
    for (id object in self.sortedObjects) {
        if (index1 < [indexesToAdd count]) {
            NSInteger indexToAdd = [indexesToAdd[index1] integerValue];
            if (index == indexToAdd) {
                [tempSortedObjects addObject:objectsToAdd[index1]];
                index1++;
                index++;
                
                continue;
            }
        }
        
        if (index2 < [indexesToRemove count]) {
            NSInteger indexToRemove = [indexesToRemove[index2] integerValue];
            
            if (index == indexToRemove) {
                index2++;
                index++;
                
                continue;
            }
        }
        
        [tempSortedObjects addObject:object];
        index++;
    }
    for (; index1 < [indexesToAdd count]; index1++) {
        [tempSortedObjects addObject:objectsToAdd[index1]];
    }
    
    copySortObjects = tempSortedObjects;
    
    BLLogDebug(@"deal insert objects");
    NSMutableArray *insertIndexPaths = [NSMutableArray array];
    NSMutableIndexSet *insertSections = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *deleteSections = [NSMutableIndexSet indexSet];
    [indexesToAdd removeAllObjects];
    [objectsToAdd removeAllObjects];
    preSection = -1;
    NSString *preGroupName = nil;
    NSInteger insertSectionCount = 0;
    NSInteger deleteSectionCount = 0;
    insertCountInSection = 0;
    
    [insertObjects sortUsingDescriptors:self.allSortDescriptors];
    if ([[copySections lastObject] offset] + [[copySections lastObject] length] != [copySortObjects count]) {
        BLLogError(@"data is wrong");
    }
    
    for (id object in insertObjects) {
        NSString *currentGroupName = [self groupNameForObject:object];
        
        BOOL foundSection = NO;
        NSUInteger section = [self sectionWithObject:object
                                            sections:copySections
                                             isFound:&foundSection];
        
        if (![preGroupName isEqualToString:currentGroupName]) {
            preGroupName = currentGroupName;
            insertCountInSection = 0;
            
            for (NSInteger index = preSection + 1; index < section + insertSectionCount; index++) {
                BLFetchedResultsSectionInfo *sectionInfo = copySections[index - insertSectionCount];
                if (self.hasGroup && sectionInfo.length == 0) {
                    [deleteSections addIndex:index - insertSectionCount];
                    deleteSectionCount++;
                }
            }
            
            if (!foundSection) {
                [insertSections addIndex:section + insertSectionCount - deleteSectionCount];
                insertSectionCount++;
            }
        }
        
        NSInteger finalSection = section + insertSectionCount - deleteSectionCount - (foundSection ? 0 : 1);
        preSection = section + insertSectionCount - (foundSection ? 0 : 1);
        NSUInteger row = 0;
        NSInteger index = 0;
        NSIndexPath *indexPath = nil;
        if (foundSection) {
            BOOL foundRow = NO;
            row = [self rowWithObject:object
                            inSection:section
                             sections:copySections
                        sortedObjects:copySortObjects
                              isFound:&foundRow];
            if (foundRow) {
                NSAssert(false, @"insert data must not be found");
            }
            
            indexPath = [NSIndexPath indexPathForRow:row + insertCountInSection inSection:finalSection];
            index = [copySections[section] offset] + row;// + insertCountInSection;
        } else {
            indexPath = [NSIndexPath indexPathForRow:row + insertCountInSection inSection:finalSection];
            if (section > 0 && section < [copySections count] + 1) {
                index = [copySections[section - 1] offset] + [copySections[section - 1] length] + row;// + insertCountInSection;
            } else if (section == 0) {
                index = row;
            } else {
                index = [[copySections lastObject] offset] + [[copySections lastObject] length] + row;// + insertCountInSection;
            }
        }
        
        if (foundSection) {
            [insertIndexPaths addObject:indexPath];
        }
        [indexesToAdd addObject:@(index)];
        [objectsToAdd addObject:object];
        insertCountInSection++;
    }
    
    for (NSInteger index = preSection + 1; index < [copySections count] + insertSectionCount; index++) {
        BLFetchedResultsSectionInfo *sectionInfo = copySections[index - insertSectionCount];
        if (self.hasGroup && sectionInfo.length == 0) {
            [deleteSections addIndex:index - insertSectionCount];
            deleteSectionCount++;
        }
    }
    
    tempSortedObjects = [NSMutableArray array];
    index = 0;
    index1 = 0;
    NSInteger indexToAdd = 0;
    for (id object in copySortObjects) {
        while (index1 < [objectsToAdd count]) {
            indexToAdd = [indexesToAdd[index1] integerValue];
            if (indexToAdd == index) {
                [tempSortedObjects addObject:objectsToAdd[index1]];
                index1++;
            } else {
                break;
            }
        }
        
        [tempSortedObjects addObject:object];
        index++;
    }
    
    for (;index1 < [objectsToAdd count]; index1++) {
        [tempSortedObjects addObject:objectsToAdd[index1]];
    }
    
    // insert indexpath in insert section, delete indexpath in delete section should be remove, or lead to tableview update crash,
    // eg: reload indexPath [0, 0]; insert section [0]; insertindexPath [0, 0];
    BLLogDebug(@"fix reload indexPaths");
    NSMutableArray *tempDeleteIndexPaths = [NSMutableArray array];
    for (NSIndexPath *indexPath in deleteIndexPaths) {
        if (![deleteSections containsIndex:indexPath.section]) {
            [tempDeleteIndexPaths addObject:indexPath];
        }
    }
    deleteIndexPaths = tempDeleteIndexPaths;
    [self generateSectionsWithObjects:tempSortedObjects];
    self.sortedObjects = tempSortedObjects;
    
    if (self.delegate && ([insertSections count] > 0 || [deleteSections count] > 0 || [insertIndexPaths count] > 0 ||
                          [reloadIndexPaths count] > 0 || [deleteIndexPaths count] > 0)) {
        //BLLogInfo(@"insert sections = %@", insertSections);
        //BLLogInfo(@"delete sections = %@", deleteSections);
        //BLLogInfo(@"insert indexpaths = %@", insertIndexPaths);
        //BLLogInfo(@"reload indexpaths = %@", reloadIndexPaths);
        //BLLogInfo(@"delete indexpaths = %@", deleteIndexPaths);
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(controllerWillChangeContent:)]) {
            [self.delegate controllerWillChangeContent:self];
        }
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(controller:didChangeWithIndexSet:forChangeType:)]) {
            [self.delegate controller:self didChangeWithIndexSet:insertSections forChangeType:BLFetchedResultsChangeInsert];
            [self.delegate controller:self didChangeWithIndexSet:deleteSections forChangeType:BLFetchedResultsChangeDelete];
        }
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(controller:didChangeWithIndexPaths:forChangeType:)]) {
            [self.delegate controller:self didChangeWithIndexPaths:insertIndexPaths forChangeType:BLFetchedResultsChangeInsert];
            [self.delegate controller:self didChangeWithIndexPaths:deleteIndexPaths forChangeType:BLFetchedResultsChangeDelete];
            [self.delegate controller:self didChangeWithIndexPaths:reloadIndexPaths forChangeType:BLFetchedResultsChangeUpdate];
        }
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(controllerDidChangeContent:)]) {
            [self.delegate controllerDidChangeContent:self];
        }
    }
}

- (void)handleDatabaseChangedNotification:(NSNotification *)notification
{
    NSNumber *fetchedId = @(_fetchedId);
    [self.connection performReadBlock:^{
        if ([fetchedId longLongValue] == self.fetchedId) {
            // insertObjects updateForNewObjects updateForOldObjects deleteObjects不能有相同的对象，否则更新出错
            NSArray *insertObjects = [self insertObjectsWithNotification:notification];
            NSDictionary *updateObjectsMap = [self updateObjectsMapWithNotification:notification];
            NSArray *deleteObjects = [self deleteObjectsWithNotification:notification];
            
            async_block_mainThread(^{
                NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
                if (fetchedId.longLongValue == self.fetchedId) {
                    NSMutableArray *finalInsertObjects = [NSMutableArray array];
                    NSMutableArray *finalUpdateObjects = [NSMutableArray array];
                    NSMutableArray *finalDeleteObjects = [NSMutableArray array];
                    
                    for (id object in insertObjects) {
                        if ([[self class] evaluateObject:object request:self.request]) {
                            NSIndexPath *indexPath = self.indexPathMapping[[self keyWithUniqueId:[object uniqueId]]];
                            if (!indexPath) {
                                [finalInsertObjects addObject:object];
                            }
                        }
                    }
                    
                    for (NSString *uniqueId in updateObjectsMap) {
                        NSIndexPath *indexPath = self.indexPathMapping[[self keyWithUniqueId:uniqueId]];
                        id object = updateObjectsMap[uniqueId];
                        BOOL isValid = NO;
                        if (object != [NSNull null]) {
                            isValid = [[self class] evaluateObject:object request:self.request];
                        }
                        
                        if (indexPath && isValid) {
                            [finalUpdateObjects addObject:object];
                        } else if (indexPath && !isValid) {
                            [finalDeleteObjects addObject:object];
                        } else if (!indexPath && isValid) {
                            [finalInsertObjects addObject:object];
                        }
                    }
                    
                    for (id object in deleteObjects) {
                        NSIndexPath *indexPath = self.indexPathMapping[[self keyWithUniqueId:[object uniqueId]]];
                        if (indexPath) {
                            [finalDeleteObjects addObject:object];
                        }
                    }
                    
                    BLLogInfo(@"-----begin handle db change, insert count = %tu, update count = %tu, delete count = %tu", [finalInsertObjects count], [finalUpdateObjects count], [finalDeleteObjects count]);
                    
                    if ([finalInsertObjects count] > 0 || [finalUpdateObjects count] > 0 || [finalDeleteObjects count] > 0) {
                        [self handleDatabaseChangedWithInsertObjects:finalInsertObjects
                                                       updateObjects:finalUpdateObjects
                                                       deleteObjects:finalDeleteObjects];
                    }
                    BLLogInfo(@"-----end handle db change, handle db change time duration = %lf", [[NSDate date] timeIntervalSince1970] - time1);
                }
            });
        }
    }];
}

- (NSArray *)insertObjectsWithNotification:(NSNotification *)notification
{
    NSMutableArray *insertObjects = [NSMutableArray array];
    NSMutableArray *insertUniqueIds = [NSMutableArray array];
    
    for (BLDBChangedObject *changedObject in [notification.userInfo objectForKey:BLDatabaseInsertKey]) {
        if ([[self.objectClass tableName] isEqualToString:[changedObject tableName]]) {
            [insertUniqueIds addObject:changedObject.uniqueId];
        }
    }
    
    NSUInteger fetchBatchSize = 50;
    NSUInteger allCount = [insertUniqueIds count];
    for (int i = 0; i < allCount; i += fetchBatchSize) {
        NSUInteger length = MIN(fetchBatchSize, allCount - i);
        NSArray *subArray = [insertUniqueIds subarrayWithRange:NSMakeRange(i, length)];
        NSMutableString *tempString = [NSMutableString stringWithFormat:@"("];
        for (int i = 0; i < length; i++) {
            [tempString appendFormat:@"?"];
            if (i != length - 1) {
                [tempString appendString:@","];
            }
        }
        [tempString appendString:@")"];
        
        NSArray *result = [self.objectClass findObjectsInConnection:self.connection
                                                              where:[NSString stringWithFormat:@"%@ IN %@", [self.objectClass uniqueIdFieldName], tempString]
                                                          arguments:subArray];
        [insertObjects addObjectsFromArray:result];
    }
    
    return insertObjects;
}

- (NSDictionary *)updateObjectsMapWithNotification:(NSNotification *)notification
{
    NSMutableDictionary *updateObjectsMap = [NSMutableDictionary dictionary];
    NSMutableArray *updateUniqueIds = [NSMutableArray array];
    
    for (BLDBChangedObject *changedObject in [notification.userInfo objectForKey:BLDatabaseUpdateKey]) {
        if ([[self.objectClass tableName] isEqualToString:[changedObject tableName]]) {
            [updateUniqueIds addObject:changedObject.uniqueId];
        }
    }
    
    NSUInteger fetchBatchSize = 50;
    NSUInteger allCount = [updateUniqueIds count];
    for (int i = 0; i < allCount; i += fetchBatchSize) {
        NSUInteger length = MIN(fetchBatchSize, allCount - i);
        NSArray *subArray = [updateUniqueIds subarrayWithRange:NSMakeRange(i, length)];
        NSMutableString *tempString = [NSMutableString stringWithFormat:@"("];
        for (int i = 0; i < length; i++) {
            [tempString appendFormat:@"?"];
            if (i != length - 1) {
                [tempString appendString:@","];
            }
        }
        [tempString appendString:@")"];
        
        NSArray *result = [self.objectClass findObjectsInConnection:self.connection
                                                              where:[NSString stringWithFormat:@"%@ IN %@", [self.objectClass uniqueIdFieldName], tempString]
                                                          arguments:subArray];
        NSUInteger resultCount = [result count];
        int missCount = 0;
        for (int i = 0; i < length; i++) {
            NSString *uniqueId = subArray[i];
            if (i < resultCount) {
                id object = result[i-missCount];
                if ([uniqueId isEqualToString:[object uniqueId]]) {
                    [updateObjectsMap setValue:object forKey:uniqueId];
                } else {
                    [updateObjectsMap setValue:[NSNull null] forKey:uniqueId];
                    missCount++;
                }
            } else {
                [updateObjectsMap setValue:[NSNull null] forKey:uniqueId];
            }
        }
    }
    
    return updateObjectsMap;
}

- (NSArray *)deleteObjectsWithNotification:(NSNotification *)notification
{
    NSMutableArray *deleteObjects = [NSMutableArray array];
    for (BLDBChangedObject *changedObject in [notification.userInfo objectForKey:BLDatabaseDeleteKey]) {
        if ([[self.objectClass tableName] isEqualToString:[changedObject tableName]]) {
            id object = [self.objectClass new];
            [object setUniqueId:changedObject.uniqueId];
            [deleteObjects addObject:object];
        }
    }
    
    return deleteObjects;
}

#pragma mark - indexPath & object

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger section = indexPath.section;
    NSUInteger row = indexPath.row;
    if (section >= [self.sections count]) {
        return nil;
    } else {
        BLFetchedResultsSectionInfo *sectionInfo = self.sections[section];
        if (row >= sectionInfo.length) {
            return nil;
        } else {
            return self.sortedObjects[sectionInfo.offset + row];
        }
    }
}

- (NSUInteger)numberOfSections
{
    return [self.sections count];
}

- (NSUInteger)numberOfRowsInSection:(NSUInteger)section
{
    if (section >= [self.sections count]) {
        return 0;
    } else {
        return [self.sections[section] length];
    }
}

- (NSString *)titleInSection:(NSUInteger)section
{
    if (section >= [self.sections count]) {
        return nil;
    } else {
        return [self.sections[section] name];
    }
}

- (NSArray *)sectionIndexTitles
{
    NSMutableArray *titles = [NSMutableArray array];
    for (BLFetchedResultsSectionInfo *sectionInfo in self.sections) {
        NSString *name = sectionInfo.name;
        name = name ? name : @"";
        [titles addObject:name];
    }
    
    return titles;
}

- (NSArray *)fetchedObjects
{
    BLFetchedResultsSectionInfo *sectionInfo = [self.sections lastObject];
    if (sectionInfo) {
        NSRange range = NSMakeRange(0, sectionInfo.offset + sectionInfo.length);
        return [self.sortedObjects subarrayWithRange:range];
    } else {
        return [NSArray array];
    }
}

- (NSUInteger)numberOfFetchedObjects
{
    BLFetchedResultsSectionInfo *sectionInfo = [self.sections lastObject];
    if (sectionInfo) {
        return sectionInfo.offset + sectionInfo.length;
    } else {
        return 0;
    }
}

#pragma mark - NSIndexPath

- (NSIndexPath *)indexPathWithObject:(id)object
{
    return [self.indexPathMapping valueForKey:[self keyWithUniqueId:[object uniqueId]]];
}

- (NSUInteger)sectionWithObject:(id)object
                        isFound:(BOOL *)isFound
{
    return [self sectionWithObject:object sections:self.sections isFound:isFound];
}

- (NSUInteger)sectionWithObject:(id)object
                       sections:(NSArray *)sections
                        isFound:(BOOL *)isFound
{
    NSUInteger section = NSNotFound;
    BLFetchedResultsSectionInfo *sectionInfo = [BLFetchedResultsSectionInfo new];
    sectionInfo.name = [self groupNameForObject:object];
    
    NSString *keyPath = @"name";
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:keyPath ascending:self.groupAscending];
    section = [self indexWithObject:sectionInfo
                            inArray:sections
                            keyPath:keyPath
                            isFound:isFound
                    sortDescriptors:@[sortDescriptor]];
    
    return section;
}

- (NSUInteger)rowWithObject:(id)object
                  inSection:(NSInteger)section
                    isFound:(BOOL *)isFound
{
    return [self rowWithObject:object
                     inSection:section
                      sections:self.sections
                 sortedObjects:self.sortedObjects
                       isFound:isFound];
}

- (NSUInteger)rowWithObject:(id)object
                  inSection:(NSInteger)section
                   sections:(NSArray *)sections
              sortedObjects:(NSArray *)sortedObjects
                    isFound:(BOOL *)isFound
{
    NSUInteger row = NSNotFound;
    NSRange range = NSMakeRange([sections[section] offset], [sections[section] length]);
    NSArray *array = [sortedObjects subarrayWithRange:range];
    
    NSString *keyPath = [[object class] uniqueIdFieldName];
    row = [self indexWithObject:object
                        inArray:array
                        keyPath:keyPath
                        isFound:isFound
                sortDescriptors:self.sortDescriptorsInGroup];
    
    return row;
}

#pragma mark - find

/*
- (NSUInteger)indexWithObject:(id)object
                      inArray:(NSArray *)array
                      keyPath:(NSString *)keyPath
                      isFound:(BOOL *)isFound
                    sortBlock:(BLSortBlock)sortBlock
                    ascending:(BOOL)ascending
{
    if (!sortBlock) {
        for (NSUInteger i = 0; i < [array count]; i++) {
            id tempObject = array[i];
            id value1 = [tempObject valueForKeyPath:keyPath];
            id value2 = [object valueForKey:keyPath];
            if ([self compareValue1:value1 value2:value2] == NSOrderedSame) {
                *isFound = YES;
                
                return i;
            }
        }
        
        *isFound = NO;
        if (ascending) {
            return 0;
        } else {
            return [array count];
        }
    } else {
        NSInteger mid = 0;
        NSInteger min = 0;
        NSInteger max = [array count] - 1;
        BOOL found = NO;
        
        while (min <= max) {
            mid = (min + max)/2;
            id tempObject = array[mid];
            
            NSComparisonResult result = sortBlock(object, tempObject);
            if (result == NSOrderedAscending) {
                max = mid - 1;
            } else if (result == NSOrderedDescending) {
                min = mid + 1;
            } else {
                id value1 = [tempObject valueForKeyPath:keyPath];
                id value2 = [object valueForKey:keyPath];
                if ([self compareValue1:value1 value2:value2] == NSOrderedSame) {
                    found = YES;
                    break;
                }
                
                // 线性查找sort keys相同  uuid不同
                NSInteger firtSameIndex = NSNotFound;
                NSInteger lastSameIndex = NSNotFound;
                for (NSInteger i = min; i <= max; i++) {
                    tempObject = array[i];
                    NSComparisonResult temp = sortBlock(object, tempObject);
                    if (temp != NSOrderedSame && lastSameIndex != NSNotFound) {
                        // 找到最后一个相等 跳出循环
                        break;
                    } else if (temp == NSOrderedSame) {
                        if (firtSameIndex == NSNotFound) {
                            firtSameIndex = i;
                        }
                        lastSameIndex = i;
                        if ([self compareValue1:value1 value2:value2] == NSOrderedSame) {
                            mid = i;
                            found = YES;
                            break;
                        }
                    }
                }
                
                if (!found) {
                    if (ascending) {
                        mid = firtSameIndex;
                    } else {
                        mid = lastSameIndex + 1;
                    }
                    
                    *isFound = found;
                    return mid;
                }
                break;
            }
        }
        
        if (!found) {
            BLLogDebug(@"The number was not found.");
        }
        *isFound = found;
        
        if (found) {
            return mid;
        } else {
            return MAX(min, max);
        }
    }
}
 */

- (NSUInteger)indexWithObject:(id)object
                      inArray:(NSArray *)array
                      keyPath:(NSString *)keyPath
                      isFound:(BOOL *)isFound
              sortDescriptors:(NSArray *)sortDescriptors
{
    if ([sortDescriptors count] < 1) {
        BOOL ascending = YES;
        for (NSUInteger i = 0; i < [array count]; i++) {
            id tempObject = array[i];
            NSComparisonResult result = [self compareObject1:object
                                                     object2:tempObject
                                             sortDescriptors:sortDescriptors
                                                   ascending:&ascending];
            if (result == NSOrderedSame) {
                id value1 = [object valueForKeyPath:keyPath];
                id value2 = [tempObject valueForKeyPath:keyPath];
                if ([self compareValue1:value1 value2:value2] == NSOrderedSame) {
                    *isFound = YES;
                    
                    return i;
                }
            }
        }
        
        *isFound = NO;
        
        return [array count];
    } else {
        NSInteger mid = 0;
        NSInteger min = 0;
        NSInteger max = [array count] - 1;
        BOOL ascending = YES;
        
        while (min <= max) {
            mid = (min + max)/2;
            id tempObject = array[mid];
            
            NSComparisonResult result = [self compareObject1:object
                                                     object2:tempObject
                                             sortDescriptors:sortDescriptors
                                                   ascending:&ascending];
            if (result == NSOrderedAscending) {
                if (ascending) {
                    max = mid - 1;
                } else {
                    min = mid + 1;
                }
            } else if (result == NSOrderedDescending) {
                if (ascending) {
                    min = mid + 1;
                } else {
                    max = mid - 1;
                }
            } else {
                id value1 = [object valueForKeyPath:keyPath];
                id value2 = [tempObject valueForKeyPath:keyPath];
                if ([self compareValue1:value1 value2:value2] == NSOrderedSame) {
                    *isFound = YES;
                    break;
                }
                
                // 线性查找sort keys相同  uuid不同
                NSInteger firtSameIndex = NSNotFound;
                NSInteger lastSameIndex = NSNotFound;
                for (NSInteger i = min; i <= max; i++) {
                    tempObject = array[i];
                    NSComparisonResult temp = result = [self compareObject1:object
                                                                    object2:tempObject
                                                            sortDescriptors:sortDescriptors
                                                                  ascending:&ascending];
                    if (temp != NSOrderedSame && lastSameIndex != NSNotFound) {
                        // 找到最后一个相等 跳出循环
                        break;
                    } else if (temp == NSOrderedSame) {
                        if (firtSameIndex == NSNotFound) {
                            firtSameIndex = i;
                        }
                        lastSameIndex = i;
                        value2 = [tempObject valueForKeyPath:keyPath];
                        if ([self compareValue1:value1 value2:value2] == NSOrderedSame) {
                            mid = i;
                            *isFound = YES;
                            break;
                        }
                    }
                }
                
                if (!*isFound) {
                    if (ascending) {
                        mid = firtSameIndex;
                    } else {
                        mid = lastSameIndex + 1;
                    }
                }
                break;
            }
        }
        
        if (!*isFound) {
            BLLogDebug(@"The number was not found.");
        }
        
        if (*isFound) {
            return mid;
        } else {
            return MAX(min, max);
        }
    }
}

#pragma mark - compare

- (NSComparisonResult)compareObject1:(id)object1
                             object2:(id)object2
                     sortDescriptors:(NSArray *)sortDescriptors
                           ascending:(BOOL *)ascending
{
    NSComparisonResult result = NSOrderedAscending;
    
    for (int i = 0; i < [sortDescriptors count]; i++) {
        NSSortDescriptor *sortDescriptor = sortDescriptors[i];
        *ascending = sortDescriptor.ascending;
        id value1 = [object1 valueForKeyPath:sortDescriptor.key];
        id value2 = [object2 valueForKeyPath:sortDescriptor.key];
        result = [self compareValue1:value1 value2:value2];
        
        if (result == NSOrderedSame) {
            continue;
        } else {
            break;
        }
    }
    
    return result;
}

- (NSComparisonResult)compareValue1:(id)value1 value2:(id)value2
{
    if (!value1 && !value2) {
        return NSOrderedSame;
    } else if (!value1 && value2) {
        return NSOrderedAscending;
    } else if (value1 && !value2) {
        return NSOrderedDescending;
    } else {
        return [value1 compare:value2];
    }
}

#pragma mark - section

- (void)generateSectionsWithObjects:(NSArray *)objects
{
    // 清空cache
    [self.indexPathMapping removeAllObjects];
    [self.sections removeAllObjects];
    
    NSInteger section = -1;
    NSInteger index = 0;
    for (id object in objects) {
        //id object = objects[index];
        BLFetchedResultsSectionInfo *sectionInfo = [self.sections lastObject];
        NSString *groupName = [self groupNameForObject:object];
        
        if (sectionInfo && [sectionInfo.name isEqualToString:groupName]) {
            sectionInfo.length++;
            
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index - sectionInfo.offset inSection:section];
            [self.indexPathMapping setValue:indexPath forKey:[self keyWithUniqueId:[object uniqueId]]];
        } else {
            section++;
            sectionInfo = [BLFetchedResultsSectionInfo new];
            sectionInfo.name = groupName;
            sectionInfo.offset = index;
            sectionInfo.length++;
            [self.sections addObject:sectionInfo];
            
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index - sectionInfo.offset inSection:section];
            NSString *uniqueId = [self keyWithUniqueId:[object uniqueId]];
            NSIndexPath *oldIndexPath = self.indexPathMapping[uniqueId];
            if (!oldIndexPath || oldIndexPath.section != indexPath.section || oldIndexPath.row != indexPath.row) {
                [self.indexPathMapping setValue:indexPath forKey:uniqueId];
            }
        }
        
        index++;
    }
    
    if (!self.hasGroup && [self.sections count] < 1) {
        BLFetchedResultsSectionInfo *sectionInfo = [BLFetchedResultsSectionInfo new];
        sectionInfo.name = @"";
        [self.sections addObject:sectionInfo];
    }
}

#pragma mark - util

- (NSArray *)evaluativeObjectsWithObjects:(NSArray *)objects
{
    return [[self class] evaluativeObjectsWithObjects:objects request:self.request];
}

+ (NSArray *)evaluativeObjectsWithObjects:(NSArray *)objects request:(BLFetchRequest *)request
{
    if (!request.predicate) {
        return objects;
    } else {
        return [objects filteredArrayUsingPredicate:request.predicate];
    }
}

+ (BOOL)evaluateObject:(id)object request:(BLFetchRequest *)request
{
    return !request.predicate || [request.predicate evaluateWithObject:object];
}

- (NSString *)keyWithIndexPath:(NSIndexPath *)indexPath
{
    char *buffer;
    asprintf(&buffer, "%p", indexPath);
    NSString *value = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    free(buffer);
    
    return value;
}

- (NSString *)keyWithUniqueId:(NSString *)uniqueId
{
    return uniqueId;
}

//- (NSString *)keyWithRowid:(int64_t)rowid
//{
//    char *buffer;
//    asprintf(&buffer, "%lld", rowid);
//    NSString *value = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
//    free(buffer);
//    
//    return value;
//}

#pragma mark - sort util

- (NSString *)groupNameForObject:(id)object
{
    NSString *groupName = @"";
    if (self.hasGroup) {
        groupName = [object valueForKeyPath:self.groupByKeyPath];
        groupName = groupName ? groupName : @"";
    }
    
    return groupName;
}

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

@end
