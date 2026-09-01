import CloudKit
import Foundation

enum CompanionAcceptedShareInbox {
    private static let userDefaultsKey = "companion.accepted-share-inbox.v1"

    static func metadataKey(_ metadata: CKShare.Metadata) -> String {
        let root = metadata.hierarchicalRootRecordID ?? metadata.share.recordID
        let share = metadata.share.recordID
        return "\(root.zoneID.ownerName)|\(root.zoneID.zoneName)|\(root.recordName)|\(share.recordName)"
    }

    static func load(from userDefaults: UserDefaults) -> [CKShare.Metadata] {
        guard let entries = userDefaults.array(forKey: userDefaultsKey) as? [Data] else {
            return []
        }
        return entries.compactMap { data in
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.Metadata.self, from: data)
        }
    }

    static func persist(_ metadata: [CKShare.Metadata], to userDefaults: UserDefaults) {
        var entries: [Data] = []
        for item in metadata {
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: item,
                requiringSecureCoding: true
            ) else {
                // Preserve the previous durable queue if one metadata item cannot archive.
                return
            }
            entries.append(data)
        }
        userDefaults.set(entries, forKey: userDefaultsKey)
    }

    static func append(_ metadata: CKShare.Metadata, to userDefaults: UserDefaults) {
        var current = load(from: userDefaults)
        let key = metadataKey(metadata)
        guard !current.contains(where: { metadataKey($0) == key }) else { return }
        current.append(metadata)
        persist(current, to: userDefaults)
    }
}
