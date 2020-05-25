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

@testable import MiniCache
import SwiftUI
import XCTest

final class MiniCacheTests: XCTestCase {

    let cache = MiniCache.shared

    override func setUp() {
        self.cache.clear()
    }

    func testCacheKeys() {
        let storage: MiniCacheStorage<String, Int> = self.cache.storage(cacheName: "Counter")
        XCTAssertNil(storage["c1"])
        storage["c1"] = 1
        storage["c2"] = 2
        XCTAssertEqual(1, storage["c1"])
        XCTAssertEqual(2, storage["c2"])

        let storage2: MiniCacheStorage<String, Int> = self.cache.storage(cacheName: "AnotherCounterCache")
        XCTAssertNil(storage2["c1"])
        storage2["c1"] = 3
        XCTAssertEqual(1, storage["c1"])
    }

    @available(iOS 13.0, *)
    @available(OSX 10.15, *)
    func testSingleValue() {
        var counterCachedValue: Binding<Int?> = self.cache.singleValue(cacheName: "Counter")
        counterCachedValue.wrappedValue = 5

        XCTAssertEqual(5, counterCachedValue.wrappedValue)

        counterCachedValue = self.cache.singleValue(cacheName: "Counter")
        XCTAssertEqual(5, counterCachedValue.wrappedValue)

        counterCachedValue = self.cache.singleValue(cacheName: "Counter", cacheVersion: "v2")
        XCTAssertNil(counterCachedValue.wrappedValue)
    }

    func testExpirationAge() {
        let storage: MiniCacheStorage<String, Int> = self.cache.storage(cacheName: "Counter", maxAge: .hours(5))
        let date = Date()
        cache.clock = { date }
        storage["Counter"] = 1
        cache.clock = { date.addingTimeInterval(1 * 60 * 60) }
        XCTAssertEqual(1, storage["Counter"])
        cache.clock = { date.addingTimeInterval(6 * 60 * 60) }
        XCTAssertNil(storage["Counter"])
    }

    func testExpirationVersion() {
        var storage: MiniCacheStorage<String, Int> = self.cache.storage(cacheName: "Counter")
        storage["Counter"] = 1
        storage = self.cache.storage(cacheName: "Counter", cacheVersion: "v2", maxAge: .hours(5))
        XCTAssertNil(storage["Counter"])
        storage["Counter"] = 1
        XCTAssertEqual(1, storage["Counter"])
    }

    func testDeleteValue() {
        let storage: MiniCacheStorage<String, Int> = self.cache.storage(cacheName: "Counter")
        storage["Counter"] = 1
        XCTAssertEqual(1, storage["Counter"])
        storage["Counter"] = nil
        XCTAssertNil(storage["Counter"])
    }

}
