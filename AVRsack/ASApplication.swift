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

