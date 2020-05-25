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
import CoreDataModelDescription
import Foundation
import os

public enum CacheMaxAge {
    case hours(_ hours: TimeInterval)
    case days(_ days: TimeInterval)
    case timeInterval(_ timeInterval: TimeInterval)

    var timeInterval: TimeInterval {
        switch self {
            case let .hours(hours):
                return hours * 60 * 60
            case let .days(days):
                return days * 60 * 60 * 24
            case let .timeInterval(timeInterval):
                return timeInterval
        }
    }
}

public class MiniCacheStorage<Key: Codable, Value: Codable> {

    let cache: String
    let cacheVersion: String
    let maxAge: CacheMaxAge
    let managedObjectContext: NSManagedObjectContext
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
    let ownerThread: Thread
    var clock = { Date() }

    fileprivate init(cache: String, cacheVersion: String, maxAge: CacheMaxAge, managedObjectContext: NSManagedObjectContext, ownerThread: Thread) {
        self.cache = cache
        self.cacheVersion = cacheVersion
        self.maxAge = maxAge
        self.managedObjectContext = managedObjectContext
        self.ownerThread = ownerThread
        self.checkThread()
    }

    public subscript(_ key: Key) -> Value? {
        get {
            self.checkThread()
            return self.object(forKey: key)
        }
        set {
            self.checkThread()
            self.setObject(newValue, forKey: key)
        }
    }

    private func object(forKey key: Key) -> Value? {
        guard let entry = fetchEntry(forKey: key) else { return nil }
        return try! self.jsonDecoder.decode(Value.self, from: entry.value!.data(using: .utf8)!)
    }

    private func setObject(_ value: Value?, forKey key: Key) {
        guard let value = value else {
            if let entry = fetchEntry(forKey: key) {
                self.managedObjectContext.delete(entry)
                try! self.managedObjectContext.save()
            }
            return
        }
        let entry = self.fetchEntry(forKey: key) ?? CacheEntry.create(in: self.managedObjectContext)
        entry.cache = self.cache
        entry.cacheVersion = self.cacheVersion
        entry.key = self.encode(key)
        entry.value = self.encode(value)
        entry.date = self.clock()
        try! self.managedObjectContext.save()
    }

    private func fetchEntry(forKey key: Key) -> CacheEntry? {
        assert(Thread.isMainThread)
        self.purgeExpiredEntries()
        let fetchRequest: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cache == %@ && key == %@", self.cache, self.encode(key))
        return try! self.managedObjectContext.fetch(fetchRequest).first
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        String(data: try! self.jsonEncoder.encode(value), encoding: .utf8)!
    }

    private func purgeExpiredEntries() {
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: CacheEntry.entityName)
        request.predicate = NSPredicate(format: "(cache == %@ && cacheVersion != %@) || %@ > date", self.cache, self.cacheVersion, self.clock().addingTimeInterval(-self.maxAge.timeInterval) as NSDate)
        try! self.managedObjectContext.execute(NSBatchDeleteRequest(fetchRequest: request))
    }

    private func checkThread() {
        assert(Thread.current == self.ownerThread, "Illegal thread usage, MiniCache ownerThread=\(self.ownerThread), actual=\(Thread.current)")
    }

}

public class MiniCache {

    public static let shared = MiniCache(name: "MiniCache", ownerThread: Thread.main)

    let log: OSLog

    let name: String
    private(set) var defaultCacheVersion: String
    private(set) var defaultMaxAge: CacheMaxAge

    public init(name: String, defaultCacheVersion: String = MiniCache.appBundleVersion, defaultMaxAge: CacheMaxAge = .days(7), ownerThread: Thread = Thread.current) {
        self.name = name
        self.defaultCacheVersion = defaultCacheVersion
        self.defaultMaxAge = defaultMaxAge
        self.ownerThread = ownerThread
        self.log = OSLog(subsystem: "MiniCache", category: self.name)
        self.checkThread()
    }

    private let ownerThread: Thread
    private let managedObjectModel = CoreDataModelDescription(
        entities: [
            .entity(
                name: "CacheEntry",
                managedObjectClass: CacheEntry.self,
                attributes: [
                    .attribute(name: "cache", type: .stringAttributeType),
                    .attribute(name: "cacheVersion", type: .stringAttributeType),
                    .attribute(name: "key", type: .stringAttributeType),
                    .attribute(name: "value", type: .stringAttributeType),
                    .attribute(name: "date", type: .dateAttributeType),
                ]
            ),
        ]
    ).makeModel()

    private lazy var persistentContainer: NSPersistentContainer = {
        /*
          The persistent container for the application. This implementation
          creates and returns a container, having loaded the store for the
          application to it. This property is optional since there are legitimate
          error conditions that could cause the creation of the store to fail.
         */
        // TODO: write in cache folder
        let container = NSPersistentContainer(name: self.name, managedObjectModel: self.managedObjectModel)
        container.loadPersistentStores(completionHandler: { store, error in
            if let url = store.url {
                os_log("Cache Location: %s", log: self.log, type: .debug, String(describing: url))
            }
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                // TODO: handle error and reset database
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    public func storage<Key: Codable, Value: Codable>(cacheName: String, cacheVersion: String = MiniCache.appBundleVersion, maxAge: CacheMaxAge? = nil) -> MiniCacheStorage<Key, Value> {
        self.checkThread()
        return MiniCacheStorage(cache: cacheName, cacheVersion: cacheVersion, maxAge: maxAge ?? self.defaultMaxAge, managedObjectContext: self.persistentContainer.viewContext, ownerThread: self.ownerThread)
    }

    public func clear() {
        self.checkThread()
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: CacheEntry.entityName)
        let managedObjectContext = self.persistentContainer.viewContext
        try! managedObjectContext.execute(NSBatchDeleteRequest(fetchRequest: request))
    }

    private func checkThread() {
        assert(Thread.current == self.ownerThread, "Illegal thread usage, MiniCache ownerThread=\(self.ownerThread), actual=\(Thread.current)")
    }

    public static var appBundleVersion: String {
        let versions = [
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
        ]
        return versions.compactMap { $0 }.joined(separator: "-")
    }

}
