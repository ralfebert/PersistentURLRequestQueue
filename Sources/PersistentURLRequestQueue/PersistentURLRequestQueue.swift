// MIT License
//
// Copyright (c) 2024 Ralf Ebert
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
import CoreDataModelDescription
import Foundation
import os.log
import SwiftUI

public class PersistentURLRequestQueue: ObservableObject {

    let name: String
    let urlSession: URLSession
    let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        queue.name = "PersistentQueue"
        queue.isSuspended = true
        return queue
    }()

    let log: OSLog
    var clock = { Date() }
    var retryTimeInterval: TimeInterval
    var scheduleTimers: Bool = true
    var errorHandler: ErrorHandler
    var completionHandlers = [NSManagedObjectID: RequestCompletionHandler]()
    var persistentContainer: NSPersistentContainer
    var managedObjectContext: NSManagedObjectContext?

    public typealias RequestCompletionHandler = (_ data: Data, _ response: URLResponse) -> Void
    public typealias ErrorHandler = (_ error: Error) -> Void

    public init(name: String, urlSession: URLSession = .shared, retryTimeInterval: TimeInterval = 30, errorHandler: ErrorHandler? = nil) {
        self.name = name
        let log = OSLog(subsystem: "PersistentQueue", category: name)
        self.log = log
        self.retryTimeInterval = retryTimeInterval
        self.urlSession = urlSession
        self.errorHandler = errorHandler ?? { error in
            // Default error handling for errors that shouldn't occur normally: crash in DEBUG mode, log error otherwise
            #if DEBUG
            fatalError("PersistentQueue error: \(error)")
            #else
            os_log("PersistentQueue error: %@", log: log, type: .error, String(describing: error))
            #endif
        }

        let container = NSPersistentContainer(name: self.name, managedObjectModel: self.managedObjectModel)

        let url = Self.storageUrl(name: self.name)
        os_log("PersistentStore Location: %s", log: self.log, type: .debug, String(describing: url))

        let description = NSPersistentStoreDescription(url: url)
        container.persistentStoreDescriptions = [description]
        self.persistentContainer = container

        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error {
                self.errorHandler(error)
            } else {
                self.managedObjectContext = container.newBackgroundContext()
            }
            self.queue.isSuspended = false
        })

    }

    private let managedObjectModel = CoreDataModelDescription(
        entities: [
            .entity(
                name: "QueueEntry",
                managedObjectClass: QueueEntry.self,
                attributes: [
                    .attribute(name: "request", type: .stringAttributeType),
                    .attribute(name: "date", type: .dateAttributeType),
                    .attribute(name: "pausedUntil", type: .dateAttributeType, isOptional: true),
                ]
            ),
        ]
    ).makeModel()

    static func storageUrl(name: String) -> URL {
        let storeDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return storeDirectory.appendingPathComponent("\(name).sqlite")
    }

    func encode(_ urlRequest: URLRequest) throws -> String {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.outputFormat = .xml
        archiver.encodeRootObject(urlRequest)
        archiver.finishEncoding()
        let data = archiver.encodedData
        return String(data: data, encoding: .utf8)!
    }

    func decode(_ string: String) throws -> URLRequest {
        let data = string.data(using: .utf8)!
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let result = try unarchiver.decodeTopLevelObject() as! URLRequest
        unarchiver.finishDecoding()
        return result
    }

    public func add(_ request: URLRequest, waitUntilPersisted: Bool = true, completion: RequestCompletionHandler? = nil) {
        let operation = BlockOperation {
            guard let managedObjectContext = self.managedObjectContext else {
                os_log("managedObjectContext not present", log: self.log, type: .error)
                return
            }
            guard let encodedValue = self.withErrorHandling({ try self.encode(request) }) else { return }
            let entry = QueueEntry.create(context: managedObjectContext)
            entry.request = encodedValue
            entry.date = self.clock()
            self.save()
            self.completionHandlers[entry.objectID] = completion
            os_log("%@ added to queue", log: self.log, type: .info, self.infoString(request: request))
            self.startProcessing()
        }
        self.queue.addOperation(operation)
        if waitUntilPersisted {
            operation.waitUntilFinished()
        }
    }

    func infoString(request: URLRequest) -> String {
        "\(request.httpMethod ?? "-") \(request.url?.absoluteString ?? "-")"
    }

    public private(set) var processing = false {
        didSet {
            self.sendChangeNotification()
        }
    }

    func sendChangeNotification() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func removeAll() throws {
        self.queue.addOperation {
            guard let managedObjectContext = self.managedObjectContext else {
                os_log("managedObjectContext not present", log: self.log, type: .error)
                return
            }
            self.withErrorHandling {
                try self.entriesOnQueue().forEach(managedObjectContext.delete)
            }
        }
    }

    private func clearPauseDates(after date: Date? = nil) {
        guard let managedObjectContext = self.managedObjectContext else {
            os_log("managedObjectContext not present", log: self.log, type: .error)
            return
        }

        self.withErrorHandling {
            let fetchRequest: NSFetchRequest<QueueEntry> = QueueEntry.fetchRequest()
            if let date = date {
                fetchRequest.predicate = NSPredicate(format: "%@ > pausedUntil", date as NSDate)
            } else {
                fetchRequest.predicate = NSPredicate(format: "pausedUntil != nil")
            }
            let entries = try managedObjectContext.fetch(fetchRequest)
            for entry in entries {
                entry.pausedUntil = nil
            }
            self.save()
        }
    }

    private func entriesOnQueue() throws -> [QueueEntry] {
        guard let managedObjectContext = self.managedObjectContext else {
            os_log("managedObjectContext not present", log: self.log, type: .error)
            return []
        }

        let fetchRequest: NSFetchRequest<QueueEntry> = QueueEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "pausedUntil == nil")
        return try managedObjectContext.fetch(fetchRequest)
    }

    func entries() throws -> [QueueEntry] {
        var entries: [QueueEntry] = []

        self.queue.addOperations([BlockOperation {
            self.withErrorHandling {
                entries = try self.entriesOnQueue()
            }
        }], waitUntilFinished: true)

        return entries
    }

    private func allEntriesCountOnQueue() throws -> Int {
        guard let managedObjectContext = self.managedObjectContext else {
            os_log("managedObjectContext not present", log: self.log, type: .error)
            return 0
        }

        let fetchRequest: NSFetchRequest<QueueEntry> = QueueEntry.fetchRequest()
        return try managedObjectContext.count(for: fetchRequest)
    }

    public func allEntriesCount() throws -> Int {
        var allEntriesCount = 0

        self.queue.addOperations([BlockOperation {
            self.withErrorHandling {
                allEntriesCount = try self.allEntriesCountOnQueue()
            }
        }], waitUntilFinished: true)

        return allEntriesCount
    }

    /**
     Starts to process the items in the queue.
     If ignorePauseDates is set to true, paused entries are immediately tried again.
     */
    public func startProcessing(ignorePauseDates: Bool = false) {
        self.queue.addOperation {
            guard let managedObjectContext = self.managedObjectContext else {
                os_log("managedObjectContext not present", log: self.log, type: .error)
                return
            }

            if self.processing {
                os_log("Queue processing is already in progress", log: self.log, type: .info)
                return
            }
            self.withErrorHandling {
                self.clearPauseDates(after: ignorePauseDates ? nil : self.clock())

                let items = try self.entriesOnQueue()
                try os_log("processQueueItems: %i/%i ready to process", log: self.log, type: .info, items.count, self.allEntriesCountOnQueue())

                if let item = items.first {
                    let request = try self.decode(item.request)
                    os_log("Processing %s", log: self.log, type: .info, self.infoString(request: request))

                    let endpoint = self.urlSession.dataTaskPublisher(for: request)
                        .tryMap { data, response -> (Data, URLResponse) in
                            if let response = response as? HTTPURLResponse {
                                if response.statusCode != 200 {
                                    throw HTTPError(statusCode: response.statusCode)
                                }
                            }
                            return (data, response)
                        }
                        .eraseToAnyPublisher()

                    self.processing = true
                    endpoint.load { result in
                        os_log("Processed %s: %s", log: self.log, type: .info, self.infoString(request: request), String(describing: result))

                        self.queue.addOperation {
                            switch result {
                                case let .success((data, response)):
                                    if let completionHandler = self.completionHandlers.removeValue(forKey: item.objectID) {
                                        completionHandler(data, response)
                                    }
                                    managedObjectContext.delete(item)
                                    // if one entry was successfully submitted, immediately send the next ones even if paused
                                    self.clearPauseDates(after: nil)
                                case .failure:
                                    item.pausedUntil = self.clock().addingTimeInterval(self.retryTimeInterval)
                                    self.scheduleTimer()
                            }
                            self.save()
                            self.processing = false
                            self.startProcessing()
                        }
                    }
                }
            }
        }
    }

    func scheduleTimer() {
        guard self.scheduleTimers else { return }
        Timer.scheduledTimer(withTimeInterval: self.retryTimeInterval + 1, repeats: false) { _ in
            self.startProcessing()
        }
    }

    func withErrorHandling<T>(_ block: () throws -> T) -> T? {
        do {
            return try block()
        } catch {
            self.errorHandler(error)
            return nil
        }
    }

    private func save() {
        guard let managedObjectContext = self.managedObjectContext else {
            os_log("managedObjectContext not present", log: self.log, type: .error)
            return
        }

        self.withErrorHandling {
            try managedObjectContext.save()
        }
        self.sendChangeNotification()
    }

}
