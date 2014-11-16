//
//  ASFileTree.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/16/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Foundation

enum ASFileType : String {
    case Unknown    = ""
    case Header     = "source.h"
    case CFile      = "source.c"
    case Arduino    = "source.ino"
    case CppFile    = "source.c++"
    case AsmFile    = "source.asm"
    case Markdown   = "doc.md"
    
    static func guessForURL(url: NSURL) -> ASFileType {
        switch url.pathExtension.lowercaseString {
        case "hpp", "hh", "h":
            return .Header
        case "c":
            return .CFile
        case "ino":
            return .Arduino
        case "cpp", "c++", "cxx", "cc":
            return .CppFile
        case "s":
            return .AsmFile
        case "md":
            return .Markdown
        default:
            return .Unknown
        }
    }
    
    var aceMode : ACEMode {
        switch self {
        case .Header,.CFile,.CppFile,.Arduino:
            return ACEModeCPP
        case .Markdown:
            return ACEModeMarkdown
        default:
            return ACEModeASCIIDoc
        }
    }
}

class ASFileNode {
    func nodeName() -> String {
        return ""
    }
    func apply(closure:(ASFileNode)->()) {
        closure(self)
    }
}

class ASFileGroup : ASFileNode {
    var name        : String
    var children    : [ASFileNode]
    var expanded    : Bool
    
    init(name: String) {
        self.name       = name
        self.children   = []
        self.expanded   = true
    }
    convenience override init() {
        self.init(name: "")
    }
    override func nodeName() -> String {
        return (expanded ? "📂" : "📁")+" "+name
    }
    override func apply(closure: (ASFileNode) -> ()) {
        super.apply(closure)
        for child in children {
            child.apply(closure)
        }
    }
}

class ASProject : ASFileGroup {
    override func nodeName() -> String {
        return "📘 "+name
    }
}

class ASFileItem : ASFileNode {
    var url     : NSURL
    var type    : ASFileType
    
    init(url: NSURL, type: ASFileType) {
        self.url    = url
        self.type   = type
    }
    override func nodeName() -> String {
        return "📄 "+url.lastPathComponent
    }
}

class ASFileTree : NSObject, NSOutlineViewDataSource {
    let root = ASProject()
    
    func addFileURL(url: NSURL, omitUnknown: Bool = true) {
        let type = ASFileType.guessForURL(url)
        if !omitUnknown || type != .Unknown {
            root.children.append(ASFileItem(url: url, type: type))
        }
    }
    func setProjectURL(url: NSURL) {
        root.name = url.lastPathComponent.stringByDeletingPathExtension
    }
    func apply(closure: (ASFileNode) -> ()) {
        root.apply(closure)
    }
    
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        if item == nil {
            return 1
        } else {
            return (item as ASFileGroup).children.count
        }
    }
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        if item == nil {
            return root
        } else {
            let group = item as ASFileGroup
            return group.children[index]
        }
    }
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        return item is ASFileGroup
    }
    func outlineView(outlineView: NSOutlineView, objectValueForTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) -> AnyObject? {
        return (item as ASFileNode).nodeName()
    }
}