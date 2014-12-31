//
//  ACEViewExt.swift
//  AVRsack
//
//  Created by Matthias Neeracher on 29/12/14.
//  Copyright (c) 2014 Aere Perennius. All rights reserved.
//

import Foundation

extension ACEView {
    class func themeIdByName(themeName: String) -> UInt? {
        for (themeIdx, theme) in enumerate(ACEThemeNames.themeNames() as [NSString]) {
            if themeName == theme {
                return UInt(themeIdx)
            }
        }
        return nil
    }
    
    class func handlerIdByName(handlerName: String) -> ACEKeyboardHandler? {
        for (handlerIdx, handler) in enumerate(ACEKeyboardHandlerNames.humanKeyboardHandlerNames() as [NSString]) {
            if handlerName == handler {
                return ACEKeyboardHandler(rawValue: UInt(handlerIdx))!
            }
        }
        return nil
    }
}