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
        for choice in choices.sorted(by: { $0["name"]! < $1["name"]! })  {
            let item        = self.addItem(withTitle: choice["name"]!, action: selector, keyEquivalent: "")
            item.target    = target
        }
    }
}

private func subdirectories(path: String) -> [String] {
    let fileManager         = FileManager.default
    var subDirs             = [String]()
    var isDir : ObjCBool    = false
    if let items = try? fileManager.contentsOfDirectory(atPath: path) {
        for item in items {
            let subPath = path+"/"+item
            if fileManager.fileExists(atPath: subPath, isDirectory: &isDir) && isDir.boolValue {
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
        let userDefaults    = UserDefaults.standard
        if let arduinoPath = userDefaults.string(forKey: "Arduino") {
            let arduinoHardwarePath = arduinoPath + "/Contents/Resources/Java/hardware"
            directories += subdirectories(path: arduinoHardwarePath)
        }
        for sketchDir in userDefaults.object(forKey: "Sketchbooks") as! [String] {
            let hardwarePath = sketchDir + "/hardware"
            directories     += subdirectories(path: hardwarePath)
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
                for line in boardsFile.components(separatedBy: "\n") {
                    if let match = property.firstMatch(in: line, options: .anchored, range: NSMakeRange(0, line.utf16.count)) {
                        let nsline          = line as NSString
                        let board           = nsline.substring(with: match.rangeAt(1)) as String
                        let property        = nsline.substring(with: match.rangeAt(2)) as String
                        let value           = nsline.substring(with: match.rangeAt(3)) as String
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
                for line in programmersFile.components(separatedBy: "\n") {
                    if let match = property.firstMatch(in: line, options: .anchored, range: NSMakeRange(0, line.utf16.count)) {
                        let nsline          = line as NSString
                        let programmer      = nsline.substring(with: match.rangeAt(1))
                        let property        = nsline.substring(with: match.rangeAt(2))
                        let value           = nsline.substring(with: match.rangeAt(3))
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
        menu.addItem(withTitle: "Title", action: nil, keyEquivalent: "")
        if choices.count <= 10 {
            menu.addSortedChoices(choices: [ASPropertyEntry](choices.values), target: target, selector: selector)
        } else {
            menu.addSortedChoices(choices: recentChoices.flatMap({ (recent: String) in choices[recent] }), target: target, selector: selector)
            menu.addItem(NSMenuItem.separator())
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
                let item                    = menu.addItem(withTitle: provenience, action: nil, keyEquivalent: "")
                let submenu                 = NSMenu()
                submenu.autoenablesItems    = false
                submenu.addSortedChoices(choices: subset, target: target, selector: selector)
                menu.setSubmenu(submenu, for: item)
            }
        }
    }
    
    func buildBoardsMenu(menu:NSMenu, recentBoards:[String], target: AnyObject, selector: Selector) {
        buildMenu(menu: menu, choices:boards, recentChoices:recentBoards, target: target, selector: selector)
    }
    
    func buildProgrammersMenu(menu:NSMenu, recentProgrammers:[String], target: AnyObject, selector: Selector) {
        buildMenu(menu: menu, choices:programmers, recentChoices:recentProgrammers, target: target, selector: selector)
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
        let userDefaults    = UserDefaults.standard
        for sketchDir in userDefaults.object(forKey: "Sketchbooks") as! [String] {
            let librariesPath = sketchDir + "/libraries"
            let dirs                 = subdirectories(path: librariesPath)
            if dirs.count > 0 {
                directories.append(librariesPath)
                libraries   += dirs
                contribLib  += dirs
            }
        }
        if let arduinoPath = userDefaults.string(forKey: "Arduino") {
            let arduinoLibrariesPath = arduinoPath + "/Contents/Resources/Java/libraries"
            let dirs                 = subdirectories(path: arduinoLibrariesPath)
            if dirs.count > 0 {
                directories.append(arduinoLibrariesPath)
                libraries   += dirs
                standardLib += dirs
            }
        }
    }
    func addStandardLibrariesToMenu(menu: NSMenu) {
        for (index,lib) in standardLib.enumerated() {
            let menuItem        = menu.addItem(withTitle: (lib as NSString).lastPathComponent, action: #selector(ASLibraries.importStandardLibrary(_:)), keyEquivalent: "")
            menuItem.target    = self
            menuItem.tag       = index
        }
    }
    func addContribLibrariesToMenu(menu: NSMenu) {
        for (index,lib) in contribLib.enumerated() {
            let menuItem        = menu.addItem(withTitle: (lib as NSString).lastPathComponent, action: #selector(ASLibraries.importContribLibrary(_:)), keyEquivalent: "")
            menuItem.target    = self
            menuItem.tag       = index
        }
    }
    @IBAction func importStandardLibrary(_ menuItem: AnyObject) {
        if let tag = (menuItem as? NSMenuItem)?.tag {
            NSApplication.shared().sendAction(#selector(ASProjDoc.importLibrary(_:)), to: nil, from: standardLib[tag])
        }
    }
    @IBAction func importContribLibrary(_ menuItem: AnyObject) {
        if let tag = (menuItem as? NSMenuItem)?.tag {
            NSApplication.shared().sendAction(#selector(ASProjDoc.importLibrary(_:)), to: nil, from: contribLib[tag])
        }
    }

    func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
        if let validator = NSApplication.shared().target(forAction: #selector(ASProjDoc.importLibrary(_:))) as? NSUserInterfaceValidations {
            return validator.validateUserInterfaceItem(anItem)
        }
        return false
    }
}
