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
    var task        : Task?
    var continuation: (()->())?
    var termination : AnyObject?
    
    init() {
        termination = NotificationCenter.default.addObserver(forName: Task.didTerminateNotification,
                                                                   object: nil, queue: nil, using:
        { (notification: Notification) in
            if notification.object as? Task == self.task {
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
        NotificationCenter.default.removeObserver(termination!)
    }
    
    func setProjectURL(url: NSURL) {
        dir       = url.URLByDeletingLastPathComponent!.URLByStandardizingPath!
    }

    func stop() {
        task?.terminate()
        task?.waitUntilExit()
    }
    
    func cleanProject() {
        do {
            try FileManager.default.removeItem(at: dir.appendingPathComponent("build")!)
        } catch _ {
        }
    }
    
    func buildProject(board: String, files: ASFileTree) {
        let toolChain               = (NSApplication.shared().delegate as! ASApplication).preferences.toolchainPath
        task = Task()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = Bundle.main.path(forResource: "BuildProject", ofType: "")!
        
        let fileManager = FileManager.default
        let libPath     = (ASLibraries.instance().directories as NSArray).componentsJoined(by: ":")
        var args        = [String]()
        if ASHardware.instance().boards[board] == nil {
            NSLog("Unable to find board %s\n", board);
            return
        }
        let boardProp   = ASHardware.instance().boards[board]!
        let library     = boardProp["library"]!
        let corePath    = library+"/cores/"+boardProp["build.core"]!
        var variantPath : String?
        if fileManager.fileExists(atPath: corePath) {
            if let variantName = boardProp["build.variant"] {
                variantPath = library+"/variants/"+variantName
                if fileManager.fileExists(atPath: variantPath!) {
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
        args.append("max_size="+boardProp["upload.maximum_size"]!)
        args.append("core="+boardProp["build.core"]!)
        args.append("libs="+libPath)
        args.append("core_path="+corePath)
        if let varPath = variantPath {
            args.append("variant_path="+varPath)
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
        let portPath                = ASSerial.fileName(forPort: port)
        let toolChain               = (NSApplication.shared().delegate as! ASApplication).preferences.toolchainPath
        task = Task()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = toolChain+"/bin/avrdude"
        
        let fileManager = FileManager.default
        var logOut      : FileHandle
        if interactive {
            let inputPipe           = Pipe()
            let outputPipe          = Pipe()
            logOut                  = outputPipe.fileHandleForWriting
            task!.standardInput     = inputPipe
            task!.standardOutput    = outputPipe
            task!.standardError     = outputPipe
        } else {
            ASSerialWin.portNeededForUpload(port: port)
            let logURL              = dir.appendingPathComponent("build/upload.log")
            fileManager.createFileAtPath(logURL.path, contents: NSData(), attributes: nil)
            logOut                  = FileHandle(forWritingAtPath: logURL.path!)!
            task!.standardOutput    = logOut
            task!.standardError     = logOut
        }
        if ASHardware.instance().boards[board] == nil {
            NSLog("Unable to find board %s\n", board);
            return
        }

        let boardProp       = ASHardware.instance().boards[board]!
        let progProp        = ASHardware.instance().programmers[programmer]
        let hasBootloader   = !useProgrammer && boardProp["upload.protocol"] != nil
        let leonardish      = hasBootloader && (boardProp["bootloader.path"] ?? "").hasPrefix("caterina")
        let proto           = hasBootloader ? boardProp["upload.protocol"] : progProp?["protocol"]
        let speed           = hasBootloader ? boardProp["upload.speed"]    : progProp?["speed"]
        let verbosity       = UserDefaults.standard.integer(forKey: "UploadVerbosity")
        var args            = Array<String>(repeating: "-v", count: verbosity)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                    ASSerialWin.portAvailableAfterUpload(port: port)
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
                let task2 = Task()
                task2.currentDirectoryPath = dir.path!
                task2.launchPath           = toolChain+"/bin/avrdude"
                task2.arguments            = loaderArgs
                task2.standardOutput       = logOut
                task2.standardError        = logOut
                continuation                = {
                    let cmdLine = task2.launchPath!+" "+(loaderArgs as NSArray).componentsJoined(by: " ")+"\n"
                    logOut.write(cmdLine.data(using: String.Encoding.utf8, allowLossyConversion: true)!)
                    task2.launch()
                    self.continuation = {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                            ASSerialWin.portAvailableAfterUpload(port: port)
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
                logOut.write("Opening port \(port) at 1200 baud\n".data(using: String.Encoding.utf8, allowLossyConversion: true)!)
            }
            if let dummyConnection = ASSerial.openPort(portPath, withSpeed: 1200) {
                usleep(50000)
                ASSerial.closePort(dummyConnection.fileDescriptor)
                sleep(1)
                for retry in 0 ..< 40 {
                    usleep(250000)
                    if (fileManager.fileExistsAtPath(portPath)) {
                        if verbosity > 0 {
                            logOut.write("Found port \(port) after \(retry) attempts.\n".data(using: String.Encoding.utf8, allowLossyConversion: true)!)
                        }
                        break;
                    }
                }
            }
        }
        let cmdLine = task!.launchPath!+" "+(args as NSArray).componentsJoined(by: " ")+"\n"
        logOut.write(cmdLine.data(using: String.Encoding.utf8, allowLossyConversion: true)!)
        task!.arguments         =   args;
        task!.launch()
        if interactive {
            let intSpeed = (speed != nil) ? Int(speed!) ?? 19200 : 19200
            ASSerialWin.showWindowWithPort(port: port, task:task!, speed:intSpeed)
            task = nil
        }
    }
    
    func disassembleProject(board: String) {
        let toolChain               = (NSApplication.shared().delegate as! ASApplication).preferences.toolchainPath
        task = Task()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = toolChain+"/bin/avr-objdump"
        
        let fileManager         = FileManager.default
        let logURL              = dir.appendingPathComponent("build/disasm.log")
        fileManager.createFileAtPath(logURL.path!, contents: NSData(), attributes: nil)
        let logOut              = FileHandle(forWritingAtPath: logURL.path!)!
        task!.standardOutput    = logOut
        task!.standardError     = logOut
        
        let showSource  = UserDefaults.standard.bool(forKey: "ShowSourceInDisassembly")
        var args        = showSource ? ["-S"] : []
        args           += ["-d", "build/"+board+"/"+dir.lastPathComponent!+".elf"]
        let cmdLine     = task!.launchPath!+" "+(args as NSArray).componentsJoined(by: " ")+"\n"
        logOut.writeData(cmdLine.dataUsingEncoding(String.Encoding.utf8, allowLossyConversion: true)!)
        task!.arguments         =   args;
        task!.launch()
    }
}
