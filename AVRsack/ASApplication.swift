//
//  AppDelegate.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

@NSApplicationMain
class ASApplication: NSObject, NSApplicationDelegate {
    @IBOutlet weak var themeMenu    : NSMenu!
    @IBOutlet weak var keyboardMenu : NSMenu!
    
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
}

