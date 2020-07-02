// MIT License
//
// Copyright (c) 2020 Ralf Ebert
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CoreData
@testable import PersistentQueue
import XCTest

extension PersistentQueue {
    func flushQueue() {
        let operation = BlockOperation {}
        self.queue.addOperation(operation)
        operation.waitUntilFinished()
    }

    func requestCount() throws -> Int {
        self.flushQueue()
        return try self.entries().count
    }
}

final class PersistentQueueTests: XCTestCase {

    let queue = PersistentQueue(name: "Tasks")

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TinyHTTPStubURLProtocol.self)
        try! self.queue.removeAll()
    }

    override func tearDown() {
        super.tearDown()
        URLProtocol.unregisterClass(TinyHTTPStubURLProtocol.self)
    }

    func testRunSingleTask() throws {
        let url = URL(string: "https://www.example.com/a")!

        let workADone = self.stubURL(url: url)

        self.queue.add(URLRequest(url: url))

        wait(for: [workADone], timeout: 1)

        try self.expectAllTasksDone()
    }

    func testRunMultipleTasks() throws {
        let urlA = URL(string: "https://www.example.com/a")!
        let urlB = URL(string: "https://www.example.com/b")!

        let workADone = self.stubURL(url: urlA)
        let workBDone = self.stubURL(url: urlB)

        self.queue.add(URLRequest(url: urlA))
        self.queue.add(URLRequest(url: urlB))

        wait(for: [workADone, workBDone], timeout: 1, enforceOrder: true)
        try self.expectAllTasksDone()
    }

    func expectAllTasksDone() throws {
        try self.waitFor(condition: { try queue.requestCount() == 0 }, timeout: 1, message: "requestCount == 0")
    }

    func stubURL(url: URL) -> XCTestExpectation {
        let resultExpectation = expectation(description: url.absoluteString)
        TinyHTTPStubURLProtocol.urls[url] = { _ in
            defer { resultExpectation.fulfill() }
            return StubbedResponse(response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data: "A".data(using: .utf8)!)
        }
        return resultExpectation
    }

    func waitFor(condition: () throws -> Bool, timeout: TimeInterval, message: String) rethrows {
        let timeoutDate = Date(timeIntervalSinceNow: timeout)
        while Date() < timeoutDate {
            if try condition() {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTFail(message)
    }

    /*
     func testCacheKeys() {
         let cache: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
         XCTAssertNil(cache["c1"])
         cache["c1"] = 1
         cache["c2"] = 2
         XCTAssertEqual(1, cache["c1"])
         XCTAssertEqual(2, cache["c2"])

         let storage2: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "AnotherCounterCache", cacheVersion: .appVersion, maxAge: .days(7))
         XCTAssertNil(storage2["c1"])
         storage2["c1"] = 3
         XCTAssertEqual(1, cache["c1"])
     }

     struct ExampleKey: Codable {
         var xid: Int
         var name: String
     }

     func testCacheKeysEncoded() throws {
         let cache: MiniCache<ExampleKey, String> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))

         cache[ExampleKey(xid: 1, name: "Alice")] = "alice-value"
         cache[ExampleKey(xid: 2, name: "Bob")] = "bob-value"
         XCTAssertEqual("alice-value", cache[ExampleKey(xid: 1, name: "Alice")])
         XCTAssertEqual("bob-value", cache[ExampleKey(xid: 2, name: "Bob")])
         XCTAssertEqual(try cache.encode(ExampleKey(xid: 1, name: "Alice")), "{\"name\":\"Alice\",\"xid\":1}")
     }

     func testExpirationAge() {
         let storage: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .hours(5))
         let date = Date()
         cacheManager.clock = { date }
         storage["Counter"] = 1
         self.cacheManager.clock = { date.addingTimeInterval(1 * 60 * 60) }
         XCTAssertEqual(1, storage["Counter"])
         self.cacheManager.clock = { date.addingTimeInterval(6 * 60 * 60) }
         XCTAssertNil(storage["Counter"])
     }

     func testExpirationVersion() {
         var storage: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
         storage["Counter"] = 1
         storage = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .custom("v2"), maxAge: .hours(5))
         XCTAssertNil(storage["Counter"])
         storage["Counter"] = 1
         XCTAssertEqual(1, storage["Counter"])
     }

     func testDeleteValue() {
         let storage: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
         storage["Counter"] = 1
         XCTAssertEqual(1, storage["Counter"])
         storage["Counter"] = nil
         XCTAssertNil(storage["Counter"])
     }

     func testCorruptValue() {
         let otherCache: MiniCache<String, String> = self.cacheManager.cache(cacheName: "SomeOtherCache", cacheVersion: .appVersion, maxAge: .days(1))
         otherCache["Example"] = "foo"

         let stringStorage: MiniCache<String, String> = self.cacheManager.cache(cacheName: "Example", cacheVersion: .appVersion, maxAge: .days(1))
         stringStorage["Example"] = "foo"
         stringStorage["Example2"] = "foo"
         let intStorage: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Example", cacheVersion: .appVersion, maxAge: .days(1))
         intStorage["Example2"] = 2
         XCTAssertNil(intStorage["Example"])
         XCTAssertEqual(intStorage["Example2"], 2)

         XCTAssertEqual(otherCache["Example"], "foo")
     }

     func testCorruptDbFile() throws {
         let cacheName = "MiniCache-Corrupt"
         let url = MiniCacheManager.cacheUrl(name: cacheName)

         try "xyz".write(to: url, atomically: true, encoding: .utf8)

         let cache = MiniCacheManager(name: cacheName)
         let stringStorage: MiniCache<String, String> = cache.cache(cacheName: "Example", cacheVersion: .appVersion, maxAge: .days(1))
         XCTAssertNil(stringStorage["foo"])
         stringStorage["foo"] = "bar"
         XCTAssertEqual(stringStorage["foo"], "bar")
     }
     */
}
