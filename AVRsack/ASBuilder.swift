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
        
        let libPath     = (ASLibraries.instance().directories as NSArray).componentsJoinedByString(":")
        var args        = [NSString]()
        let boardProp   = ASHardware.instance().boards[board]!
        args.append("board="+board)
        args.append("mcu="+boardProp["build.mcu"])
        args.append("f_cpu="+boardProp["build.f_cpu"])
        args.append("core="+boardProp["build.core"])
        args.append("variant="+boardProp["build.variant"])
        args.append("libs="+libPath)
        args.append("--")
        args            += files.paths
        task!.arguments =   args;
        task!.launch()
        
        files.paths
    }
}