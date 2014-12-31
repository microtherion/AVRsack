//
//  ASSerialWin.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 27/12/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

private var serialInstances     = [String : ASSerialWin]()
private var keyboardHandler     : ACEKeyboardHandler = .Ace

class ASSerialWin: NSWindowController {
    @IBOutlet weak var portPopUp : NSPopUpButton!
    @IBOutlet weak var inputLine : NSTextField!
    @IBOutlet weak var logView   : ACEView!
    
    var baudRate        : Int32 = 9600 {
        didSet(oldRate) {
            if portHandle != nil {
                connect(self)   // Disconnect existing
                connect(self)   // Reconnect
            }
        }
    }
    var sendCR              = false
    var sendLF              = true
    var scrollToBottom      : Bool = true {
        didSet(oldScroll) {
            if scrollToBottom {
                logView.gotoLine(1000000000, column: 0, animated: true)
            }
        }
    }
    var port                = ""
    var serialData          = ""
    var serialObserver      : AnyObject!
    dynamic var portHandle  : NSFileHandle?
    var currentTheme        : UInt = 0
    var fontSize            : UInt = 12
    var portDefaults        = [String: AnyObject]()
    
    class func showWindowWithPort(port: String) {
        if let existing = serialInstances[port] {
            existing.showWindow(self)
        } else {
            let newInstance = ASSerialWin(port:port)
            serialInstances[port] = newInstance
            newInstance.showWindow(self)
        }
    }
    
    convenience init(port: String) {
        self.init(windowNibName:"ASSerialWin")
        self.port       = port

        let userDefaults = NSUserDefaults.standardUserDefaults()
       
        if let portDef = (userDefaults.objectForKey("SerialDefaults") as NSDictionary).objectForKey(port) as? [String: AnyObject] {
            portDefaults = portDef
        } else {
            portDefaults["Theme"]       = userDefaults.stringForKey("SerialTheme")
            portDefaults["FontSize"]    = userDefaults.objectForKey("FontSize")
            portDefaults["SendCR"]      = sendCR
            portDefaults["SendLF"]      = sendLF
        }
        if let themeId = ACEView.themeIdByName(portDefaults["Theme"] as String) {
            currentTheme = themeId
        }
        fontSize = portDefaults["FontSize"] as UInt
        sendCR   = portDefaults["SendCR"] as Bool
        sendLF   = portDefaults["SendLF"] as Bool

        if let handlerName = userDefaults.stringForKey("Bindings") {
            if let handlerId = ACEView.handlerIdByName(handlerName) {
                keyboardHandler = handlerId
            }
        }

        var nc          = NSNotificationCenter.defaultCenter()
        serialObserver  = nc.addObserverForName(kASSerialPortsChanged, object: nil, queue: nil, usingBlock: { (NSNotification) in
            self.rebuildPortMenu()
        })
    }
    
    override func finalize() {
        NSNotificationCenter.defaultCenter().removeObserver(serialObserver)
        serialInstances.removeValueForKey(port)
    }
    
    override func windowDidLoad() {
        logView.setReadOnly(true)
        logView.setShowPrintMargin(false)
        logView.setTheme(currentTheme)
        logView.setKeyboardHandler(keyboardHandler)
        logView.setFontSize(fontSize)
        logView.setMode(UInt(ACEModeText))
        logView.alphaValue = 0.8
        rebuildPortMenu()
        window?.title   = port
        connect(self)
        super.windowDidLoad()
    }
    
    func rebuildPortMenu() {
        portPopUp.removeAllItems()
        portPopUp.addItemsWithTitles(ASSerial.ports())
        portPopUp.selectItemWithTitle(port)
    }
    
    @IBAction func selectPort(item: AnyObject) {
        port    = (item as NSPopUpButton).titleOfSelectedItem!
        window?.title   = port
    }

    @IBAction func sendInput(AnyObject) {
        let line = inputLine.stringValue + (sendCR ? "\r" : "") + (sendLF ? "\n" : "")
        let data = line.dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: true)!
        portHandle?.writeData(data)
    }
    
    @IBAction func connect(AnyObject) {
        if portHandle != nil {
            ASSerial.restorePort(portHandle!.fileDescriptor)
            portHandle!.closeFile()
            portHandle = nil
        } else {
            portHandle = ASSerial.openPort(port, withSpeed: baudRate)
            if portHandle != nil {
                serialData  = ""
                logView.setString(serialData)
                portHandle!.readabilityHandler = {(handle) in
                    let newData         = handle.availableData
                    let newString       = NSString(data: newData, encoding: NSASCIIStringEncoding)!
                    self.serialData    += newString
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.logView.setString(self.serialData)
                        if self.scrollToBottom {
                            self.logView.gotoLine(1000000000, column: 0, animated: true)
                        }
                    })
                }
            }
        }
    }
    
    var connectButtonTitle : String {
        get {
            return (portHandle != nil) ? "Disconnect" : "Connect"
        }
    }
    class func keyPathsForValuesAffectingConnectButtonTitle() -> NSSet {
        return NSSet(object: "portHandle")
    }

    // MARK: Editor configuration
    
    @IBAction func changeTheme(item: NSMenuItem) {
        let userDefaults = NSUserDefaults.standardUserDefaults()
        currentTheme = UInt(item.tag)
        logView.setTheme(currentTheme)
        let themeName = ACEThemeNames.humanNameForTheme(currentTheme)
        userDefaults.setObject(themeName, forKey: "SerialTheme")
        portDefaults["Theme"] = themeName
        updatePortDefaults()
    }
    @IBAction func changeKeyboardHandler(item: NSMenuItem) {
        keyboardHandler = ACEKeyboardHandler(rawValue: UInt(item.tag))!
        NSUserDefaults.standardUserDefaults().setObject(
            ACEKeyboardHandlerNames.humanNameForKeyboardHandler(keyboardHandler), forKey: "Bindings")
        NSNotificationCenter.defaultCenter().postNotificationName("Bindings", object: item)
    }
    
    func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
        if let menuItem = anItem as? NSMenuItem {
            if menuItem.action == "changeTheme:" {
                menuItem.state = (menuItem.tag == Int(currentTheme) ? NSOnState : NSOffState)
                return true
            } else if menuItem.action == "changeKeyboardHandler:" {
                menuItem.state = (menuItem.tag == Int(keyboardHandler.rawValue) ? NSOnState : NSOffState)
                return true
            }
        }
        return true
    }
    
    @IBAction func makeTextLarger(AnyObject) {
        fontSize += 1
        logView.setFontSize(fontSize)
        portDefaults["FontSize"] = fontSize
        updatePortDefaults()
    }
    @IBAction func makeTextSmaller(AnyObject) {
        if fontSize > 6 {
            fontSize -= 1
            logView.setFontSize(fontSize)
            portDefaults["FontSize"] = fontSize
            updatePortDefaults()
        }
    }
    
    func updatePortDefaults() {
        let userDefaults = NSUserDefaults.standardUserDefaults()
        let serialDefaults = userDefaults.objectForKey("SerialDefaults") as NSDictionary
        serialDefaults.setValue(portDefaults, forKey:port)
        userDefaults.setObject(serialDefaults, forKey:"SerialDefaults")
    }
}
