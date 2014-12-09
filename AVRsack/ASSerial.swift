//
//  ASSerial.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 12/2/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

let kASSerialPortsChanged    = "PortsChanged"

class ASSerialWatcher {
}

private let serialInstance = ASSerial()

class ASSerial {
    class func instance() -> ASSerial { return serialInstance }
    
    let watchSlashDev   : dispatch_source_t
    init() {
        let fd = open("/dev", O_EVTONLY)
        watchSlashDev = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, UInt(fd), DISPATCH_VNODE_WRITE, dispatch_get_main_queue())
        dispatch_source_set_event_handler(watchSlashDev) { () -> Void in
            NSNotificationCenter.defaultCenter().postNotificationName(kASSerialPortsChanged, object: nil)
        }
        dispatch_resume(watchSlashDev)
    }

    func ports() -> [String] {
        let devices = NSFileManager.defaultManager().contentsOfDirectoryAtPath("/dev", error: nil)!
        var cuDevs  = [String]()
        for dev in devices as [String] {
            if dev.hasPrefix("cu") {
                cuDevs.append("/dev/"+dev)
            }
        }
        return cuDevs
    }
}