# PersistentURLRequestQueue

This package provides a serial 'persistent URLRequest queue': Send requests to the backend server, but if the app is offline or a timeout/error happens, persist the request and retry it later after a while.

## Setting up a queue

```swift
let queue = PersistentURLRequestQueue(name: "Tasks", urlSession: .shared, retryTimeInterval: 30)
```

Short version:

```swift
let queue = PersistentURLRequestQueue(name: "Tasks")
```

## Enqueuing a request

```swift
var request = URLRequest(url: URL(string: "http://www.example.com")!)
request.httpMethod = "POST"
queue.add(request)
```

This request will be immediately persisted and PersistentURLRequestQueue will try to send it until it got a HTTP Success (200) response code. If a request fails, it will be retried after `retryTimeInterval`. It's a serial queue, only one request will be processed at a time.

## Observing the queue

You can also be notified if the request finishes immediately in the current app session:

```swift
queue.add(request) { data, response in
    os_log("Request was sent.")
}
```

You can ask for the number of entries still outstanding:

```swift
let count = queue.allEntriesCount()
```

`PersistentURLRequestQueue` is a SwiftUI `ObservableObject` that sends a change notification when the number of entries changes.

## Manually starting a queue run

It's recommended to start a queue run when the app appeared or when the reachability of the device changes ([Reachability.swift](https://github.com/ashleymills/Reachability.swift) helps with that):

```swift
queue.startProcessing(ignorePauseDates: true)
```
