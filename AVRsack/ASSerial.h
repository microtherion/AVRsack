//
//  ASSerial.h
//  AVRsack
//
//  Created by Matthias Neeracher on 12/15/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * kASSerialPortsChanged;

@interface NSFileHandle (ExceptionSafety)

- (NSData *)availableDataIgnoringExceptions;

@end

@interface ASSerial : NSObject

+ (NSString *) fileNameForPort:(NSString *)port;
+ (NSArray<NSString *> *) ports;
+ (NSFileHandle *)openPort:(NSString *) port withSpeed:(int)speed;
+ (void)restorePort:(int)fileDescriptor;
+ (void)closePort:(int)fileDescriptor;

@end
