//
//  ASSerialWin.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 27/12/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

private var serialInstances = [String : ASSerialWin]()

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
    var port                = ""
    var serialData          = ""
    var serialObserver      : AnyObject!
    dynamic var portHandle  : NSFileHandle?
    
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
}
