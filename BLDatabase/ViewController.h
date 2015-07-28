//
//  ViewController.h
//  BLAlimeiDatabase
//
//  Created by surewxw on 15/1/21.
//  Copyright (c) 2015年 wxw. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (nonatomic, strong) UITableView *tableView;

- (IBAction)insertPressed:(id)sender;
- (IBAction)updatePressed:(id)sender;
- (IBAction)deletePressed:(id)sender;
- (IBAction)findPressed:(id)sender;

@end

