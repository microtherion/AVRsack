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
        return NSDocumentController.shared().currentDocument != nil
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        //
        // Retrieve static app defaults
        //
        let fileManager     = FileManager.default
        let workSpace       = NSWorkspace.shared()
        let userDefaults    = UserDefaults.standard
        let appDefaultsURL  = Bundle.main.url(forResource: "Defaults", withExtension: "plist")!
        var appDefaults     = NSDictionary(contentsOf: appDefaultsURL) as! [String: Any]
        //
        // Add dynamic app defaults
        //
        if let arduinoPath = workSpace.urlForApplication(withBundleIdentifier: "cc.arduino.Arduino")?.path {
            appDefaults["Arduino"]      = arduinoPath
        }
        var sketchbooks             = [String]()
        for doc in fileManager.urls(for: .documentDirectory, in: .userDomainMask) {
            sketchbooks.append(doc.appendingPathComponent("Arduino").path)
            sketchbooks.append(doc.appendingPathComponent("AVRSack").path)
        }
        appDefaults["Sketchbooks"]  = sketchbooks
        if fileManager.fileExists(atPath: "/usr/local/CrossPack-AVR") {
            appDefaults["Toolchain"] = "/usr/local/CrossPack-AVR"
        } else {
            appDefaults["Toolchain"] = ""
        }
        
        userDefaults.register(defaults: appDefaults)
    }
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        themeMenu.removeAllItems()
        for (index, theme) in ACEThemeNames.humanThemeNames().enumerated() {
            let menuItem = themeMenu.addItem(withTitle: theme, action: Selector(("changeTheme:")), keyEquivalent: "")
            menuItem.tag = index
        }
        keyboardMenu.removeAllItems()
        for (index, theme) in ACEKeyboardHandlerNames.humanKeyboardHandlerNames().enumerated() {
            let menuItem = keyboardMenu.addItem(withTitle: theme, action: Selector(("changeKeyboardHandler:")), keyEquivalent: "")
            menuItem.tag = index
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    func applicationWillTerminate(aNotification: NSNotification) {
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "Sketchbook":
            menu.removeAllItems()
            sketches = [String]()
            for sketchBook in UserDefaults.standard.object(forKey:"Sketchbooks") as! [String] {
                if FileManager.default.fileExists(atPath: sketchBook) {
                    ASSketchBook.addSketches(menu: menu, target: self, action: #selector(ASApplication.openSketch(_:)), path: sketchBook, sketches: &sketches)
                }
            }
        case "Examples":
            menu.removeAllItems()
            examples = [String]()
            if let arduinoURL = NSWorkspace.shared().urlForApplication(withBundleIdentifier: "cc.arduino.Arduino") {
                let examplePath = arduinoURL.appendingPathComponent("Contents/Resources/Java/examples", isDirectory:true).path
                ASSketchBook.addSketches(menu: menu, target: self, action: #selector(ASApplication.openExample(_:)), path: examplePath, sketches: &examples)
            }
            ASLibraries.instance().addContribLibraryExamplesToMenu(menu: menu, sketches: &examples)
            ASLibraries.instance().addStandardLibraryExamplesToMenu(menu: menu, sketches: &examples)
        case "Import Standard Library":
            menu.removeAllItems()
            ASLibraries.instance().addStandardLibrariesToMenu(menu: menu)
        case "Import Contributed Library":
            menu.removeAllItems()
            ASLibraries.instance().addContribLibrariesToMenu(menu: menu)
        case "Serial Monitor":
            menu.item(at: 0)?.isHidden = !hasDocument()
            while menu.numberOfItems > 2 {
                menu.removeItem(at: 2)
            }
            for port in ASSerial.ports() {
                menu.addItem(withTitle: port, action:#selector(ASApplication.serialConnectMenu(_:)), keyEquivalent:"")
            }
        default:
            break
        }
    }

    @IBAction func serialConnectMenu(_ port: NSMenuItem) {
        ASSerialWin.showWindowWithPort(port: port.title)
    }

    func openTemplate(template: URL, fromReadOnly: Bool) {
        let editable : String
        if fromReadOnly {
            editable = "editable "
        } else {
            editable = ""
        }
        ASApplication.newProjectLocation(documentWindow: nil,
            message: "Save \(editable)copy of project \(template.lastPathComponent)")
        { (saveTo) -> Void in
            let oldName     = template.lastPathComponent
            let newName     = saveTo.lastPathComponent
            let fileManager = FileManager.default
            do {
                try fileManager.copyItem(at: template, to: saveTo)
                let contents = fileManager.enumerator(at: saveTo,
                    includingPropertiesForKeys: [URLResourceKey.nameKey, URLResourceKey.pathKey],
                    options: .skipsHiddenFiles, errorHandler: nil)
                while let item = contents?.nextObject() as? URL {
                    let itemBase   = item.deletingPathExtension().lastPathComponent
                    if itemBase == oldName {
                        let newItem = item.deletingLastPathComponent().appendingPathComponent(
                            newName).appendingPathExtension(item.pathExtension)
                        try fileManager.moveItem(at: item, to: newItem)
                    }
                }
            } catch (_) {
            }
            let sketch = ASSketchBook.findSketch(path: saveTo.path)
            switch sketch {
            case .Sketch(_, let path):
                let doc = NSDocumentController.shared()
                doc.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { (doc, alreadyOpen, error) -> Void in
                }
            default:
                break
            }
        }
    }
    
    @IBAction func openSketch(_ item: NSMenuItem) {
        let url = URL(fileURLWithPath: sketches[item.tag])
        let doc = NSDocumentController.shared()
        doc.openDocument(withContentsOf: url, display: true) { (doc, alreadyOpen, error) -> Void in
        }
    }
    
    @IBAction func openExample(_ item: NSMenuItem) {
        let url = NSURL(fileURLWithPath: examples[item.tag])
        openTemplate(template: url.deletingLastPathComponent!, fromReadOnly:true)
    }

    @IBAction func createSketch(_: AnyObject) {
        ASApplication.newProjectLocation(documentWindow: nil,
            message: "Create Project")
        { (saveTo) -> Void in
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: saveTo, withIntermediateDirectories:false, attributes:nil)
                let proj            = saveTo.appendingPathComponent(saveTo.lastPathComponent+".avrsackproj")
                let docController   = NSDocumentController.shared()
                if let doc = try docController.openUntitledDocumentAndDisplay(true) as? ASProjDoc {
                    doc.fileURL = proj
                    doc.updateProjectURL()
                    doc.createFileAtURL(url: saveTo.appendingPathComponent(saveTo.lastPathComponent+".ino"))
                    try doc.write(to: proj, ofType: "Project", for: .saveAsOperation, originalContentsURL: nil)
                }
            } catch _ {
            }
        }
    }
    
    class func newProjectLocation(documentWindow: NSWindow?, message: String, completion: @escaping (URL) -> ()) {
        let savePanel                       = NSSavePanel()
        savePanel.allowedFileTypes          = [kUTTypeFolder as String]
        savePanel.message                   = message
        if let window = documentWindow {
            savePanel.beginSheetModal(for: window, completionHandler: { (returnCode) -> Void in
                if returnCode == NSFileHandlingPanelOKButton {
                    completion(savePanel.url!)
                }
            })
        } else {
            savePanel.begin(completionHandler: { (returnCode) -> Void in
                if returnCode == NSFileHandlingPanelOKButton {
                    completion(savePanel.url!)
                }
            })
        }
    }

    @IBAction func goToHelpPage(_ sender: AnyObject) {
        let helpString: CFString
        switch sender.tag {
        case 0:
            helpString = "license.html" as CFString
        default:
            abort()
        }
        let locBookName = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as! CFString
        AHGotoPage(locBookName, helpString, nil)
    }

    @IBAction func goToHelpURL(_ sender: AnyObject) {
        let helpString: String
        switch sender.tag {
        case 0:
            helpString = "https://github.com/microtherion/AVRsack/issues"
        default:
            abort()
        }
        NSWorkspace.shared().open(URL(string: helpString)!)
    }
}

