//
//  ASHardware.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/23/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

typealias ASPropertyEntry = [String: String]
typealias ASProperties      = [String: ASPropertyEntry]

extension NSMenu {
    func addSortedChoices(choices:[ASPropertyEntry], target: AnyObject, selector: Selector) {
        for choice in choices.sorted({ $0["name"] < $1["name"] })  {
            let item        = self.addItemWithTitle(choice["name"]!, action: selector, keyEquivalent: "")
            item?.target    = target
        }
    }
}

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

private let hardwareInstance = ASHardware()
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
            let boardsPath  = dir+"/boards.txt"
            let provenience = dir.lastPathComponent
            if let boardsFile = NSString(contentsOfFile: boardsPath, usedEncoding: nil, error: nil) {
                var seen = [String: Bool]()
                for line in boardsFile.componentsSeparatedByString("\n") as [NSString] {
                    if let match = property?.firstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.length)) {
                        let board           = line.substringWithRange(match.rangeAtIndex(1))
                        let property        = line.substringWithRange(match.rangeAtIndex(2))
                        let value           = line.substringWithRange(match.rangeAtIndex(3))
                        if seen.updateValue(true, forKey: board) == nil {
                            boards[board]                   = ASPropertyEntry()
                            boards[board]!["provenience"]   = provenience
                            boards[board]!["library"]       = dir
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
            let provenience = dir.lastPathComponent
            if let programmersFile = NSString(contentsOfFile: programmersPath, usedEncoding: nil, error: nil) {
                var seen = [String: Bool]()
                for line in programmersFile.componentsSeparatedByString("\n") as [NSString] {
                    if let match = property?.firstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.length)) {
                        let programmer      = line.substringWithRange(match.rangeAtIndex(1))
                        let property        = line.substringWithRange(match.rangeAtIndex(2))
                        let value           = line.substringWithRange(match.rangeAtIndex(3))
                        if seen.updateValue(true, forKey: programmer) == nil {
                            programmers[programmer] = ASPropertyEntry()
                            programmers[programmer]!["provenience"]   = provenience
                        }
                        programmers[programmer]![property] = value
                    }
                }
            }
        }
    }
    
    func buildMenu(menu:NSMenu, choices:ASProperties, recentChoices:[String], target: AnyObject, selector: Selector) {
        menu.removeAllItems()
        if choices.count <= 10 {
            menu.addSortedChoices([ASPropertyEntry](choices.values), target: target, selector: selector)
        } else {
            menu.addSortedChoices(recentChoices.map({ (recent: String) in choices[recent]! }), target: target, selector: selector)
            menu.addItem(NSMenuItem.separatorItem())
            var seen = [String: Bool]()
            for prop in choices.values {
                seen[prop["provenience"]!] = true
            }
            var sortedKeys = [String](seen.keys)
            sortedKeys.sort { $0 < $1 }
            for provenience in sortedKeys {
                var subset = [ASPropertyEntry]()
                for prop in choices.values {
                    if prop["provenience"] == provenience {
                        subset.append(prop)
                    }
                }
                let item                    = menu.addItemWithTitle(provenience, action: nil, keyEquivalent: "")!
                let submenu                 = NSMenu()
                submenu.autoenablesItems    = false
                submenu.addSortedChoices(subset, target: target, selector: selector)
                menu.setSubmenu(submenu, forItem: item)
            }
        }
    }
    
    func buildBoardsMenu(menu:NSMenu, recentBoards:[String], target: AnyObject, selector: Selector) {
        buildMenu(menu, choices:boards, recentChoices:recentBoards, target: target, selector: selector)
    }
    
    func buildProgrammersMenu(menu:NSMenu, recentProgrammers:[String], target: AnyObject, selector: Selector) {
        buildMenu(menu, choices:programmers, recentChoices:recentProgrammers, target: target, selector: selector)
    }
}

private let librariesInstance = ASLibraries()
class ASLibraries {
    class func instance() -> ASLibraries { return librariesInstance }
    let directories = [NSString]()
    let libraries   = [NSString]()
    init() {
        //
        // Gather hardware directories
        //
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        let fileManager     = NSFileManager.defaultManager()
        if let arduinoPath = userDefaults.stringForKey("Arduino") {
            let arduinoLibrariesPath = arduinoPath + "/Contents/Resources/Java/libraries"
            let dirs                 = subdirectories(arduinoLibrariesPath)
            if dirs.count > 0 {
                directories.append(arduinoLibrariesPath)
                libraries   += dirs
            }
        }
        for sketchDir in userDefaults.objectForKey("Sketchbooks") as [NSString] {
            let librariesPath = sketchDir + "/libraries"
            let dirs                 = subdirectories(librariesPath)
            if dirs.count > 0 {
                directories.append(librariesPath)
                libraries   += dirs
            }
        }
    }
}
