#if canImport(SwiftUI)
import SwiftUI

@propertyWrapper
@available(OSX 10.15, *)
@available(iOS 13.0, *)
public struct CacheValue<Value : Codable> {

    private let binding : Binding<Value?>
    
    public init(cache: MiniCache, key: String, maxAge: TimeInterval) {
        self.binding = cache.singleValue(cache: key, maxAge: maxAge)
    }

    public var wrappedValue : Value? {
        get {
            return binding.wrappedValue
        }
        set {
            binding.wrappedValue = newValue
        }
    }
}
#endif
