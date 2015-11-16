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
    @IBOutlet weak var inputLine : NSTextField!
    @IBOutlet weak var logView   : ACEView!
    
    var baudRate        : Int = 9600 {
        didSet(oldRate) {
            if portHandle != nil {
                connect(self)   // Disconnect existing
                connect(self)   // Reconnect
            }
            portDefaults["BaudRate"] = baudRate
            updatePortDefaults()
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
    var termination         : AnyObject!
    dynamic var portHandle  : NSFileHandle?
    var currentTheme        : ACETheme = .Xcode
    var fontSize            : UInt = 12
    var portDefaults        = [String: AnyObject]()
    var shouldReconnect     = false
    dynamic var task        : NSTask?

    class func showWindowWithPort(port: String) {
        if let existing = serialInstances[port] {
            existing.showWindow(self)
        } else {
            let newInstance = ASSerialWin(port:port)
            serialInstances[port] = newInstance
            newInstance.showWindow(self)
        }
    }
    class func showWindowWithPort(port: String, task: NSTask, speed: Int) {
        if let existing = serialInstances[port] {
            existing.showWindowWithTask(task, speed:speed)
        } else {
            let newInstance = ASSerialWin(port:port)
            serialInstances[port] = newInstance
            newInstance.showWindowWithTask(task, speed:speed)
        }
    }
    class func portNeededForUpload(port: String) {
        if let existing = serialInstances[port] {
            existing.disconnectTemporarily()
        }
    }
    class func portAvailableAfterUpload(port: String) {
        if let existing = serialInstances[port] {
            existing.reconnect()
        }
    }
    
    convenience init(port: String) {
        self.init(windowNibName:"ASSerialWin")
        self.port       = port

        let userDefaults = NSUserDefaults.standardUserDefaults()
       
        if let portDef = (userDefaults.objectForKey("SerialDefaults") as! NSDictionary).objectForKey(port) as? [String: AnyObject] {
            portDefaults = portDef
        } else {
            portDefaults["Theme"]       = userDefaults.stringForKey("SerialTheme")
            portDefaults["FontSize"]    = userDefaults.objectForKey("FontSize")
            portDefaults["SendCR"]      = sendCR
            portDefaults["SendLF"]      = sendLF
            portDefaults["BaudRate"]    = 19200
        }
        if let themeId = ACEView.themeIdByName(portDefaults["Theme"] as! String) {
            currentTheme = themeId
        }
        fontSize = portDefaults["FontSize"] as! UInt
        sendCR   = portDefaults["SendCR"] as! Bool
        sendLF   = portDefaults["SendLF"] as! Bool
        baudRate = portDefaults["BaudRate"] as! Int

        if let handlerName = userDefaults.stringForKey("Bindings") {
            if let handlerId = ACEView.handlerIdByName(handlerName) {
                keyboardHandler = handlerId
            }
        }

        let nc          = NSNotificationCenter.defaultCenter()
        serialObserver  = nc.addObserverForName(kASSerialPortsChanged, object: nil, queue: nil, usingBlock: { (NSNotification) in
            self.willChangeValueForKey("hasValidPort")
            self.didChangeValueForKey("hasValidPort")

            if self.task == nil {
                if self.hasValidPort {
                    self.reconnect()
                } else {
                    self.disconnectTemporarily()
                }
            }
        })
        termination = NSNotificationCenter.defaultCenter().addObserverForName(NSTaskDidTerminateNotification,
            object: nil, queue: nil, usingBlock:
            { (notification: NSNotification) in
                if notification.object as? NSTask == self.task {
                    self.task        = nil
                    self.portHandle  = nil
                }
        })
    }
    
    override func finalize() {
        if portHandle != nil {
            connect(self)
        }
        NSNotificationCenter.defaultCenter().removeObserver(serialObserver)
        NSNotificationCenter.defaultCenter().removeObserver(termination)
        serialInstances.removeValueForKey(port)
    }

    func windowWillClose(notification: NSNotification) {
        if portHandle != nil {
            connect(self)
        }
    }
    
    override func windowDidLoad() {
        logView.setReadOnly(true)
        logView.setShowPrintMargin(false)
        logView.setTheme(currentTheme)
        logView.setKeyboardHandler(keyboardHandler)
        logView.setFontSize(fontSize)
        logView.setMode(.Text)
        logView.alphaValue = 0.8
        window?.title   = port
        if task == nil {
            connect(self)
        }
        super.windowDidLoad()
    }

    func installReader(handle: NSFileHandle?) {
        if let readHandle = handle {
            serialData  = ""
            logView.setString(serialData)
            readHandle.readabilityHandler = {(handle) in
                let newData         = handle.availableDataIgnoringExceptions()
                let newString       = NSString(data: newData, encoding: NSASCIIStringEncoding) as! String
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

    @IBAction func sendInput(_: AnyObject) {
        let line = inputLine.stringValue + (sendCR ? "\r" : "") + (sendLF ? "\n" : "")
        let data = line.dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: true)!
        portHandle?.writeData(data)
    }
    
    func showWindowWithTask(task: NSTask, speed:Int) {
        if portHandle != nil {
            connect(self)
        }
        baudRate        = speed
        self.task       = task
        portHandle      = (task.standardInput as! NSPipe).fileHandleForWriting
        showWindow(self)
        installReader((task.standardOutput as? NSPipe)?.fileHandleForReading)
    }
    
    @IBAction func connect(_: AnyObject) {
        shouldReconnect = false
        if task != nil {
            task!.interrupt()
        } else if portHandle != nil {
            let fd = portHandle!.fileDescriptor
            ASSerial.restorePort(fd)
            ASSerial.closePort(fd)
            portHandle = nil
        } else {
            portHandle = ASSerial.openPort(port, withSpeed: Int32(baudRate))
            installReader(portHandle)
        }
    }
    func disconnectTemporarily() {
        if portHandle != nil {
            connect(self)           // Disconnect temporarily
            shouldReconnect  = true // But express interest to reconnect
        }
    }
    func reconnect() {
        if portHandle == nil && shouldReconnect {
            connect(self)           // Reconnect
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
    var hasValidPort : Bool {
        get {
            return ASSerial.ports().contains(port)
        }
    }

    // MARK: Editor configuration
    
    @IBAction func changeTheme(item: NSMenuItem) {
        let userDefaults = NSUserDefaults.standardUserDefaults()
        currentTheme = ACETheme(rawValue: UInt(item.tag)) ?? .Xcode
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
                menuItem.state = (UInt(menuItem.tag) == currentTheme.rawValue ? NSOnState : NSOffState)
                return true
            } else if menuItem.action == "changeKeyboardHandler:" {
                menuItem.state = (menuItem.tag == Int(keyboardHandler.rawValue) ? NSOnState : NSOffState)
                return true
            }
        }
        return true
    }
    
    @IBAction func makeTextLarger(_: AnyObject) {
        fontSize += 1
        logView.setFontSize(fontSize)
        portDefaults["FontSize"] = fontSize
        updatePortDefaults()
    }
    @IBAction func makeTextSmaller(_: AnyObject) {
        if fontSize > 6 {
            fontSize -= 1
            logView.setFontSize(fontSize)
            portDefaults["FontSize"] = fontSize
            updatePortDefaults()
        }
    }
    
    func updatePortDefaults() {
        let userDefaults    = NSUserDefaults.standardUserDefaults()
        let sd              = userDefaults.objectForKey("SerialDefaults") as! [String: AnyObject]
        let serialDefaults  = NSMutableDictionary(dictionary: sd)
        serialDefaults.setValue(NSDictionary(dictionary:portDefaults), forKey:port)
        userDefaults.setObject(serialDefaults, forKey:"SerialDefaults")
    }

    @IBAction func saveDocument(_: AnyObject) {
        let savePanel                   = NSSavePanel()
        savePanel.allowedFileTypes      = ["log"]
        savePanel.allowsOtherFileTypes  = true
        savePanel.extensionHidden       = false
        savePanel.beginSheetModalForWindow(window!, completionHandler: { (returnCode) -> Void in
            if returnCode == NSFileHandlingPanelOKButton {
                do {
                    try self.serialData.writeToURL(savePanel.URL!, atomically:false, encoding:NSUTF8StringEncoding)
                } catch _ {
                }
            }
        })
    }
}
