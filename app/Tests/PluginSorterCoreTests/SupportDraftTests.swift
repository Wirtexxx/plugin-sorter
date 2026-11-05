import Foundation
import Testing
@testable import PluginSorterCore

@Suite("Draft message to support")
struct SupportDraftTests {
    private let context = SupportContext(macOS: "14.5", cpu: "arm64", appVersion: "1.2")

    private func bundle(_ path: String, version: String = "1.37", archs: [String] = ["x86_64", "arm64"]) -> PluginBundle {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/" + path)
        let format = PluginFormat.allCases.first { $0.fileExtension == url.pathExtension } ?? .vst3
        return PluginBundle(url: url, format: format, vendor: "Xfer", version: version, executable: nil,
                            archs: archs, quarantined: false, au: nil, nested: false)
    }

    private func plugin(_ name: String = "OTT", bundles: [PluginBundle]? = nil) -> ManagedPlugin {
        ManagedPlugin(key: "ott", name: name, vendor: "Xfer",
                      bundles: bundles ?? [bundle("VST3/OTT.vst3"), bundle("Components/OTT.component", version: "1.36", archs: ["arm64"])])
    }

    private func make(_ plugin: ManagedPlugin, issues: [String: [PluginSorterCore.Issue]] = [:]) -> SupportDraft {
        SupportDraft.make(plugin: plugin, issues: issues, context: context)
    }

    @Test func bodyListsEveryFormatWithVersionAndArchs() {
        let body = make(plugin()).body
        #expect(body.contains("VST3 1.37 (arm64, x86_64)"))
        #expect(body.contains("AU 1.36 (arm64)"))
    }

    @Test func bodyStatesTheSystem() {
        let body = make(plugin()).body
        #expect(body.contains("macOS 14.5"))
        #expect(body.contains("arm64"))
        #expect(body.contains("Plugin Sorter 1.2"))
    }

    @Test func specialCharactersAreEncoded() {
        let name = "A&B ?=+ #%"
        let draft = make(plugin(name, bundles: [bundle("VST3/AB.vst3")]))
        let text = draft.mailto.absoluteString
        #expect(text.hasPrefix("mailto:?subject="))
        // Raw separators of the query appear only where they separate: one "&" between subject and body
        #expect(text.filter { $0 == "&" }.count == 1)
        #expect(!text.contains(" "))
        let parts = URLComponents(url: draft.mailto, resolvingAgainstBaseURL: false)
        let items = parts?.queryItems ?? []
        #expect(items.first { $0.name == "subject" }?.value == draft.subject)
        #expect(items.first { $0.name == "body" }?.value == draft.body)
        #expect(draft.subject.contains(name))
    }

    @Test func longErrorIsCut() {
        let file = bundle("VST3/OTT.vst3")
        let long = String(repeating: "x", count: 10_000)
        let draft = make(plugin(bundles: [file]), issues: [file.id: [.loadFailed(long)]])
        #expect(draft.body.count < SupportDraft.maxErrorLength + 1000)
        #expect(draft.body.contains("…"))
        #expect(!draft.body.contains(long))
    }

    @Test func bodyHasNoHomePath() {
        let file = bundle("VST3/OTT.vst3")
        let home = NSHomeDirectory()
        let issue = PluginSorterCore.Issue.validationFailed("cannot open \(home)/Library/Caches/ott.db")
        let body = make(plugin(bundles: [file]), issues: [file.id: [issue]]).body
        #expect(!body.contains(home))
        #expect(body.contains("~/Library/Caches/ott.db"))
    }

    @Test func healthyFormatIsMarkedWorking() {
        let broken = bundle("VST3/OTT.vst3")
        let fine = bundle("Components/OTT.component")
        let body = make(plugin(bundles: [broken, fine]), issues: [broken.id: [.timeout]]).body
        let lines = body.components(separatedBy: "\n")
        #expect(lines.first { $0.contains("AU") }?.contains("works") == true)
        #expect(lines.first { $0.contains("VST3") }?.contains("works") == false)
    }
}
