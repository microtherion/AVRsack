//
//  ASBuilder.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/24/14.
//  Copyright © 2014-2015 Aere Perennius. All rights reserved.
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
        let library     = boardProp["library"]!
        var corePath    = library+"/cores/"+boardProp["build.core"]!
        var variantPath : NSString?
        if fileManager.fileExistsAtPath(corePath) {
            if let variantName = boardProp["build.variant"] {
                variantPath = library+"/variants/"+variantName
                if fileManager.fileExistsAtPath(variantPath!) {
                    args.append("variant="+variantName)
               } else {
                    variantPath = nil
                }
            }
        } else {
            NSLog("Unable to find core %s\n", boardProp["build.core"]!)
            return
        }
        args.append("toolchain="+toolChain)
        args.append("project="+dir.lastPathComponent!)
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

    enum Mode {
    case Upload
    case BurnBootloader
    case Interactive
    }

    func uploadProject(board: String, programmer: String, port: String, mode: Mode = .Upload) {
        let useProgrammer           = mode != .Upload
        let interactive             = mode == .Interactive
        let portPath                = ASSerial.fileNameForPort(port)
        let toolChain               = (NSApplication.sharedApplication().delegate as ASApplication).preferences.toolchainPath
        task = NSTask()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = toolChain+"/bin/avrdude"
        
        let fileManager = NSFileManager.defaultManager()
        var logOut      : NSFileHandle
        if interactive {
            let inputPipe           = NSPipe()
            let outputPipe          = NSPipe()
            logOut                  = outputPipe.fileHandleForWriting
            task!.standardInput     = inputPipe
            task!.standardOutput    = outputPipe
            task!.standardError     = outputPipe
        } else {
            ASSerialWin.portNeededForUpload(port)
            let logURL              = dir.URLByAppendingPathComponent("build/upload.log")
            fileManager.createFileAtPath(logURL.path!, contents: NSData(), attributes: nil)
            logOut                  = NSFileHandle(forWritingAtPath: logURL.path!)!
            task!.standardOutput    = logOut
            task!.standardError     = logOut
        }
        
        let libPath         = (ASLibraries.instance().directories as NSArray).componentsJoinedByString(":")
        let boardProp       = ASHardware.instance().boards[board]!
        let progProp        = ASHardware.instance().programmers[programmer]
        let hasBootloader   = !useProgrammer && boardProp["upload.protocol"] != nil
        let leonardish      = hasBootloader && (boardProp["bootloader.path"] ?? "").hasPrefix("caterina")
        let proto           = hasBootloader ? boardProp["upload.protocol"] : progProp?["protocol"]
        let speed           = hasBootloader ? boardProp["upload.speed"]    : progProp?["speed"]
        let verbosity       = NSUserDefaults.standardUserDefaults().integerForKey("UploadVerbosity")
        var args            = Array<String>(count: verbosity, repeatedValue: "-v")
        args               += [
            "-C", toolChain+"/etc/avrdude.conf",
            "-p", boardProp["build.mcu"]!, "-c", proto!, "-P", portPath]
        switch mode {
        case .Upload:
            if hasBootloader {
                args      += ["-D"]
            }
            args          += ["-U", "flash:w:build/"+board+"/"+dir.lastPathComponent!+".hex:i"]
            continuation   = {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(2*NSEC_PER_SEC)), dispatch_get_main_queue(), {
                    ASSerialWin.portAvailableAfterUpload(port)
                })
            }
        case .BurnBootloader:
            var loaderArgs = args
            args          += ["-e"]
            if let unlock = boardProp["bootloader.unlock_bits"] {
                args      += ["-Ulock:w:"+unlock+":m"]
            }
            if let efuse = boardProp["bootloader.extended_fuses"] {
                args      += ["-Uefuse:w:"+efuse+":m"]
            }
            let hfuse = boardProp["bootloader.high_fuses"]!
            let lfuse = boardProp["bootloader.low_fuses"]!
            args          += ["-Uhfuse:w:"+hfuse+":m", "-Ulfuse:w:"+lfuse+":m"]
            var needPhase2 = false
            if let loaderPath = boardProp["bootloader.path"] {
                let loader  = boardProp["library"]!+"/bootloaders/"+loaderPath+"/"+boardProp["bootloader.file"]!
                loaderArgs += ["-Uflash:w:"+loader+":i"]
                needPhase2  = true
            }
            if let lock = boardProp["bootloader.lock_bits"] {
                loaderArgs += ["-Ulock:w:"+lock+":m"]
                needPhase2  = true
            }
            if needPhase2 {
                let task2 = NSTask()
                task2.currentDirectoryPath = dir.path!
                task2.launchPath           = toolChain+"/bin/avrdude"
                task2.arguments            = loaderArgs
                task2.standardOutput       = logOut
                task2.standardError        = logOut
                continuation                = {
                    let cmdLine = task2.launchPath+" "+(loaderArgs as NSArray).componentsJoinedByString(" ")+"\n"
                    logOut.writeData(cmdLine.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
                    task2.launch()
                    self.continuation = {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(2*NSEC_PER_SEC)), dispatch_get_main_queue(), {
                            ASSerialWin.portAvailableAfterUpload(port)
                        })
                    }
                }
            }
        case .Interactive:
            args          += ["-t"]
        }
        if speed != nil {
            args.append("-b")
            args.append(speed!)
        }
        
        //
        // For Leonardo & the like, reset by opening port at 1200 baud
        //
        if leonardish {
            if verbosity > 0 {
                logOut.writeData("Opening port \(port) at 1200 baud\n".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
            }
            if let dummyConnection = ASSerial.openPort(portPath, withSpeed: 1200) {
                usleep(50000)
                ASSerial.closePort(dummyConnection.fileDescriptor)
                sleep(1)
                for (var retry=0; retry < 40; ++retry) {
                    usleep(250000)
                    if (fileManager.fileExistsAtPath(portPath)) {
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
        if interactive {
            let intSpeed = speed?.toInt() ?? 19200
            ASSerialWin.showWindowWithPort(port, task:task!, speed:intSpeed)
            task = nil
        }
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
        args           += ["-d", "build/"+board+"/"+dir.lastPathComponent!+".elf"]
        let cmdLine     = task!.launchPath+" "+(args as NSArray).componentsJoinedByString(" ")+"\n"
        logOut.writeData(cmdLine.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)!)
        task!.arguments         =   args;
        task!.launch()
    }
}