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

private let kTypeKey            = "Type"
private let kNodeTypeProject    = "Project"
private let kNodeTypeGroup      = "Group"
private let kNodeTypeFile       = "File"
private let kNameKey            = "Name"

class ASFileNode {
    func nodeName() -> String {
        return ""
    }
    func apply(closure:(ASFileNode)->()) {
        closure(self)
    }
    func propertyList(rootPath: NSString) -> AnyObject {
        return ""
    }
    class func readPropertyList(prop: NSDictionary, rootURL: NSURL) -> ASFileNode {
        switch prop[kTypeKey] as String {
        case kNodeTypeProject:
            return ASProject(prop, withRootURL:rootURL)
        case kNodeTypeGroup:
            return ASFileGroup(prop, withRootURL:rootURL)
        case kNodeTypeFile:
            return ASFileItem(prop, withRootURL:rootURL)
        default:
            assertionFailure("Undefined item type in file hierarchy")
        }
    }
    func paths(rootPath: NSString) -> [NSString] {
        return [NSString]()
    }
}

class ASFileGroup : ASFileNode {
    var name        : String
    var children    : [ASFileNode]
    var expanded    : Bool

    private let kChildrenKey = "Children"
    private let kExpandedKey = "Expanded"
    private var kNodeType : String { return kNodeTypeGroup }

    init(name: String = "") {
        self.name       = name
        self.children   = []
        self.expanded   = true
    }
    init(_ prop: NSDictionary, withRootURL rootURL: NSURL) {
        name        = prop[kNameKey] as String
        expanded    = prop[kExpandedKey] as Bool
        children    = []
        for child in (prop[kChildrenKey] as NSArray) {
            children.append(ASFileNode.readPropertyList(child as NSDictionary, rootURL: rootURL))
        }
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
    func childrenPropertyList(rootPath: NSString) -> [AnyObject] {
        return children.map() { (node) in node.propertyList(rootPath) }
    }
    override func propertyList(rootPath: NSString) -> AnyObject {
        return [kTypeKey: kNodeType, kNameKey: name, kExpandedKey: expanded,
            kChildrenKey: childrenPropertyList(rootPath)]
    }
    override func paths(rootPath: NSString) -> [NSString] {
        var allPaths = [NSString]()
        for child in children {
            allPaths += child.paths(rootPath)
        }
        return allPaths
    }
}

class ASProject : ASFileGroup {
    override private var kNodeType : String { return kNodeTypeProject }
    
    override func nodeName() -> String {
        return "📘 "+name
    }
}

class ASFileItem : ASFileNode {
    var url     : NSURL
    var type    : ASFileType

    private let kPathKey = "Path"
    private let kKindKey = "Kind"

    init(url: NSURL, type: ASFileType) {
        self.url    = url
        self.type   = type
    }
    init(_ prop: NSDictionary, withRootURL rootURL: NSURL) {
        type = ASFileType(rawValue: prop[kKindKey] as String)!
        url  = NSURL(string: prop[kPathKey] as NSString, relativeToURL: rootURL)!.standardizedURL!
    }
    override func nodeName() -> String {
        return "📄 "+url.lastPathComponent
    }
    
    func relativePath(relativeTo: String) -> String {
        let path        = url.path!
        let relComp     = relativeTo.componentsSeparatedByString("/") as [String]
        let pathComp    = path.componentsSeparatedByString("/") as [String]
        let relCount    = relComp.count
        let pathCount   = pathComp.count
        
        var matchComp = 0
        while (matchComp < relCount && matchComp < pathCount) {
            if pathComp[matchComp] == relComp[matchComp] {
                ++matchComp
            } else {
                break
            }
        }
        if matchComp==1 {
            return path
        }
        
        let resComp = Array(count: relCount-matchComp, repeatedValue: "..")+pathComp[matchComp..<pathCount]
        return "/".join(resComp)
    }
    override func propertyList(rootPath: NSString) -> AnyObject {
        return [kTypeKey: kNodeTypeFile, kKindKey: type.rawValue, kPathKey: relativePath(rootPath)]
    }
    override func paths(rootPath: NSString) -> [NSString] {
        return [relativePath(rootPath)]
    }
}

class ASFileTree : NSObject, NSOutlineViewDataSource {
    var root = ASProject()
    var dir  = NSURL()
    
    func addFileURL(url: NSURL, omitUnknown: Bool = true) {
        let type = ASFileType.guessForURL(url)
        if !omitUnknown || type != .Unknown {
            root.children.append(ASFileItem(url: url.standardizedURL!, type: type))
        }
    }
    func setProjectURL(url: NSURL) {
        root.name = url.lastPathComponent.stringByDeletingPathExtension
        dir       = url.URLByDeletingLastPathComponent!.standardizedURL!
    }
    func apply(closure: (ASFileNode) -> ()) {
        root.apply(closure)
    }
    func propertyList() -> AnyObject {
        return root.propertyList(dir.path!)
    }
    func readPropertyList(prop: NSDictionary) {
        root = ASFileNode.readPropertyList(prop, rootURL:dir) as ASProject
    }
    var paths : [NSString] {
        return root.paths(dir.path!)
    }
    
    // MARK: Outline Data Source
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