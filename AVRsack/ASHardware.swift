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

extension NSMenu {
    func addSortedChoices(choices:[ASPropertyEntry], target: AnyObject, selector: Selector) {
        for choice in choices.sort({ $0["name"] < $1["name"] })  {
            let item        = self.addItemWithTitle(choice["name"]!, action: selector, keyEquivalent: "")
            item?.target    = target
        }
    }
}

private func subdirectories(path: String) -> [String] {
    let fileManager         = NSFileManager.defaultManager()
    var subDirs             = [String]()
    var isDir : ObjCBool    = false
    if let items = try? fileManager.contentsOfDirectoryAtPath(path) {
        for item in items {
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
    var directories = [String]()
    var programmers = ASProperties()
    var boards      = ASProperties()
    init() {
        //
        // Gather hardware directories
        //
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        if let arduinoPath = userDefaults.stringForKey("Arduino") {
            let arduinoHardwarePath = arduinoPath + "/Contents/Resources/Java/hardware"
            directories += subdirectories(arduinoHardwarePath)
        }
        for sketchDir in userDefaults.objectForKey("Sketchbooks") as! [String] {
            let hardwarePath = sketchDir + "/hardware"
            directories     += subdirectories(hardwarePath)
        }
        let property = try! NSRegularExpression(pattern: "\\s*(\\w+)\\.(\\S+?)\\s*=\\s*(\\S.*\\S)\\s*", options: [])
        //
        // Gather board declarations
        //
        for dir in directories {
            let boardsPath  = dir+"/boards.txt"
            let provenience = (dir as NSString).lastPathComponent
            if let boardsFile = try? NSString(contentsOfFile: boardsPath, usedEncoding: nil) {
                var seen = [String: Bool]()
                for line in boardsFile.componentsSeparatedByString("\n") {
                    if let match = property.firstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.utf16.count)) {
                        let nsline          = line as NSString
                        let board           = nsline.substringWithRange(match.rangeAtIndex(1)) as String
                        let property        = nsline.substringWithRange(match.rangeAtIndex(2)) as String
                        let value           = nsline.substringWithRange(match.rangeAtIndex(3)) as String
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
            let provenience = (dir as NSString).lastPathComponent
            if let programmersFile = try? NSString(contentsOfFile: programmersPath, usedEncoding: nil) {
                var seen = [String: Bool]()
                for line in programmersFile.componentsSeparatedByString("\n") {
                    if let match = property.firstMatchInString(line, options: .Anchored, range: NSMakeRange(0, line.utf16.count)) {
                        let nsline          = line as NSString
                        let programmer      = nsline.substringWithRange(match.rangeAtIndex(1))
                        let property        = nsline.substringWithRange(match.rangeAtIndex(2))
                        let value           = nsline.substringWithRange(match.rangeAtIndex(3))
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
        menu.addItemWithTitle("Title", action: "", keyEquivalent: "")
        if choices.count <= 10 {
            menu.addSortedChoices([ASPropertyEntry](choices.values), target: target, selector: selector)
        } else {
            menu.addSortedChoices(recentChoices.flatMap({ (recent: String) in choices[recent] }), target: target, selector: selector)
            menu.addItem(NSMenuItem.separatorItem())
            var seen = [String: Bool]()
            for prop in choices.values {
                seen[prop["provenience"]!] = true
            }
            var sortedKeys = [String](seen.keys)
            sortedKeys.sortInPlace { $0 < $1 }
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
class ASLibraries : NSObject {
    class func instance() -> ASLibraries { return librariesInstance }
    var directories = [String]()
    var libraries   = [String]()
    var standardLib = [String]()
    var contribLib  = [String]()
    override init() {
        //
        // Gather hardware directories
        //
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        for sketchDir in userDefaults.objectForKey("Sketchbooks") as! [String] {
            let librariesPath = sketchDir + "/libraries"
            let dirs                 = subdirectories(librariesPath)
            if dirs.count > 0 {
                directories.append(librariesPath)
                libraries   += dirs
                contribLib  += dirs
            }
        }
        if let arduinoPath = userDefaults.stringForKey("Arduino") {
            let arduinoLibrariesPath = arduinoPath + "/Contents/Resources/Java/libraries"
            let dirs                 = subdirectories(arduinoLibrariesPath)
            if dirs.count > 0 {
                directories.append(arduinoLibrariesPath)
                libraries   += dirs
                standardLib += dirs
            }
        }
    }
    func addStandardLibrariesToMenu(menu: NSMenu) {
        for (index,lib) in standardLib.enumerate() {
            let menuItem        = menu.addItemWithTitle((lib as NSString).lastPathComponent, action: "importStandardLibrary:", keyEquivalent: "")
            menuItem?.target    = self
            menuItem?.tag       = index
        }
    }
    func addContribLibrariesToMenu(menu: NSMenu) {
        for (index,lib) in contribLib.enumerate() {
            let menuItem        = menu.addItemWithTitle((lib as NSString).lastPathComponent, action: "importContribLibrary:", keyEquivalent: "")
            menuItem?.target    = self
            menuItem?.tag       = index
        }
    }
    @IBAction func importStandardLibrary(menuItem: AnyObject) {
        if let tag = (menuItem as? NSMenuItem)?.tag {
            NSApplication.sharedApplication().sendAction("importLibrary:", to: nil, from: standardLib[tag])
        }
    }
    @IBAction func importContribLibrary(menuItem: AnyObject) {
        if let tag = (menuItem as? NSMenuItem)?.tag {
            NSApplication.sharedApplication().sendAction("importLibrary:", to: nil, from: contribLib[tag])
        }
    }

    func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
        if let validator = NSApplication.sharedApplication().targetForAction("importLibrary:") as? NSUserInterfaceValidations {
            return validator.validateUserInterfaceItem(anItem)
        }
        return false
    }
}
