//
//  ASProjDoc.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Swift
import Cocoa

private var keyboardHandler   : ACEKeyboardHandler = .ace

func pushToFront( list: inout [String], front: String) {
    let kMaxRecents = 8
    
    if let existing = list.index(of: front) {
        if existing == 0 {
            return
        } else {
            list.remove(at: existing)
        }
    } else if list.count >= kMaxRecents {
        list.removeLast()
    }
    list.insert(front, at: 0)
}

class ASProjDoc: NSDocument, NSOutlineViewDelegate, NSMenuDelegate, NSOpenSavePanelDelegate, ACEViewDelegate {
    @IBOutlet weak var editor   : ACEView!
    @IBOutlet weak var auxEdit  : ACEView!
    @IBOutlet weak var editors  : NSStackView!
    @IBOutlet weak var outline  : NSOutlineView!
    @IBOutlet weak var boardTool: NSPopUpButton!
    @IBOutlet weak var progTool : NSPopUpButton!
    @IBOutlet weak var portTool : NSPopUpButton!
    @IBOutlet weak var printView: ACEView!
    
    let files                   = ASFileTree()
    let builder                 = ASBuilder()
    var mainEditor              : ASFileNode?
    var currentTheme            : ACETheme = .xcode
    var fontSize                : UInt = 12
    var themeObserver           : AnyObject!
    var serialObserver          : AnyObject!
    dynamic var board           = "uno"
    dynamic var programmer      = "arduino"
    dynamic var port            : String = ""
    var recentBoards            = [String]()
    var recentProgrammers       = [String]()
    var logModified             = Date.distantPast
    var logSize                 = 0
    var updateLogTimer          : Timer?
    var printingDone            : () -> () = {}
    var printModDate            : Date?
    var printRevision           : String?
    var printShowPanel          = false
    var jumpingToIssue          = false
    var currentIssueLine        = -1

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
        let userDefaults = UserDefaults.standard
        if let themeName = userDefaults.string(forKey: kThemeKey) {
            if let themeId = ACEView.themeIdByName(themeName: themeName) {
                currentTheme = themeId
            }
        }
        if let handlerName = userDefaults.string(forKey: kBindingsKey) {
            if let handlerId = ACEView.handlerIdByName(handlerName: handlerName) {
                keyboardHandler = handlerId
            }
        }
        
        fontSize = UInt(userDefaults.integer(forKey: kFontSizeKey))
        board               = userDefaults.string(forKey: kBoardKey)!
        programmer          = userDefaults.string(forKey: kProgrammerKey)!
        port                = userDefaults.string(forKey: kPortKey)!
        recentBoards        = userDefaults.object(forKey: kRecentBoardsKey) as! [String]
        recentProgrammers   = userDefaults.object(forKey: kRecentProgrammersKey) as! [String]
        
        let nc          = NotificationCenter.default
        themeObserver   = nc.addObserver(forName: NSNotification.Name(kBindingsKey), object: nil, queue: nil, using: { (NSNotification) in
            self.editor?.setKeyboardHandler(keyboardHandler)
        })
        serialObserver  = nc.addObserver(forName: NSNotification.Name(kASSerialPortsChanged), object: nil, queue: nil, using: { (NSNotification) in
            if self.portTool != nil {
                self.rebuildPortMenu()
            }
        })
        updateLogTimer  =
            Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(ASProjDoc.updateLog(_:)), userInfo: nil, repeats: true)
    }
    override func finalize() {
        saveCurEditor()
        NotificationCenter.default.removeObserver(themeObserver)
        NotificationCenter.default.removeObserver(serialObserver)
    }
    
    override func windowControllerDidLoadNib(_ aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        editor.setShowPrintMargin(false)
        editor.setTheme(currentTheme)
        editor.setKeyboardHandler(keyboardHandler)
        editor.setFontSize(fontSize)
        editor.delegate = self

        auxEdit.setShowPrintMargin(false)
        auxEdit.setTheme(currentTheme)
        auxEdit.setKeyboardHandler(keyboardHandler)
        auxEdit.setFontSize(fontSize)

        editors.setViews([editor], in: .top)

        outline.register(forDraggedTypes: [files.kLocalReorderPasteboardType])
        outline.setDraggingSourceOperationMask(NSDragOperation.every, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)

        outline.dataSource = files
        files.apply() { node in
            if let group = node as? ASFileGroup {
                if group.expanded {
                    self.outline.expandItem(node)
                }
            }
        }
        outlineViewSelectionDidChange(Notification(name: Notification.Name(""), object: nil))
        menuNeedsUpdate(boardTool.menu!)
        menuNeedsUpdate(progTool.menu!)
        rebuildPortMenu()
        updateChangeCount(.changeCleared)
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
            do {
                try editor.string().write(to: file.url, atomically: true, encoding: String.Encoding.utf8)
            } catch _ {
            }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let data = [kVersionKey: kCurVersion,
            kThemeKey: ACEThemeNames.name(for: currentTheme),
            kFontSizeKey: fontSize,
            kFilesKey: files.propertyList(),
            kBoardKey: board,
            kProgrammerKey: programmer,
            kPortKey: port,
            kRecentBoardsKey: recentBoards,
            kRecentProgrammersKey: recentProgrammers
        ] as [String : Any]
        return try PropertyListSerialization.data(fromPropertyList: data, format:.xml, options:0)
    }

    func updateProjectURL() {
        files.setProjectURL(url: fileURL!)
        builder.setProjectURL(url: fileURL!)
    }

    func importProject(url: URL) throws {
        let existingProject = url.appendingPathComponent(url.lastPathComponent+".avrsackproj")
        if let hasProject = try? existingProject.checkResourceIsReachable(), hasProject {
            fileURL = existingProject
            try read(from: existingProject, ofType:"Project")
            return
        }
        let filesInProject =
            (try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles)) 
        updateProjectURL()
        for file in filesInProject {
            files.addFileURL(url: file)
        }
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        if typeName == "Arduino Source File" {
            let projectURL = url.deletingPathExtension().appendingPathExtension("avrsackproj")
            try importProject(url: url.deletingLastPathComponent())
            fileURL = projectURL
            try write(to: projectURL, ofType: "Project", for: .saveAsOperation, originalContentsURL: nil)
         } else {
            fileURL = url
            try super.read(from: url, ofType: typeName)
        }
    }
    override func read(from data: Data, ofType typeName: String) throws {
        if typeName != ("Project" as String) {
            throw NSError(domain: "AVRSack", code: 0, userInfo: nil)
        }
        updateProjectURL()
        let projectData =
            (try PropertyListSerialization.propertyList(from: data, options:[], format:nil)) as! NSDictionary
        let projectVersion = projectData[kVersionKey] as! Double
        assert(projectVersion <= floor(kCurVersion+1.0), "Project version too new for this app")
        if let themeName = projectData[kThemeKey] as? String {
            if let themeId = ACEView.themeIdByName(themeName: themeName) {
                currentTheme = themeId
            }
        }
        if let fontSz = projectData[kFontSizeKey] as? Int {
            fontSize = UInt(fontSz)
        }
        files.readPropertyList(prop: projectData[kFilesKey] as? Dictionary<String, AnyObject> ?? [:])
        board               = (projectData[kBoardKey] as? String) ?? board
        programmer          = (projectData[kProgrammerKey] as? String) ?? programmer
        port                = (projectData[kPortKey] as? String) ?? port
        recentBoards        = (projectData[kRecentBoardsKey] as? [String]) ?? recentBoards
        recentProgrammers   = (projectData[kRecentProgrammersKey] as? [String]) ?? recentProgrammers
        updateChangeCount(.changeCleared)
    }

    override func duplicate(_ sender: Any?) {
        let app = NSApplication.shared().delegate as! ASApplication
        app.openTemplate(template: fileURL!.deletingLastPathComponent(), fromReadOnly:false)
    }

    func updateLog(_: AnyObject?) {
        if let logNode = mainEditor as? ASLogNode {
            guard let fileURL = fileURL else { return }
            let url = fileURL.deletingLastPathComponent().appendingPathComponent(logNode.path)
            if let values = try? url.resourceValues(forKeys: [.attributeModificationDateKey, .fileSizeKey]) {
                if values.attributeModificationDate!.compare(logModified) == .orderedDescending
                 || values.fileSize! != logSize
                {
                    var enc : String.Encoding  = .utf8
                    let newText     = try? String(contentsOf: url, usedEncoding:&enc)
                    editor.setString(newText ?? "")
                    editor.gotoLine(1000000000, column: 0, animated: true)
                    logModified         = values.attributeModificationDate!
                    logSize             = values.fileSize!
                    currentIssueLine    = -1
                }
            }
        }
    }
    func selectNode(selection: ASFileNode?) {
        if selection !== mainEditor {
            saveCurEditor()
        }
        if let file = (selection as? ASFileItem) {
            var enc : String.Encoding  = .utf8
            let contents = try? String(contentsOf:file.url, usedEncoding:&enc)
            editor.setString(contents ?? "")
            editor.setMode(file.type.aceMode)
            editor.alphaValue = 1.0
            mainEditor = selection
        } else if selection is ASLogNode {
            editor.setString("")
            editor.setMode(.text)
            editor.alphaValue = 0.8
            logModified = NSDate.distantPast
            logSize     = -1
            mainEditor  = selection
            updateLog(nil)
        } else {
            editor.alphaValue = 0.0
        }
    }
    func selectNodeInOutline(selection: ASFileNode) {
        let selectedIndexes = IndexSet(integer: outline.row(forItem: selection))
        outline.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
    }
    func selectedFiles() -> [ASFileItem] {
        var selection = [ASFileItem]()
        for index in outline.selectedRowIndexes {
            if let file = self.outline.item(atRow: index) as? ASFileItem {
                selection.append(file)
            }
        }
        return selection
    }

    // MARK: Printing

    override func print(withSettings printSettings: [String : Any], showPrintPanel: Bool, delegate: Any?, didPrint didPrintSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        printingDone =
            { () -> () in
                InvokeCallback(delegate, didPrintSelector, contextInfo);
            }
        printModDate = nil
        if let logNode = mainEditor as? ASLogNode {
            if let url = fileURL?.deletingLastPathComponent().appendingPathComponent(logNode.path),
               let values = try? url.resourceValues(forKeys: [.attributeModificationDateKey])
            {
                printModDate = values.attributeModificationDate
            }
        }
        if printModDate == nil {
            printModDate    = mainEditor?.modDate()
        }
        printRevision   = mainEditor?.revision()
        printShowPanel  = showPrintPanel

        editor.print(self)
    }

    func printInformation() -> NSPrintInfo! {
        let info = printInfo.copy() as! NSPrintInfo

        //
        // Minimize margins
        //
        let kXMargin : CGFloat = 50.0
        let kYMargin : CGFloat = 50.0
        let paperSize   = info.paperSize
        var maxBounds   = info.imageablePageBounds

        if paperSize.width - maxBounds.size.width < kXMargin {
            let adjust = kXMargin-paperSize.width+maxBounds.size.width
            maxBounds.origin.x      += 0.5*adjust
            maxBounds.size.width    -= adjust
        }
        if paperSize.height - maxBounds.size.height < kYMargin {
            let adjust = kYMargin-paperSize.height+maxBounds.size.height
            maxBounds.origin.y      += 0.5*adjust
            maxBounds.size.height   -= adjust
        }
        info.leftMargin    = maxBounds.origin.x
        info.bottomMargin  = maxBounds.origin.y
        info.topMargin     = paperSize.height-maxBounds.size.height-info.bottomMargin
        info.rightMargin   = paperSize.width-maxBounds.size.width-info.leftMargin

        return info
    }

    func startPrintOperation(printOp: NSPrintOperation) {
        if let editorName = mainEditor?.name {
            printOp.jobTitle = editorName
        } else if let fileName = fileURL?.lastPathComponent {
            printOp.jobTitle = (fileName as NSString).deletingLastPathComponent
        } else {
            printOp.jobTitle = "Untitled"
        }
        printOp.showsPrintPanel = printShowPanel
    }

    func printHeaderHeight() -> Float {
        return 41.0
    }

    func printFooterHeight() -> Float {
        return 20.0
    }

    func drawPrintHeader(forPage pageNo: Int32, in r: NSRect) {
        var rect = r
        rect.origin.y       += 5.0
        rect.size.height    -= 5.0

        let ctx = NSGraphicsContext.current()!
        ctx.saveGraphicsState()
        NSColor(white: 0.95, alpha: 1.0).setFill()
        var wideBox = rect
        wideBox.size.height = 20.0
        wideBox.origin.y   += 0.5*(rect.size.height-wideBox.size.height)
        NSRectFill(wideBox)

        NSColor(white: 0.7, alpha: 1.0).setFill()
        var pageNoBox = rect
        pageNoBox.size.width = 50.0
        pageNoBox.origin.x  += 0.5*(rect.size.width-pageNoBox.size.width)
        NSRectFill(pageNoBox)
        ctx.restoreGraphicsState()

        let pageNoFont = NSFont.userFixedPitchFont(ofSize: 25.0)!
        let pageNoAttr = [
            NSFontAttributeName: pageNoFont,
            NSForegroundColorAttributeName: NSColor.white,
            NSStrokeWidthAttributeName: -5.0] as [String : Any]
        let pageNoStr  = "\(pageNo)"
        let pageNoSize = pageNoStr.size(withAttributes: pageNoAttr)
        let pageNoAt   = NSPoint(
            x: pageNoBox.origin.x+0.5*(pageNoBox.size.width-pageNoSize.width),
            y: pageNoBox.origin.y+3.5)
        pageNoStr.draw(at: pageNoAt, withAttributes:pageNoAttr)

        let kXOffset  : CGFloat = 5.0
        let titleFont = NSFont.userFont(ofSize: 12.0)!
        let titleAttr = [NSFontAttributeName:titleFont]
        var titleAt   = NSPoint(
            x: wideBox.origin.x+kXOffset,
            y: wideBox.origin.y+0.5*(wideBox.size.height-titleFont.ascender+titleFont.descender))

        if let fileNameStr = mainEditor?.name {
            fileNameStr.draw(at: titleAt, withAttributes:titleAttr)
        }
        if let projectNameStr = fileURL?.lastPathComponent {
            let projectNameTrimmed = (projectNameStr as NSString).deletingPathExtension
            let projectNameSize = projectNameTrimmed.size(withAttributes: titleAttr)
            titleAt.x = wideBox.origin.x+wideBox.size.width-projectNameSize.width-kXOffset
            projectNameTrimmed.draw(at: titleAt, withAttributes:titleAttr)
        }
    }

    func drawPrintFooter(forPage pageNo: Int32, in r: NSRect) {
        var rect = r
        rect.size.height    -= 5.0

        let ctx = NSGraphicsContext.current()!
        ctx.saveGraphicsState()
        NSColor(white: 0.95, alpha: 1.0).setFill()
        NSRectFill(rect)
        ctx.restoreGraphicsState()

        let kXOffset  : CGFloat = 5.0
        let footFont  = NSFont.userFixedPitchFont(ofSize: 10.0)!
        let footAttr  = [NSFontAttributeName:footFont]
        var footAt   = NSPoint(
            x: rect.origin.x+kXOffset,
            y: rect.origin.y+0.5*(rect.size.height-footFont.ascender+footFont.descender))

        if let revisionStr = printRevision {
            revisionStr.draw(at: footAt, withAttributes:footAttr)
        }
        if let modDate = printModDate
        {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            let modDateStr = dateFormatter.string(from: modDate)
            let modDateSize = modDateStr.size(withAttributes: footAttr)
            footAt.x = rect.origin.x+rect.size.width-modDateSize.width-kXOffset
            modDateStr.draw(at: footAt, withAttributes:footAttr)
        }
    }

    func endPrintOperation() {
        printingDone()
    }

    // MARK: Outline View Delegate

    func outlineViewSelectionDidChange(_ notification: Notification) {
        willChangeValue(forKey: "hasSelection")
        if !jumpingToIssue {
            editors.setViews([], in: .bottom)
        }
        if outline.numberOfSelectedRows < 2 {
            selectNode(selection: outline.item(atRow: outline.selectedRow) as! ASFileNode?)
        }
        didChangeValue(forKey: "hasSelection")
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        let group       = notification.userInfo!["NSObject"] as! ASFileGroup
        group.expanded  = true
        updateChangeCount(.changeDone)
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        let group       = notification.userInfo!["NSObject"] as! ASFileGroup
        group.expanded  = false
        updateChangeCount(.changeDone)
    }
    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, item: Any) {
        if let textCell = cell as? NSTextFieldCell, let item = item as? ASFileNode {
            textCell.textColor = NSColor.black
            if item === files.root || item === files.buildLog || item === files.uploadLog || item === files.disassembly {
                textCell.font = NSFont.boldSystemFont(ofSize: 13.0)
            } else {
                textCell.font = NSFont.systemFont(ofSize: 13.0)
                if !item.exists() {
                    textCell.textColor = NSColor.red
                }
            }
        }
    }
    func outlineView(_ outlineView: NSOutlineView, shouldTrackCell cell: NSCell, for tableColumn: NSTableColumn?, item: Any) -> Bool {
        return outlineView.isRowSelected(outlineView.row(forItem: item))
    }

    // MARK: File manipulation
    @IBAction func delete(_: AnyObject) {
        let selection  = selectedFiles()
        var name       : String
        var ref        : String
        if selection.count == 1 {
            name    = "file “\(selection[0].url.lastPathComponent)”"
            ref     = "reference to it"
        } else {
            name    = "\(selection.count) selected files"
            ref     = "references to them"
        }
        let alert           = NSAlert()
        alert.messageText   =
            "Do you want to move the \(name) to the Trash, or only remove the \(ref)?"
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: selection.count == 1 ? "Remove Reference" : "Remove References")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        alert.beginSheetModal(for: outline.window!) { (response) in
            if response != NSAlertThirdButtonReturn {
                if response == NSAlertFirstButtonReturn {
                    NSWorkspace.shared().recycle(selection.map {$0.url}, completionHandler:nil)
                }
                self.files.apply { (node) in
                    if let group = node as? ASFileGroup {
                        for file in selection {
                            for (groupIdx, groupItem) in group.children.enumerated() {
                                if file as ASFileNode === groupItem {
                                    group.children.remove(at: groupIdx)
                                    break
                                }
                            }
                        }
                    }
                }
                self.outline.deselectAll(self)
                self.outline.reloadData()
                self.updateChangeCount(.changeDone)
            }
        }
    }

    @IBAction func add(_: AnyObject) {
        let panel = NSOpenPanel()
        panel.canChooseFiles            = true
        panel.canChooseDirectories      = false
        panel.allowsMultipleSelection   = true
        panel.allowedFileTypes          = ["h", "hpp", "hh", "c", "cxx", "c++", "cpp", "cc", "ino", "s", "md"]
        panel.delegate                  = self
        panel.beginSheetModal(for: outline.window!, completionHandler: { (returnCode: Int) -> Void in
            if returnCode == NSFileHandlingPanelOKButton {
                for url in panel.urls {
                    self.files.addFileURL(url: url)
                }
                self.outline.deselectAll(self)
                self.outline.reloadData()
                self.updateChangeCount(.changeDone)
            }
        })

    }

    func panel(_ panel:Any, shouldEnable url:URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let resourceID = values.fileResourceIdentifier
        else {
            return true
        }
        var shouldEnable = true
        files.apply {(node) in
            if let file = node as? ASFileItem,
               let values = try? file.url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
               let thisID = values.fileResourceIdentifier
            {
                if resourceID.isEqual(thisID) {
                    shouldEnable = false
                }
            }
        }
        return shouldEnable
    }

    var hasSelection : Bool {
        return selectedFiles().count > 0
    }

    func createFileAtURL(url: URL) {
        let type        = ASFileType.guessForURL(url: url)
        var firstPfx    = ""
        var prefix      = ""
        var lastPfx     = ""
        switch type {
        case .Header, .CFile:
            firstPfx    = "/*"
            prefix      = " *"
            lastPfx     = " */"
        case .CppFile, .Arduino:
            prefix      = "//"
        case .AsmFile:
            prefix      = ";"
        case .Markdown:
            firstPfx    = "<!---"
            prefix      = " "
            lastPfx     = " -->"
        default:
            break
        }
        var header = ""
        if prefix != ("" as String) {
            if firstPfx == "" {
                firstPfx    = prefix
            }
            if lastPfx == "" {
                lastPfx     = prefix
            }
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            header = firstPfx + "\n" +
                prefix + " Project: " + fileURL!.deletingLastPathComponent().lastPathComponent + "\n" +
                prefix + " File:    " + url.lastPathComponent + "\n" +
                prefix + " Created: " + dateFmt.string(from: Date()) + "\n" +
                lastPfx + "\n\n"
        }
        do {
            try header.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        } catch _ {
        }
        files.addFileURL(url: url)
        outline.reloadData()
    }

    @IBAction func createFile(_: AnyObject) {
        let savePanel                       = NSSavePanel()
        savePanel.allowedFileTypes          =
            [kUTTypeCSource as String, kUTTypeCHeader as String, kUTTypeCPlusPlusSource as String, kUTTypeAssemblyLanguageSource as String,
             "public.assembly-source", "net.daringfireball.markdown"]
        savePanel.beginSheetModal(for: outline.window!, completionHandler: { (returnCode) -> Void in
            if returnCode == NSFileHandlingPanelOKButton {
                self.createFileAtURL(url: savePanel.url!)
            }
        })
    }

    func importLibrary(_ lib: String) {
        var includes    = ""
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(atPath: lib) {
            for file in files {
                if file.hasSuffix(".h") {
                    includes += "#include <\(file)>\n"
                }
            }
        }
        let text    = editor.string() as NSString
        var insert  = NSMakeRange(text.length, 0)
        let postHeaderComments = try! NSRegularExpression(pattern: "((?:\\s+|/\\*.*?\\*/|//.*?\\n)*)(.*?\\n)", options: .dotMatchesLineSeparators)
        if let match = postHeaderComments.firstMatch(in: text as String, options:.anchored, range:NSMakeRange(0, text.length)) {
            let range       = match.rangeAt(2)
            insert.location = range.location
            let content     = text.substring(with: range)
            if !content.hasPrefix("#include") {
                includes += "\n"
            }
        }

        editor.setString(text.replacingCharacters(in: insert, with: includes))
    }

    // MARK: Editor configuration
    
    @IBAction func changeTheme(_ item: NSMenuItem) {
        currentTheme = ACETheme(rawValue: UInt(item.tag)) ?? .xcode
        editor.setTheme(currentTheme)
        UserDefaults.standard.set(
            ACEThemeNames.humanName(for: currentTheme), forKey: kThemeKey)
        updateChangeCount(.changeDone)
    }
    @IBAction func changeKeyboardHandler(_ item: NSMenuItem) {
        keyboardHandler = ACEKeyboardHandler(rawValue: UInt(item.tag))!
        UserDefaults.standard.set(
            ACEKeyboardHandlerNames.humanName(for: keyboardHandler), forKey: kBindingsKey)
        NotificationCenter.default.post(name: NSNotification.Name(kBindingsKey), object: item)
    }
    
    override func validateUserInterfaceItem(_ anItem: NSValidatedUserInterfaceItem) -> Bool {
        if let menuItem = anItem as? NSMenuItem {
            if menuItem.action == #selector(ASProjDoc.changeTheme(_:)) {
                menuItem.state = (UInt(menuItem.tag) == currentTheme.rawValue ? NSOnState : NSOffState)
                return true
            } else if menuItem.action == #selector(ASProjDoc.changeKeyboardHandler(_:)) {
                menuItem.state = (menuItem.tag == Int(keyboardHandler.rawValue) ? NSOnState : NSOffState)
                return true
            } else if menuItem.action == #selector(ASProjDoc.serialConnect(_:)) {
                menuItem.title = port

                return true
            } else if menuItem.action == #selector(ASLibraries.importStandardLibrary(_:)) ||
                menuItem.action == #selector(ASLibraries.importContribLibrary(_:))
            {
                return mainEditor is ASFileItem
            }
        }
        return super.validateUserInterfaceItem(anItem)
    }
    
    @IBAction func makeTextLarger(_: AnyObject) {
        fontSize += 1
        editor.setFontSize(fontSize)
        updateChangeCount(.changeDone)
    }
    @IBAction func makeTextSmaller(_: AnyObject) {
        if fontSize > 6 {
            fontSize -= 1
            editor.setFontSize(fontSize)
            updateChangeCount(.changeDone)
        }
    }

    // MARK: Issues
    @IBAction func jumpToIssue(_ sender: AnyObject) {
        let direction : Int = (sender as! NSMenuItem).tag
        if editors.views(in: .bottom).count == 0 {
            editors.addView(auxEdit, in: .bottom)

            let url = fileURL?.deletingLastPathComponent().appendingPathComponent(files.buildLog.path)
            if url == nil {
                return
            }
            var enc : String.Encoding = .utf8
            let contents = try? String(contentsOf:url!, usedEncoding:&enc)
            auxEdit.setString(contents ?? "")
            editor.setMode(.text)
            editor.alphaValue = 1.0
        }
        let buildLog = auxEdit.string().components(separatedBy: "\n")
        let issueRe  = try! NSRegularExpression(pattern: "(\\S+?):(\\d+):.*", options: [])

        currentIssueLine += direction
        while currentIssueLine > -1 && currentIssueLine < buildLog.count {
            let line    = buildLog[currentIssueLine]
            let range   = NSMakeRange(0, line.utf16.count)
            if let match = issueRe.firstMatch(in: line, options:.anchored, range:range) {
                let file        = match.rangeAt(1)
                let lineTxt     = match.rangeAt(2)
                let nsline      = line as NSString
                let lineNo      = Int(nsline.substring(with: lineTxt))!
                let fileName    = nsline.substring(with: file) as NSString
                let fileURL : URL

                if fileName.hasPrefix("../../") {
                    fileURL = files.dir.appendingPathComponent(fileName.substring(from: 6))
                } else {
                    fileURL = URL(fileURLWithPath:fileName as String).standardizedFileURL
                }

                jumpingToIssue = true
                if let values = try? fileURL.resourceValues(forKeys: [.fileResourceIdentifierKey]),
                   let resourceID = values.fileResourceIdentifier
                {
                    files.apply {(node) in
                        if let file = node as? ASFileItem,
                           let values = try? file.url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
                           let thisID = values.fileResourceIdentifier,
                           resourceID.isEqual(thisID)
                        {
                            self.selectNodeInOutline(selection: node)
                            self.editor.gotoLine(lineNo, column:0, animated:true)
                        }
                    }
                }
                jumpingToIssue = false

                auxEdit.gotoLine(currentIssueLine+1, column:0, animated: true)
                break
            }
            currentIssueLine += direction
        }
    }
    
    // MARK: Build / Upload
    
    @IBAction func buildProject(_: AnyObject) {
        selectNodeInOutline(selection: files.buildLog)
        builder.buildProject(board: board, files: files)
    }
    
    @IBAction func cleanProject(_: AnyObject) {
        builder.cleanProject()
        selectNodeInOutline(selection: files.buildLog)
    }

    func rebuildPortMenu() {
        willChangeValue(forKey: "hasValidPort")
        portTool.removeAllItems()
        portTool.addItem(withTitle: "Title")
        portTool.addItems(withTitles: ASSerial.ports())
        portTool.setTitle(port)
        didChangeValue(forKey: "hasValidPort")
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "Boards":
            ASHardware.instance().buildBoardsMenu(menu: menu, recentBoards: recentBoards,
                                                  target: self, selector: #selector(ASProjDoc.selectBoard(_:)))
            boardTool.setTitle(selectedBoard)
        case "Programmers":
            ASHardware.instance().buildProgrammersMenu(menu: menu, recentProgrammers: recentProgrammers,
                target: self, selector: #selector(ASProjDoc.selectProgrammer(_:)))
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

                    pushToFront(list: &recentBoards, front: board)
                    
                    let userDefaults = UserDefaults.standard
                    var globalBoards = userDefaults.object(forKey:kRecentBoardsKey) as! [String]
                    pushToFront(list: &globalBoards, front: board)
                    userDefaults.set(globalBoards, forKey: kRecentBoardsKey)

                    updateChangeCount(.changeDone)
                    menuNeedsUpdate(boardTool.menu!)
                    
                    break
                }
            }
        }
    }
    
    @IBAction func selectBoard(_ item: AnyObject) {
        selectedBoard = (item as! NSMenuItem).title
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
                    
                    pushToFront(list: &recentProgrammers, front: programmer)
                    
                    let userDefaults = UserDefaults.standard
                    var globalProgs = userDefaults.object(forKey:kRecentProgrammersKey) as! [String]
                    pushToFront(list: &globalProgs, front: programmer)
                    userDefaults.set(globalProgs, forKey: kRecentProgrammersKey)
                    
                    updateChangeCount(.changeDone)
                    progTool.setTitle(newProg)
                    menuNeedsUpdate(progTool.menu!)
                    
                    break
                }
            }
        }
    }
    
    @IBAction func selectProgrammer(_ item: AnyObject) {
        selectedProgrammer = (item as! NSMenuItem).title
    }
    
    @IBAction func selectPort(_ item: AnyObject) {
        port    = (item as! NSPopUpButton).titleOfSelectedItem!
        portTool.setTitle(port)
    }
    
    var hasUploadProtocol : Bool {
        get {
            if let proto = ASHardware.instance().boards[board]?["upload.protocol"] {
                return proto != ("" as String)
            } else {
                return false
            }
        }
    }
    class func keyPathsForValuesAffectingHasUploadProtocol() -> NSSet {
        return NSSet(object: "board")
    }
    
    var hasValidPort : Bool {
        get {
            return ASSerial.ports().contains(port)
        }
    }
    class func keyPathsForValuesAffectingHasValidPort() -> NSSet {
        return NSSet(object: "port")
    }
    
    var canUpload : Bool {
        get {
            return hasValidPort && (hasUploadProtocol || programmer != ("" as String))
        }
    }
    class func keyPathsForValuesAffectingCanUpload() -> NSSet {
        return NSSet(objects: "hasValidPort", "hasUploadProtocol", "programmer")
    }
    
    @IBAction func uploadProject(_ sender: AnyObject) {
        builder.continuation = {
            self.selectNodeInOutline(selection: self.files.uploadLog)
            DispatchQueue.main.async(execute: {
                self.builder.uploadProject(board: self.board, programmer:self.programmer, port:self.port)
            })
        }
        buildProject(sender)
    }

    @IBAction func uploadTerminal(_: AnyObject) {
        builder.uploadProject(board: board, programmer:programmer, port:port, mode:.Interactive)
    }

    @IBAction func burnBootloader(_: AnyObject) {
        self.selectNodeInOutline(selection: self.files.uploadLog)
        builder.uploadProject(board: board, programmer:programmer, port:port, mode:.BurnBootloader)
    }

    @IBAction func disassembleProject(_ sender: AnyObject) {
        builder.continuation = {
            self.selectNodeInOutline(selection: self.files.disassembly)
            self.builder.disassembleProject(board: self.board)
        }
        buildProject(sender)
    }
    
    @IBAction func serialConnect(_: AnyObject) {
        ASSerialWin.showWindowWithPort(port: port)
    }
}

