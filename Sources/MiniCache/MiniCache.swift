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

public class MiniCacheStorage<Key: Codable, Value: Codable> {

    let cache: String
    let cacheVersion: String
    let maxAge: TimeInterval
    let managedObjectContext: NSManagedObjectContext
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
    var clock = { Date() }

    fileprivate init(cache: String, cacheVersion: String, maxAge: TimeInterval, managedObjectContext: NSManagedObjectContext) {
        self.cache = cache
        self.cacheVersion = cacheVersion
        self.maxAge = maxAge
        self.managedObjectContext = managedObjectContext
    }

    public subscript(_ key: Key) -> Value? {
        get {
            guard let entry = fetchEntry(forKey: key) else { return nil }
            return try! self.jsonDecoder.decode(Value.self, from: entry.value!.data(using: .utf8)!)
        }
        set {
            self.setObject(newValue, forKey: key, validUntil: self.clock().addingTimeInterval(self.maxAge))
        }
    }

    private func setObject(_ value: Value?, forKey key: Key, validUntil: Date) {
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
        request.predicate = NSPredicate(format: "(cache == %@ && cacheVersion != %@) || %@ > date", self.cache, self.cacheVersion, self.clock().addingTimeInterval(-self.maxAge) as NSDate)
        try! self.managedObjectContext.execute(NSBatchDeleteRequest(fetchRequest: request))
    }

}

public class MiniCache {

    public static let log = OSLog(subsystem: "MiniCache", category: "MiniCache")

    public init() {}

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
        let container = NSPersistentContainer(name: "MiniCache", managedObjectModel: self.managedObjectModel)
        container.loadPersistentStores(completionHandler: { store, error in
            if let url = store.url {
                os_log("Cache Location: %s", log: Self.log, type: .debug, String(describing: url))
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

    public func storage<Key: Codable, Value: Codable>(cache: String, cacheVersion: String = MiniCache.defaultCacheVersion, maxAge: TimeInterval = MiniCache.defaultMaxAge) -> MiniCacheStorage<Key, Value> {
        MiniCacheStorage(cache: cache, cacheVersion: cacheVersion, maxAge: maxAge, managedObjectContext: self.persistentContainer.viewContext)
    }

    public func clear() {
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: CacheEntry.entityName)
        let managedObjectContext = self.persistentContainer.viewContext
        try! managedObjectContext.execute(NSBatchDeleteRequest(fetchRequest: request))
    }

    public static var defaultCacheVersion: String {
        let versions = [
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
        ]
        return versions.compactMap { $0 }.joined(separator: "-")
    }

    public static var defaultMaxAge: TimeInterval {
        TimeInterval(7 * 24 * 60 * 60)
    }

}
