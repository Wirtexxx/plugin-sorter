import Foundation

enum PluginFormat: String, CaseIterable {
    case vst3 = "VST3", vst = "VST", au = "AU", clap = "CLAP"

    var folder: String {
        switch self {
        case .vst3: return "VST3"
        case .vst:  return "VST"
        case .au:   return "Components"
        case .clap: return "CLAP"
        }
    }

    var fileExtension: String {
        switch self {
        case .vst3: return "vst3"
        case .vst:  return "vst"
        case .au:   return "component"
        case .clap: return "clap"
        }
    }
}
