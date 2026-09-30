import Foundation

struct CompanionMember: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var alias: String?

    var displayName: String { alias ?? name }
}

extension Show {
    func applyCompanionMembers(_ members: [CompanionMember], status: ShowCompanionStatus) {
        let aliases = Dictionary(companionMembers.compactMap { member in
            member.alias.map { (member.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        companionMembers = members.filter { seen.insert($0.id).inserted }.map { member in
            var updated = member
            updated.alias = aliases[member.id]
            return updated
        }
        applyCompanionState(status: status, names: companionMembers.map(\.displayName), preserveDuplicates: true)
    }

    func setCompanionAlias(_ alias: String, for memberID: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAlias = trimmed.isEmpty ? nil : trimmed
        if let index = companionMembers.firstIndex(where: { $0.id == memberID }) {
            companionMembers[index].alias = resolvedAlias
        } else if let fallbackIndex = companionMembers.isEmpty ? Int(memberID.replacingOccurrences(of: "fallback-", with: "").replacingOccurrences(of: "p-", with: "")) : nil,
                  fallbackIndex < companionNames.count {
            companionMembers = companionNames.enumerated().map { idx, name in
                CompanionMember(id: "fallback-\(idx)", name: name, alias: idx == fallbackIndex ? resolvedAlias : nil)
            }
        }
        applyCompanionState(status: companionStatus, names: companionMembers.map(\.displayName), preserveDuplicates: true)
    }
}
