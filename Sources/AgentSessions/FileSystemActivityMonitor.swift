import CoreServices
import Foundation

final class FileSystemActivityMonitor {
    typealias Handler = ([String]) -> Void

    private let paths: [String]
    private let latency: CFTimeInterval
    private let queue: DispatchQueue
    private let handler: Handler
    private var stream: FSEventStreamRef?

    init(paths: [URL], latency: TimeInterval, queue: DispatchQueue, handler: @escaping Handler) {
        self.paths = paths.map(\.path)
        self.latency = latency
        self.queue = queue
        self.handler = handler
    }

    @discardableResult
    func start() -> Bool {
        guard stream == nil else {
            return true
        }

        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else {
            return false
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )
        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, _, _ in
            guard let info else {
                return
            }

            let monitor = Unmanaged<FileSystemActivityMonitor>
                .fromOpaque(info)
                .takeUnretainedValue()
            monitor.handle(eventCount: eventCount, eventPaths: eventPaths)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existingPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }

        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func handle(eventCount: Int, eventPaths: UnsafeMutableRawPointer) {
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        guard !paths.isEmpty || eventCount > 0 else {
            return
        }

        handler(paths)
    }
}
