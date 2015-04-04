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
        switch url.pathExtension!.lowercaseString {
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
            return .CPP
        case .Markdown:
            return .Markdown
        default:
            return .Text
        }
    }
}

private let kTypeKey            = "Type"
private let kNodeTypeProject    = "Project"
private let kNodeTypeGroup      = "Group"
private let kNodeTypeFile       = "File"
private let kNameKey            = "Name"

//
// <rdar://problem/19787270> At the moment, Swift crashes at link time with an assertion 
//      if anything other than a value type or an @objc class is put into a container
//      exposed to ObjC APIs. As a workaround, we declare this hierarchy @objc
//
@objc class ASFileNode {
    var name        : String

    init(name: String) {
        self.name = name
    }

    func nodeName() -> String {
        return ""
    }
    func apply(closure:(ASFileNode)->()) {
        closure(self)
    }
    func propertyList(rootPath: String) -> AnyObject {
        return ""
    }
    class func readPropertyList(prop: NSDictionary, rootURL: NSURL) -> ASFileNode {
        switch prop[kTypeKey] as! String {
        case kNodeTypeProject:
            return ASProject(prop, withRootURL:rootURL)
        case kNodeTypeGroup:
            return ASFileGroup(prop, withRootURL:rootURL)
        case kNodeTypeFile:
            return ASFileItem(prop, withRootURL:rootURL)
        default:
            assertionFailure("Undefined item type in file hierarchy")
            abort()
        }
    }
    func paths(rootPath: String) -> [String] {
        return [String]()
    }
    func exists() -> Bool {
        return true
    }
    func modDate() -> NSDate? {
        return nil;
    }
    func revision() -> String? {
        return nil;
    }
}

class ASLogNode : ASFileNode {
    var path        : String
    
    init(name: String, path: String) {
        self.path = path
        super.init(name: name)
    }
    override func nodeName() -> String {
        return "📜 "+name
    }
}

class ASFileGroup : ASFileNode {
    var children    : [ASFileNode]
    var expanded    : Bool

    private let kChildrenKey = "Children"
    private let kExpandedKey = "Expanded"
    private var kNodeType : String { return kNodeTypeGroup }

    override init(name: String = "") {
        self.children   = []
        self.expanded   = true
        super.init(name: name)
    }
    init(_ prop: NSDictionary, withRootURL rootURL: NSURL) {
        expanded    = prop[kExpandedKey] as! Bool
        children    = []
        for child in (prop[kChildrenKey] as! [NSDictionary]) {
            children.append(ASFileNode.readPropertyList(child, rootURL: rootURL))
        }
        super.init(name: prop[kNameKey] as! String)
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
    func childrenPropertyList(rootPath: String) -> [AnyObject] {
        return children.map() { (node) in node.propertyList(rootPath) }
    }
    override func propertyList(rootPath: String) -> AnyObject {
        return [kTypeKey: kNodeType, kNameKey: name, kExpandedKey: expanded,
            kChildrenKey: childrenPropertyList(rootPath)]
    }
    override func paths(rootPath: String) -> [String] {
        var allPaths = [String]()
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
        super.init(name:url.lastPathComponent!)
    }
    init(_ prop: NSDictionary, withRootURL rootURL: NSURL) {
        type = ASFileType(rawValue: prop[kKindKey] as! String)!
        if let relativeURL = NSURL(string: prop[kPathKey] as! String, relativeToURL: rootURL) {
            url  = relativeURL.URLByStandardizingPath!
        } else {
            url = NSURL(fileURLWithPath:(prop[kPathKey] as! String))!.URLByStandardizingPath!
        }
        super.init(name:url.lastPathComponent!)
    }
    override func nodeName() -> String {
        return "📄 "+name
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
    override func propertyList(rootPath: String) -> AnyObject {
        return [kTypeKey: kNodeTypeFile, kKindKey: type.rawValue, kPathKey: relativePath(rootPath)]
    }
    override func paths(rootPath: String) -> [String] {
        return [relativePath(rootPath)]
    }
    override func exists() -> Bool {
        return url.checkResourceIsReachableAndReturnError(nil)
    }
    override func modDate() -> NSDate? {
        var date: AnyObject?
        url.getResourceValue(&date, forKey: NSURLContentModificationDateKey, error: nil)
        return date as? NSDate
    }
    override func revision() -> String? {
        let task            = NSTask()
        task.launchPath     = NSBundle.mainBundle().pathForResource("FileRevision", ofType: "")!
        let outputPipe      = NSPipe()
        task.standardOutput = outputPipe
        task.standardError  = NSFileHandle.fileHandleWithNullDevice()
        task.arguments      = [url.path!]
        task.launch()

        return NSString(data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: NSUTF8StringEncoding) as? String
    }
}

class ASFileTree : NSObject, NSOutlineViewDataSource {
    var root        = ASProject()
    var dir         = NSURL()
    var buildLog    = ASLogNode(name: "Build Log", path: "build/build.log")
    var uploadLog   = ASLogNode(name: "Upload Log", path: "build/upload.log")
    var disassembly = ASLogNode(name: "Disassembly", path: "build/disasm.log")
    
    func addFileURL(url: NSURL, omitUnknown: Bool = true) {
        let type = ASFileType.guessForURL(url)
        if !omitUnknown || type != .Unknown {
            root.children.append(ASFileItem(url: url.URLByStandardizingPath!, type: type))
        }
    }
    func setProjectURL(url: NSURL) {
        root.name = url.lastPathComponent!.stringByDeletingPathExtension
        dir       = url.URLByDeletingLastPathComponent!.URLByStandardizingPath!
    }
    func apply(closure: (ASFileNode) -> ()) {
        root.apply(closure)
    }
    func propertyList() -> AnyObject {
        return root.propertyList(dir.path!)
    }
    func readPropertyList(prop: NSDictionary) {
        root = ASFileNode.readPropertyList(prop, rootURL:dir) as! ASProject
    }
    var paths : [String] {
        return root.paths(dir.path!)
    }
    
    // MARK: Outline Data Source
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        if item == nil {
            return 4
        } else {
            return (item as! ASFileGroup).children.count
        }
    }
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        if item == nil {
            switch index {
            case 1:
                return buildLog
            case 2:
                return uploadLog
            case 3:
                return disassembly
            default:
                return root
            }
        } else {
            let group = item as! ASFileGroup
            return group.children[index]
        }
    }
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        return item is ASFileGroup
    }
    func outlineView(outlineView: NSOutlineView, objectValueForTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) -> AnyObject? {
        return (item as! ASFileNode).nodeName()
    }
}