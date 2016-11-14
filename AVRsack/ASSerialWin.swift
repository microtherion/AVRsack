//
//  ASSerialWin.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 27/12/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

private var serialInstances     = [String : ASSerialWin]()
private var keyboardHandler     : ACEKeyboardHandler = .ace

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
    dynamic var portHandle  : FileHandle?
    var currentTheme        : ACETheme = .xcode
    var fontSize            : UInt = 12
    var portDefaults        = [String: AnyObject]()
    var shouldReconnect     = false
    dynamic var task        : Task?

    class func showWindowWithPort(port: String) {
        if let existing = serialInstances[port] {
            existing.showWindow(self)
        } else {
            let newInstance = ASSerialWin(port:port)
            serialInstances[port] = newInstance
            newInstance.showWindow(self)
        }
    }
    class func showWindowWithPort(port: String, task: Task, speed: Int) {
        if let existing = serialInstances[port] {
            existing.showWindowWithTask(task: task, speed:speed)
        } else {
            let newInstance = ASSerialWin(port:port)
            serialInstances[port] = newInstance
            newInstance.showWindowWithTask(task: task, speed:speed)
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

        let userDefaults = UserDefaults.standard
       
        if let portDef = (userDefaults.object(forKey:"SerialDefaults") as! NSDictionary).object(forKey:port) as? [String: AnyObject] {
            portDefaults = portDef
        } else {
            portDefaults["Theme"]       = userDefaults.string(forKey:"SerialTheme")
            portDefaults["FontSize"]    = userDefaults.object(forKey:"FontSize")
            portDefaults["SendCR"]      = sendCR
            portDefaults["SendLF"]      = sendLF
            portDefaults["BaudRate"]    = 19200
        }
        if let themeId = ACEView.themeIdByName(themeName: portDefaults["Theme"] as! String) {
            currentTheme = themeId
        }
        fontSize = portDefaults["FontSize"] as! UInt
        sendCR   = portDefaults["SendCR"] as! Bool
        sendLF   = portDefaults["SendLF"] as! Bool
        baudRate = portDefaults["BaudRate"] as! Int

        if let handlerName = userDefaults.string(forKey:"Bindings") {
            if let handlerId = ACEView.handlerIdByName(handlerName: handlerName) {
                keyboardHandler = handlerId
            }
        }

        let nc          = NotificationCenter.default
        serialObserver  = nc.addObserver(forName: NSNotification.Name(kASSerialPortsChanged), object: nil, queue: nil, using: { (NSNotification) in
            self.willChangeValue(forKey: "hasValidPort")
            self.didChangeValue(forKey: "hasValidPort")

            if self.task == nil {
                if self.hasValidPort {
                    self.reconnect()
                } else {
                    self.disconnectTemporarily()
                }
            }
        })
        termination = NotificationCenter.default.addObserver(forName: Task.didTerminateNotification,
                                                                   object: nil, queue: nil, using:
            { (notification: Notification) in
                if notification.object as? Task == self.task {
                    self.task        = nil
                    self.portHandle  = nil
                }
        })
    }
    
    override func finalize() {
        if portHandle != nil {
            connect(self)
        }
        NotificationCenter.default.removeObserver(serialObserver)
        NotificationCenter.default.removeObserver(termination)
        serialInstances.removeValue(forKey: port)
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
        logView.setMode(.text)
        logView.alphaValue = 0.8
        window?.title   = port
        if task == nil {
            connect(self)
        }
        super.windowDidLoad()
    }

    func installReader(handle: FileHandle?) {
        if let readHandle = handle {
            serialData  = ""
            logView.setString(serialData)
            readHandle.readabilityHandler = {(handle) in
                if let newData = handle.availableDataIgnoringExceptions(),
                   let newString = String(data: newData, encoding: String.Encoding.ascii)
                {
                    self.serialData    += newString
                    DispatchQueue.main.async(execute: {
                        self.logView.setString(self.serialData)
                        if self.scrollToBottom {
                            self.logView.gotoLine(1000000000, column: 0, animated: true)
                        }
                    })
                }
            }
        }
    }

    @IBAction func sendInput(_: AnyObject) {
        let line = inputLine.stringValue + (sendCR ? "\r" : "") + (sendLF ? "\n" : "")
        let data = line.data(using: String.Encoding.ascii, allowLossyConversion: true)!
        portHandle?.write(data)
    }
    
    func showWindowWithTask(task: Task, speed:Int) {
        if portHandle != nil {
            connect(self)
        }
        baudRate        = speed
        self.task       = task
        portHandle      = (task.standardInput as! Pipe).fileHandleForWriting
        showWindow(self)
        installReader(handle: (task.standardOutput as? Pipe)?.fileHandleForReading)
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
            installReader(handle: portHandle)
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
    
    @IBAction func changeTheme(_ item: NSMenuItem) {
        let userDefaults = UserDefaults.standard
        currentTheme = ACETheme(rawValue: UInt(item.tag)) ?? .xcode
        logView.setTheme(currentTheme)
        let themeName = ACEThemeNames.humanName(for: currentTheme)
        userDefaults.set(themeName, forKey: "SerialTheme")
        portDefaults["Theme"] = themeName
        updatePortDefaults()
    }
    @IBAction func changeKeyboardHandler(_ item: NSMenuItem) {
        keyboardHandler = ACEKeyboardHandler(rawValue: UInt(item.tag))!
        UserDefaults.standard.set(
            ACEKeyboardHandlerNames.humanName(for: keyboardHandler), forKey: "Bindings")
        NotificationCenter.default.post(name: Notification.Name("Bindings"), object: item)
    }

    func validateUserInterfaceItem(anItem: NSValidatedUserInterfaceItem) -> Bool {
        if let menuItem = anItem as? NSMenuItem {
            if menuItem.action == #selector(ASSerialWin.changeTheme(_:)) {
                menuItem.state = (UInt(menuItem.tag) == currentTheme.rawValue ? NSOnState : NSOffState)
                return true
            } else if menuItem.action == #selector(ASSerialWin.changeKeyboardHandler(_:)) {
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
        let userDefaults    = UserDefaults.standard
        let sd              = userDefaults.object(forKey:"SerialDefaults") as! [String: AnyObject]
        let serialDefaults  = NSMutableDictionary(dictionary: sd)
        serialDefaults.setValue(NSDictionary(dictionary:portDefaults), forKey:port)
        userDefaults.set(serialDefaults, forKey:"SerialDefaults")
    }

    @IBAction func saveDocument(_: AnyObject) {
        let savePanel                   = NSSavePanel()
        savePanel.allowedFileTypes      = ["log"]
        savePanel.allowsOtherFileTypes  = true
        savePanel.isExtensionHidden       = false
        savePanel.beginSheetModal(for: window!, completionHandler: { (returnCode) -> Void in
            if returnCode == NSFileHandlingPanelOKButton {
                do {
                    try self.serialData.write(to: savePanel.url!, atomically:false, encoding:String.Encoding.utf8)
                } catch _ {
                }
            }
        })
    }
}
