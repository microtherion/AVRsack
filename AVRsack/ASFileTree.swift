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
    
    static func guessForURL(url: URL) -> ASFileType {
        switch url.pathExtension.lowercased() {
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
            return .markdown
        default:
            return .text
        }
    }
}

private let kTypeKey            = "Type"
private let kNodeTypeProject    = "Project"
private let kNodeTypeGroup      = "Group"
private let kNodeTypeFile       = "File"
private let kNameKey            = "Name"

class ASFileNode : Equatable {
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

    func propertyList(rootPath: String) -> Dictionary<String, Any> {
        return [:]
    }

    class func readPropertyList(prop: Dictionary<String, AnyObject>, rootURL: URL) -> ASFileNode {
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

    func modDate() -> Date? {
        return nil;
    }

    func revision() -> String? {
        return nil;
    }
}

func ==(a: ASFileNode, b: ASFileNode) -> Bool {
    return a === b
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
    fileprivate var kNodeType : String { return kNodeTypeGroup }

    override init(name: String = "") {
        self.children   = []
        self.expanded   = true
        super.init(name: name)
    }

    init(_ prop: Dictionary<String, AnyObject>, withRootURL rootURL: URL) {
        expanded    = prop[kExpandedKey] as! Bool
        children    = []
        for child in (prop[kChildrenKey] as! [Dictionary<String, AnyObject>]) {
            children.append(ASFileNode.readPropertyList(prop: child, rootURL: rootURL))
        }
        super.init(name: prop[kNameKey] as! String)
    }

    override func nodeName() -> String {
        return (expanded ? "📂" : "📁")+" "+name
    }

    override func apply(closure: (ASFileNode) -> ()) {
        super.apply(closure: closure)
        for child in children {
            child.apply(closure: closure)
        }
    }

    func childrenPropertyList(rootPath: String) -> [Any] {
        return children.map() { (node) in node.propertyList(rootPath: rootPath) }
    }

    override func propertyList(rootPath: String) -> Dictionary<String, Any> {
        return [kTypeKey: kNodeType, kNameKey: name, kExpandedKey: expanded,
                kChildrenKey: childrenPropertyList(rootPath: rootPath)]
    }

    override func paths(rootPath: String) -> [String] {
        var allPaths = [String]()
        for child in children {
            allPaths += child.paths(rootPath: rootPath)
        }
        return allPaths
    }
}

class ASProject : ASFileGroup {
    override fileprivate var kNodeType : String { return kNodeTypeProject }
    
    override init(name: String = "") {
        super.init(name: name)
    }

    override init(_ prop: Dictionary<String, AnyObject>, withRootURL rootURL: URL) {
        super.init(prop, withRootURL:rootURL)
        name = rootURL.lastPathComponent
    }

    override func nodeName() -> String {
        return "📘 "+name
    }
}

class ASFileItem : ASFileNode {
    var url     : URL
    var type    : ASFileType

    private let kPathKey = "Path"
    private let kKindKey = "Kind"

    init(url: URL, type: ASFileType) {
        self.url    = url
        self.type   = type
        super.init(name:url.lastPathComponent)
    }

    init(_ prop: Dictionary<String, AnyObject>, withRootURL rootURL: URL) {
        type = ASFileType(rawValue: prop[kKindKey] as! String)!
        let path = prop[kPathKey] as! NSString
        if path.isAbsolutePath {
            url = URL(fileURLWithPath:path as String).standardizedFileURL
        } else {
            url = URL(fileURLWithPath: path as String, relativeTo: rootURL).standardizedFileURL
        }
        var fileExists = false
        do {
            fileExists = try url.checkResourceIsReachable()
        } catch {
            fileExists = false
        }
        if !fileExists {
            //
            // When projects get moved, .ino files get renamed but that fact is not 
            // yet reflected in the project file.
            //
            let urlDir  = url.deletingLastPathComponent()
            let newName = rootURL.appendingPathExtension(url.pathExtension).lastPathComponent
            let altURL  = urlDir.appendingPathComponent(newName)
            if let altExists = try? altURL.checkResourceIsReachable(), altExists {
                url = altURL
            }
        }
        super.init(name:url.lastPathComponent)
    }

    override func nodeName() -> String {
        return "📄 "+name
    }
    
    func relativePath(relativeTo: String) -> String {
        let path        = (url.path as NSString).resolvingSymlinksInPath
        let relComp     = relativeTo.components(separatedBy: "/") as [String]
        let pathComp    = path.components(separatedBy: "/") as [String]
        let relCount    = relComp.count
        let pathCount   = pathComp.count
        
        var matchComp = 0
        while (matchComp < relCount && matchComp < pathCount) {
            if pathComp[matchComp] == relComp[matchComp] {
                matchComp += 1
            } else {
                break
            }
        }
        if matchComp==1 {
            return path
        }
        
        let resComp = Array(repeating: "..", count: relCount-matchComp)+pathComp[matchComp..<pathCount]
        return resComp.joined(separator: "/")
    }

    override func propertyList(rootPath: String) -> Dictionary<String, Any> {
        return [kTypeKey: kNodeTypeFile, kKindKey: type.rawValue,
                kPathKey: relativePath(relativeTo: rootPath)]
    }

    override func paths(rootPath: String) -> [String] {
        return [relativePath(relativeTo: rootPath)]
    }

    override func exists() -> Bool {
        do {
            return try url.checkResourceIsReachable()
        } catch {
            return false
        }
    }

    override func modDate() -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])

        return values?.contentModificationDate
    }

    override func revision() -> String? {
        let task            = Process()
        task.launchPath     = Bundle.main.path(forResource: "FileRevision", ofType: "")!
        let outputPipe      = Pipe()
        task.standardOutput = outputPipe
        task.standardError  = FileHandle.nullDevice
        task.arguments      = [url.path]
        task.launch()

        return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: String.Encoding.utf8)
    }
}

class ASFileTree : NSObject, NSOutlineViewDataSource {
    var root        = ASProject()
    var dir         = URL(fileURLWithPath: "/")
    var buildLog    = ASLogNode(name: "Build Log", path: "build/build.log")
    var uploadLog   = ASLogNode(name: "Upload Log", path: "build/upload.log")
    var disassembly = ASLogNode(name: "Disassembly", path: "build/disasm.log")
    var dragged     = [ASFileNode]()
    
    func addFileURL(url: URL, omitUnknown: Bool = true) {
        let type = ASFileType.guessForURL(url: url)
        if !omitUnknown || type != .Unknown {
            root.children.append(ASFileItem(url: url.standardizedFileURL, type: type))
        }
    }
    func setProjectURL(url: URL) {
        root.name = url.deletingPathExtension().lastPathComponent
        dir       = url.deletingLastPathComponent().standardizedFileURL
    }
    func projectPath() -> String {
        return (dir.path as NSString).resolvingSymlinksInPath
    }
    func apply(closure: (ASFileNode) -> ()) {
        root.apply(closure: closure)
    }
    func propertyList() -> Any {
        return root.propertyList(rootPath: projectPath())
    }
    func readPropertyList(prop: Dictionary<String, AnyObject>) {
        root = ASFileNode.readPropertyList(prop: prop, rootURL:dir) as! ASProject
    }
    var paths : [String] {
        return root.paths(rootPath: projectPath())
    }
    
    // MARK: Outline Data Source
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return 4
        } else {
            return (item as! ASFileGroup).children.count
        }
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
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
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is ASFileGroup
    }
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        return (item as! ASFileNode).nodeName()
    }

    let kLocalReorderPasteboardType = "ASFilePasteboardType"
    private func outlineView(_ outlineView: NSOutlineView, writeItems items: [AnyObject], to pasteboard: NSPasteboard) -> Bool {
        dragged = items as! [ASFileNode]
        pasteboard.declareTypes([kLocalReorderPasteboardType], owner: self)
        pasteboard.setData(Data(), forType: kLocalReorderPasteboardType)

        return true
    }
    func itemIsDescendentOfDrag(outlineView: NSOutlineView, item: ASFileNode) -> Bool {
        if dragged.contains(item) {
            return true
        } else if item is ASProject {
            return false
        } else {
            return itemIsDescendentOfDrag(outlineView: outlineView, item: outlineView.parent(forItem: item) as! ASFileNode)
        }
    }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if info.draggingPasteboard().availableType(from: [kLocalReorderPasteboardType]) == nil {
            return [] // Only allow reordering drags
        }
        for drag in dragged {
            switch (drag) {
            case is ASProject, is ASLogNode:
                return [] // Don't allow root or log nodes to be dragged
            default:
                break
            }
        }
        switch (item) {
        case is ASProject, is ASFileGroup:
            if itemIsDescendentOfDrag(outlineView: outlineView, item: item as! ASFileNode) {
                return [] // Don't allow drag on member of dragged items or a descendent thereof
            }
        default:
            return [] // Don't allow drag onto leaf
        }
        return NSDragOperation.generic
    }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex insertAtIndex: Int) -> Bool {
        var insertAtIndex = insertAtIndex
        let parent : ASFileGroup = (item as? ASFileGroup) ?? root
        if insertAtIndex == NSOutlineViewDropOnItemIndex {
            insertAtIndex = parent.children.count
        }
        outlineView.beginUpdates()
        for item in dragged {
            let origParent  = outlineView.parent(forItem: item) as! ASFileGroup
            let origIndex   = origParent.children.index(of: item)!
            origParent.children.remove(at: origIndex)
            outlineView.removeItems(at:IndexSet(integer:origIndex), inParent:origParent, withAnimation:[])
            if origParent == parent && insertAtIndex > origIndex {
                insertAtIndex -= 1
            }
            parent.children.insert(item, at:insertAtIndex)
            outlineView.insertItems(at:IndexSet(integer:insertAtIndex), inParent: parent, withAnimation:NSTableViewAnimationOptions.effectGap)
            insertAtIndex += 1
        }
        outlineView.endUpdates()
        (outlineView.delegate as! ASProjDoc).updateChangeCount(NSDocumentChangeType.changeDone)

        return true
    }
}
