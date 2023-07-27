import ArgumentParser
import Foundation
import OpenCloudKit
import Parser

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
struct SynchronizerApp: AsyncParsableCommand {
    static let containerID = "iCloud.space.celestia.Celestia"
    static let environment = CKEnvironment.production

    @Argument
    var path: String
    @Argument
    var recordType: String
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

    func run() async throws {
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
        let parser = Parser()

        if let dataKey {
            let data = try await handler.fetchData(recordType: recordType, mainKey: mainKey, targetDataKey: dataKey)
            try parser.writeLocalizedData(dataById: data, to: path)
        } else {
            let stringsByKeys = try await handler.fetchStrings(recordType: recordType, mainKey: mainKey, englishKey: englishKey)

            let stringsByLocales = try parser.convertToStringsByLocales(stringsByKeys)
            try parser.writeStrings(stringsByLocales, to: path)
        }
    }
}
