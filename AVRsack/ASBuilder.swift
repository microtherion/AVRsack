//
//  ASBuilder.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/24/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

class ASBuilder {
    var dir         = NSURL()
    var task        : NSTask?
    var continuation: (()->())?
    var termination : AnyObject?
    
    init() {
        termination = NSNotificationCenter.defaultCenter().addObserverForName(NSTaskDidTerminateNotification,
            object: nil, queue: nil, usingBlock:
        { (notification: NSNotification!) in
            if notification.object as? NSTask == self.task {
                if self.task!.terminationStatus == 0 {
                    if let cont = self.continuation {
                        self.continuation = nil
                        cont()
                    }
                } else {
                    self.continuation = nil
                }
            }
        })
    }
    func finalize() {
        NSNotificationCenter.defaultCenter().removeObserver(termination!)
    }
    
    func setProjectURL(url: NSURL) {
        dir       = url.URLByDeletingLastPathComponent!.standardizedURL!
    }

    func stop() {
        task?.terminate()
        task?.waitUntilExit()
    }
    
    func cleanProject() {
        NSFileManager.defaultManager().removeItemAtURL(dir.URLByAppendingPathComponent("build"), error: nil)
    }
    
    func buildProject(board: String, files: ASFileTree) {
        let toolChain               = (NSApplication.sharedApplication().delegate as ASApplication).preferences.toolchainPath
        task = NSTask()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = NSBundle.mainBundle().pathForResource("BuildProject", ofType: "")!
        
        let fileManager = NSFileManager.defaultManager()
        let libPath     = (ASLibraries.instance().directories as NSArray).componentsJoinedByString(":")
        var args        = [NSString]()
        let boardProp   = ASHardware.instance().boards[board]!
        var corePath    = ""
        var variantPath : NSString?
        for hw in ASHardware.instance().directories {
            corePath = hw+"/cores/"+boardProp["build.core"]!
            if fileManager.fileExistsAtPath(corePath) {
                if let variantName = boardProp["build.variant"] {
                    variantPath = hw+"/variants/"+variantName
                    if fileManager.fileExistsAtPath(variantPath!) {
                        args.append("variant="+variantName)
                   } else {
                        variantPath = nil
                    }
                }
                break
            } else {
                corePath = ""
            }
        }
        if corePath == "" {
            NSLog("Unable to find core %s\n", boardProp["build.core"]!)
            return
        }
        args.append("toolchain="+toolChain)
        args.append("project="+dir.lastPathComponent)
        args.append("board="+board)
        args.append("mcu="+boardProp["build.mcu"]!)
        args.append("f_cpu="+boardProp["build.f_cpu"]!)
        args.append("max_size"+boardProp["upload.maximum_size"]!)
        args.append("core="+boardProp["build.core"]!)
        args.append("libs="+libPath)
        args.append("core_path="+corePath)
        if variantPath != nil {
            args.append("variant_path="+variantPath!)
        }
        args.append("usb_vid="+(boardProp["build.vid"] ?? "null"));
        args.append("usb_pid="+(boardProp["build.pid"] ?? "null"));
        args.append("--")
        args                   += files.paths
        task!.arguments         =   args;
        task!.launch()
    }
    
    func uploadProject(board: String, programmer: String, port: String) {
        let toolChain               = (NSApplication.sharedApplication().delegate as ASApplication).preferences.toolchainPath
        task = NSTask()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = toolChain+"/bin/avrdude"
        
        let fileManager = NSFileManager.defaultManager()
        let logURL              = dir.URLByAppendingPathComponent("build/upload.log")
        fileManager.createFileAtPath(logURL.path!, contents: NSData(), attributes: nil)
        let logOut              = NSFileHandle(forWritingAtPath: logURL.path!)!
        task!.standardOutput    = logOut
        task!.standardError     = logOut
        
        let libPath         = (ASLibraries.instance().directories as NSArray).componentsJoinedByString(":")
        let boardProp       = ASHardware.instance().boards[board]!
        let progProp        = ASHardware.instance().programmers[programmer]
        let hasBootloader   = boardProp["upload.protocol"] != nil
        let leonardish      = hasBootloader && (boardProp["bootloader.path"] ?? "").hasPrefix("caterina")
        let proto           = hasBootloader ? boardProp["upload.protocol"] : progProp?["protocol"]
        let speed           = hasBootloader ? boardProp["upload.speed"]    : progProp?["speed"]
        let verbosity       = NSUserDefaults.standardUserDefaults().integerForKey("UploadVerbosity")
        var args            = Array<String>(count: verbosity, repeatedValue: "-v")
        args               += [
            "-C", toolChain+"/etc/avrdude.conf",
            "-p", boardProp["build.mcu"]!, "-c", proto!, "-P", port,
            "-U", "flash:w:build/"+board+"/"+dir.lastPathComponent+".hex:i"]
        if speed != nil {
            args.append("-b")
            args.append(speed!)
        }
        
        //
        // For Leonardo & the like, reset by opening port at 1200 baud
        //
        if leonardish {
            if verbosity > 0 {
                logOut.writeData("Opening \(port) at 1200 baud\n".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
            }
            if let dummyConnection = ASSerial.openPort(port, withSpeed: 1200) {
                ASSerial.restorePort(dummyConnection.fileDescriptor)
                dummyConnection.closeFile()
                sleep(5)
                for (var retry=0; retry < 10; ++retry) {
                    if (NSFileManager.defaultManager().fileExistsAtPath(port)) {
                        if verbosity > 0 {
                            logOut.writeData("Found port \(port) after \(retry) attempts.\n".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
                        }
                        break;
                    }
                }
            }
        }
        let cmdLine = task!.launchPath+" "+(args as NSArray).componentsJoinedByString(" ")+"\n"
        logOut.writeData(cmdLine.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
        task!.arguments         =   args;
        task!.launch()
    }
    
    func disassembleProject(board: String) {
        let toolChain               = (NSApplication.sharedApplication().delegate as ASApplication).preferences.toolchainPath
        task = NSTask()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = toolChain+"/bin/avr-objdump"
        
        let fileManager = NSFileManager.defaultManager()
        let logURL              = dir.URLByAppendingPathComponent("build/disasm.log")
        fileManager.createFileAtPath(logURL.path!, contents: NSData(), attributes: nil)
        let logOut              = NSFileHandle(forWritingAtPath: logURL.path!)!
        task!.standardOutput    = logOut
        task!.standardError     = logOut
        
        let showSource  = NSUserDefaults.standardUserDefaults().boolForKey("ShowSourceInDisassembly")
        var args        = showSource ? ["-S"] : []
        args           += ["-d", "build/"+board+"/"+dir.lastPathComponent+".elf"]
        let cmdLine     = task!.launchPath+" "+(args as NSArray).componentsJoinedByString(" ")+"\n"
        logOut.writeData(cmdLine.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
        task!.arguments         =   args;
        task!.launch()
    }
}