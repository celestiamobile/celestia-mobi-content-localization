import Foundation
import MWRequest
import OpenCloudKit

enum CloudKitHandlerError: Error {
    case cloudKit(error: Error)
    case removalNotAllowed
    case internalError
    case json
    case englishResourceMissing
    case dataMissing
    case stringConversion
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
        case .dataMissing:
            return "Data is missing from the record"
        case .stringConversion:
            return "Error converting string to data"
        }
    }
}

public class CloudKitHandler {
    public init() {}

    public static func configure(_ config: CKContainerConfig) {
        CloudKit.shared.configure(with: CKConfig(containers: [config]))
    }

    private func duplicateData(dataInformation: (data: Data, targetId: String, language: String, reference: String, id: String), mainKey: String, dataKey: String) async throws {
        let db = CKContainer.default().publicCloudDatabase
        let referenceRecordID = CKRecord.ID(recordName: dataInformation.reference)
        let referenceRecordResults = try await db.records(for: [referenceRecordID])
        guard let recordResult = referenceRecordResults[referenceRecordID] else {
            throw CloudKitHandlerError.dataMissing
        }
        let record = try recordResult.get()
        let newRecord = CKRecord(recordType: record.recordType, recordID: CKRecord.ID(recordName: dataInformation.targetId))
        let temporaryDirectory = NSTemporaryDirectory()
        for key in record.allKeys() {
            guard let value = record[key] else {
                throw CloudKitHandlerError.dataMissing
            }
            if let asset = value as? CKAsset {
                let data = try await AsyncDataRequestHandler.get(url: asset.fileURL.absoluteString)
                let tempPath = (temporaryDirectory as NSString).appendingPathComponent(UUID().uuidString)
                let fileURL = URL(fileURLWithPath: tempPath)
                try data.write(to: fileURL)
                newRecord[key] = CKAsset(fileURL: fileURL)
            } else if let assets = value as? [CKAsset] {
                var newAssets = [CKAsset]()
                for asset in assets {
                    let data = try await AsyncDataRequestHandler.get(url: asset.fileURL.absoluteString)
                    let tempPath = (temporaryDirectory as NSString).appendingPathComponent(UUID().uuidString)
                    let fileURL = URL(fileURLWithPath: tempPath)
                    try data.write(to: fileURL)
                    newAssets.append(CKAsset(fileURL: fileURL))
                }
                newRecord[key] = newAssets
            } else {
                newRecord[key] = value
            }
        }
        newRecord[dataKey] = dataInformation.data
        let recordDuplicateResults = try await db.modifyRecords(saving: [newRecord], deleting: [], savePolicy: .allKeys)
        guard let recordDuplicateResult = recordDuplicateResults.saveResults[newRecord.recordID] else {
            throw CloudKitHandlerError.dataMissing
        }
        switch recordDuplicateResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }
        let mainRecordID = CKRecord.ID(recordName: dataInformation.id)
        let mainRecordResults = try await db.records(for: [mainRecordID], desiredKeys: [mainKey])
        guard let mainRecordResult = mainRecordResults[mainRecordID] else {
            throw CloudKitHandlerError.dataMissing
        }
        let mainRecord = try mainRecordResult.get()
        guard let value = mainRecord[mainKey] as? String else {
            throw CloudKitHandlerError.dataMissing
        }
        guard var json = try? JSONDecoder().decode([String: String].self, from: value.data(using: .utf8)!) else {
            throw CloudKitHandlerError.json
        }
        json[dataInformation.language] = newRecord.recordID.recordName
        guard let encodedData = try? JSONEncoder().encode(json) else {
            throw CloudKitHandlerError.json
        }
        guard let str = String(data: encodedData, encoding: .utf8) else {
            throw CloudKitHandlerError.stringConversion
        }
        mainRecord[mainKey] = str
        guard let modifyResult = try await db.modifyRecords(saving: [mainRecord], deleting: [], savePolicy: .changedKeys).saveResults[mainRecordID] else {
            throw CloudKitHandlerError.dataMissing
        }
        switch modifyResult {
        case .success:
            break
        case .failure(let error):
            throw error
        }
    }

    public func duplicateData(dataInformations: [(data: Data, targetId: String, language: String, reference: String, id: String)], mainKey: String, dataKey: String) async throws {
        for dataInformation in dataInformations {
            try await duplicateData(dataInformation: dataInformation, mainKey: mainKey, dataKey: dataKey)
        }
    }

    public func uploadDataChanges(dataById: [String: Data], dataKey: String) async throws {
        let db = CKContainer.default().publicCloudDatabase
        let recordResults = try await db.records(for: dataById.keys.map { CKRecord.ID(recordName: $0) }, desiredKeys: [dataKey])
        print("Fetching original records...")
        var modifiedRecords = [CKRecord]()
        for (id, recordResult) in recordResults {
            switch recordResult {
            case .success(let record):
                guard let data = dataById[id.recordName] else {
                    throw CloudKitHandlerError.dataMissing
                }
                record[dataKey] = data
                modifiedRecords.append(record)
            case .failure(let error):
                throw error
            }
        }
        print("Saving records...")
        let saveResults = try await db.modifyRecords(saving: modifiedRecords, deleting: [], savePolicy: .changedKeys).saveResults
        for (_, recordResult) in saveResults {
            switch recordResult {
            case .success:
                continue
            case .failure(let error):
                throw error
            }
        }
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
            let recordResults = try await db.records(for: allChanges.keys.map({ CKRecord.ID(recordName: $0) }), desiredKeys: desiredKeys)
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
                    continue
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

        let records = try await db.allRecords(query: query, desiredKeys: desiredKeys)

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

    public func fetchData(recordType: String, mainKey: String, targetDataKey: String) async throws -> [String: [String: (id: String, data: Data)]] {
        let db = CKContainer.default().publicCloudDatabase

        print("Fetch records...")
        let query = CKQuery(recordType: recordType, filters: [])
        let desiredKeys = [mainKey]

        let records = try await db.allRecords(query: query, desiredKeys: desiredKeys)

        print("Parsing record results...")
        var initialResults = [String: [String: String]]()
        var dataIds = Set<String>()
        for record in records {
            guard let resources = record[mainKey] as? String, !resources.isEmpty else {
                continue
            }
            guard let json = try? JSONDecoder().decode([String: String].self, from: resources.data(using: .utf8)!) else {
                throw CloudKitHandlerError.json
            }
            guard json["en"] != nil else {
                throw CloudKitHandlerError.englishResourceMissing
            }

            initialResults[record.recordID.recordName] = json
            dataIds.formUnion(json.values)
        }

        print("Fetching data...")
        var currentIds = [String]()
        var dataResults = [String: Data]()
        func getDataRecords() async throws {
            let dataRecordResults = try await db.records(for: currentIds.map { CKRecord.ID(recordName: $0) }, desiredKeys: [targetDataKey])
            for (id, recordResult) in dataRecordResults {
                switch recordResult {
                case .success(let record):
                    guard let data = record[targetDataKey] as? Data else {
                        throw CloudKitHandlerError.dataMissing
                    }
                    dataResults[id.recordName] = data
                case .failure(let error):
                    throw error
                }
            }
        }

        for dataId in dataIds {
            currentIds.append(dataId)
            if currentIds.count == 50 {
                try await getDataRecords()
                currentIds = []
            }
        }
        if !currentIds.isEmpty {
            try await getDataRecords()
        }

        print("Matching data...")
        var finalResults = [String: [String: (id: String, data: Data)]]()
        for (id, initialResult) in initialResults {
            var recordResults = [String: (id: String, data: Data)]()
            for (language, dataId) in initialResult {
                guard let data = dataResults[dataId] else {
                    throw CloudKitHandlerError.internalError
                }
                recordResults[language] = (dataId, data)
            }
            finalResults[id] = recordResults
        }
        return finalResults
    }
}

extension CKDatabase {
    func allRecords(query: CKQuery, desiredKeys: [String]) async throws -> [CKRecord]  {
        var records = [CKRecord]()
        var cursor: CKQueryOperation.Cursor?
        do {
            let (recordResults, newCursor) = try await self.records(matching: query, desiredKeys: desiredKeys)
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
                let (recordResults, newCursor) = try await self.records(continuingMatchFrom: currentCursor, desiredKeys: desiredKeys)
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
        return records
    }
}
