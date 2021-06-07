//
//  main.swift
//  hexrays-docset
//
//  Created by Tanner Bennett on 6/7/21.
//

import Foundation
import ArgumentParser

struct hrdocset: ParsableCommand {
    @Argument(help: ArgumentHelp("The path to a .docset folder."), completion: .directory)
    var docsetPath: String
    
    @available(macOS, deprecated: 10.14)
    mutating func run() throws {
        print("Starting index...")
        let indexer = Indexer(forDocsetAt: self.docsetPath)
        
        indexer
            .index { file, error in
                if let error = error {
                    print("Error indexing \(file): \(error.localizedDescription)")
                } else {
                    print(file)
                }
            }
            .await { i in
                print("Done: indexed \(i.fileCount) file(s) in \(Int(i.duration!))s")                
            }
    }
}

hrdocset.main()
