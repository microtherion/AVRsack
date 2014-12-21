//
//  ASSketchBook.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 12/20/14.
//  Copyright © 2014 Aere Perennius. All rights reserved.
//

import Foundation

class ASSketchBook {
    enum SketchBookItem {
    case Nothing
    case Sketch(String, String)
    case SketchDir(String, [SketchBookItem])
    }
    
    private class func enumerateSketches(path: NSString) -> SketchBookItem {
        let fileManager = NSFileManager.defaultManager()
        let contents    = fileManager.contentsOfDirectoryAtPath(path, error: nil) as [String]
        for item in contents {
            switch item.pathExtension {
            case "ino", "avrsackproj":
                return .Sketch(path.lastPathComponent, path.stringByAppendingPathComponent(item))
            default:
                break
            }
        }
        var sketches = [SketchBookItem]()
        for item in contents {
            let subpath = path.stringByAppendingPathComponent(item)
            var isDir   : ObjCBool = false
            if fileManager.fileExistsAtPath(subpath, isDirectory: &isDir) && isDir {
                let subEnum = enumerateSketches(subpath)
                switch subEnum {
                case .Nothing:
                    break
                default:
                    sketches.append(subEnum)
                }
            }
        }
        sketches.sort({ (a: SketchBookItem, b: SketchBookItem) -> Bool in
            var itemA : String = ""
            switch a {
            case .Sketch(let item, _):
                itemA = item
            case .SketchDir(let item, _):
                itemA = item
            default:
                break
            }
            switch b {
            case .Sketch(let item, _):
                return itemA < item
            case .SketchDir(let item, _):
                return itemA < item
            default:
                return itemA < ""
            }
        })
        return sketches.count > 0 ? .SketchDir(path.lastPathComponent, sketches) : .Nothing
    }
    
    class func appendSketchesToMenu(menu: NSMenu, target: AnyObject, action: Selector, sketchList: [SketchBookItem], inout sketches: [String]) {
        for sketch in sketchList {
            switch (sketch) {
            case .Sketch(let item, let path):
                let menuItem                = menu.addItemWithTitle(item, action: action, keyEquivalent: "")
                menuItem?.target            = target
                menuItem?.tag               = sketches.count
                sketches.append(path)
            case .SketchDir(let item, let subSketches):
                let menuItem                = menu.addItemWithTitle(item, action: nil, keyEquivalent: "")
                let submenu                 = NSMenu()
                submenu.autoenablesItems    = false
                appendSketchesToMenu(submenu, target: target, action: action, sketchList: subSketches, sketches: &sketches)
                menu.setSubmenu(submenu, forItem: menuItem!)
            default:
                break
            }
        }
    }
    
    class func addSketches(menu: NSMenu, target: AnyObject, action: Selector, path: NSString, inout sketches: [String]) {
        switch enumerateSketches(path) {
        case .SketchDir(let item, let sketchList):
            appendSketchesToMenu(menu, target: target, action: action, sketchList: sketchList, sketches: &sketches)
        default:
            break
        }
    }
}