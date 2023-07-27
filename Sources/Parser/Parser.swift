import Foundation

enum ParserError {
    case malformed
    case englishResourceMissing
    case directoryIteration
    case createDirectory
    case writeFile
    case stringConversion
}

extension ParserError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformed:
            return "Malformed file"
        case .englishResourceMissing:
            return "English resource missing"
        case .directoryIteration:
            return "Error in iterating contents of a directory"
        case .createDirectory:
            return "Error creating a directory"
        case .writeFile:
            return "Error writing to file"
        case .stringConversion:
            return "Error converting string to data"
        }
    }
}

public class Parser {
    public init() {}

    public func parseFile(at path: String) throws -> [String: String] {
        let stringsFilePath = (path as NSString).appendingPathComponent("Localizable.strings")
        guard let dictionary = NSDictionary(contentsOfFile: stringsFilePath) as? [String: String] else {
            throw ParserError.malformed
        }
        return dictionary
    }

    private func parseLocalizedDataForDataDirectory(at path: String) throws -> (existing: [String: (id: String, data: Data)], new: [String: Data]) {
        guard let languages = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            throw ParserError.directoryIteration
        }

        var existingResults = [String: (id: String, data: Data)]()
        var newResults = [String: Data]()
        for language in languages {
            guard language != ".DS_Store" else { continue }
            let languagePath = (path as NSString).appendingPathComponent(language)
            let idFilePath = (languagePath as NSString).appendingPathComponent("id.txt").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let dataFilePath = (languagePath as NSString).appendingPathComponent("data.html")
            if FileManager.default.fileExists(atPath: idFilePath) {
                let id = try String(contentsOfFile: idFilePath, encoding: .utf8)
                existingResults[language] = (id, try Data(contentsOf: URL(fileURLWithPath: dataFilePath)))
            } else {
                newResults[language] = try Data(contentsOf: URL(fileURLWithPath: dataFilePath))
            }
        }
        return (existingResults, newResults)
    }

    public func parseDataDirectory(at path: String) throws -> [String: (existing: [String: (id: String, data: Data)], new: [String: Data], reference: String)] {
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            throw ParserError.directoryIteration
        }

        var results = [String: (existing: [String: (id: String, data: Data)], new: [String: Data], reference: String)]()
        for id in ids {
            guard id != ".DS_Store" else { continue }
            let result = try parseLocalizedDataForDataDirectory(at: (path as NSString).appendingPathComponent(id))
            guard let englishResource = result.existing["en"] else {
                throw ParserError.englishResourceMissing
            }
            results[id] = (result.existing, result.new, englishResource.id)
        }
        return results
    }

    public func parseDirectory(at path: String) throws -> [String: [String: String]] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            throw ParserError.directoryIteration
        }

        var stringsByLocale = [String: [String: String]]()
        for content in contents {
            guard content.hasSuffix(".lproj") else { continue }
            let locale = String(content[content.startIndex..<content.index(content.endIndex, offsetBy: -6)])
            stringsByLocale[locale] = try parseFile(at: (path as NSString).appendingPathComponent(content))
        }

        guard let englishStrings = stringsByLocale["en"] else {
            throw ParserError.englishResourceMissing
        }

        // Remove strings that are not included in en
        var clearedStringsByLocale = [String: [String: String]]()
        for (locale, strings) in stringsByLocale {
            var newStrings = [String: String]()
            for (key, value) in strings {
                if englishStrings[key] == nil { continue }
                newStrings[key] = value
            }
            if !newStrings.isEmpty {
                clearedStringsByLocale[locale] = newStrings
            }
        }

        return clearedStringsByLocale
    }

    public func writeLocalizedData(dataById: [String: [String: (id: String, data: Data)]], to path: String) throws {
        let fileManager = FileManager.default
        for (id, localizedData) in dataById {
            let idDirectory = (path as NSString).appendingPathComponent(id)
            try fileManager.createDirectory(atPath: idDirectory, withIntermediateDirectories: true)
            for (language, languageData) in localizedData {
                let languageDirectory = (idDirectory as NSString).appendingPathComponent(language)
                try fileManager.createDirectory(atPath: languageDirectory, withIntermediateDirectories: true)
                let idFilePath = (languageDirectory as NSString).appendingPathComponent("id.txt").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let dataFilePath = (languageDirectory as NSString).appendingPathComponent("data.html")
                guard let idData = languageData.id.data(using: .utf8) else {
                    throw ParserError.stringConversion
                }
                try languageData.data.write(to: URL(fileURLWithPath: dataFilePath))
                try idData.write(to: URL(fileURLWithPath: idFilePath))
            }
        }
    }

    public func writeStrings(_ stringsByLocale: [String: [String: String]], to path: String) throws {
        guard let englishStrings = stringsByLocale["en"] else {
            throw ParserError.englishResourceMissing
        }
        for (locale, strings) in stringsByLocale {
            let directory = (path as NSString).appendingPathComponent("\(locale).lproj")
            do {
                if !FileManager.default.fileExists(atPath: directory) {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                }
            } catch {
                throw ParserError.createDirectory
            }

            var singleStrings = [String]()
            let stringsPath = (directory as NSString).appendingPathComponent("Localizable.strings")
            for (key, english) in englishStrings.sorted(by: { $0.key < $1.key }) {
                let string: String
                let escapedEnglish = english.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\"")
                if let value = strings[key] {
                    let escapedValue = value.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\"", with: "\\\"")
                    string = "// English: \(escapedEnglish)\n\"\(key)\" = \"\(escapedValue)\";"
                } else {
                    string = "// English: \(escapedEnglish)\n//\"\(key)\" = \"\(escapedEnglish)\";"
                }
                singleStrings.append(string)
            }
            do {
                try singleStrings.joined(separator: "\n\n").write(toFile: stringsPath, atomically: true, encoding: .utf8)
            } catch {
                throw ParserError.writeFile
            }
        }
    }

    public func convertToStringsByKeys(_ stringsByLocale: [String: [String: String]]) throws -> [String: [String: String]] {
        guard let englishStrings = stringsByLocale["en"] else {
            throw ParserError.englishResourceMissing
        }
        var results = [String: [String: String]]()
        for (key, value) in englishStrings {
            var result = ["en": value]
            for (locale, strings) in stringsByLocale {
                if let string = strings[key] {
                    result[locale] = string
                }
            }
            results[key] = result
        }
        return results
    }

    public func convertToStringsByLocales(_ stringsByKeys: [String: [String: String]]) throws -> [String: [String: String]] {
        var results = [String: [String: String]]()
        for (key, strings) in stringsByKeys {
            var hasEnglishResource = false
            for (locale, string) in strings {
                if !hasEnglishResource, locale == "en" {
                    hasEnglishResource = true
                }
                if results[locale] != nil {
                    results[locale]![key] = string
                } else {
                    results[locale] = [key: string]
                }
            }
            if !hasEnglishResource {
                throw ParserError.englishResourceMissing
            }
        }
        return results
    }
}
