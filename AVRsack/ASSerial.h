//
//  ASSerial.h
//  AVRsack
//
//  Created by Matthias Neeracher on 12/15/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * kASSerialPortsChanged;

@interface ASSerial : NSObject

+ (NSArray *) ports;
+ (NSFileHandle *)openPort:(NSString *) port withSpeed:(int)speed;

@end
