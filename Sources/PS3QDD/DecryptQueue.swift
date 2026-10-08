import Combine
import Foundation
import PS3QDDCore

/// A one-way stop signal, readable from the decryption thread and writable from the
/// main actor. A plain `Bool` would be a data race; this is the smallest thing that
/// is not.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Everything the window shows. All mutable state lives here rather than in `@State`,
/// because the SwiftUI macro plugin is not available with Command Line Tools alone.
@MainActor
final class DecryptQueue: ObservableObject {
    enum JobState: Equatable {
        case queued
        case running
        case done
        case alreadyDone
        case stopped
        case skipped(String)
        case failed(String)
    }

    @MainActor
    final class Job: ObservableObject, Identifiable {
        let id = UUID()
        let url: URL
        let outputURL: URL
        let cancelFlag = CancelFlag()

        @Published var state: JobState = .queued
        @Published var fraction: Double = 0
        @Published var bytesPerSecond: Double = 0
        @Published var etaSeconds: Double?

        var scan: DiscScan?
        var key: DiscKey?

        var name: String { url.lastPathComponent }

        var isSkipped: Bool {
            if case .skipped = state { return true }
            return false
        }

        var isPending: Bool { state == .queued }

        init(url: URL, outputURL: URL) {
            self.url = url
            self.outputURL = outputURL
        }

        func apply(_ progress: DecryptProgress) {
            fraction = progress.fraction
            bytesPerSecond = progress.bytesPerSecond
            etaSeconds = progress.etaSeconds
        }
    }

    @Published var isoFolder: URL?
    @Published var keysURL: URL?
    @Published var outputFolder: URL?
    @Published var deleteOriginal = false
    @Published var jobs: [Job] = []
    @Published var isRunning = false
    @Published var statusMessage = ""
    @Published var showingISOPicker = false
    @Published var showingKeyPicker = false
    @Published var showingOutputPicker = false

    private var keyStore: KeyStore?
    private var prepareTask: Task<Void, Never>?
    private var runner: Task<Void, Never>?

    init() {
        // The keys file that scripts/prepare-keys.sh writes, if it is already there.
        let defaults = KeyStore.defaultFileURL
        if FileManager.default.fileExists(atPath: defaults.path) {
            keysURL = defaults
            keyStore = try? KeyStore.load(from: defaults)
        }
    }

    var canStart: Bool {
        !isRunning && jobs.contains { $0.isPending }
    }

    var emptyMessage: String {
        if isoFolder == nil { return "Choose a folder of encrypted ISOs to begin." }
        if jobs.isEmpty { return "No .iso files in that folder." }
        return ""
    }

    var summary: String {
        guard !jobs.isEmpty else { return "" }
        let ready = jobs.filter { $0.isPending }.count
        let done = jobs.filter { $0.state == .done || $0.state == .alreadyDone }.count
        let skipped = jobs.filter { $0.isSkipped }.count
        let failed = jobs.filter { if case .failed = $0.state { return true } else { return false } }.count
        var parts = ["\(jobs.count) image(s)", "\(ready) ready", "\(done) done"]
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Choosing inputs

    func setISOFolder(_ url: URL) {
        isoFolder = url
        prepare()
    }

    func setKeys(_ url: URL) {
        keysURL = url
        do {
            let store = try KeyStore.load(from: url)
            keyStore = store
            statusMessage = "Loaded \(store.count) keys"
        } catch {
            keyStore = nil
            statusMessage = "Could not read keys: \(Self.describe(error))"
        }
        prepare()
    }

    func setOutputFolder(_ url: URL) {
        outputFolder = url
        prepare()
    }

    /// Enumerates the folder, validates each image's region map and looks up its key.
    /// Anything that fails validation is marked skipped instead of being handed to the
    /// engine, which would otherwise decrypt a plain image in place and corrupt it.
    func prepare() {
        prepareTask?.cancel()
        jobs = []
        guard let isoFolder else {
            statusMessage = ""
            return
        }

        let store = keyStore
        let outputDirectory = outputFolder ?? isoFolder
        statusMessage = "Scanning images..."

        prepareTask = Task { [weak self] in
            let files = await Task.detached(priority: .utility) {
                Self.findImages(in: isoFolder)
            }.value
            if Task.isCancelled { return }

            var prepared: [Job] = []
            for file in files {
                if Task.isCancelled { return }
                let probe = await Task.detached(priority: .utility) {
                    () -> (scan: DiscScan?, key: DiscKey?) in
                    (try? Decryptor.scan(input: file), store?.key(forISO: file.lastPathComponent))
                }.value

                let job = Job(url: file, outputURL: Self.outputURL(for: file, in: outputDirectory))
                job.scan = probe.scan
                job.key = probe.key
                if probe.scan == nil {
                    job.state = .skipped("Not an encrypted PS3 disc image")
                } else if probe.key == nil {
                    job.state = .skipped("No key found for this title")
                }
                prepared.append(job)
            }

            guard let self, !Task.isCancelled else { return }
            self.jobs = prepared
            self.statusMessage = prepared.isEmpty ? "" : "Ready"
        }
    }

    // MARK: - Running

    func start() {
        guard canStart else { return }
        isRunning = true
        statusMessage = ""
        runner = Task { [weak self] in
            await self?.runAll()
        }
    }

    func stopAll() {
        for job in jobs { job.cancelFlag.cancel() }
    }

    private func runAll() async {
        for job in jobs where job.isPending {
            await run(job)
        }
        isRunning = false
        statusMessage = "Finished"
    }

    private func run(_ job: Job) async {
        guard let key = job.key, let scan = job.scan else {
            job.state = .skipped("Nothing to do")
            return
        }

        job.state = .running
        job.fraction = 0

        let input = job.url
        let output = job.outputURL
        let flag = job.cancelFlag
        let shouldDeleteSource = deleteOriginal

        let outcome: Outcome = await Task.detached(priority: .userInitiated) {
            // A finished output of the full expected size means an earlier run already
            // did this one.
            if Self.fileSize(of: output) == scan.totalBytes {
                return .alreadyDone
            }
            do {
                try Decryptor.decrypt(
                    input: input,
                    output: output,
                    key: key,
                    scan: scan,
                    progress: { progress in
                        Task { @MainActor in job.apply(progress) }
                    },
                    isCancelled: { flag.isCancelled }
                )
                return .done
            } catch DecryptorError.cancelled {
                return .stopped
            } catch {
                return .failed(Self.describe(error))
            }
        }.value

        switch outcome {
        case .done:
            job.state = .done
            job.fraction = 1
            job.bytesPerSecond = 0
            job.etaSeconds = nil
            if shouldDeleteSource, Self.isRegularFile(input) {
                try? FileManager.default.removeItem(at: input)
            }
        case .alreadyDone:
            job.state = .alreadyDone
            job.fraction = 1
        case .stopped:
            job.state = .stopped
        case .failed(let message):
            job.state = .failed(message)
        }
    }

    // MARK: - Helpers

    private enum Outcome: Sendable {
        case done
        case alreadyDone
        case stopped
        case failed(String)
    }

    nonisolated static func findImages(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "iso" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Writing next to the source would collide with the source, so that case gets a
    /// distinct name.
    nonisolated static func outputURL(for input: URL, in folder: URL) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        let sameFolder = folder.standardizedFileURL == input.deletingLastPathComponent().standardizedFileURL
        let name = sameFolder ? "\(stem)_decrypted.iso" : "\(stem).iso"
        return folder.appendingPathComponent(name)
    }

    /// `removeItem` deletes a directory and everything under it, and a folder named
    /// `Something.iso` sorts into the image list, so the delete is restricted to files.
    nonisolated static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    nonisolated static func fileSize(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case let DecryptorError.insufficientSpace(needed, available):
            return "Not enough free space: needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), "
                + "only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available"
        case let KeyStoreError.noKeysFound(path):
            return "No keys found in \(path)"
        case let KeyStoreError.malformedLine(number):
            return "Line \(number) of the keys file is not a title and a 32-character key"
        case let KeyStoreError.unsupportedSource(path):
            return "Nothing readable at \(path)"
        case let DecryptorError.notSectorAligned(bytes):
            return "File size \(bytes) is not a multiple of 2048"
        case DecryptorError.notAPS3Image:
            return "No valid PS3 region map"
        case DecryptorError.unreadableHeader:
            return "Could not read the first sector"
        case let DecryptorError.writeFailed(offset, code):
            return "Write failed at byte \(offset) (code \(code))"
        case let DecryptorError.shortRead(offset):
            return "Unexpected end of file at byte \(offset)"
        case let DecryptorError.decryptionFailed(status):
            return "The decryption engine failed (code \(status))"
        case DecryptorError.cancelled:
            return "Stopped"
        case let DecryptorError.cannotCreateOutput(path):
            return "Could not create \(path)"
        default:
            return error.localizedDescription
        }
    }
}
