//
//  ASSerial.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 12/2/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

class ASSerial {
    class func ports() -> [String] {
        let devices = NSFileManager.defaultManager().contentsOfDirectoryAtPath("/dev", error: nil)!
        var cuDevs  = [String]()
        for dev in devices as [String] {
            if dev.substringToIndex(dev.startIndex.successor().successor()) == "cu" {
                cuDevs.append("/dev/"+dev)
            }
        }
        return cuDevs
    }
}