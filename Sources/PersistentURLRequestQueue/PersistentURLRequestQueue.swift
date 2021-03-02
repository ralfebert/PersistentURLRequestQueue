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
import CoreDataModelDescription
import Foundation
import os.log
import Reachability

public class PersistentURLRequestQueue {

    internal let name: String
    internal let urlSession: URLSession
    internal let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        queue.name = "PersistentQueue"
        return queue
    }()

    internal let log: OSLog
    internal var clock = { Date() }
    internal var subscriptions = Set<AnyCancellable>()
    internal var retryTimeInterval: TimeInterval
    internal var scheduleTimers: Bool = true
    internal var completionHandlers = [NSManagedObjectID: RequestCompletionHandler]()
    internal var persistentContainer: NSPersistentContainer

    public typealias RequestCompletionHandler = (_ data: Data, _ response: URLResponse) -> Void

    public init(name: String, urlSession: URLSession = .shared, retryTimeInterval: TimeInterval = 30, connectionStatus: AnyPublisher<Reachability.Connection, Never>) {
        self.name = name
        self.log = OSLog(subsystem: "PersistentQueue", category: name)
        self.retryTimeInterval = retryTimeInterval
        self.urlSession = urlSession

        let container = NSPersistentContainer(name: self.name, managedObjectModel: self.managedObjectModel)

        let url = Self.storageUrl(name: self.name)
        os_log("PersistentStore Location: %s", log: self.log, type: .debug, String(describing: url))

        let description = NSPersistentStoreDescription(url: url)
        container.persistentStoreDescriptions = [description]
        self.persistentContainer = container

        container.loadPersistentStores(completionHandler: { _, error in

            connectionStatus
                .sink { connection in
                    switch connection {
                        case .none, .unavailable:
                            break
                        case .wifi, .cellular:
                            os_log("%s became available: Scheduling queue run", log: self.log, type: .info, String(describing: connection))
                            self.clearPauseDates()
                            self.startProcessing()
                    }
                }
                .store(in: &self.subscriptions)

            if let error = error {
                os_log("Error with PeristentQueue storage: %@", log: self.log, type: .error, String(describing: error))
                fatalError(String(describing: error))

            }
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

    private var managedObjectContext: NSManagedObjectContext {
        self.persistentContainer.viewContext
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

    public func add(_ request: URLRequest, completion: RequestCompletionHandler? = nil) {
        assert(Thread.isMainThread)
        let operation = BlockOperation {
            guard let encodedValue = self.withErrorHandling({ try self.encode(request) }) else { return }
            let entry = QueueEntry.create(context: self.managedObjectContext)
            entry.request = encodedValue
            entry.date = self.clock()
            self.save()
            self.completionHandlers[entry.objectID] = completion
            os_log("%@ added to queue", log: self.log, type: .info, self.infoString(request: request))
            self.startProcessing()
        }
        self.queue.addOperation(operation)
        operation.waitUntilFinished()
    }

    func infoString(request: URLRequest) -> String {
        "\(request.httpMethod ?? "-") \(request.url?.absoluteString ?? "-")"
    }

    var processing = false

    func removeAll() throws {
        try self.entries().forEach(self.managedObjectContext.delete)
    }

    func updatePausedEntries() {
        self.withErrorHandling {
            let fetchRequest: NSFetchRequest<QueueEntry> = QueueEntry.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "%@ > pausedUntil", self.clock() as NSDate)
            let entries = try self.managedObjectContext.fetch(fetchRequest)
            for entry in entries {
                entry.pausedUntil = nil
            }
            self.save()
        }
    }

    func clearPauseDates() {
        self.withErrorHandling {
            let fetchRequest: NSFetchRequest<QueueEntry> = QueueEntry.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "pausedUntil != nil")
            let entries = try self.managedObjectContext.fetch(fetchRequest)
            for entry in entries {
                entry.pausedUntil = nil
            }
            self.save()
        }
    }

    func entries() throws -> [QueueEntry] {
        let fetchRequest: NSFetchRequest<QueueEntry> = QueueEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "pausedUntil == nil")
        return try self.managedObjectContext.fetch(fetchRequest)
    }

    func requestCount() throws -> Int {
        try self.entries().count
    }

    public func startProcessing() {
        self.queue.addOperation {
            if self.processing {
                os_log("Queue processing is already in progress", log: self.log, type: .info)
                return
            }
            self.withErrorHandling {
                self.updatePausedEntries()

                let items = try self.entries()
                os_log("processQueueItems: %i items to process", log: self.log, type: .info, items.count)

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
                                case let .success(data, response):
                                    if let completionHandler = self.completionHandlers.removeValue(forKey: item.objectID) {
                                        completionHandler(data, response)
                                    }
                                    self.managedObjectContext.delete(item)
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

    // Default error handling for errors that shouldn't occur normally: crash in DEBUG mode, log error otherwise
    func handleError(_ error: Error) {
        #if DEBUG
        fatalError("PersistentQueue error: \(error)")
        #else
        os_log("PersistentQueue error: %@", log: self.log, type: .error, String(describing: error))
        #endif
    }

    func withErrorHandling<T>(_ block: () throws -> T) -> T? {
        do {
            return try block()
        } catch {
            self.handleError(error)
            return nil
        }
    }

    func save() {
        self.withErrorHandling {
            try self.managedObjectContext.save()
        }
    }

}
