//
//  Indexer.swift
//  hexrays-docset
//
//  Created by Tanner Bennett on 6/7/21.
//

import Foundation
import WebKit

@available(macOS, deprecated: 10.14) // To effectively silence WebView warnings
class Indexer {
    enum State: Equatable {
        case idle
        case indexing
        case fixingUp
        case complete(duration: Double)
    }
    
    private let db: PDBManager
    private var page: DocumentDelegate! = nil
    private var insertedRows: [AnchorData] = []
    private var documentsFolder: String
    private var pendingFixups: IndexingIterator<[AnchorData]>? = nil
    private var currentFixup: AnchorData! = nil
    private var files: [String] = [] {
        didSet {
            self.fileIterator = self.files.makeIterator()
        }
    }
    
//    private var completion: (Indexer) -> Void
    private var callback: (String, Error?) -> Void = { _,_ in }
    
    private var fileIterator: IndexingIterator<[String]>!
    private func next() -> String? { return self.fileIterator.next() }
        
    var fileCount: Int { self.files.count }
    var complete: Bool { self.duration != nil }
    var state: State = .idle
    var duration: Double? {
        if case let .complete(duration) = self.state {
            return duration
        }
        
        return nil
    }
    
    private var startTime = 0.0
    private var endTime = 0.0
    
    init(forDocsetAt path: String) {        
        self.db = PDBManager(docsetPath: path)
        self.documentsFolder = path.appendingPathComponent("Contents/Resources/Documents")
        
        self.page = DocumentDelegate { [weak self] file, error in
            if let error = error {
                self?.callback(file ?? "", error)
                self?.step()
            } else if let self = self {
                // Callback passes nil file if the
                // active file didn't actually change
                if let file = file {
                    self.callback(file, nil)
                }
                
                self.processCurrentDocument()
                self.step()
            }
        }
    }
    
    /// Keep the current runloop alive until indexing and fix-up-ing completes
    func await(_ completion: (Indexer) -> Void) {
        while !self.complete {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
        
        completion(self)
    }
    
    /// Start indexing and continue asynchronously until complete
    func index(fileCallback: @escaping (String, Error?) -> Void) -> Indexer {
        self.callback = fileCallback
        self.startTime = NSDate().timeIntervalSince1970
        self.state = .indexing
        
        self.files = try! FileManager.default
            .contentsOfDirectory(atPath: self.documentsFolder)
            .filter { $0.hasSuffix(".shtml") }
        
        self.step()
        return self
    }
    
    /// Process the next file if available, otherwise stop
    func step() {
        guard let filename = self.next() else { return self.fixupUnknownLinks() }
        self.currentFixup = self.pendingFixups?.next()
        let path = self.documentsFolder.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: path) {
            self.page.currentURL = path
        } else {
            print("    Skipping " + filename)
            step()
        }
    }
    
    /// List of closures that indicate if a filename should be ignored
    static let ignoredFilenames: [(String) -> Bool] = [
        { s in Indexer.ignoredPrefixes.anySatisfy(s.hasPrefix(_:)) },
        { s in Indexer.ignoredSuffixes.anySatisfy(s.hasSuffix(_:)) },
    ]
    // Don't ignore these actually... we want to index their content.
    // Instead, ignore links TO these pages, in the parser.
    static let ignoredPrefixes: [String] = [/* "globals_", "functions_" */]
    static let ignoredSuffixes = ["_t-members.shtml"]
    
    /// Whether we should ignore this URL
    private func shouldSkip(_ fileURL: NSString) -> Bool {
        let filename = fileURL.lastPathComponent
        /// Ignore it if any of them said to skip it
        return Indexer.ignoredFilenames.anySatisfy { $0(filename) }
    }
    
    /// Index or fix-up the next file, which has just finished loading
    private func processCurrentDocument() {
        if !self.shouldSkip(self.page.currentURL.ns) {
            if self.state == .indexing {
                var items: [AnchorData] = []
                
                // Process all table rows
                let rows = self.page.document.getElementsByClassName("memberdecls")?
                    .flatMap { element in
                        return element.getElementsByTagName("tr")
                    }
                items += rows?.flatMap { DocumentParser.parseTableRows($0) } ?? []
                
                // Process all anchors, ignoring links to missing files
                let anchors = self.page.document.getElementsByTagName("a")!
                items += DocumentParser.parseLinks(anchors)
                    .filter { $0.fileExists(atPath: self.documentsFolder) }
                
                self.db.insert(indexes: items)
                self.insertedRows += items                
            } else {
                func updateItem(with _type: ItemType, stripNamespace strip: Bool) {
                    let fixedItem = self.currentFixup.with(type: _type)
                    self.db.update(index: fixedItem, stripNamespace: strip)
                    self.insertedRows.append(fixedItem)
                }
                
                // Does this node have a fragment?
                if let fragment = self.currentFixup.fragment {
                    // Is this a method or ivar?
                    if let node = self.page.getHTMLElement(id: fragment) {
//                        let prv = node.previousHTMLSibling?.dbd ?? ""
//                        let dbd = node.dbd
//                        let next = node.nextHTMLSibling?.dbd ?? ""
                        if let type = node.type {
                            updateItem(with: type, stripNamespace: true)
                        }
                    }
                }
                // If not, then we were linked to an entire page
                else if let type = self.page.document.pageType {
                    updateItem(with: type, stripNamespace: false)
                }
            }
        }
    }
    
    /// Fixup "unknown" entries then stop when done, or stop if we already did
    private func fixupUnknownLinks() {
        if self.state == .fixingUp {
            return self.stop()
        }
        
        self.state = .fixingUp
        self.callback("Fixing up unknown links…", nil)        
        
        // Grab the unknown items and clear inserted rows 
        let unknowns = self.insertedRows.filter(\.type.isUnknown).sorted()
        self.insertedRows = [] // Free up memory, probably
        
        // Begin fixing up the unknown indexes by loading their
        // pages to examine the surroundings of the linked item
        self.pendingFixups = unknowns.makeIterator()
        self.files = unknowns.map(\.filename)
        self.step()
    }
    
    /// Calculate the end duration and set termination flag
    private func stop() {
        self.db.removeNilTypes()
        self.endTime = NSDate().timeIntervalSince1970
        self.state = .complete(duration: self.endTime - self.startTime)
    }
}
