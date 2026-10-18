import Observation

/// Main-actor state changes on every supported OS, without polling.
struct BSObservationValues<Value: Sendable>: AsyncSequence {
    typealias AsyncIterator = AsyncStream<Value>.Iterator
    private let stream: AsyncStream<Value>

    @MainActor
    init(_ read: @escaping @MainActor () -> Value) {
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = Observer(read: read, continuation: continuation)
            continuation.onTermination = { [observer] _ in
                Task { @MainActor in observer.stop() }
            }
            observer.observe()
        }
    }

    func makeAsyncIterator() -> AsyncIterator { stream.makeAsyncIterator() }

    @MainActor
    private final class Observer {
        private var read: (@MainActor () -> Value)?
        private let continuation: AsyncStream<Value>.Continuation

        init(read: @escaping @MainActor () -> Value, continuation: AsyncStream<Value>.Continuation) {
            self.read = read
            self.continuation = continuation
        }

        func stop() { read = nil }

        func observe() {
            guard let read else { return }
            let value = withObservationTracking(read) { [weak self] in
                // Observation fires before mutation; read and rearm on the next turn.
                Task { @MainActor in self?.observe() }
            }
            continuation.yield(value)
        }
    }
}
