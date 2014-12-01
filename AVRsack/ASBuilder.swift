//
//  ASBuilder.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/24/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

class ASBuilder {
    var dir     = NSURL()
    var task    : NSTask?
    
    func setProjectURL(url: NSURL) {
        dir       = url.URLByDeletingLastPathComponent!.standardizedURL!
    }

    func buildProject(board: String, files: ASFileTree) {
        task = NSTask()
        task!.currentDirectoryPath  = dir.path!
        task!.launchPath            = NSBundle.mainBundle().pathForResource("BuildProject", ofType: "")!
        
        let fileManager         = NSFileManager.defaultManager()
        let libPath     = (ASLibraries.instance().directories as NSArray).componentsJoinedByString(":")
        var args        = [NSString]()
        let boardProp   = ASHardware.instance().boards[board]!
        var corePath    = ""
        var variantPath : NSString?
        for hw in ASHardware.instance().directories {
            corePath = hw+"/cores/"+boardProp["build.core"]
            if fileManager.fileExistsAtPath(corePath) {
                if boardProp["build.variant"] != "" {
                    variantPath = hw+"/variants/"+boardProp["build.variant"]
                    if !fileManager.fileExistsAtPath(corePath) {
                        variantPath = nil
                    }
                }
                break
            } else {
                corePath = ""
            }
        }
        if corePath == "" {
            NSLog("Unable to find core %s\n", boardProp["build.core"])
            return
        }
        args.append("project="+dir.lastPathComponent)
        args.append("board="+board)
        args.append("mcu="+boardProp["build.mcu"])
        args.append("f_cpu="+boardProp["build.f_cpu"])
        args.append("core="+boardProp["build.core"])
        args.append("variant="+boardProp["build.variant"])
        args.append("libs="+libPath)
        args.append("core_path="+corePath)
        if variantPath != nil {
            args.append("variant_path="+variantPath!)
        }
        args.append("--")
        args            += files.paths
        task!.arguments =   args;
        task!.launch()
        
        files.paths
    }
}