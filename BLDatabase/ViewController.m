//
//  ViewController.m
//  BLAlimeiDatabase
//
//  Created by alibaba on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import "ViewController.h"
#import "BLBaseDBObject.h"
#import "BLBaseDBObject+Common.h"
#import "BLTestObject.h"
#import "BLFetchRequest.h"
#import "BLFetchedResultsController.h"
#import "BLDatabase.h"
#import "BLDatabaseConnection.h"
#import "BLAccount.h"

@interface ViewController () <UITableViewDataSource, UITableViewDelegate, BLFetchedResultsControllerDelegate>

@property (nonatomic, strong) NSMutableArray *sectionList;
@property (nonatomic, strong) BLFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) BLDatabase *database;
@property (nonatomic, strong) BLDatabaseConnection *uiConnection;
@property (nonatomic, strong) BLDatabaseConnection *backgroundConnection;
@property (nonatomic, strong) dispatch_queue_t backgroundQueue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"还原" style:UIBarButtonItemStylePlain target:self action:@selector(leftPressed:)];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"动画" style:UIBarButtonItemStylePlain target:self action:@selector(rightPressed:)];
    
    self.database = [BLDatabase defaultDatabase];
    [self.database setSchemaVersion:1
                 withMigrationBlock:^(BLDatabaseConnection *connection, NSUInteger oldSchemaVersion) {
                         [BLTestObject createTableAndIndexIfNeededInConnection:connection];
                         [BLAccount createTableAndIndexIfNeededInConnection:connection];
                 }];
    
    self.uiConnection = [self.database newConnection];
    self.backgroundConnection = [self.database newConnection];
    
    self.backgroundQueue = dispatch_queue_create("com.background.sql", DISPATCH_QUEUE_SERIAL);
    
    BLFetchRequest *request = [[BLFetchRequest alloc] init];
    request.predicate = nil;
    request.sqlAfterWhere = nil;
    //request.fieldNames = @[@"name", @"groupName"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
    
    BLFetchedResultsController *controller = [[BLFetchedResultsController alloc] initWithFetchRequest:request
                                                                                       groupByKeyPath:@"groupName"
                                                                                       groupAscending:YES
                                                                                          objectClass:[BLTestObject class]
                                                                                 inConnection:self.uiConnection];
    [controller performFetch];
    controller.delegate = self;
    self.fetchedResultsController = controller;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    CGRect frame = self.tableView.frame;
    frame.origin.y = 44;
    self.tableView.frame = frame;
    self.tableView.rowHeight = 44;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    
    [self.view addSubview:self.tableView];
}

- (void)leftPressed:(id)sender
{
    __weak BLDatabaseConnection *connection = self.backgroundConnection;
    [connection performReadWriteBlockInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLTestObject findObjectsInConnection:connection];
        [connection deleteObjects:result];
    }];
}

- (void)rightPressed:(id)sender
{
    __weak BLDatabaseConnection *connection = self.backgroundConnection;
    [connection performReadWriteBlockInTransaction:^(BOOL *rollback) {
        int count = 100;
        NSArray *result = [BLTestObject findObjectsInConnection:connection
                                                                orderBy:nil
                                                                 length:count
                                                                 offset:0
                                                                  where:nil];
        
        int index = 0;
        for (BLTestObject *object in result) {
            if (index % 2 == 0) {
                //                            [object setGroupName:[NSString stringWithFormat:@"%c", (arc4random() % 26) + 65]];
                //                            object.name = [NSString stringWithFormat:@"%c", (arc4random() % 26) + 65];
                //                            [connection insertOrUpdateObject:object];
            } else {
                [connection deleteObject:object];
            }
            index++;
        }
        
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.groupName = [NSString stringWithFormat:@"%c", (arc4random() % 26) + 65];
            object.name = [NSString stringWithFormat:@"%c", (arc4random() % 26) + 65];
            [connection insertObject:object];
        }
    }];

    
    return;
    
    //[self.sectionList addObject:@[@""]];
    //[self.sectionList[0] removeObjectAtIndex:4];
    //[self.sectionList[0] removeObjectAtIndex:2];
    //[self.sectionList[0] removeObjectAtIndex:0];
    //[self.sectionList[0] insertObject:@(5) atIndex:2];
    //[self.sectionList[0] insertObject:@(6) atIndex:3];
    //[self.sectionList insertObject:[NSArray arrayWithObject:@"test"] atIndex:0];
    //[self.sectionList removeLastObject];
    
    //[self.sectionList[0] insertObject:@(222) atIndex:0];
    //[self.sectionList[0] insertObject:@(111) atIndex:0];
    //[self.sectionList[0] insertObject:@(333) atIndex:2];
    //[self.sectionList[0] insertObject:@(444) atIndex:3];
    //[self.sectionList[0] insertObject:@(555) atIndex:3];
    
    //[self.sectionList[0] removeObjectAtIndex:1];
    //[self.sectionList[0] removeObjectAtIndex:2];
    //[self.sectionList[0] removeObjectAtIndex:2];
    [self.sectionList removeObjectAtIndex:0];
    //[self.sectionList insertObject:[NSArray arrayWithObjects:@(999), nil] atIndex:0];
    //[self.sectionList removeLastObject];
    
    NSMutableArray *insertIndexPaths = [NSMutableArray array];
    NSMutableArray *updateIndexPaths = [NSMutableArray array];
    NSMutableArray *deleteIndexPaths = [NSMutableArray array];
    
    NSMutableIndexSet *insertIndexSet = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *deleteIndexSet = [NSMutableIndexSet indexSet];
    [deleteIndexSet addIndex:0];
    //[insertIndexSet addIndex:0];
    //[insertIndexSet addIndex:[self.sectionList count] - 1];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:[self.sectionList count] - 1]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:0]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:1 inSection:0]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:3 inSection:0]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:0]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:1]];
    [deleteIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:0]];
    //[deleteIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:1]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:1]];
    [updateIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:1]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:4 inSection:0]];
    //[insertIndexPaths addObject:[NSIndexPath indexPathForRow:4 inSection:0]];
    //[updateIndexPaths addObject:[NSIndexPath indexPathForRow:0 inSection:0]];
    //[deleteIndexPaths addObject:[NSIndexPath indexPathForRow:2 inSection:0]];
    //[deleteIndexPaths addObject:[NSIndexPath indexPathForRow:4 inSection:0]];
    //[deleteIndexPaths addObject:[NSIndexPath indexPathForRow:2 inSection:0]];
    
    [self.tableView beginUpdates];
    [self.tableView insertSections:insertIndexSet withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.tableView deleteSections:deleteIndexSet withRowAnimation:UITableViewRowAnimationAutomatic];
    //[self.tableView insertSections:insertIndexSet withRowAnimation:UITableViewRowAnimationAutomatic];
    [self.tableView deleteRowsAtIndexPaths:deleteIndexPaths withRowAnimation:UITableViewRowAnimationRight];
    [self.tableView insertRowsAtIndexPaths:insertIndexPaths withRowAnimation:UITableViewRowAnimationLeft];
    [self.tableView reloadRowsAtIndexPaths:updateIndexPaths withRowAnimation:UITableViewRowAnimationMiddle];
    //[self.tableView moveRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] toIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    [self.tableView endUpdates];
    //[self.tableView reloadData];
}

- (void)reset
{
    self.sectionList = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        NSMutableArray *array = [NSMutableArray array];
        for (int j = 0; j < 1; j++) {
            [array addObject:@(i * 10 + j)];
        }
        [self.sectionList addObject:array];
    }
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.fetchedResultsController numberOfSections];
    //return [self.sectionList count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.fetchedResultsController numberOfRowsInSection:section];
    //return [self.sectionList[section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    //NSLog(@"cell for indexPath %@", indexPath);
    static NSString *identifier = @"tableViewCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    
    id object = [self.fetchedResultsController objectAtIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ ===", [object name]];
    //cell.textLabel.text = [NSString stringWithFormat:@"%@ ===", self.sectionList[indexPath.section][indexPath.row]];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 22;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.fetchedResultsController titleInSection:section];
}

- (void)controller:(BLFetchedResultsController *)controller
   didChangeAtIndexPath:(NSIndexPath *)indexPath
     forChangeType:(BLFetchedResultsChangeType)type
{
    //NSLog(@"-----indexPath = %@ type = %d", indexPath, type);
//    if (type == BLFetchedResultsChangeInsert) {
//        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
//    } else if (type == BLFetchedResultsChangeUpdate) {
//        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
//    } else if (type == BLFetchedResultsChangeDelete) {
//        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
//    }
}

- (void)controller:(BLFetchedResultsController *)controller
  didChangeAtSectionIndex:(NSUInteger)sectionIndex
     forChangeType:(BLFetchedResultsChangeType)type
{
    //NSLog(@"-----sectionIndex = %tu type = %d", sectionIndex, type);
//    if (type == BLFetchedResultsChangeInsert) {
//        [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationAutomatic];
//    } else if (type == BLFetchedResultsChangeDelete) {
//        [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationAutomatic];
//    }
}

- (void)controller:(BLFetchedResultsController *)controller didChangeWithIndexSet:(NSIndexSet *)indexSet forChangeType:(BLFetchedResultsChangeType)type
{
        if (type == BLFetchedResultsChangeInsert) {
            [self.tableView insertSections:indexSet withRowAnimation:UITableViewRowAnimationAutomatic];
        } else if (type == BLFetchedResultsChangeDelete) {
            [self.tableView deleteSections:indexSet withRowAnimation:UITableViewRowAnimationAutomatic];
        }
}

- (void)controller:(BLFetchedResultsController *)controller didChangeWithIndexPaths:(NSArray *)indexPaths forChangeType:(BLFetchedResultsChangeType)type
{
        if (type == BLFetchedResultsChangeInsert) {
            [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationLeft];
        } else if (type == BLFetchedResultsChangeUpdate) {
            [self.tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
        } else if (type == BLFetchedResultsChangeDelete) {
            [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationRight];
        }
}

- (void)controllerWillChangeContent:(BLFetchedResultsController *)controller
{
    NSLog(@"-----begin update");
    [self.tableView beginUpdates];
}

- (void)controllerDidChangeContent:(BLFetchedResultsController *)controller
{
    NSLog(@"-----end update");
    [self.tableView endUpdates];
    //[self.tableView reloadData];
}

- (IBAction)insertPressed:(id)sender
{
    __weak BLDatabaseConnection *connection = self.backgroundConnection;
    [connection performReadWriteBlockInTransaction:^(BOOL *rollback) {
        int count = 1000;
        
        for (int i = 0; i < count; i++) {
            BLTestObject *object = [BLTestObject new];
            object.age = 10;
            object.groupName = [NSString stringWithFormat:@"%c", (arc4random() % 26) + 65];
            object.name = [NSString stringWithFormat:@"%c", (arc4random() % 26) + 65];
            [connection insertObject:object];
        }
    }];
}

- (IBAction)updatePressed:(id)sender
{
}

- (IBAction)deletePressed:(id)sender
{
    __weak BLDatabaseConnection *connection = self.backgroundConnection;
    [connection performReadWriteBlockInTransaction:^(BOOL *rollback) {
        NSArray *result = [BLTestObject findObjectsInConnection:connection];
        [connection deleteObjects:result];
    }];
}

- (IBAction)findPressed:(id)sender
{
    __weak BLDatabaseConnection *connection = self.backgroundConnection;
    [connection performReadBlock:^(void) {
        NSArray *result = [BLTestObject findObjectsInConnection:connection];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil
                                                            message:[NSString stringWithFormat:@"%zd", [result count]]
                                                           delegate:nil
                                                  cancelButtonTitle:nil
                                                  otherButtonTitles:@"cancel", nil];
            [alert show];
        });
    }];
}
@end
