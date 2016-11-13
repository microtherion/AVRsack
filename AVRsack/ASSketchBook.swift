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
    
    class func findSketch(path: String) -> SketchBookItem {
        let fileManager = FileManager.default
        var inoSketch   = SketchBookItem.Nothing
        let contents    = (try! fileManager.contentsOfDirectory(atPath: path))
        let nspath      = path as NSString
        for item in contents {
            switch (item as NSString).pathExtension {
            case "avrsackproj":
                return .Sketch(nspath.lastPathComponent, nspath.appendingPathComponent(item))
            case "ino":
                inoSketch = .Sketch(nspath.lastPathComponent, nspath.appendingPathComponent(item))
            default:
                break
            }
        }
        return inoSketch
    }
    
    private class func enumerateSketches(path: String) -> SketchBookItem {
        let fileManager = FileManager.default
        let contents    = (try! fileManager.contentsOfDirectory(atPath: path)) 
        let nspath      = path as NSString
        let sketch      = findSketch(path: path)
        switch sketch {
        case .Sketch:
            return sketch
        default:
            break
        }
        var sketches = [SketchBookItem]()
        for item in contents {
            let subpath = nspath.appendingPathComponent(item)
            var isDir   : ObjCBool = false
            if fileManager.fileExists(atPath: subpath, isDirectory: &isDir) && isDir.boolValue {
                let subEnum = enumerateSketches(path: subpath)
                switch subEnum {
                case .Nothing:
                    break
                default:
                    sketches.append(subEnum)
                }
            }
        }
        sketches.sort(by: { (a: SketchBookItem, b: SketchBookItem) -> Bool in
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
        return sketches.count > 0 ? .SketchDir(nspath.lastPathComponent, sketches) : .Nothing
    }
    
    class func appendSketchesToMenu(menu: NSMenu, target: AnyObject, action: Selector, sketchList: [SketchBookItem], sketches: inout [String]) {
        for sketch in sketchList {
            switch (sketch) {
            case .Sketch(let item, let path):
                let menuItem                = menu.addItem(withTitle: item, action: action, keyEquivalent: "")
                menuItem.target            = target
                menuItem.tag               = sketches.count
                sketches.append(path)
            case .SketchDir(let item, let subSketches):
                let menuItem                = menu.addItem(withTitle: item, action: nil, keyEquivalent: "")
                let submenu                 = NSMenu()
                submenu.autoenablesItems    = false
                appendSketchesToMenu(menu: submenu, target: target, action: action, sketchList: subSketches, sketches: &sketches)
                menu.setSubmenu(submenu, for: menuItem)
            default:
                break
            }
        }
    }
    
    class func addSketches(menu: NSMenu, target: AnyObject, action: Selector, path: String, sketches: inout [String]) {
        switch enumerateSketches(path: path) {
        case .SketchDir(_, let sketchList):
            appendSketchesToMenu(menu: menu, target: target, action: action, sketchList: sketchList, sketches: &sketches)
        default:
            break
        }
    }
}
