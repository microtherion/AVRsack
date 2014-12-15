//
//  ASSerial.m
//  AVRsack
//
//  Created by Matthias Neeracher on 12/15/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

#import "ASSerial.h"

#include <dispatch/dispatch.h>

static dispatch_source_t watchSlashDev;

NSString * kASSerialPortsChanged = @"PortsChanged";

@implementation ASSerial

+ (void)initialize {
    int fd = open("/dev", O_EVTONLY);
    watchSlashDev =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
    dispatch_source_set_event_handler(watchSlashDev, ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kASSerialPortsChanged object: nil];
    });
    dispatch_resume(watchSlashDev);
}

+ (NSArray *)ports {
    NSMutableArray * cuPorts = [NSMutableArray array];
    for (NSString * port in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev" error: nil]) {
        if ([[port substringToIndex:2] isEqualToString:@"cu"])
            [cuPorts addObject:[@"/dev/" stringByAppendingString:port]];
    }
    return cuPorts;
}

@end
