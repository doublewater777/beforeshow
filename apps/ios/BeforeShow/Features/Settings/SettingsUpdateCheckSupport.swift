import Foundation
import Observation
import SwiftUI
import UIKit

// MARK: - App Store Information

enum AppStoreInformation {
    static let appStoreID = "6780078298"

    static var appStoreURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }
}

// MARK: - App Update Checker

@MainActor
@Observable
final class AppUpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(remoteVersion: String)
        case updateAvailable(remoteVersion: String)
        case failed
    }

    var status: Status = .idle
    let currentVersion: String
    let appStoreID: String
    @ObservationIgnored private let fetchRemoteVersion: @Sendable () async throws -> String?

    init(
        currentVersion: String = AppVersionInformation.current.marketingVersion,
        appStoreID: String = AppStoreInformation.appStoreID,
        fetchRemoteVersion: (@Sendable () async throws -> String?)? = nil
    ) {
        self.currentVersion = currentVersion
        self.appStoreID = appStoreID
        self.fetchRemoteVersion = fetchRemoteVersion ?? { [appStoreID] in
            try await Self.lookupRemoteVersion(appStoreID: appStoreID)
        }
    }

    var hasUpdate: Bool {
        if case .updateAvailable = status {
            return true
        }
        return false
    }

    var remoteVersion: String? {
        switch status {
        case .upToDate(let version), .updateAvailable(let version):
            return version
        case .idle, .checking, .failed:
            return nil
        }
    }

    func check() async {
        guard status != .checking else { return }
        status = .checking
        do {
            guard let remote = try await fetchRemoteVersion(), !remote.isEmpty else {
                status = .failed
                return
            }
            if Self.isVersion(remote, newerThan: currentVersion) {
                status = .updateAvailable(remoteVersion: remote)
            } else {
                status = .upToDate(remoteVersion: remote)
            }
        } catch {
            status = .failed
        }
    }

    func openAppStore(openURL: ((URL) -> Void)? = nil) {
        guard let url = appStoreURL else { return }
        if let openURL {
            openURL(url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    var appStoreURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }

    static func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(remoteComponents.count, currentComponents.count)
        guard maxCount > 0 else { return false }

        for index in 0..<maxCount {
            let remotePart = index < remoteComponents.count ? remoteComponents[index] : 0
            let currentPart = index < currentComponents.count ? currentComponents[index] : 0
            if remotePart > currentPart {
                return true
            } else if remotePart < currentPart {
                return false
            }
        }
        return false
    }

    static func lookupRemoteVersion(
        appStoreID: String,
        regionCode: String? = nil,
        session: URLSession = .shared
    ) async throws -> String? {
        let region = regionCode ?? Locale.current.region?.identifier.lowercased()
        if let region, !region.isEmpty {
            if let version = try await performLookup(appStoreID: appStoreID, country: region, session: session) {
                return version
            }
        }
        return try await performLookup(appStoreID: appStoreID, country: nil, session: session)
    }

    private static func performLookup(
        appStoreID: String,
        country: String?,
        session: URLSession
    ) async throws -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var items = [URLQueryItem(name: "id", value: appStoreID)]
        if let country {
            items.append(URLQueryItem(name: "country", value: country))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        return decoded.results.first?.version
    }
}

// MARK: - App Store Lookup Response

struct AppStoreLookupResponse: Decodable, Equatable {
    struct AppResult: Decodable, Equatable {
        let version: String
        let trackViewUrl: String?
    }

    let resultCount: Int
    let results: [AppResult]
}

// MARK: - Settings Update Check Row

struct SettingsUpdateCheckRow: View {
    @State private var checker: AppUpdateChecker
    @Environment(\.openURL) private var openURL

    init(checker: AppUpdateChecker? = nil) {
        _checker = State(initialValue: checker ?? AppUpdateChecker())
    }

    var body: some View {
        Button {
            checker.openAppStore(openURL: { openURL($0) })
            if checker.status == .failed || checker.status == .idle {
                Task { await checker.check() }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BSColor.Stage.accent.opacity(0.14))
                        .frame(width: 30, height: 30)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 0.5)
                        )

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.accent)
                }

                Text(BSLocalization.text("检查更新"))
                    .font(BSFont.V3.body)
                    .foregroundStyle(BSColor.Stage.foreground)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(BSLocalization.format("当前 v%@", checker.currentVersion))
                        .font(BSFont.V3.small)
                        .foregroundStyle(BSColor.Stage.muted)

                    HStack(spacing: 4) {
                        if checker.status == .checking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.65)
                                .frame(width: 10, height: 10)
                        }

                        Text(remoteStatusText)
                            .font(BSFont.V3.small)
                            .foregroundStyle(checker.hasUpdate ? BSColor.Stage.heroWarmGold : BSColor.Stage.muted)
                    }
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(checker.hasUpdate ? BSColor.Stage.accent : BSColor.Stage.dim)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            await checker.check()
        }
    }

    private var remoteStatusText: String {
        switch checker.status {
        case .idle:
            return BSLocalization.text("未检查")
        case .checking:
            return BSLocalization.text("检查中...")
        case .upToDate(let version):
            return BSLocalization.format("最新 v%@", version)
        case .updateAvailable(let version):
            return BSLocalization.format("最新 v%@ · 可更新", version)
        case .failed:
            return BSLocalization.text("获取失败")
        }
    }
}
