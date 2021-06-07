//
//  DocumentDelegate.swift
//  hexrays-docset
//
//  Created by Tanner Bennett on 6/8/21.
//

import Foundation
import WebKit

@available(macOS, deprecated: 10.14)
class DocumentDelegate: NSObject, WebFrameLoadDelegate {
    private let webview = WebView()
    
    var callback: (String?, Error?) -> Void
    var currentURL: String {
        get { self.webview.mainFrameURL }
        set {
            // Is this the same URL we already have open?
            if let file = self.document?.url?.ns.lastPathComponent, file == newValue.ns.lastPathComponent {
                // If so, trigger another step since we're already ready
                self.callback(nil, nil)
            }
            // If not, actually load a new document
            else {
                self.webview.mainFrameURL = newValue
            }
        }
    }
    
    var document: DOMDocument! { self.webview.mainFrameDocument }
    
    init(callback: @escaping (String?, Error?) -> Void) {
        self.callback = callback
        
        super.init()
        self.webview.frameLoadDelegate = self
    }
    
    func getHTMLElement(id: String) -> DOMHTMLElement? {
        return self.document.getElementById(id) as? DOMHTMLElement
    }
    
    // MARK: Delegate methods
    
    func webView(_ sender: WebView!, didFailProvisionalLoadWithError error: Error!, for frame: WebFrame!) {
        self.callback(frame.domDocument.url.ns.lastPathComponent, error)
    }
    
    func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        if frame == self.webview.mainFrame {
            self.callback(frame.domDocument.url.ns.lastPathComponent, nil)
        } else {
            fatalError()
        }
    }
}
