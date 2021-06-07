//
//  Extensions.swift
//  hexrays-docset
//
//  Created by Tanner Bennett on 6/7/21.
//

import Foundation
import WebKit

extension PDBManager {
    func insert(indexes: [AnchorData]) {
        for i in indexes {
            self.executeStatement(kInsertIndexStatement, arguments: i.dictionaryValue)
        }
    }
    
    func update(index: AnchorData, stripNamespace: Bool = false) {
        var index = index
        if stripNamespace, let name = index.name.startingAfter("::") {
            index.name = name
            // TODO: delete old row?
        }
        
        self.executeStatement(kUpdateIndexStatement, arguments: index.dictionaryValue)
    }
    
    func removeNilTypes() {
        self.executeStatement("DELETE FROM searchIndex WHERE type = 'NIL'")
    }
}

extension String {
    var ns: NSString { self as NSString }
    
    func appendingPathComponent(_ component: String) -> String {
        return self.ns.appendingPathComponent(component)
    }
    
    func startingAt(_ substring: String) -> String? {
        guard let range = self.range(of: substring) else { return nil }
        let trim: Range<String.Index> = Range(
            uncheckedBounds: (range.lowerBound, self.endIndex)
        )
        
        return String(self[trim])
    }
    
    func startingAfter(_ substring: String) -> String? {
        guard let range = self.range(of: substring) else { return nil }
        let trim: Range<String.Index> = Range(
            uncheckedBounds: (range.upperBound, self.endIndex)
        )
        
        return String(self[trim])
    }
    
    func upTo(_ substring: String) -> String? {
        guard let range = self.range(of: substring) else { return nil }
        let trim: Range<String.Index> = Range(
            uncheckedBounds: (self.startIndex, range.lowerBound)
        )
        
        return String(self[trim])
    }
    
    var startingAtLastPath: String! {
        let lpc = self.ns.lastPathComponent
        return self.startingAt(lpc)!
    }
}

extension URL {
    var startingAtLastPath: String! {
        let string = self.absoluteString
        let lpc = self.lastPathComponent
        return string.startingAt(lpc)!
    }
}

extension Collection {
    func anySatisfy(_ predicate: (Self.Element) throws -> Bool) rethrows -> Bool {
        for e in self {
            if try predicate(e) {
                return true
            }
        }
        
        return false
    }
}

extension Collection where Element: Hashable {
    /// The element that appears most in the set
    var modeElement: Element? {
        var counts: [Element: Int] = [:]
        for e in self {
            counts[e] = (counts[e] ?? 0) + 1
        }
        
        var max: (e: Element?, c: Int) = (nil, 0)
        for (e, c) in counts {
            if c > max.c {
                max = (e, c)
            }
        }
        
        return max.e
    }
}

@available(macOS, deprecated: 10.14)
public struct DOMNodeListIterator<T: DOMNode>: IteratorProtocol {
    public typealias Element = T
    
    private let list: DOMNodeList
    private var position: UInt32 = 0
    
    init(list: DOMNodeList) {
        self.list = list
    }
    
    public mutating func next() -> T? {
        defer { self.position += 1 }
        return self.list.item(self.position) as? T
    }
}

@available(macOS, deprecated: 10.14)
extension DOMNodeList: Sequence {
    public typealias Element = DOMHTMLElement
    public typealias Iterator = DOMNodeListIterator
    
    /// I only care about anchors, so...
    public func makeIterator() -> DOMNodeListIterator<Element> {
        return DOMNodeListIterator(list: self)
    }
    
    public var underestimatedCount: Int { Int(self.length) }
    
    public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<Element>) throws -> R) rethrows -> R? {
        return nil
    }
    
    var first: Element? {
        return self.item(0) as? Element
    }
    
    subscript(idx: UInt32) -> Element! {
        get {
            return self.item(idx) as? Element
        }
    }
}

@available(macOS, deprecated: 10.14)
extension DOMNamedNodeMap {
    var string: String {
        return (0..<self.length)
            .map { self.item($0) as! DOMAttr }
            .map { $0.name + "='" + $0.value + "'" }
            .joined(separator: " ")
    }
}

@available(macOS, deprecated: 10.14)
extension DOMHTMLElement {
    var parentHTMLElement: DOMHTMLElement! {
        return self.parentElement as? DOMHTMLElement
    }
    var firstHTMLChild: DOMHTMLElement! {
        return self.firstElementChild as? DOMHTMLElement
    }
    
    var nextHTMLSibling: DOMHTMLElement! {
        return self.nextElementSibling as? DOMHTMLElement
    }
    var previousHTMLSibling: DOMHTMLElement! {
        return self.previousElementSibling as? DOMHTMLElement
    }
    
    var nonEmptyText: String? {
        if let t = self.textContent, !t.isEmpty {
            return t
        }
        
        return nil
    }
    
    var displayedText: String? {
        return self.nonEmptyText ?? self.title
    }
    
    var title: String? {
        return self.attributes.getNamedItem("title")?.textContent
    }
    
    var dbd: String {
        let tag = self.tagName!.lowercased()
        return "<\(tag) \(self.attributes.string)>\(self.innerHTML ?? "")</\(tag)>"
    }

    var isMacro: Bool {
        // All macros are uppercase
        guard self.textContent.uppercased() == self.textContent else {
            return false
        }
        
        let text = self.parentHTMLElement.previousSibling?.textContent ?? ""
        return text.contains("#define") // Defines end with a non-breaking space, ew
    }
    
    /// For the links handled in `var type` below
    var memberName: String? {
        assert(self.displayedText == nil)
        //               a    td                 td               b <-- holds name
        if let nameTag = self.parentHTMLElement?.nextHTMLSibling?.firstHTMLChild {
            if nameTag.tagName == "B", let name = nameTag.displayedText {
                return name
            }
        }
        
        return nil
    }
    
    var type: ItemType? {
        // At this point, we expect to have something like this:
        // ```
        // <tbody>
        //     <tr class="heading">
        //         …
        //             <h2 class="groupheader">
        //                 <a name="TYPE"></a>
        //             </h2>
        //         …
        //     </tr>
        //     …
        //     <tr class="memitem:FRAGMENT">
        //         <td …>
        //   THIS -->  <a id="FRAGMENT"></a>
        //             <a class="el" href="ret_type_page.shtml">RETURN_TYPE</a>
        //         </td>
        //         <td …>
        //             <b>THE_METHOD</a>
        //             " ( "
        //             <a class="el" href="arg_type_page.shtml">ARG_1</a>
        //             " ) "
        //         </td>
        // ```
        //                  a    td      tr      tbody   tr.heading
        guard let heading = self.parent?.parent?.parent?.firstChild as? DOMHTMLElement,
              heading.className == "heading" else {
            return nil
        }
        
        guard let group = heading.getElementsByClassName("groupheader")?.first else {
            return nil
        }
        
        guard let groupType = group.firstElementChild.getAttribute("name") else {
            return nil
        }
        
        switch groupType {
            case "pub-methods": return .method
            case "pub-attribs": return .ivar
            default: return nil
        }
    }
}

@available(macOS, deprecated: 10.14)
extension DOMHTMLTableRowElement {
    var memberInfo: (type: ItemType, name: String)? {
        // At this point, we expect to have something like this:
        // ```
        // <tbody>
        //     <tr class="heading">
        //         …
        //             <h2 class="groupheader">
        //                 <a name="TYPE"></a>
        //             </h2>
        //         …
        //     </tr>
        //     …
        //     <tr class="memitem:FRAGMENT">   <-- THIS
        //         <td …>
        //             <a id="FRAGMENT"></a>
        //             <a class="el" href="ret_type_page.shtml">RETURN_TYPE</a>
        //         </td>
        //         <td …>
        //             <b>THE_METHOD</a>
        //             " ( "
        //             <a class="el" href="arg_type_page.shtml">ARG_1</a>
        //             " ) "
        //         </td>
        // ```
        //                  tr   tbody   tr.heading
        guard let heading = self.parent?.firstChild as? DOMHTMLElement,
              heading.className == "heading" else {
            return nil
        }
        
        guard let group = heading.getElementsByClassName("groupheader")?.first else {
            return nil
        }
        
        guard let groupType = group.firstElementChild.getAttribute("name") else {
            return nil
        }
        
        guard let type: ItemType = {
            switch groupType {
                case "pub-methods": fallthrough
                case "pub-static-methods": fallthrough
                case "pro-methods": fallthrough
                case "pro-static-methods":
                    return .method
                case "pub-attribs": fallthrough
                case "pub-static-attribs": fallthrough
                case "pro-attribs": fallthrough
                case "pro-static-attribs":
                    return .ivar
                case "define-members": return .enumCase
                case "friends": return .unknown // Don't care
                case "inherited": return .unknown // Don't care
                case "nested-classes": return .type
                case "typedef-members": return .type
                case "var-members": return .constant
                case "enum-members": return .enum
                case "func-members": return .function
                case "pub-types": return .unknown // Don't care, usually just associated types
                case "files": return .unknown // Don't careeeeeee
                default: return nil
            }
        }() else {
            return nil
        }
        
        //                  td   tbody         b / a <-- holds name
        guard let nameTag = self.childNodes[1]?.firstHTMLChild else {
            // Tags like this appear for "struct {" on pages like classvalrng__t.shtml
            return nil
        }
        guard /* nameTag.tagName == "B", */ let name = nameTag.displayedText else {
            return nil
        }
        
        return (type, name)
    }
}

@available(macOS, deprecated: 10.14)
extension DOMDocument {
    var pageType: ItemType? {
        if let title = self.getElementsByClassName("title")?.first, let text = title.displayedText {
            if text.contains("Struct Reference") || text.contains("Class Reference") {
                return .type
            }
            if text.lowercased().contains("bits for ") || text.hasSuffix(" flags") || text.hasSuffix(" bits") {
                return .enum
            }
        }
        
        return nil
    }
}
