# DDTestCase helper

## Installation

1. Clone repository
2. Build for release
```
cd /Project/Directory
swift build -c release
```
3. Copy to /usr/local/bin/
```
cp -f Console /usr/local/bin/ddtestcase-helper 
```
4. How to use
4.1 Single file
```
ddtestcase-helper /path/to/file.swift
```
4.2 All files in the folder
```
for file in Unit\ Tests/*.swift; do ddtestcase-helper "$file"; done
```


## Background

### XCTestCase Lifecycle

TLDR: Test cases are not deallocated until the end of a Test Run.
[More Info Here](https://qualitycoding.org/xctestcase-teardown/)

### Long Lived Instance Variables

> TLDR: Any instance variables allocated in `setUp()` must be deallocated in `tearDown()`.

As mentioned previously, a test case is not deallocated until the end of the test run, which means that any instance variables allocated in `setUp` will have the same lifetime as the test case. This can lead to all kinds of unexpected test failures which are difficult to diagnose. 

Consider the following class:

```
class DeliveryChangedObserver { 

    var handler: (() -> Void)?

    init() { 
        NotificationCenter.current.addObserver(
            for: .deliveryChanged, 
            target: self, 
            action: #selector(handleNotification))
    }
    
    deinit { 
        NotificationCenter.shared.removeObserver(self)
    }
    
    @objc private func handleNotification() { 
        handler?()
    }
}
```

We have an object that calls a handler when a notification is recieved. When the object is deallocated, the observer is removed and the object will no longer respond to notifications.

Now consider the following test case. This is a valid test and it will pass.

```
class DeliveryChangeObserverTests: XCTestCase { 

    var sut: DeliveryChangedObserver!
    
    override func setUp() { 
        sut = .init()
    }
    
    func test_handlerCalled() { 
        let exp = expectation(for: #function)
        sut.handler = { exp.fulfill() }
        
        NotificationCenter.shared.post(.deliveryChanged, object: nil)
        
        wait(for: [exp], timeout: 1.0)
    }
}
```

#### Why is this a problem? 

The `sut` is an instance variable that has the same lifetime as the test case which is never deallocated. If any other code posts the same notification, the `sut` will receive the notification, the expectation will be fulfilled again, and the test will be marked as a failure due to the expectation being over fulfilled. This issue may not even appear when the test is added. It may appear later when a new test case is added to the test suite that is executed after this test case. In either case it's difficult to track down and make more work for the next developer.

#### How do we fix it?

We need to override the `tearDown` method to deallocate the instance variable. This will cause the `deinit` method of the instance to be called, and the observation to be removed. Now, when other test cases or objects publish the notification, this object will not be around to receive it, and the test will not fail unexpectedly. We also have the added benefit of freeing up memory and improving the performance of the overall test suite.

```
override func tearDown() {
    super.tearDown()
    self.sut = nil
}
```

All instance variables created in `setUp` must be deallocated in `tearDown`.

#### How do we maintain this going forward?

Add a `SwiftLint` rule or build script to ensure all instance variables in the test are set to `nil` in the `tearDown` or `tearDownWithError` methods.


### Singletons and Service Resolver

The `ServiceResolver` is effectively a singleton which means it's possible for tests to share state.

#### Why is this a problem?

Existing tests sometimes rely on stale dependencies (dependencies they didn't register with the service resolver). Which means they are not running in a stable/clean environment. 

When tests are added/modified, they may change the configuration of a dependency, which may cause unrelated tests that rely on that dependency to fail.

#### How do we fix it?

Reset the service resolver in the `tearDown` method. This will cause the test case to fail immediately after attempting to access a dependency that wasn't registered in `setUp`. This ensures that the tests are running in a clean/stable environment.

#### How do we maintain this going forward?

1. All tests inherit from a subclass of `XCTestCase` that resets the service resolver in the `tearDown` and `tearDownWithError` methods.
2. Add a `SwiftLint` rule or build script to ensure:
    1. `super.tearDown()` and `super.tearDownWithError()` are in every test case.
    2. Every test case in the `Unit Tests` folder inherits from the `XCTestCase` subclass.

## Base Test Case Example

An alternative solution could be to reset the service resolver in `class func tearDown()` which is not overriden in any of our test cases. This would reset the resolver after every test case is run, rather than every test method, and would eliminate the need for a `SwiftLint` check for super in the `tearDown` instance methods.

```
import XCTest
@testable import DDCommons

class DDTestCase: XCTestCase {

    override func tearDown() {
        // Ensures the resolver is reset after every test method is run.
        ServiceResolver.shared.reset()
    }
    
    override func tearDownWithError() throws {
        // Ensures the resolver is reset after every test method is run.
        ServiceResolver.shared.reset()
    }
    
    override class func tearDown() {
        // Ensures the resolver is reset after every test case is run.
        ServiceResolver.shared.reset()
    }
}
```
