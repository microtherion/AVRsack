//
//  AppDelegate.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

@NSApplicationMain
class ASApplication: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @IBOutlet var themeMenu    : NSMenu!
    @IBOutlet var keyboardMenu : NSMenu!
    @IBOutlet var preferences  : ASPreferences!
    var sketches = [String]()
    var examples = [String]()

    func hasDocument() -> Bool {
        if let doc = NSDocumentController.sharedDocumentController().currentDocument as? NSDocument {
            return true
        } else {
            return false
        }
    }

    func applicationWillFinishLaunching(notification: NSNotification) {
        //
        // Retrieve static app defaults
        //
        let fileManager     = NSFileManager.defaultManager()
        let workSpace       = NSWorkspace.sharedWorkspace()
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        let appDefaultsURL  = NSBundle.mainBundle().URLForResource("Defaults", withExtension: "plist")!
        let appDefaults     = NSMutableDictionary(contentsOfURL: appDefaultsURL)!
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
        for (index, theme) in enumerate(ACEThemeNames.humanThemeNames() as [NSString]) {
            let menuItem = themeMenu.addItemWithTitle(theme, action: "changeTheme:", keyEquivalent: "")
            menuItem!.tag = index
        }
        keyboardMenu.removeAllItems()
        for (index, theme) in enumerate(ACEKeyboardHandlerNames.humanKeyboardHandlerNames() as [NSString]) {
            let menuItem = keyboardMenu.addItemWithTitle(theme, action: "changeKeyboardHandler:", keyEquivalent: "")
            menuItem!.tag = index
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
            for sketchBook in NSUserDefaults.standardUserDefaults().objectForKey("Sketchbooks") as [NSString] {
                if NSFileManager.defaultManager().fileExistsAtPath(sketchBook) {
                    ASSketchBook.addSketches(menu, target: self, action: "openSketch:", path: sketchBook, sketches: &sketches)
                }
            }
        case "Examples":
            menu.removeAllItems()
            examples = [String]()
            if let arduinoPath = NSWorkspace.sharedWorkspace().URLForApplicationWithBundleIdentifier("cc.arduino.Arduino")?.path {
                let examplePath = arduinoPath.stringByAppendingPathComponent("Contents/Resources/Java/examples")
                ASSketchBook.addSketches(menu, target: self, action: "openExample:", path: examplePath, sketches: &examples)
            }
        case "Serial Monitor":
            menu.itemAtIndex(0)?.hidden = !hasDocument()
            while menu.numberOfItems > 2 {
                menu.removeItemAtIndex(2)
            }
            for port in ASSerial.ports() as [String] {
                menu.addItemWithTitle(port, action:"serialConnectMenu:", keyEquivalent:"")
            }
        default:
            break
        }
    }

    @IBAction func serialConnectMenu(port: NSMenuItem) {
        ASSerialWin.showWindowWithPort(port.title)
    }

    func openTemplate(template: NSURL) {
        ASApplication.newProjectLocation(nil,
            message: "Save editable copy of project \(template.lastPathComponent)")
        { (saveTo) -> Void in
            let oldName     = template.lastPathComponent
            let newName     = saveTo.lastPathComponent
            let fileManager = NSFileManager.defaultManager()
            fileManager.copyItemAtURL(template, toURL: saveTo, error: nil)
            let contents = fileManager.enumeratorAtURL(saveTo,
                includingPropertiesForKeys: [NSURLNameKey, NSURLPathKey],
                options: .SkipsHiddenFiles, errorHandler: nil)
            while let item = contents?.nextObject() as? NSURL {
                var renameItem = false
                var itemName   = item.lastPathComponent
                if itemName.stringByDeletingPathExtension == oldName {
                    renameItem = true
                    itemName   = newName.stringByAppendingPathExtension(itemName.pathExtension)!
                }
                if renameItem {
                    fileManager.moveItemAtURL(item,
                        toURL: item.URLByDeletingLastPathComponent!.URLByAppendingPathComponent(itemName),
                        error: nil)
                }
            }
            let sketch = ASSketchBook.findSketch(saveTo.path!)
            switch sketch {
            case .Sketch(_, let path):
                let doc = NSDocumentController.sharedDocumentController() as NSDocumentController
                doc.openDocumentWithContentsOfURL(NSURL(fileURLWithPath: path)!, display: true) { (doc, alreadyOpen, error) -> Void in
                }
            default:
                break
            }
        }
    }
    
    @IBAction func openSketch(item: NSMenuItem) {
        let url = NSURL(fileURLWithPath: sketches[item.tag])!
        let doc = NSDocumentController.sharedDocumentController() as NSDocumentController
        doc.openDocumentWithContentsOfURL(url, display: true) { (doc, alreadyOpen, error) -> Void in
        }
    }
    
    @IBAction func openExample(item: NSMenuItem) {
        let url = NSURL(fileURLWithPath: examples[item.tag])!
        openTemplate(url.URLByDeletingLastPathComponent!)
    }
    
    class func newProjectLocation(documentWindow: NSWindow?, message: String, completion: (NSURL) -> ()) {
        let savePanel                       = NSSavePanel()
        savePanel.allowedFileTypes          = [kUTTypeFolder]
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
}

