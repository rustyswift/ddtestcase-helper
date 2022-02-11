//
//  main.swift
//  DDTestcaseHelper
//
//  Created by Rostyslav Kobyzskyi on 2/3/22.
//

import Foundation
import Core
import SwiftSyntax

func rewrite() {
    guard let filepath = CommandLine.arguments.dropFirst().first else {
        print("incorrect input: 0")
        return
    }
    
    let url = URL(fileURLWithPath: filepath)
    guard url.isFileURL && url.pathExtension == "swift" else {
        print("incorrect input: 1")
        return
    }
    do {
        var rewritten = ""
        try DDTestCaseRewriter().visit(url).write(to: &rewritten)
        try rewritten.data(using: .utf8)?.write(to: url)
        print("Success!")
    } catch {
        print("Failure: \(error)")
    }
}

rewrite()
