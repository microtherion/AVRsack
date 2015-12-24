//
//  AppDelegate.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014-2015 Aere Perennius. All rights reserved.
//

import Cocoa
import Carbon

@NSApplicationMain
class ASApplication: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @IBOutlet var themeMenu    : NSMenu!
    @IBOutlet var keyboardMenu : NSMenu!
    @IBOutlet var preferences  : ASPreferences!
    var sketches = [String]()
    var examples = [String]()

    func hasDocument() -> Bool {
        return NSDocumentController.sharedDocumentController().currentDocument != nil
    }

    func applicationWillFinishLaunching(notification: NSNotification) {
        //
        // Retrieve static app defaults
        //
        let fileManager     = NSFileManager.defaultManager()
        let workSpace       = NSWorkspace.sharedWorkspace()
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        let appDefaultsURL  = NSBundle.mainBundle().URLForResource("Defaults", withExtension: "plist")!
        var appDefaults     = NSDictionary(contentsOfURL: appDefaultsURL) as! [String: AnyObject]
        //
        // Add dynamic app defaults
        //
        if let arduinoPath = workSpace.URLForApplicationWithBundleIdentifier("cc.arduino.Arduino")?.path {
            appDefaults["Arduino"]      = arduinoPath
        }
        var sketchbooks             = [NSString]()
        for doc in fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask) {
            sketchbooks.append(doc.URLByAppendingPathComponent("Arduino").path!)
            sketchbooks.append(doc.URLByAppendingPathComponent("AVRSack").path!)
        }
        appDefaults["Sketchbooks"]  = sketchbooks
        if fileManager.fileExistsAtPath("/usr/local/CrossPack-AVR") {
            appDefaults["Toolchain"] = "/usr/local/CrossPack-AVR"
        } else {
            appDefaults["Toolchain"] = ""
        }
        
        userDefaults.registerDefaults(appDefaults)
    }
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        themeMenu.removeAllItems()
        for (index, theme) in ACEThemeNames.humanThemeNames().enumerate() {
            let menuItem = themeMenu.addItemWithTitle(theme, action: "changeTheme:", keyEquivalent: "")!
            menuItem.tag = index
        }
        keyboardMenu.removeAllItems()
        for (index, theme) in ACEKeyboardHandlerNames.humanKeyboardHandlerNames().enumerate() {
            let menuItem = keyboardMenu.addItemWithTitle(theme, action: "changeKeyboardHandler:", keyEquivalent: "")!
            menuItem.tag = index
        }
    }
    func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
        return false
    }
    func applicationWillTerminate(aNotification: NSNotification) {
    }

    func menuNeedsUpdate(menu: NSMenu) {
        switch menu.title {
        case "Sketchbook":
            menu.removeAllItems()
            sketches = [String]()
            for sketchBook in NSUserDefaults.standardUserDefaults().objectForKey("Sketchbooks") as! [String] {
                if NSFileManager.defaultManager().fileExistsAtPath(sketchBook) {
                    ASSketchBook.addSketches(menu, target: self, action: "openSketch:", path: sketchBook, sketches: &sketches)
                }
            }
        case "Examples":
            menu.removeAllItems()
            examples = [String]()
            if let arduinoURL = NSWorkspace.sharedWorkspace().URLForApplicationWithBundleIdentifier("cc.arduino.Arduino") {
                let examplePath = arduinoURL.URLByAppendingPathComponent("Contents/Resources/Java/examples", isDirectory:true).path!
                ASSketchBook.addSketches(menu, target: self, action: "openExample:", path: examplePath, sketches: &examples)
            }
        case "Import Standard Library":
            menu.removeAllItems()
            ASLibraries.instance().addStandardLibrariesToMenu(menu)
        case "Import Contributed Library":
            menu.removeAllItems()
            ASLibraries.instance().addContribLibrariesToMenu(menu)
        case "Serial Monitor":
            menu.itemAtIndex(0)?.hidden = !hasDocument()
            while menu.numberOfItems > 2 {
                menu.removeItemAtIndex(2)
            }
            for port in ASSerial.ports() {
                menu.addItemWithTitle(port, action:"serialConnectMenu:", keyEquivalent:"")
            }
        default:
            break
        }
    }

    @IBAction func serialConnectMenu(port: NSMenuItem) {
        ASSerialWin.showWindowWithPort(port.title)
    }

    func openTemplate(template: NSURL, fromReadOnly: Bool) {
        let editable : String
        if fromReadOnly {
            editable = "editable "
        } else {
            editable = ""
        }
        ASApplication.newProjectLocation(nil,
            message: "Save \(editable)copy of project \(template.lastPathComponent!)")
        { (saveTo) -> Void in
            let oldName     = template.lastPathComponent!
            let newName     = saveTo.lastPathComponent!
            let fileManager = NSFileManager.defaultManager()
            do {
                try fileManager.copyItemAtURL(template, toURL: saveTo)
                let contents = fileManager.enumeratorAtURL(saveTo,
                    includingPropertiesForKeys: [NSURLNameKey, NSURLPathKey],
                    options: .SkipsHiddenFiles, errorHandler: nil)
                while let item = contents?.nextObject() as? NSURL {
                    let itemBase   = item.URLByDeletingPathExtension?.lastPathComponent!
                    if itemBase == oldName {
                        let newItem = item.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(
                            newName).URLByAppendingPathExtension(item.pathExtension!)
                        try fileManager.moveItemAtURL(item, toURL: newItem)
                    }
                }
            } catch (_) {
            }
            let sketch = ASSketchBook.findSketch(saveTo.path!)
            switch sketch {
            case .Sketch(_, let path):
                let doc = NSDocumentController.sharedDocumentController() 
                doc.openDocumentWithContentsOfURL(NSURL(fileURLWithPath: path), display: true) { (doc, alreadyOpen, error) -> Void in
                }
            default:
                break
            }
        }
    }
    
    @IBAction func openSketch(item: NSMenuItem) {
        let url = NSURL(fileURLWithPath: sketches[item.tag])
        let doc = NSDocumentController.sharedDocumentController()
        doc.openDocumentWithContentsOfURL(url, display: true) { (doc, alreadyOpen, error) -> Void in
        }
    }
    
    @IBAction func openExample(item: NSMenuItem) {
        let url = NSURL(fileURLWithPath: examples[item.tag])
        openTemplate(url.URLByDeletingLastPathComponent!, fromReadOnly:true)
    }

    @IBAction func createSketch(_: AnyObject) {
        ASApplication.newProjectLocation(nil,
            message: "Create Project")
        { (saveTo) -> Void in
            let fileManager = NSFileManager.defaultManager()
            do {
                try fileManager.createDirectoryAtURL(saveTo, withIntermediateDirectories:false, attributes:nil)
                let proj            = saveTo.URLByAppendingPathComponent(saveTo.lastPathComponent!+".avrsackproj")
                let docController   = NSDocumentController.sharedDocumentController()
                if let doc = try docController.openUntitledDocumentAndDisplay(true) as? ASProjDoc {
                    doc.fileURL = proj
                    doc.updateProjectURL()
                    doc.createFileAtURL(saveTo.URLByAppendingPathComponent(saveTo.lastPathComponent!+".ino"))
                    try doc.writeToURL(proj, ofType: "Project", forSaveOperation: .SaveAsOperation, originalContentsURL: nil)
                }
            } catch _ {
            }
        }
    }
    
    class func newProjectLocation(documentWindow: NSWindow?, message: String, completion: (NSURL) -> ()) {
        let savePanel                       = NSSavePanel()
        savePanel.allowedFileTypes          = [kUTTypeFolder as String]
        savePanel.message                   = message
        if let window = documentWindow {
            savePanel.beginSheetModalForWindow(window, completionHandler: { (returnCode) -> Void in
                if returnCode == NSFileHandlingPanelOKButton {
                    completion(savePanel.URL!)
                }
            })
        } else {
            savePanel.beginWithCompletionHandler({ (returnCode) -> Void in
                if returnCode == NSFileHandlingPanelOKButton {
                    completion(savePanel.URL!)
                }
            })
        }
    }

    @IBAction func goToHelpPage(sender: AnyObject) {
        let helpString: String
        switch sender.tag() {
        case 0:
            helpString = "license.html"
        default:
            abort()
        }
        let locBookName = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleHelpBookName") as! String
        AHGotoPage(locBookName, helpString, nil)
    }

    @IBAction func goToHelpURL(sender: AnyObject) {
        let helpString: String
        switch sender.tag() {
        case 0:
            helpString = "https://github.com/microtherion/AVRsack/issues"
        default:
            abort()
        }
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: helpString)!)
    }
}

