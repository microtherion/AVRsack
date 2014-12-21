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
    @IBOutlet weak var themeMenu    : NSMenu!
    @IBOutlet weak var keyboardMenu : NSMenu!
    @IBOutlet weak var preferences  : ASPreferences!
    var sketches = [String]()
    var examples = [String]()
    
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

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
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
            
        default:
            break
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
        let doc = NSDocumentController.sharedDocumentController() as NSDocumentController
        doc.openDocumentWithContentsOfURL(url, display: true) { (doc, alreadyOpen, error) -> Void in
        }
    }
}

