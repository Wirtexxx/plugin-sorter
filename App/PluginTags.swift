import Foundation

/// Categories a plugin reports about itself: VST3 sub-categories ("Fx", "Reverb") or CLAP features
/// ("audio-effect", "reverb"). Read in a separate copy of the app (`--tags`), like the load check,
/// because it means loading the plugin.
enum PluginTags {
    /// Lowercased tags, nil when the plugin couldn't be read.
    static func read(_ format: PluginFormat, _ url: URL) -> [String]? {
        guard format == .vst3 || format == .clap, let helper = Helper.process(["--tags", format.rawValue, url.path]),
              let output = PluginChecker.runLogged(helper, timeout: 30, successMarker: "TAGS OK"),
              output.contains("TAGS OK") else { return nil }
        return output.split(separator: "\n")
            .filter { $0.hasPrefix("TAG ") }
            .map { String($0.dropFirst(4)).lowercased() }
    }

    /// Entry point for `--tags FORMAT PATH`. Prints "TAG …" lines, then "TAGS OK".
    static func runHelper(_ args: [String]) -> Never {
        alarm(Helper.timeLimit)
        guard args.count >= 3, let format = PluginFormat(rawValue: args[1]) else { _exit(1) }
        let url = URL(fileURLWithPath: args[2])
        guard let bundle = Bundle(url: url), let executable = bundle.executablePath,
              let handle = dlopen(executable, RTLD_NOW | RTLD_LOCAL) else { _exit(10) }

        let tags: [String]
        switch format {
        case .vst3: tags = vst3(handle, url)
        case .clap: tags = clap(handle, url)
        default:    tags = []
        }
        for tag in tags { print("TAG " + tag) }
        print("TAGS OK")
        fflush(stdout)
        // _exit skips plugin destructors, some of which abort outside a real host
        _exit(0)
    }

    // MARK: - VST3

    /// IPluginFactory2's interface id, in the byte order VST3 uses outside Windows.
    private static let factory2IID: [UInt8] = [0x00, 0x07, 0xB6, 0x50, 0xF2, 0x4B, 0x4C, 0x0B,
                                               0xA4, 0x64, 0xED, 0xB9, 0xF0, 0x0B, 0x2A, 0xBB]

    /// Sub-categories of the audio processor classes, split at "|".
    private static func vst3(_ handle: UnsafeMutableRawPointer, _ url: URL) -> [String] {
        if let entry = dlsym(handle, "bundleEntry"), let cfBundle = CFBundleCreate(nil, url as CFURL) {
            typealias BundleEntry = @convention(c) (CFBundle) -> Bool
            guard unsafeBitCast(entry, to: BundleEntry.self)(cfBundle) else { return [] }
        }
        typealias GetFactory = @convention(c) () -> UnsafeMutableRawPointer?
        guard let symbol = dlsym(handle, "GetPluginFactory"),
              let factory = unsafeBitCast(symbol, to: GetFactory.self)() else { return [] }

        // COM-style objects: the first word points at the vtable.
        // FUnknown: queryInterface, addRef, release; IPluginFactory: getFactoryInfo, countClasses,
        // getClassInfo, createInstance; IPluginFactory2 adds getClassInfo2.
        typealias QueryInterface = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<UInt8>,
                                                   UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
        typealias CountClasses = @convention(c) (UnsafeMutableRawPointer) -> Int32
        typealias ClassInfo2 = @convention(c) (UnsafeMutableRawPointer, Int32, UnsafeMutableRawPointer) -> Int32
        let table = factory.load(as: UnsafePointer<UnsafeRawPointer>.self)
        var object: UnsafeMutableRawPointer?
        let result = factory2IID.withUnsafeBufferPointer {
            unsafeBitCast(table[0], to: QueryInterface.self)(factory, $0.baseAddress!, &object)
        }
        guard result == 0, let factory2 = object else { return [] }
        let table2 = factory2.load(as: UnsafePointer<UnsafeRawPointer>.self)
        let count = unsafeBitCast(table2[4], to: CountClasses.self)(factory2)

        // PClassInfo2: cid[16], cardinality, category[32], name[64], classFlags, subCategories[128], …
        let size = 440
        let info = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { info.deallocate() }
        var tags: [String] = []
        for index in 0..<max(count, 0) {
            memset(info, 0, size)
            guard unsafeBitCast(table2[7], to: ClassInfo2.self)(factory2, index, info) == 0,
                  text(info + 20, 32) == "Audio Module Class" else { continue }
            tags += text(info + 120, 128).split(separator: "|").map(String.init)
        }
        return tags
    }

    private static func text(_ pointer: UnsafeRawPointer, _ capacity: Int) -> String {
        let bytes = pointer.assumingMemoryBound(to: UInt8.self)
        var out: [UInt8] = []
        for i in 0..<capacity {
            if bytes[i] == 0 { break }
            out.append(bytes[i])
        }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - CLAP

    /// Features of every plugin in the file.
    private static func clap(_ handle: UnsafeMutableRawPointer, _ url: URL) -> [String] {
        // clap_plugin_entry: clap_version (padded to 16 bytes), init, deinit, get_factory
        guard let entry = dlsym(handle, "clap_entry") else { return [] }
        typealias Init = @convention(c) (UnsafePointer<CChar>) -> Bool
        typealias GetFactory = @convention(c) (UnsafePointer<CChar>) -> UnsafeRawPointer?
        let initialize = unsafeBitCast(entry.load(fromByteOffset: 16, as: UnsafeRawPointer.self), to: Init.self)
        guard url.path.withCString(initialize) else { return [] }
        let getFactory = unsafeBitCast(entry.load(fromByteOffset: 32, as: UnsafeRawPointer.self), to: GetFactory.self)
        guard let factory = "clap.plugin-factory".withCString(getFactory) else { return [] }

        // clap_plugin_factory: get_plugin_count, get_plugin_descriptor
        typealias Count = @convention(c) (UnsafeRawPointer) -> UInt32
        typealias Descriptor = @convention(c) (UnsafeRawPointer, UInt32) -> UnsafeRawPointer?
        let count = unsafeBitCast(factory.load(as: UnsafeRawPointer.self), to: Count.self)(factory)
        let descriptor = unsafeBitCast(factory.load(fromByteOffset: 8, as: UnsafeRawPointer.self), to: Descriptor.self)
        var tags: [String] = []
        for index in 0..<count {
            // clap_plugin_descriptor: clap_version, eight strings, then the NULL-terminated features
            guard let plugin = descriptor(factory, index),
                  let features = plugin.load(fromByteOffset: 80, as: UnsafePointer<UnsafePointer<CChar>?>?.self)
            else { continue }
            var n = 0
            while let feature = features[n] {
                tags.append(String(cString: feature))
                n += 1
            }
        }
        return tags
    }
}

/// Tags already read, so sorting again doesn't load every plugin a second time.
/// Plugins that couldn't be read are remembered too: a crashing plugin would otherwise cost a timeout each time.
final class TagCache {
    private struct Record: Codable {
        let modified: Date
        let tags: [String]
    }

    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Plugin Sorter/plugin-tags.json")

    private var records: [String: Record] = [:]
    private let url: URL
    private let lock = NSLock()

    init(url: URL = TagCache.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
        }
    }

    /// Safe to call from several threads at once; an updated plugin is read again.
    func tags(_ format: PluginFormat, _ bundle: URL) -> [String] {
        let modified = (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
        lock.lock()
        let cached = records[bundle.path]
        lock.unlock()
        if let cached = cached, cached.modified == modified { return cached.tags }

        let tags = PluginTags.read(format, bundle) ?? []
        lock.lock()
        records[bundle.path] = Record(modified: modified, tags: tags)
        try? JSONEncoder().encode(records).write(to: url, options: .atomic)
        lock.unlock()
        return tags
    }
}
