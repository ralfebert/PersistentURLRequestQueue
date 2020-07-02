# PersistentQueue

A persistent queue with Codable values.

## Creating a cache manager

```swift
let cacheManager = MiniCacheManager(name: "MiniCache")
```

To define a global cache manager for your app, you could define a static `shared` property:

```swift
extension MiniCacheManager {
    static let shared = MiniCacheManager(name: "MiniCache")
}
```

## Creating a cache

To create a cache, declare a `MiniCache<Key, Value>` and initialize it using the cache manager:

```swift
let cache: MiniCache<String, Int> = self.cacheManager.cache(cacheName: "Counter", cacheVersion: .appVersion, maxAge: .days(7))
```

Any type that is conform to `Codable` can be used as Key/Value type.

## Accessing cache values

Writing:

```swift
cache["foo"] = 1
```

Reading:

```swift
let value = cache["foo"]
```

## Cache expiry by version

When creating a cache, you can specify a cache version. When the cache is accessed, all entries that don't match the cache version, are automatically cleared. This can be used to prevent data from older versions of the app being read in newer versions. Valid values:

* `.appVersion`: The app version and build number as defined in your Info.plist file is used as cache version. So whenever a cache is accessed from a new app version, the cache is cleared automatically.
* `.custom`: A custom version string that you need to change manually when you change something about the Codable types used for caching that's incompatible to old cache entries.

## Cache expiry by age

For every cache, you need to define a `maxAge` that configures how long cache entries stay valid:

* `maxAge: .days(7)`
* `maxAge: .hours(1)`
* `maxAge: .timeInterval(1000)`

## Thread safety

Only the thread that creates the MiniCacheManager is allowed to use it. When compiled with DEBUG, when this rule is violated, this is a fatalError, when compiled without DEBUG, an error will be logged.

## Error handling

* When a cache value cannot be decoded, `nil` is returned and an error is logged.
* When the cache database cannot be opened, the database file is removed to recover.
* All other (unexpected) errors will be a fatalError when compiled with DEBUG and a error log entry otherwise.

## Internal storage

Core Data is used internally to implement the persistent cache storage. This is an implementation detail, nothing of Core Data is exposed to the outside.
All data from a `MiniCacheManager` will be persisted in the app Caches directory in a file `[name].sqlite`. 