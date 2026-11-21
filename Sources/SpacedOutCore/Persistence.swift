import Foundation

public protocol StatePersisting: Sendable {
    func load() throws -> PersistedState
    func save(_ state: PersistedState) throws
}

public final class AtomicJSONStore: StatePersisting, @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("SpacedOut", isDirectory: true)
                .appendingPathComponent("state.json", isDirectory: false)
        }
    }

    public func load() throws -> PersistedState {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PersistedState()
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return PersistedState()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(PersistedState.self, from: data)
        } catch {
            // keep a backup of corrupt data instead of silently wiping history
            let backupName = "state.corrupt.\(Int(Date().timeIntervalSince1970)).json"
            let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? data.write(to: backupURL, options: .atomic)
            throw error
        }
    }

    public func save(_ state: PersistedState) throws {
        lock.lock()
        defer { lock.unlock() }

        let parentDir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let tempURL = parentDir.appendingPathComponent(".state.\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: fileURL)
        }
    }
}

public final class InMemoryStateStore: StatePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PersistedState

    public init(initialState: PersistedState = PersistedState()) {
        self.state = initialState
    }

    public func load() throws -> PersistedState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func save(_ state: PersistedState) throws {
        lock.lock()
        defer { lock.unlock() }
        self.state = state
    }
}
