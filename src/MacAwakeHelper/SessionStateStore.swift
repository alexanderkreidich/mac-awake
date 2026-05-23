import Foundation

public enum SessionStateStoreError: Error, Equatable {
    case corruptedState
}

public protocol SessionStateStoring {
    func load() throws -> SessionState
    func save(_ state: SessionState) throws
}

public final class SessionStateStore: SessionStateStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func load() throws -> SessionState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .inactive
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(SessionState.self, from: data)
        } catch is DecodingError {
            throw SessionStateStoreError.corruptedState
        }
    }

    public func save(_ state: SessionState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}
