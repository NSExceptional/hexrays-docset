//
//  DocumentParser.swift
//  hexrays-docset
//
//  Created by Tanner Bennett on 6/7/21.
//

import Foundation
import WebKit

enum ItemType: String {
    case unknown = "NIL"
    case framework = "Framework"
//    case macro = "Macro"
    case enumCase = "Value"
    case type = "Type"
    case sample = "Sample"
    case `enum` = "Enum"
    case function = "Function"
    case method = "Method"
    case ivar = "Property"
    case constant = "Constant"
    
    var isUnknown: Bool { self == .unknown }
    var isKnown: Bool { self != .unknown }
}

struct AnchorData: Comparable {
    let node: DOMHTMLElement
    var name: String
    var type: ItemType
    let href: String
    let fragment: String?
    let filename: String
    
    func with(type: ItemType) -> AnchorData {
        var d = self
        d.type = type
        return d
    }
    
    func fileExists(atPath folder: String) -> Bool {
        let path = folder.appendingPathComponent(self.filename)
        return FileManager.default.fileExists(atPath: path)
    }
    
    var dictionaryValue: [String: String] {
        return ["$name": name, "$type": type.rawValue, "$path": href]
    }
    
    static func < (lhs: AnchorData, rhs: AnchorData) -> Bool {
        return lhs.href < rhs.href
    }
}

@available(macOS, deprecated: 10.14)
struct DocumentParser {
    
    static let knownSuffixesToTypes: [String: ItemType] = [
        // I don't really care to differentiate between struct/class
        "_t": .type, "index.shtml": .framework,
        ".cpp": .sample, "source.shtml": .sample, "cpp-example.shtml": .sample,
    ]
    
    static let ignoredPaths: Set<String> = [
        "index.shtml", "pages.shtml", "modules.shtml", "files.shtml",
        "annotated.shtml", "hierarchy.shtml", "functions.shtml",
        "globals.shtml", "examples.shtml",
    ]
    static let ignoredClassNames: Set<String> = [
        "line",
    ]
    static let ignoredNames: Set<String> = [
        "SDK Reference", "◆ ", "More...",
    ]
    static let ignoredPathPrefixes: [String] = [
        "globals_", "functions_"
    ]
    
    static func keepNode(_ anchor: AnchorData) -> Bool {
        return anchor.name.count > 1
            && !self.ignoredPaths.contains(anchor.filename)
            && !self.ignoredNames.contains(anchor.name)
            && !self.ignoredClassNames.contains(anchor.node.className)
            && self.ignoredPathPrefixes.allSatisfy { !anchor.href.hasPrefix($0) }
    }
    
    static func parseTableRows(_ rows: DOMNodeList) -> [AnchorData] {
        return rows.map { $0 as! DOMHTMLTableRowElement }
            .flatMap(self.data(forRow:))
            .filter(self.keepNode(_:))
    }
    
    static func parseLinks(_ anchors: DOMNodeList) -> [AnchorData] {
        return anchors.map { $0 as! DOMHTMLAnchorElement }
            .flatMap(self.data(forAnchor:))
            .filter(self.keepNode(_:))
    }
    
    static func type(for text: String, or url: String, or node: DOMHTMLAnchorElement) -> ItemType {
        for target in [text, url] {
            for (suffix, type) in self.knownSuffixesToTypes {
                if target.hasSuffix(suffix) {
                    return type
                }
            }
        }
        
        if node.isMacro {
            return .enumCase
        }
        
        return .unknown
    }
    
    /// For methods and ivars
    static func data(forRow node: DOMHTMLTableRowElement) -> AnchorData? {
        guard let cls = node.className else {
            return nil
        }
        
        // Is this a method or ivar?
        if let fragment = cls.startingAfter("memitem:") {
            guard let info = node.memberInfo else {
                return nil
            }
            
            let file = node.ownerDocument.url.ns.lastPathComponent
            return AnchorData(
                node: node,
                name: info.name,
                type: info.type,
                href: file + "#" + fragment,
                fragment: fragment,
                filename: file
            )
        }
        
        return nil
    }
    
    /// For... everything else?
    static func data(forAnchor node: DOMHTMLAnchorElement) -> AnchorData? {
        guard let url = node.absoluteLinkURL, url.isFileURL else {
            return nil
        }
        
        let parent = node.parentHTMLElement!
        
        // Skip because this node is not the first child
        guard parent.firstChild == node else {
            return nil
        }
        
        guard let name = node.displayedText ?? node.memberName, !name.isEmpty else {
            return nil
        }
        
//        let attrs = node.attributeKeys
        let relativeURL = url.startingAtLastPath
        let type = self.type(for: name, or: url.path, or: node)
        let data = AnchorData(
            node: node,
            name: name,
            type: type,
            href: relativeURL!,
            fragment: url.fragment,
            filename: node.absoluteLinkURL.lastPathComponent
        )
        return data
    }
}
