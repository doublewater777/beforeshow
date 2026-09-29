import CloudKit
import Foundation

private final class CompanionShareMetadataCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CKShare.Metadata, Error>?

    init(_ continuation: CheckedContinuation<CKShare.Metadata, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func finish(_ result: Result<CKShare.Metadata, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
        return pending != nil
    }
}

extension CloudKitCompanionSharingService {
    static func fetchMetadataWithRootRecord(
        for shareURL: URL,
        in container: CKContainer = CKContainer(identifier: defaultContainerIdentifier)
    ) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let completion = CompanionShareMetadataCompletion(continuation)
            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            operation.shouldFetchRootRecord = true
            operation.qualityOfService = .userInitiated
            operation.timeoutIntervalForRequest = 10
            operation.timeoutIntervalForResource = 15
            operation.perShareMetadataResultBlock = { _, result in
                completion.finish(result.mapError { Self.mapError($0, fallback: .acceptFailed) })
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    completion.finish(.failure(CompanionSharingError.acceptFailed))
                case .failure(let error):
                    completion.finish(.failure(Self.mapError(error, fallback: .acceptFailed)))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                if completion.finish(.failure(CompanionSharingError.networkFailure)) {
                    operation.cancel()
                }
            }
            container.add(operation)
        }
    }
}
