//
//  ASProjDoc.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Swift
import Cocoa

private var keyboardHandler   : ACEKeyboardHandler = .Ace

func pushToFront(inout list: [String], front: String) {
    let kMaxRecents = 8
    
    if let existing = find(list, front) {
        if existing == 0 {
            return
        } else {
            list.removeAtIndex(existing)
        }
    } else if list.count >= kMaxRecents {
        list.removeLast()
    }
    list.insert(front, atIndex: 0)
}

class ASProjDoc: NSDocument, NSOutlineViewDelegate, NSMenuDelegate {
    @IBOutlet weak var editor   : ACEView!
    @IBOutlet weak var outline  : NSOutlineView!
    @IBOutlet weak var boardTool: NSPopUpButton!
    @IBOutlet weak var progTool : NSPopUpButton!
    @IBOutlet weak var portTool : NSPopUpButton!
    
    let files                   = ASFileTree()
    let builder                 = ASBuilder()
    var mainEditor              : ASFileNode?
    var currentTheme            : UInt = 0
    var fontSize                : UInt = 12
    var themeObserver           : AnyObject?
    var board                   = "uno"
    var programmer              = "arduino"
    var port                    = ""
    var recentBoards            = [String]()
    var recentProgrammers       = [String]()
    var logModified             = NSDate.distantPast() as NSDate
    var logSize                 = 0
    var updateLogTimer          : NSTimer?
    
    let kVersionKey             = "Version"
    let kCurVersion             = 1.0
    let kFilesKey               = "Files"
    let kThemeKey               = "Theme"
    let kFontSizeKey            = "FontSize"
    let kBindingsKey            = "Bindings"
    let kBoardKey               = "Board"
    let kProgrammerKey          = "Programmer"
    let kPortKey                = "Port"
    let kRecentBoardsKey        = "RecentBoards"
    let kRecentProgrammersKey   = "RecentProgrammers"

    // MARK: Initialization / Finalization
    
    override init() {
        super.init()
        let userDefaults = NSUserDefaults.standardUserDefaults()
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
        board               = userDefaults.stringForKey(kBoardKey)!
        programmer          = userDefaults.stringForKey(kProgrammerKey)!
        port                = userDefaults.stringForKey(kPortKey)!
        recentBoards        = userDefaults.objectForKey(kRecentBoardsKey) as [String]
        recentProgrammers   = userDefaults.objectForKey(kRecentProgrammersKey) as [String]
        
        updateLogTimer  =
            NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: "updateLog:", userInfo: nil, repeats: true)
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
        menuNeedsUpdate(boardTool.menu!)
        menuNeedsUpdate(progTool.menu!)
        portTool.removeAllItems()
        portTool.addItemWithTitle("Title")
        portTool.addItemsWithTitles(ASSerial.ports())
        portTool.setTitle(port)
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
            kFilesKey: files.propertyList(),
            kBoardKey: board,
            kProgrammerKey: programmer,
            kPortKey: port
        ]
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
                builder.setProjectURL(fileURL!)
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
        builder.setProjectURL(fileURL!)
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
        board               = (projectData[kBoardKey] as? String) ?? board
        programmer          = (projectData[kProgrammerKey] as? String) ?? programmer
        port                = (projectData[kPortKey] as? String) ?? port
        recentBoards        = (projectData[kRecentBoardsKey] as? [String]) ?? recentBoards
        recentProgrammers   = (projectData[kRecentProgrammersKey] as? [String]) ?? recentProgrammers
        updateChangeCount(.ChangeCleared)
        
        return true
    }
 
    func updateLog(AnyObject?) {
        if let logNode = mainEditor as? ASLogNode {
            let url = fileURL!.URLByDeletingLastPathComponent?.URLByAppendingPathComponent(logNode.path)
            if url == nil {
                return
            }
            var modified : AnyObject?
            var size     : AnyObject?
            if (!url!.getResourceValue(&modified, forKey:NSURLAttributeModificationDateKey, error:nil)) {
                return
            }
            if (!url!.getResourceValue(&size, forKey:NSURLFileSizeKey, error:nil)) {
                return
            }
            
            if (modified as NSDate).compare(logModified) == .OrderedDescending || (size as Int) != logSize {
                var enc : UInt  = 0
                let newText     = NSString(contentsOfURL:url!, usedEncoding:&enc, error:nil)
                editor.setString(newText)
                editor.gotoLine(1000000000, column: 0, animated: true)
                logModified = modified as NSDate
                logSize     = size as Int
            }
        }
    }
    func selectNode(selection: ASFileNode?) {
        if selection !== mainEditor {
            saveCurEditor()
        }
        if let file = (selection as? ASFileItem) {
            var enc : UInt = 0
            editor.setString(NSString(contentsOfURL:file.url, usedEncoding:&enc, error:nil))
            editor.setMode(UInt(file.type.aceMode))
            editor.alphaValue = 1.0
            mainEditor = selection
        } else if let log = (selection as? ASLogNode) {
            editor.setString("")
            editor.setMode(UInt(ACEModeASCIIDoc))
            editor.alphaValue = 0.8
            logModified = NSDate.distantPast() as NSDate
            logSize     = -1
            mainEditor  = selection
            updateLog(nil)
        } else {
            editor.alphaValue = 0.0
        }
    }

    // MARK: Outline View Delegate

    func outlineViewSelectionDidChange(notification: NSNotification) {
        selectNode(outline.itemAtRow(outline.selectedRow) as ASFileNode?)
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
    func outlineView(outlineView: NSOutlineView, willDisplayCell cell: AnyObject, forTableColumn tableColumn: NSTableColumn?, item: AnyObject) {
        if item === files.root || item === files.buildLog || item === files.uploadLog {
            (cell as NSCell).font = NSFont.boldSystemFontOfSize(13.0)
        } else {
            (cell as NSCell).font = NSFont.systemFontOfSize(13.0)
        }
    }
    
    // MARK: Editor configuration
    
    @IBAction func changeTheme(item: NSMenuItem) {
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
            if menuItem.action == "changeTheme:" {
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
    
    // MARK: Build / Upload
    
    @IBAction func uploadProject(AnyObject) {
    }
    
    @IBAction func buildProject(AnyObject) {
        selectNode(files.buildLog)
        builder.buildProject(board, files: files)
    }
    
    @IBAction func cleanProject(AnyObject) {
        builder.cleanProject()
        selectNode(files.buildLog)
    }

    func menuNeedsUpdate(menu: NSMenu) {
        switch menu.title {
        case "Boards":
            ASHardware.instance().buildBoardsMenu(menu, recentBoards: recentBoards,
                target: self, selector: "selectBoard:")
            boardTool.setTitle(selectedBoard)
        case "Programmers":
            ASHardware.instance().buildProgrammersMenu(menu, recentProgrammers: recentProgrammers,
                target: self, selector: "selectProgrammer:")
            progTool.setTitle(selectedProgrammer)
        default:
            break
        }
    }
    
    var selectedBoard : String {
        get {
            let boardProps = ASHardware.instance().boards[board]
            return boardProps?["name"] ?? ""
        }
        set (newBoard) {
            for (ident, prop) in ASHardware.instance().boards {
                if prop["name"] == newBoard {
                    board = ident

                    pushToFront(&recentBoards, board)
                    
                    let userDefaults = NSUserDefaults.standardUserDefaults()
                    var globalBoards = userDefaults.objectForKey(kRecentBoardsKey) as [String]
                    pushToFront(&globalBoards, board)
                    userDefaults.setObject(globalBoards, forKey: kRecentBoardsKey)

                    updateChangeCount(.ChangeDone)
                    menuNeedsUpdate(boardTool.menu!)
                    
                    break
                }
            }
        }
    }
    
    @IBAction func selectBoard(item: AnyObject) {
        selectedBoard = (item as NSMenuItem).title
    }

    var selectedProgrammer : String {
        get {
            let progProps = ASHardware.instance().programmers[programmer]
            return progProps?["name"] ?? ""
        }
        set (newProg) {
            for (ident, prop) in ASHardware.instance().programmers {
                if prop["name"] == newProg {
                    programmer = ident
                    
                    pushToFront(&recentProgrammers, programmer)
                    
                    let userDefaults = NSUserDefaults.standardUserDefaults()
                    var globalProgs = userDefaults.objectForKey(kRecentProgrammersKey) as [String]
                    pushToFront(&globalProgs, programmer)
                    userDefaults.setObject(globalProgs, forKey: kRecentProgrammersKey)
                    
                    updateChangeCount(.ChangeDone)
                    progTool.setTitle(newProg)
                    menuNeedsUpdate(progTool.menu!)
                    
                    break
                }
            }
        }
    }
    
    @IBAction func selectProgrammer(item: AnyObject) {
        selectedProgrammer = (item as NSMenuItem).title
    }
    
    @IBAction func selectPort(item: AnyObject) {
        port    = (item as NSPopUpButton).titleOfSelectedItem!
        portTool.setTitle(port)
    }
    
    var hasUploadProtocol : Bool {
        get {
            return ASHardware.instance().boards[board]?["upload.protocol"] != nil
        }
    }
}

