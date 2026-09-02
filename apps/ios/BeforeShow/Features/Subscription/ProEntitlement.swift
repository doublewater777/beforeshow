import Foundation

enum ProEntitlementState: Equatable {
    case free
    case active(productID: String, expirationDate: Date?)
    case expired(productID: String, expirationDate: Date)

    var isProActive: Bool {
        if case .active = self {
            return true
        }

        return false
    }
}

enum ProEntitlementStorage {
    private struct StoredEntitlement: Codable, Equatable {
        var state: String
        var productID: String?
        var expirationDate: Date?
    }

    static let appStorageKey = "proEntitlementState"

    static func encode(_ entitlement: ProEntitlementState) -> String {
        let stored: StoredEntitlement
        switch entitlement {
        case .free:
            stored = StoredEntitlement(state: "free", productID: nil, expirationDate: nil)
        case .active(let productID, let expirationDate):
            stored = StoredEntitlement(state: "active", productID: productID, expirationDate: expirationDate)
        case .expired(let productID, let expirationDate):
            stored = StoredEntitlement(state: "expired", productID: productID, expirationDate: expirationDate)
        }

        guard let data = try? JSONEncoder().encode(stored),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string
    }

    static func decode(_ rawValue: String) -> ProEntitlementState {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredEntitlement.self, from: data) else {
            return .free
        }

        switch stored.state {
        case "active":
            guard let productID = stored.productID else { return .free }
            return .active(productID: productID, expirationDate: stored.expirationDate)
        case "expired":
            guard let productID = stored.productID,
                  let expirationDate = stored.expirationDate else {
                return .free
            }
            return .expired(productID: productID, expirationDate: expirationDate)
        default:
            return .free
        }
    }
}
