import Foundation

/// Watches a *directory* with a DispatchSource and calls `onChange` on the main queue,
/// debounced. Watching the directory (not the file) survives the atomic replace that
/// `Data.write(options: .atomic)` and most editors do.
final class FileWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "uk.trinh.DotBar.watch", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?

    init?(directory: URL, debounce: TimeInterval, onChange: @escaping () -> Void) {
        self.url = directory
        self.debounce = debounce
        self.onChange = onChange
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                            eventMask: [.write, .rename, .delete, .extend, .attrib],
                                                            queue: queue)
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { [fd] in close(fd) }
        source = src
        src.resume()
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
