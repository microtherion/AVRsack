//
//  ASProjDoc.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

private var keyboardHandler   : ACEKeyboardHandler = .Ace

class ASProjDoc: NSDocument, NSOutlineViewDelegate {
    @IBOutlet weak var editor   : ACEView!
    @IBOutlet weak var outline  : NSOutlineView!
    let files                   : ASFileTree = ASFileTree()
    var mainEditor              : ASFileNode?
    var currentTheme            : UInt = 0
    var fontSize                : UInt = 12
    var themeObserver           : AnyObject?
    
    let kVersionKey     = "Version"
    let kCurVersion     = 1.0
    let kFilesKey       = "Files"
    let kThemeKey       = "Theme"
    let kFontSizeKey    = "FontSize"
    let kBindingsKey    = "Bindings"

    // MARK: Initialization / Finalization
    
    override init() {
        super.init()
        let userDefaults = NSUserDefaults.standardUserDefaults()
        userDefaults.registerDefaults([kThemeKey: "xcode", kFontSizeKey: 12, kBindingsKey: "Ace"])
        if let themeName = userDefaults.stringForKey(kThemeKey) {
            for (themeIdx, theme) in enumerate(ACEThemeNames.themeNames() as [NSString]) {
                if themeName == theme {
                    currentTheme = UInt(themeIdx)
                    break
                }
            }
        }
        if let handlerName = userDefaults.stringForKey(kBindingsKey) {
            for (handlerIdx, handler) in enumerate(ACEKeyboardHandlerNames.humanKeyboardHandlerNames() as [NSString]) {
                if handlerName == handler {
                    keyboardHandler = ACEKeyboardHandler(rawValue: UInt(handlerIdx))!
                    break
                }
            }
        }
        fontSize = UInt(userDefaults.integerForKey(kFontSizeKey))
        themeObserver = NSNotificationCenter.defaultCenter().addObserverForName(kBindingsKey, object: nil, queue: nil, usingBlock: { (NSNotification) in
                self.editor.setKeyboardHandler(keyboardHandler)
        })
    }
    override func finalize() {
        saveCurEditor()
        NSNotificationCenter.defaultCenter().removeObserver(themeObserver!)
    }
    
    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        editor.setShowPrintMargin(false)
        editor.setTheme(currentTheme)
        editor.setKeyboardHandler(keyboardHandler)
        editor.setFontSize(fontSize)
        outline.setDataSource(files)
        files.apply() { node in
            if let group = node as? ASFileGroup {
                if group.expanded {
                    self.outline.expandItem(node)
                }
            }
        }
        updateChangeCount(.ChangeCleared)
        outlineViewSelectionDidChange(NSNotification(name: "", object: nil))
    }

    override class func autosavesInPlace() -> Bool {
        return true
    }

    override var windowNibName: String? {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return "ASProjDoc"
    }

    // MARK: Load / Save
    
    func saveCurEditor() {
        if let file = (mainEditor as? ASFileItem) {
            editor.string().writeToURL(file.url, atomically: true, encoding: NSUTF8StringEncoding, error: nil)
        }
    }
    
    override func dataOfType(typeName: String, error outError: NSErrorPointer) -> NSData? {
        let data = [kVersionKey: kCurVersion,
            kThemeKey: ACEThemeNames.nameForTheme(currentTheme),
            kFontSizeKey: fontSize,
            kFilesKey: files.propertyList()]
        return NSPropertyListSerialization.dataFromPropertyList(data, format: .XMLFormat_v1_0, errorDescription: nil)
    }

    func importProject(url: NSURL, error outError: NSErrorPointer) -> Bool {
        let existingProject = url.URLByAppendingPathComponent(url.lastPathComponent+".avrsackproj")
        if existingProject.checkResourceIsReachableAndReturnError(nil) {
            fileURL = existingProject
            return readFromURL(existingProject, ofType:"Project", error:outError)
        }
        let filesInProject =
            NSFileManager.defaultManager().contentsOfDirectoryAtURL(url, includingPropertiesForKeys: nil,
                options: .SkipsHiddenFiles, error: nil)!
        for file in filesInProject {
            files.addFileURL(file as NSURL)
        }
        return true
    }
    
    override func readFromURL(url: NSURL, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
        var success : Bool = false
        if typeName == "Arduino Source File" {
            let projectURL = url.URLByDeletingPathExtension!.URLByAppendingPathExtension("avrsackproj")
            success = importProject(url.URLByDeletingLastPathComponent!, error: outError)
            if success {
                files.setProjectURL(fileURL!)
                fileURL = projectURL
                success = writeToURL(projectURL, ofType: "Project", forSaveOperation: .SaveAsOperation, originalContentsURL: nil, error: outError)
            }
        } else {
            success = super.readFromURL(url, ofType: typeName, error: outError)
        }
        return success
    }
    override func readFromData(data: NSData, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
        if typeName != "Project" {
            return false
        }
        files.setProjectURL(fileURL!)
        let projectData : NSDictionary = NSPropertyListSerialization.propertyListFromData(data, mutabilityOption: .Immutable, format: nil, errorDescription: nil) as NSDictionary
        let projectVersion = projectData[kVersionKey] as Double
        assert(projectVersion <= floor(kCurVersion+1.0), "Project version too new for this app")
        if let themeName = projectData[kThemeKey] as? NSString {
            for (themeIdx, theme) in enumerate(ACEThemeNames.themeNames() as [NSString]) {
                if themeName == theme {
                    currentTheme = UInt(themeIdx)
                    break
                }
            }
        }
        if let fontSz = projectData[kFontSizeKey] as? Int {
            fontSize = UInt(fontSz)
        }
        files.readPropertyList(projectData[kFilesKey] as NSDictionary)
        updateChangeCount(.ChangeCleared)
        
        return true
    }
 
    // MARK: Outline View Delegate
    
    func outlineViewSelectionDidChange(notification: NSNotification) {
        let selection = outline.itemAtRow(outline.selectedRow) as ASFileNode?
        if selection !== mainEditor {
            saveCurEditor()
        }
        if let file = (selection as? ASFileItem) {
            var enc : UInt = 0
            editor.setString(NSString(contentsOfURL:file.url, usedEncoding:&enc, error:nil))
            editor.setMode(UInt(file.type.aceMode))
            editor.alphaValue = 1.0
        } else {
            editor.alphaValue = 0.0
        }
    }
    func outlineViewItemDidExpand(notification: NSNotification) {
        let group       = notification.userInfo!["NSObject"] as ASFileGroup
        group.expanded  = true
        updateChangeCount(.ChangeDone)
    }
    func outlineViewItemDidCollapse(notification: NSNotification) {
        let group       = notification.userInfo!["NSObject"] as ASFileGroup
        group.expanded  = false
        updateChangeCount(.ChangeDone)
    }
    
    // MARK: Editor configuration
    
    @IBAction func setTheme(item: NSMenuItem) {
        currentTheme = UInt(item.tag)
        editor.setTheme(currentTheme)
        NSUserDefaults.standardUserDefaults().setObject(
            ACEThemeNames.humanNameForTheme(currentTheme), forKey: kThemeKey)
        updateChangeCount(.ChangeDone)
    }
    @IBAction func changeKeyboardHandler(item: NSMenuItem) {
        keyboardHandler = ACEKeyboardHandler(rawValue: UInt(item.tag))!
        NSUserDefaults.standardUserDefaults().setObject(
            ACEKeyboardHandlerNames.humanNameForKeyboardHandler(keyboardHandler), forKey: kBindingsKey)
        NSNotificationCenter.defaultCenter().postNotificationName(kBindingsKey, object: item)
    }
    
    override func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
        if let menuItem = anItem as? NSMenuItem {
            if menuItem.action == "setTheme:" {
                menuItem.state = (menuItem.tag == Int(currentTheme) ? NSOnState : NSOffState)
                return true
            } else if menuItem.action == "changeKeyboardHandler:" {
                menuItem.state = (menuItem.tag == Int(keyboardHandler.rawValue) ? NSOnState : NSOffState)
                return true
            }
        }
        return super.validateUserInterfaceItem(anItem)
    }
    
    @IBAction func makeTextLarger(AnyObject) {
        fontSize += 1
        editor.setFontSize(fontSize)
        updateChangeCount(.ChangeDone)
    }
    @IBAction func makeTextSmaller(AnyObject) {
        if fontSize > 6 {
            fontSize -= 1
            editor.setFontSize(fontSize)
            updateChangeCount(.ChangeDone)
        }
    }
}

