//
//  ASHardware.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/23/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

typealias ASPropertyEntry   = [String: String]
typealias ASProperties      = [String: ASPropertyEntry]

private func subdirectories(path: NSString) -> [NSString] {
    let fileManager         = NSFileManager.defaultManager()
    var subDirs             = [NSString]()
    var isDir : ObjCBool    = false
    if fileManager.fileExistsAtPath(path, isDirectory: &isDir) && isDir {
        for item in fileManager.contentsOfDirectoryAtPath(path, error: nil) as [NSString] {
            let subPath = path+"/"+item
            if fileManager.fileExistsAtPath(subPath, isDirectory: &isDir) && isDir {
                subDirs.append(subPath)
            }
        }
    }
    return subDirs
}

let hardwareInstance = ASHardware()
class ASHardware {
    class func instance() -> ASHardware { return hardwareInstance }
    let directories = [NSString]()
    let programmers = ASProperties()
    let boards      = ASProperties()
    init() {
        //
        // Gather hardware directories
        //
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        let fileManager     = NSFileManager.defaultManager()
        if let arduinoPath = userDefaults.stringForKey("Arduino") {
            let arduinoHardwarePath = arduinoPath + "/Contents/Resources/Java/hardware"
            directories += subdirectories(arduinoHardwarePath)
        }
        for sketchDir in userDefaults.objectForKey("Sketchbooks") as [NSString] {
            let hardwarePath = sketchDir + "/hardware"
            directories     += subdirectories(hardwarePath)
        }
        let property = NSRegularExpression(pattern: "\\s*(\\w+)\\.(\\S+?)\\s*=\\s*(\\S.*\\S)\\s*", options: nil, error: nil)
        //
        // Gather board declarations
        //
        for dir in directories {
            let boardsPath = dir+"/boards.txt"
            if let boardsFile = NSString(contentsOfFile: boardsPath, usedEncoding: nil, error: nil) {
                var seen = [String: Bool]()
                for line in boardsFile.componentsSeparatedByString("\n") as [NSString] {
                    if let match = property?.firstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.length)) {
                        let board           = line.substringWithRange(match.rangeAtIndex(1))
                        let property        = line.substringWithRange(match.rangeAtIndex(2))
                        let value           = line.substringWithRange(match.rangeAtIndex(3))
                        if seen.updateValue(true, forKey: board) == nil {
                            boards[board]   = ASPropertyEntry()
                        }
                        boards[board]![property]  = value
                    }
                }
            }
        }
        //
        // Gather programmer declarations
        //
        for dir in directories {
            let programmersPath = dir+"/programmers.txt"
            if let programmersFile = NSString(contentsOfFile: programmersPath, usedEncoding: nil, error: nil) {
                var seen = [String: Bool]()
                for line in programmersFile.componentsSeparatedByString("\n") as [NSString] {
                    if let match = property?.firstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.length)) {
                        let programmer      = line.substringWithRange(match.rangeAtIndex(1))
                        let property        = line.substringWithRange(match.rangeAtIndex(2))
                        let value           = line.substringWithRange(match.rangeAtIndex(3))
                        if seen.updateValue(true, forKey: programmer) == nil {
                            programmers[programmer] = ASPropertyEntry()
                            seen[programmer]        = true
                        }
                        programmers[programmer]![property] = value
                    }
                }
            }
        }
    }
}