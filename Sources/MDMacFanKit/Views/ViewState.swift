import SwiftUI

/// Local view state without `@State`: in recent SDKs `@State` is a macro, and the macro plugin only ships
/// with Xcode. Using `@StateObject` keeps the project buildable with the Command Line Tools alone.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
