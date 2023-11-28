import ArgumentParser
import Foundation
import OpenCloudKit
import Parser

enum ActionError: Error {
    case unsupported
}

extension ActionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Unsupported action"
        }
    }
}

enum ArgumentError: Error {
    case noAuth
}

extension ArgumentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAuth:
            return "No authentication method is provided"
        }
    }
}

@main
struct UploaderApp: AsyncParsableCommand {
    static let containerID = "iCloud.space.celestia.Celestia"
    static let environment = CKEnvironment.production

    @Argument
    var oldPath: String
    @Argument
    var newPath: String
    @Argument
    var mainKey: String
    @Argument
    var dataKey: String?

    @Option(help: "The key file path for CloudKit.")
    var keyFilePath: String?

    @Option(help: "The key ID for CloudKit.")
    var keyID: String?

    @Option(help: "The API token for CloudKit.")
    var apiToken: String?

    @Option
    var englishKey: String?

    @Option
    var keywordsKey: String?

    func run() async throws {
        let parser = Parser()

        let config: CKContainerConfig
        if let keyID, let keyFilePath {
            let serverKeyAuth = try CKServerToServerKeyAuth(keyID: keyID, privateKeyFile: keyFilePath)
            config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, serverToServerKeyAuth: serverKeyAuth)
        } else if let apiToken {
            config = CKContainerConfig(containerIdentifier: Self.containerID, environment: Self.environment, apiTokenAuth: apiToken)
        } else {
            throw ArgumentError.noAuth
        }

        CloudKitHandler.configure(config)
        let handler = CloudKitHandler()

        if let dataKey {
            let oldDataCollection = try parser.parseDataDirectory(at: oldPath)
            let newDataCollection = try parser.parseDataDirectory(at: newPath)
            var dataById = [String: Data]()
            var dataToDuplicate = [(data: Data, targetId: String, language: String, reference: String, id: String)]()
            for (id, newData) in newDataCollection {
                guard newData.new.isEmpty else {
                    throw ActionError.unsupported
                }
                guard let oldData = oldDataCollection[id] else {
                    throw ActionError.unsupported
                }
                guard oldData.new.isEmpty else {
                    throw ActionError.unsupported
                }
                for (language, dataWithId) in newData.existing {
                    if let oldDataWithId = oldData.existing[language] {
                        guard oldDataWithId.id == dataWithId.id else {
                            throw ActionError.unsupported
                        }
                        if dataWithId.data != oldDataWithId.data {
                            dataById[dataWithId.id] = dataWithId.data
                        }
                    } else {
                        dataToDuplicate.append((dataWithId.data, dataWithId.id, language, newData.reference, id))
                    }
                }
            }
            if !dataById.isEmpty {
                try await handler.uploadDataChanges(dataById: dataById, dataKey: dataKey)
            }
            if !dataToDuplicate.isEmpty {
                try await handler.duplicateData(dataInformations: dataToDuplicate, mainKey: mainKey, dataKey: dataKey)
            }
        } else {
            let oldStringsByLocales = try parser.parseDirectory(at: oldPath)
            let newStringsByLocales = try parser.parseDirectory(at: newPath)
            let oldStringsByKeys = try parser.convertToStringsByKeys(oldStringsByLocales)
            let newStringsByKeys = try parser.convertToStringsByKeys(newStringsByLocales)

            let addedOnes = newStringsByKeys.filter({ oldStringsByKeys[$0.key] == nil })
            let removedOnes = oldStringsByKeys.filter({ newStringsByKeys[$0.key] == nil })
            let changedOnes = newStringsByKeys.filter({ oldStringsByKeys[$0.key] != nil && oldStringsByKeys[$0.key] != $0.value })

            try await handler.uploadChanges(addedStrings: addedOnes, removedStrings: removedOnes, changedStrings: changedOnes, mainKey: mainKey, englishKey: englishKey, keywordsKey: keywordsKey)
        }
    }
}
