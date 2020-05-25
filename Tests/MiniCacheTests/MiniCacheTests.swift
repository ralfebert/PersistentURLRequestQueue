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

    let cacheManager = MiniCacheManager(name: "MiniCache")

    override func setUp() {
        self.cacheManager.clearAll()
    }

    func testCacheKeys() {
        let storage: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
        XCTAssertNil(storage["c1"])
        storage["c1"] = 1
        storage["c2"] = 2
        XCTAssertEqual(1, storage["c1"])
        XCTAssertEqual(2, storage["c2"])

        let storage2: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "AnotherCounterCache", cacheVersion: .appVersion, maxAge: .days(7))
        XCTAssertNil(storage2["c1"])
        storage2["c1"] = 3
        XCTAssertEqual(1, storage["c1"])
    }

    @available(iOS 13.0, *)
    @available(OSX 10.15, *)
    func testSingleValue() {
        var counterCachedValue: Binding<Int?> = self.cacheManager.singleValue(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
        counterCachedValue.wrappedValue = 5

        XCTAssertEqual(5, counterCachedValue.wrappedValue)

        counterCachedValue = self.cacheManager.singleValue(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
        XCTAssertEqual(5, counterCachedValue.wrappedValue)

        counterCachedValue = self.cacheManager.singleValue(cacheName: "Counter", cacheVersion: .custom("v2"), maxAge: .days(7))
        XCTAssertNil(counterCachedValue.wrappedValue)
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

}
