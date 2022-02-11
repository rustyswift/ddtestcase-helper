//
//  Example.swift
//  Console
//
//  Created by Rostyslav Kobyzskyi on 2/3/22.
//

import XCTest

class DDTestCase: XCTestCase {
    override func setUp() { }
    override func tearDown() { }
}

/// Example of random protocol which will be in the list of inheritances
protocol Sample {}

/// Example of another Test Case which is already has correct inheritance
class Other: DDTestCase {}

/// Example of random class which should not be changed
class Other1 {
    var test: String!
}

/// Example of unit test class which should be changed
class ExampleTests: XCTestCase, Sample {
    
    /// The list of properties we would like to be nullifies (must be optional with "!" mark)
    private var var1: String!
    var var2: String!
    
    /// This function must have super call after
    override func setUpWithError() throws {
        
    }
    
    /// This function must have super call after and nothing else changed
    override func setUp() {
        var random: String!
        var1 = "hello, world"
    }
    
    /// This function must not be touched
    func testVar1() {
        
    }
    
    /// The tearDown function must be introduced where var1 = nil and var2 = nil
}

