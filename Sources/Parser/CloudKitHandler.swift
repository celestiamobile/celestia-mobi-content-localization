import Foundation
import OpenCloudKit

enum CloudKitHandlerError: Error {
    case cloudKit(error: Error)
    case removalNotAllowed
    case internalError
    case json
    case englishResourceMissing
}

extension CloudKitHandlerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cloudKit(let error):
            return "CloudKit error: \(error.localizedDescription)"
        case .removalNotAllowed:
            return "Removal is not allowed"
        case .internalError:
            return "Internal error"
        case .json:
            return "JSON error"
        case .englishResourceMissing:
            return "English resource missing"
        }
    }
}

public class CloudKitHandler {
    public init() {}

    public static func configure(_ config: CKContainerConfig) {
        CloudKit.shared.configure(with: CKConfig(containers: [config]))
    }

    public func uploadChanges(addedStrings: [String: [String: String]], removedStrings: [String: [String: String]], changedStrings: [String: [String: String]], mainKey: String, englishKey: String?) async throws {
        guard removedStrings.isEmpty else {
            throw CloudKitHandlerError.removalNotAllowed
        }

        let db = CKContainer.default().publicCloudDatabase
        print("Fetch original records...")
        var allChanges = [String: [String: String]]()
        for (key, added) in addedStrings {
            allChanges[key] = added
        }
        for (key, changed) in changedStrings {
            allChanges[key] = changed
        }
        let desiredKeys = [mainKey, englishKey].compactMap { $0 }
        var records = [String: CKRecord]()
        do {
            var recordResults = try await db.records(for: allChanges.keys.map({ CKRecord.ID(recordName: $0) }), desiredKeys: desiredKeys)
            for (_, recordResult) in recordResults {
                switch recordResult {
                case .success(let record):
                    records[record.recordID.recordName] = record
                case .failure(let error):
                    throw error
                }
            }
        } catch {
            throw CloudKitHandlerError.cloudKit(error: error)
        }

        print("Merging record changes...")
        var recordsToSave = [CKRecord]()
        for (key, strings) in allChanges {
            guard let record = records[key] else {
                print("Record missing for \(key)")
                throw CloudKitHandlerError.internalError
            }

            var stringsToSave = strings
            if let englishKey {
                // Remove en from the strings
                record[englishKey] = strings["en"]
                stringsToSave["en"] = nil
            }

            do {
                let stringData = try JSONEncoder().encode(stringsToSave)
                record[mainKey] = String(data: stringData, encoding: .utf8)!
            } catch {
                throw CloudKitHandlerError.json
            }
            recordsToSave.append(record)
        }

        print("Uploading record changes...")
        do {
            let saveResults = try await db.modifyRecords(saving: recordsToSave, deleting: [], savePolicy: .changedKeys).saveResults

            for (_, recordResult) in saveResults {
                switch recordResult {
                case .success:
                    break
                case .failure(let error):
                    throw error
                }
            }
        } catch {
            throw CloudKitHandlerError.cloudKit(error: error)
        }
    }

    public func fetchStrings(recordType: String, mainKey: String, englishKey: String?) async throws -> [String: [String: String]] {
        let db = CKContainer.default().publicCloudDatabase

        print("Fetch records...")
        let query = CKQuery(recordType: recordType, filters: [])
        let desiredKeys = [mainKey, englishKey].compactMap { $0 }

        var records = [CKRecord]()
        var cursor: CKQueryOperation.Cursor?
        do {
            let (recordResults, newCursor) = try await db.records(matching: query, desiredKeys: desiredKeys)
            for (_, recordResult) in recordResults {
                switch recordResult {
                case .success(let record):
                    records.append(record)
                case .failure(let error):
                    throw error
                }
            }
            cursor = newCursor
        } catch {
            throw CloudKitHandlerError.cloudKit(error: error)
        }

        while let currentCursor = cursor {
            print("Continue to fetch records...")
            do {
                let (recordResults, newCursor) = try await db.records(continuingMatchFrom: currentCursor, desiredKeys: desiredKeys)
                for (_, recordResult) in recordResults {
                    switch recordResult {
                    case .success(let record):
                        records.append(record)
                    case .failure(let error):
                        throw error
                    }
                }
                cursor = newCursor
            } catch {
                throw CloudKitHandlerError.cloudKit(error: error)
            }
        }

        print("Parsing record results...")
        var results = [String: [String: String]]()
        for record in records {
            if let englishKey {
                guard let english = record[englishKey] as? String else {
                    throw CloudKitHandlerError.englishResourceMissing
                }
                var result = ["en": english]
                if let others = record[mainKey] as? String, !others.isEmpty {
                    guard let json = try? JSONDecoder().decode([String: String].self, from: others.data(using: .utf8)!) else {
                        throw CloudKitHandlerError.json
                    }
                    for (locale, string) in json {
                        result[locale] = string
                    }
                }
                results[record.recordID.recordName] = result
            } else {
                guard let others = record[mainKey] as? String, !others.isEmpty else {
                    continue
                }
                guard let json = try? JSONDecoder().decode([String: String].self, from: others.data(using: .utf8)!) else {
                    throw CloudKitHandlerError.json
                }
                guard json["en"] != nil else {
                    throw CloudKitHandlerError.englishResourceMissing
                }
                results[record.recordID.recordName] = json
            }
        }
        return results
    }
}
