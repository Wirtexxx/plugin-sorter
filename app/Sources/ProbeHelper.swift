import Foundation

/// The `--probe` helper: loads a plugin and looks up its entry point. Its code runs here, so this
/// process is the one that may crash.
enum ProbeHelper {
    /// Entry point for `--probe FORMAT PATH`. Prints "PROBE OK" or the reason it failed.
    static func run(_ args: [String]) -> Never {
        alarm(Helper.timeLimit)
        guard args.count >= 3, let format = PluginFormat(rawValue: args[1]) else { _exit(1) }
        let url = URL(fileURLWithPath: args[2])
        func fail(_ message: String) -> Never {
            print(message)
            fflush(stdout)
            _exit(10)
        }

        guard let bundle = Bundle(url: url), let executable = bundle.executablePath else { fail("no executable") }
        guard let handle = dlopen(executable, RTLD_NOW | RTLD_LOCAL) else {
            fail(dlerror().map { String(cString: $0) } ?? "dlopen failed")
        }

        switch format {
        case .vst3:
            // Hosts call bundleEntry before asking for the factory
            if let entry = dlsym(handle, "bundleEntry"), let cfBundle = CFBundleCreate(nil, url as CFURL) {
                typealias BundleEntry = @convention(c) (CFBundle) -> Bool
                guard unsafeBitCast(entry, to: BundleEntry.self)(cfBundle) else { fail("bundleEntry returned false") }
            }
            guard let symbol = dlsym(handle, "GetPluginFactory") else { fail("GetPluginFactory not found") }
            typealias GetFactory = @convention(c) () -> UnsafeMutableRawPointer?
            guard unsafeBitCast(symbol, to: GetFactory.self)() != nil else { fail("no plugin factory") }
        case .vst:
            guard dlsym(handle, "VSTPluginMain") != nil || dlsym(handle, "main_macho") != nil else {
                fail("VSTPluginMain not found")
            }
        case .clap:
            guard dlsym(handle, "clap_entry") != nil else { fail("clap_entry not found") }
        case .au:
            break
        }
        print("PROBE OK")
        fflush(stdout)
        // _exit skips plugin destructors, some of which abort outside a real host
        _exit(0)
    }
}
