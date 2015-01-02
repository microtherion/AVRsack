//
//  ASSerial.m
//  AVRsack
//
//  Created by Matthias Neeracher on 12/15/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

#import "ASSerial.h"

#include <dispatch/dispatch.h>
#include <termios.h>
#include <sys/ioctl.h>

static dispatch_source_t        watchSlashDev;
static NSMutableDictionary *    savedAttrs;

NSString * kASSerialPortsChanged = @"PortsChanged";

@implementation NSFileHandle (ExceptionSafety)

- (NSData *)availableDataIgnoringExceptions {
    @try {
        return [self availableData];
    }
    @catch (NSException *exception) {
        return [NSData data];
    }
}

@end

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
            [cuPorts addObject:[port substringFromIndex:3]];
    }
    return [cuPorts sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSString *) fileNameForPort:(NSString *)port
{
    if ([port containsString:@"/"])
        return port;
    else
        return [NSString stringWithFormat:@"/dev/cu.%@", port];
}

+ (NSFileHandle *)openPort:(NSString *)port withSpeed:(int)speed {
    int fd = open([[self fileNameForPort:port] UTF8String], O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0)
        return nil;
    if (ioctl(fd, TIOCEXCL) < 0)
        goto failed;
    termios origAttr, newAttr;
    if (tcgetattr(fd, &origAttr) < 0)
        goto failed;
    newAttr = origAttr;
    cfmakeraw(&newAttr);
    cfsetspeed(&newAttr, speed);
    newAttr.c_cflag &= ~(PARENB | CSIZE | CSTOPB | CRTSCTS);
    newAttr.c_cflag |= CS8;
    tcsetattr(fd, TCSANOW, &newAttr);
    tcsetattr(fd, TCSAFLUSH, &newAttr);
    if (!savedAttrs) {
        savedAttrs = [NSMutableDictionary dictionary];
    }
    [savedAttrs setObject:[NSData dataWithBytes:&origAttr length:sizeof(origAttr)] forKey:[NSNumber numberWithInt:fd]];
    return [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:NO];
failed:
    close(fd);
    
    return nil;
}

+ (void)restorePort:(int)fileDescriptor {
    NSNumber * fd = [NSNumber numberWithInt:fileDescriptor];
    if (NSData * attr = [savedAttrs objectForKey:fd]) {
        tcsetattr(fileDescriptor, TCSADRAIN, (termios *)[attr bytes]);
        [savedAttrs removeObjectForKey:fd];
    }
}

+ (void)closePort:(int)fileDescriptor {
    NSNumber * fd = [NSNumber numberWithInt:fileDescriptor];
    close(fileDescriptor);
    [savedAttrs removeObjectForKey:fd];
}
@end
