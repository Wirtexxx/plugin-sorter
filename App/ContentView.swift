import SwiftUI

/// The window: one screen with every plugin.
struct ContentView: View {
    @StateObject private var model: AppModel
    @AppStorage("language") private var language = Lang.system.rawValue
    @AppStorage(Skin.key) private var skin = Skin.violet.rawValue

    init(model: AppModel = AppModel()) {
        _model = StateObject(wrappedValue: model)
    }

    private var t: L10n { L10n(lang: Lang(rawValue: language) ?? .en) }

    var body: some View {
        ZStack {
            Chassis()
            MainView(model: model, t: t)
                .padding(.horizontal, 10)
                .padding(.top, 30)
                .padding(.bottom, 10)
                // Colours are read from the skin while views are built, so rebuild them when it changes
                .id(skin)
        }
        .background(WindowStyler())
        .onAppear {
            Shell.prompt = t("admin.prompt")
            model.refresh()
        }
        .onChange(of: language) { _ in Shell.prompt = t("admin.prompt") }
    }
}
