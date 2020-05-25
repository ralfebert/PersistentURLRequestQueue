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
import Foundation

@objc(CacheEntry)
class CacheEntry: NSManagedObject {

    static let entityName = "CacheEntry"

    static func create(context: NSManagedObjectContext) -> CacheEntry {
        NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context) as! CacheEntry
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<CacheEntry> {
        NSFetchRequest<CacheEntry>(entityName: Self.entityName)
    }

    @NSManaged var cache: String
    @NSManaged var cacheVersion: String
    @NSManaged var key: String
    @NSManaged var value: String
    @NSManaged var date: Date

}
