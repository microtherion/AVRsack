//
//  ASProjDoc.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 11/15/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Cocoa

class ASProjDoc: NSDocument, NSOutlineViewDelegate {
    @IBOutlet weak var editor   : ACEView!
    @IBOutlet weak var outline  : NSOutlineView!
    let files                   : ASFileTree = ASFileTree()
    var mainEditor              : ASFileNode?
    
    // MARK: Initialization / Finalization
    
    override init() {
        super.init()
        // Add your subclass-specific initialization here.
    }
    override func finalize() {
        saveCurEditor()
    }
    
    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        outline.setDataSource(files)
        files.apply() { node in
            if let group = node as? ASFileGroup {
                if group.expanded {
                    self.outline.expandItem(node)
                }
            }
        }
    }

    override class func autosavesInPlace() -> Bool {
        return true
    }

    override var windowNibName: String? {
        // Returns the nib file name of the document
        // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
        return "ASProjDoc"
    }

    // MARK: Load / Save
    
    func saveCurEditor() {
        if let file = (mainEditor as? ASFileItem) {
            editor.string().writeToURL(file.url, atomically: true, encoding: NSUTF8StringEncoding, error: nil)
        }
    }
    
    let kVersionKey = "Version"
    let kCurVersion = 1.0
    let kFilesKey   = "Files"
    
    override func dataOfType(typeName: String, error outError: NSErrorPointer) -> NSData? {
        let data = [kVersionKey: kCurVersion, kFilesKey: files.propertyList()]
        return NSPropertyListSerialization.dataFromPropertyList(data, format: .XMLFormat_v1_0, errorDescription: nil)
    }

    func importProject(url: NSURL, error outError: NSErrorPointer) -> Bool {
        let existingProject = url.URLByAppendingPathComponent(url.lastPathComponent+".avrsackproj")
        if existingProject.checkResourceIsReachableAndReturnError(nil) {
            fileURL = existingProject
            return readFromURL(existingProject, ofType:"Project", error:outError)
        }
        let filesInProject =
            NSFileManager.defaultManager().contentsOfDirectoryAtURL(url, includingPropertiesForKeys: nil,
                options: .SkipsHiddenFiles, error: nil)!
        for file in filesInProject {
            files.addFileURL(file as NSURL)
        }
        return true
    }
    
    override func readFromURL(url: NSURL, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
        var success : Bool = false
        if typeName == "Arduino Source File" {
            let projectURL = url.URLByDeletingPathExtension!.URLByAppendingPathExtension("avrsackproj")
            success = importProject(url.URLByDeletingLastPathComponent!, error: outError)
            if success {
                files.setProjectURL(fileURL!)
                fileURL = projectURL
                success = writeToURL(projectURL, ofType: "Project", forSaveOperation: .SaveAsOperation, originalContentsURL: nil, error: outError)
            }
        } else {
            success = super.readFromURL(url, ofType: typeName, error: outError)
        }
        return success
    }
    override func readFromData(data: NSData, ofType typeName: String, error outError: NSErrorPointer) -> Bool {
        if typeName != "Project" {
            return false
        }
        files.setProjectURL(fileURL!)
        let projectData : NSDictionary = NSPropertyListSerialization.propertyListFromData(data, mutabilityOption: .Immutable, format: nil, errorDescription: nil) as NSDictionary
        let projectVersion = projectData[kVersionKey] as Double
        assert(projectVersion <= floor(kCurVersion+1.0), "Project version too new for this app")
        files.readPropertyList(projectData[kFilesKey] as NSDictionary)
        
        return true
    }
 
    // MARK: Outline View Delegate
    
    func outlineViewSelectionDidChange(notification: NSNotification) {
        let selection = outline.itemAtRow(outline.selectedRow) as ASFileNode?
        if selection !== mainEditor {
            saveCurEditor()
        }
        if let file = (selection as? ASFileItem) {
            var enc : UInt = 0
            editor.setString(NSString(contentsOfURL:file.url, usedEncoding:&enc, error:nil))
            editor.setMode(UInt(file.type.aceMode))
        }
    }
    func outlineViewItemDidExpand(notification: NSNotification) {
        let group       = notification.userInfo!["NSObject"] as ASFileGroup
        group.expanded  = true
    }
    func outlineViewItemDidCollapse(notification: NSNotification) {
        let group       = notification.userInfo!["NSObject"] as ASFileGroup
        group.expanded  = false
    }
}

