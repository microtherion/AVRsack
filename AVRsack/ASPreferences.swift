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
            return UserDefaults.standard.object(forKey: "Toolchain") as! String
        }
        set(newToolchain) {
            UserDefaults.standard.set(newToolchain, forKey: "Toolchain")
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
                return NSWorkspace.shared().urlForApplication(withBundleIdentifier: "cc.arduino.Arduino")!.path +
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
            return FileManager.default.fileExists(atPath: "/usr/local/CrossPack-AVR/bin")
        }
    }
    
    func otherToolchainDialog() {
        let openPanel                       = NSOpenPanel()
        openPanel.delegate                  = self
        openPanel.canChooseFiles            = false
        openPanel.canChooseDirectories      = true
        openPanel.allowsMultipleSelection   = false
        openPanel.resolvesAliases           = true
        openPanel.beginSheetModal(for: window!, completionHandler: { (returnCode: Int) -> Void in
            if returnCode == NSFileHandlingPanelOKButton {
                self.toolchainPref   = openPanel.url!.path
            }
        })
    }
    
    func panel(_ sender: AnyObject, shouldEnable url: URL) -> Bool {
        let gccPath = url.appendingPathComponent("bin/avr-gcc")
        return FileManager.default.fileExists(atPath: gccPath.path)
    }
}
