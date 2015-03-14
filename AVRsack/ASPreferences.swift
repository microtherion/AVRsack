//
//  ASPreferences.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 12/10/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Cocoa

private let kASToolchainCrosspack   = 0
private let kASToolchainArduino     = 1
private let kASToolchainOther       = 2

class ASPreferences: NSWindowController, NSOpenSavePanelDelegate {
    var toolchainPref : String {
        get {
            return NSUserDefaults.standardUserDefaults().objectForKey("Toolchain") as! String
        }
        set(newToolchain) {
            NSUserDefaults.standardUserDefaults().setObject(newToolchain, forKey: "Toolchain")
        }
    }
    var toolchainType : Int {
        get {
            switch toolchainPref {
            case "/usr/local/CrossPack-AVR":
                return kASToolchainCrosspack
            case "":
                return kASToolchainArduino
            default:
                return kASToolchainOther
            }
        }
        
        set (toolchain) {
            switch toolchain {
            case kASToolchainCrosspack:
                toolchainPref   = "/usr/local/CrossPack-AVR"
            case kASToolchainArduino:
                toolchainPref   = ""
            default:
                otherToolchainDialog()
            }
        }
    }
    class func keyPathsForValuesAffectingToolchainType() -> NSSet {
        return NSSet(objects: "toolchainPref")
    }

    var toolchainPath : String {
        get {
            if toolchainPref != ("" as String) {
                return toolchainPref
            } else {
                return NSWorkspace.sharedWorkspace().URLForApplicationWithBundleIdentifier("cc.arduino.Arduino")!.path! +
                    "/Contents/Resources/Java/hardware/tools/avr"
            }
        }
    }
    class func keyPathsForValuesAffectingToolchainPath() -> NSSet {
        return NSSet(objects: "toolchainPref")
    }

    convenience init() {
        self.init(windowNibName:"ASPreferences")
    }
    
    var hasCrossPackAVR : Bool {
        get {
            return NSFileManager.defaultManager().fileExistsAtPath("/usr/local/CrossPack-AVR/bin")
        }
    }
    
    func otherToolchainDialog() {
        let openPanel                       = NSOpenPanel()
        openPanel.delegate                  = self
        openPanel.canChooseFiles            = false
        openPanel.canChooseDirectories      = true
        openPanel.allowsMultipleSelection   = false
        openPanel.resolvesAliases           = true
        openPanel.beginSheetModalForWindow(window!, completionHandler: { (returnCode: Int) -> Void in
            if returnCode == NSFileHandlingPanelOKButton {
                self.toolchainPref   = openPanel.URL!.path!
            }
        })
    }
    
    func panel(sender: AnyObject, shouldEnableURL url: NSURL) -> Bool {
        let gccPath = url.URLByAppendingPathComponent("bin/avr-gcc")
        return NSFileManager.defaultManager().fileExistsAtPath(gccPath.path!)
    }
}
