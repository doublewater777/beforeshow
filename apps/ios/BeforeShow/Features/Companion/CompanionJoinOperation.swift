import SwiftData

/// Both onboarding and returning-user confirmation share the durable success boundary.
@MainActor
enum CompanionJoinOperation {
    static func run(
        source: String,
        in modelContext: ModelContext,
        strategy: CompanionAcceptedImportStrategy,
        accept: (CompanionAnalyticsAttempt) async throws -> CompanionSessionSnapshot
    ) async throws -> (session: CompanionSessionSnapshot, result: CompanionAcceptedImportResult) {
        let attempt = CompanionAnalyticsAttempt(.join, source: source)
        attempt.stage = "cloud_accept"
        do {
            let session = try await attempt.withCloudDiagnostics { try await accept(attempt) }
            attempt.linkSession(session.recordName)
            attempt.stage = "local_import"
            let result = try CompanionAcceptedSessionImporter.apply(session, in: modelContext, strategy: strategy)
            attempt.finish(.succeeded)
            return (session, result)
        } catch {
            attempt.finish(.failed, error: error)
            throw error
        }
    }
}
