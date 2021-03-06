//
//  PinViewController.h
//  iosFirmata
//
//  Created by Jacob on 11/11/13.
//  Copyright (c) 2013 Augmetous Inc.
//

#import <UIKit/UIKit.h>
#import "Firmata.h"

@interface PinViewController : UIViewController <FirmataProtocol, UITextFieldDelegate, UIGestureRecognizerDelegate>

@property (weak, nonatomic) IBOutlet UILabel *deviceLabel;
@property (weak, nonatomic) IBOutlet UILabel *pinStatus;
@property (weak, nonatomic) IBOutlet UILabel *pinLabel;
@property (weak, nonatomic) IBOutlet UISlider *pinSlider;
@property (weak, nonatomic) IBOutlet UISwitch *modeSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *statusSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *reportSwitch;
@property (weak, nonatomic) IBOutlet UITextField *i2cAddressTextField;
@property (weak, nonatomic) IBOutlet UITextField *i2cPayloadTextField;
@property (weak, nonatomic) IBOutlet UITextView *i2cResultTextView;

@property (strong, nonatomic) Firmata *currentFirmata;
@property (strong, nonatomic) NSMutableDictionary *pinDictionary;
@property (strong, nonatomic) NSMutableArray *pinsArray;
@property (strong, nonatomic) NSMutableDictionary *analogMapping;
@property (strong, nonatomic) NSTimer *ignoreTimer;

@property bool ignoreReporting;
@property int pinNumber;

-(IBAction)sendi2c:(id)sender;
-(IBAction)toggleValue:(id)sender;
-(IBAction)toggleMode:(id)sender;
-(IBAction)toggleReporting:(id)sender;
-(IBAction)refresh:(id)sender;

@end
