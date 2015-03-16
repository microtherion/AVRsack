//
//  ASVestigial.m
//  AVRsack
//
//  Created by Matthias Neeracher on 16/03/15.
//  Copyright © 2015 Aere Perennius. All rights reserved.
//

#import "ASVestigial.h"

void
InvokeCallback(id target, SEL selector, void * context)
{
    if (!target)
        return;
    NSMethodSignature * sig   = [target methodSignatureForSelector:selector];
    NSInvocation * invocation = [NSInvocation invocationWithMethodSignature:sig];
    [invocation setArgument:&context atIndex:2];
    [invocation invokeWithTarget:target];
}