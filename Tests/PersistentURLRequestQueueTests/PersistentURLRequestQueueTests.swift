// MIT License
//
// Copyright (c) 2021 Ralf Ebert
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

import Combine
import CoreData
@testable import PersistentURLRequestQueue
import XCTest

extension PersistentURLRequestQueue {

    func flush() {
        while self.processing {
            let operation = BlockOperation {}
            self.queue.addOperation(operation)
            operation.waitUntilFinished()
            Thread.sleep(forTimeInterval: 0.1)
        }
        let operation = BlockOperation {}
        self.queue.addOperation(operation)
        operation.waitUntilFinished()
    }

}

class SharedQueue {

    static var shared = SharedQueue()
    var queue: PersistentURLRequestQueue

    private init() {
        self.queue = PersistentURLRequestQueue(name: "Tasks")
        self.queue.scheduleTimers = false
    }

}

final class PersistentURLRequestQueueTests: XCTestCase {

    let queue = SharedQueue.shared.queue

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(TinyHTTPStubURLProtocol.self)
        try! self.queue.removeAll()
    }

    override func tearDown() {
        super.tearDown()
        self.queue.flush()
        URLProtocol.unregisterClass(TinyHTTPStubURLProtocol.self)
    }

    func testRunSingleTask() throws {
        let url = URL(string: "https://www.example.com/a")!

        let workADone = self.stubURL(url: url, result: "A")

        self.queue.add(URLRequest(url: url))

        wait(for: [workADone], timeout: 1)

        try self.expectAllTasksDone()
    }

    func testRunMultipleTasks() throws {
        let urlA = URL(string: "https://www.example.com/a")!
        let urlB = URL(string: "https://www.example.com/b")!

        let workADone = self.stubURL(url: urlA, result: "A")
        let workBDone = self.stubURL(url: urlB, result: "B")

        self.queue.add(URLRequest(url: urlA))
        self.queue.add(URLRequest(url: urlB))

        wait(for: [workADone, workBDone], timeout: 1, enforceOrder: true)
        try self.expectAllTasksDone()
    }

    func testRerunFailedTask() throws {
        let date = Date()
        queue.clock = { date }
        let url = URL(string: "https://www.example.com/a")!

        var workADone = self.stubURL(url: url, status: 500)

        self.queue.add(URLRequest(url: url))

        wait(for: [workADone], timeout: 1)

        self.queue.flush()

        self.stubURLWithFailure(url: url, message: "task should not be re-run before time interval")
        self.queue.startProcessing()
        self.queue.flush()

        self.queue.clock = { date.addingTimeInterval(self.queue.retryTimeInterval + 5) }

        self.queue.startProcessing()

        workADone = self.stubURL(url: url, result: "A")

        wait(for: [workADone], timeout: 1)
        try self.expectAllTasksDone()
    }

    func expectAllTasksDone() throws {
        try self.waitFor(condition: { try queue.allEntriesCount() == 0 }, timeout: 1, message: "requestCount == 0")
    }

    func stubURL(url: URL, result: String) -> XCTestExpectation {
        let resultExpectation = expectation(description: url.absoluteString)
        TinyHTTPStubURLProtocol.urls[url] = { _ in
            defer { resultExpectation.fulfill() }
            return StubbedResponse(response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, data: result.data(using: .utf8)!)
        }
        return resultExpectation
    }

    func stubURLWithFailure(url: URL, message: String) {
        TinyHTTPStubURLProtocol.urls[url] = { _ in
            XCTFail(message)
            return StubbedResponse(response: HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, data: "error".data(using: .utf8)!)
        }
    }

    func stubURL(url: URL, status: Int) -> XCTestExpectation {
        let resultExpectation = expectation(description: url.absoluteString)
        TinyHTTPStubURLProtocol.urls[url] = { _ in
            defer { resultExpectation.fulfill() }
            return StubbedResponse(response: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, data: "error".data(using: .utf8)!)
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

}
