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

public class MiniCacheStorage<Key: Codable, Value: Codable> {

    private let cache: String
    private let cacheVersion: String
    private let maxAge: TimeInterval
    private let managedObjectContext: NSManagedObjectContext
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

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
            if let newValue = newValue {
                self.setObject(newValue, forKey: key, validUntil: Date().addingTimeInterval(self.maxAge))
            }
            // TODO: support deletion?
        }
    }

    public func setObject(_ value: Value, forKey key: Key, validUntil: Date) {
        if let entry = fetchEntry(forKey: key) {
            entry.value = self.encode(value)
        } else {
            let entry = CacheEntry.create(in: self.managedObjectContext)
            entry.cache = self.cache
            entry.cacheVersion = self.cacheVersion
            entry.key = self.encode(key)
            entry.value = self.encode(value)
            entry.date = validUntil
        }
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
        let request: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        request.predicate = NSPredicate(format: "(cache == %@ && cacheVersion != %@) || date > %@", self.cache, self.cacheVersion, Date().addingTimeInterval(self.maxAge) as NSDate)
        let results = try! self.managedObjectContext.fetch(request)
        results.forEach(self.managedObjectContext.delete)
        // TODO: self.managedObjectContext.execute(NSBatchDeleteRequest(fetchRequest: request))
    }

}

public class MiniCache {

    public init() {}

    private let modelDescription = CoreDataModelDescription(
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
    )

    private lazy var persistentContainer: NSPersistentContainer = {
        /*
          The persistent container for the application. This implementation
          creates and returns a container, having loaded the store for the
          application to it. This property is optional since there are legitimate
          error conditions that could cause the creation of the store to fail.
         */
        // TODO: write in cache folder
        let container = NSPersistentContainer(name: "MiniCache", managedObjectModel: self.modelDescription.makeModel())
        container.loadPersistentStores(completionHandler: { store, error in
            debugPrint("MiniCache location: \(String(describing: store.url))")
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
        let request: NSFetchRequest<CacheEntry> = CacheEntry.fetchRequest()
        let managedObjectContext = self.persistentContainer.viewContext
        let results = try! managedObjectContext.fetch(request)
        results.forEach(managedObjectContext.delete)
        // TODO: self.managedObjectContext.execute(NSBatchDeleteRequest(fetchRequest: request))
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
