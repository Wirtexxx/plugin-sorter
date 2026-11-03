import Foundation

enum Lang: String, CaseIterable, Identifiable {
    case en, ru, uk, de

    var id: String { rawValue }

    /// The language's own name, shown the same whatever language is selected.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .de: return "Deutsch"
        }
    }

    /// First supported language from the system preferences, English otherwise.
    static var system: Lang {
        for code in Locale.preferredLanguages {
            if let lang = Lang(rawValue: String(code.prefix(2))) { return lang }
        }
        return .en
    }
}

struct L10n {
    let lang: Lang

    func callAsFunction(_ key: String, _ args: CVarArg...) -> String {
        let format = Self.table[key]?[lang] ?? Self.table[key]?[.en] ?? key
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    func status(_ status: Status) -> String {
        switch status {
        case .idle:              return ""
        case .noFormats:         return self("status.noFormats")
        case .undone:            return self("status.undone")
        case .cancelled:         return self("status.cancelled")
        case .willMove(let n):   return self("status.willMove", n)
        case .moved(let n):      return self("status.moved", n)
        case .auRestored(let n): return self("status.auRestored", n)
        case .failed(let error): return self("status.failed", error)
        }
    }

    func flStatus(_ status: FLStatus) -> String {
        switch status {
        case .idle:                         return ""
        case .done(let shots, let cards):   return self("fl.done", shots, cards)
        case .removed(let n):               return self("fl.removed", n)
        case .failed(let error):            return self("status.failed", error)
        }
    }

    func managerStatus(_ status: ManagerStatus) -> String {
        switch status {
        case .idle:                          return ""
        case .checked(let ok, let w, let f): return self("mgr.checked", ok, w, f)
        case .trashed(let n):                return self("mgr.trashed", n)
        case .toggled(let disabled, let n):  return self(disabled ? "mgr.turnedOff" : "mgr.turnedOn", n)
        case .fixed:                         return self("mgr.fixed")
        case .cancelled:                     return self("status.cancelled")
        case .failed(let error):             return self("status.failed", error)
        }
    }

    func fix(_ fix: Fix) -> String {
        switch fix {
        case .unquarantine:
            return self("fix.unquarantine")
        case .relocate(_, let to) where to.pathExtension.lowercased() == PluginFormat.au.fileExtension:
            return self("fix.toComponents")
        case .relocate(_, let to):
            return self("fix.relocate", to.lastPathComponent, to.deletingLastPathComponent().lastPathComponent)
        case .resetAUCache:
            return self("fix.resetAU")
        }
    }

    func favoritesStatus(_ status: FavoritesStatus) -> String {
        switch status {
        case .idle:               return ""
        case .removed(let n):     return self("fav.status.removed", n)
        case .restored(let n):    return self("fav.status.restored", n)
        case .sorted(let n):      return self("fav.status.sorted", n)
        case .unsorted(let n):    return self("fav.status.unsorted", n)
        case .failed(let error):  return self("status.failed", error)
        }
    }

    func issue(_ issue: Issue) -> String {
        switch issue {
        case .noBinary:                 return self("issue.noBinary")
        case .wrongArch(let archs):     return self("issue.wrongArch", archs.joined(separator: ", "), PluginInventory.hostArch)
        case .rosetta:                  return self("issue.rosetta")
        case .quarantined:              return self("issue.quarantined")
        case .notRegistered:            return self("issue.notRegistered")
        case .validationFailed(let why): return self("issue.validation", why)
        case .loadFailed(let why):      return self("issue.load", why)
        case .timeout:                  return self("issue.timeout")
        }
    }

    func note(_ note: Note) -> String {
        switch note.kind {
        case .waves:    return self("note.waves", note.text)
        case .kept:     return self("note.kept", note.text)
        case .unknown:  return self("note.unknown", note.text)
        case .exists:   return self("note.exists", note.text)
        case .restored: return self("note.restored", note.text)
        case .skipped:  return self("note.skipped", note.text)
        case .other:    return note.text
        }
    }

    /// Filled one entry per statement: as a single dictionary literal it got slow enough to type-check
    /// that CI's compiler could give up on it.
    private static let table: [String: [Lang: String]] = {
        var t: [String: [Lang: String]] = [:]
        t["subtitle"] = [
            .en: "Sorts your plugins into developer folders",
            .ru: "Раскладывает плагины по папкам разработчиков",
            .uk: "Розкладає плагіни по теках розробників",
            .de: "Sortiert Plugins in Herstellerordner",
        ]
        t["fav.status.removed"] = [.en: "Removed from favourites: %d", .ru: "Убрано из избранного: %d", .uk: "Прибрано з обраного: %d", .de: "Aus Favoriten entfernt: %d"]
        t["fav.status.restored"] = [.en: "Put back: %d", .ru: "Возвращено: %d", .uk: "Повернено: %d", .de: "Zurückgeholt: %d"]
        t["fav.status.sorted"] = [
            .en: "Sorted into categories: %d. Restart FL Studio",
            .ru: "Разложено по категориям: %d. Перезапустите FL Studio",
            .uk: "Розкладено за категоріями: %d. Перезапустіть FL Studio",
            .de: "In Kategorien sortiert: %d. Starte FL Studio neu",
        ]
        t["fav.status.unsorted"] = [.en: "Back where they were: %d", .ru: "Возвращено на место: %d", .uk: "Повернено на місце: %d", .de: "Zurück an alter Stelle: %d"]
        t["fav.reading"] = [.en: "Reading categories", .ru: "Читаю категории", .uk: "Читаю категорії", .de: "Lese Kategorien"]
        t["fav.noCategory"] = [.en: "No category", .ru: "Без категории", .uk: "Без категорії", .de: "Ohne Kategorie"]
        t["main.search"] = [.en: "Find a plugin", .ru: "Найти плагин", .uk: "Знайти плагін", .de: "Plugin suchen"]
        t["view.list"] = [.en: "List", .ru: "Список", .uk: "Список", .de: "Liste"]
        t["view.cards"] = [.en: "Cards", .ru: "Карточки", .uk: "Картки", .de: "Karten"]
        t["filter.all"] = [.en: "All", .ru: "Все", .uk: "Усі", .de: "Alle"]
        t["filter.problems"] = [.en: "Problems", .ru: "Проблемы", .uk: "Проблеми", .de: "Probleme"]
        t["filter.notInFL"] = [.en: "Not in FL", .ru: "Не в FL", .uk: "Не в FL", .de: "Nicht in FL"]
        t["filter.new"] = [.en: "New", .ru: "Новые", .uk: "Нові", .de: "Neu"]
        t["filter.disabled"] = [.en: "Off", .ru: "Выключены", .uk: "Вимкнені", .de: "Aus"]
        t["filter.duplicates"] = [.en: "Duplicates", .ru: "Дубли", .uk: "Дублі", .de: "Duplikate"]
        t["col.plugin"] = [.en: "Plugin", .ru: "Плагин", .uk: "Плагін", .de: "Plugin"]
        t["col.formats"] = [.en: "Formats", .ru: "Форматы", .uk: "Формати", .de: "Formate"]
        t["col.category"] = [.en: "FL category", .ru: "Категория FL", .uk: "Категорія FL", .de: "FL-Kategorie"]
        t["col.size"] = [.en: "Size", .ru: "Размер", .uk: "Розмір", .de: "Größe"]
        t["main.checking"] = [.en: "Checking %d of %d · %@", .ru: "Проверяю %d из %d · %@", .uk: "Перевіряю %d з %d · %@", .de: "Prüfe %d von %d · %@"]
        t["main.empty"] = [.en: "Nothing here", .ru: "Здесь пусто", .uk: "Тут порожньо", .de: "Nichts hier"]
        t["row.notSeen"] = [
            .en: "FL hasn't seen this plugin yet — refresh the plugin list in FL",
            .ru: "FL ещё не видел этот плагин — обновите список плагинов в FL",
            .uk: "FL ще не бачив цей плагін — оновіть список плагінів у FL",
            .de: "FL kennt dieses Plugin noch nicht — aktualisiere die Plugin-Liste in FL",
        ]
        t["row.addFavorite"] = [.en: "Add to FL favourites", .ru: "Добавить в избранное FL", .uk: "Додати в обране FL", .de: "Zu FL-Favoriten hinzufügen"]
        t["row.removeFavorite"] = [.en: "Remove from FL favourites", .ru: "Убрать из избранного FL", .uk: "Прибрати з обраного FL", .de: "Aus FL-Favoriten entfernen"]
        t["row.recheck"] = [.en: "Check again", .ru: "Проверить ещё раз", .uk: "Перевірити ще раз", .de: "Erneut prüfen"]
        t["row.stale"] = [
            .en: "Deleted, but still in FL's favourites",
            .ru: "Удалён, но остался в избранном FL",
            .uk: "Видалений, але залишився в обраному FL",
            .de: "Gelöscht, aber noch in den FL-Favoriten",
        ]
        t["row.removeFromFL"] = [.en: "Remove from FL", .ru: "Убрать из FL", .uk: "Прибрати з FL", .de: "Aus FL entfernen"]
        t["row.picture"] = [.en: "Picture in FL", .ru: "Картинка в FL", .uk: "Картинка в FL", .de: "Bild in FL"]
        t["row.dropHint"] = [.en: "Drop an image here", .ru: "Перетащите картинку сюда", .uk: "Перетягніть картинку сюди", .de: "Bild hierher ziehen"]
        t["row.inFL"] = [.en: "In FL", .ru: "В FL", .uk: "У FL", .de: "In FL"]
        t["row.formatsHint"] = [
            .en: "Click a format to add or remove it in FL's favourites",
            .ru: "Клик по формату добавляет его в избранное FL или убирает",
            .uk: "Клік по формату додає його в обране FL або прибирає",
            .de: "Ein Klick auf ein Format nimmt es in die FL-Favoriten auf oder entfernt es",
        ]
        t["task.folders"] = [.en: "Plugin folders", .ru: "Папки плагинов", .uk: "Папки плагінів", .de: "Plugin-Ordner"]
        t["task.folders.left"] = [
            .en: "%d outside developer folders", .ru: "%d лежат вне папок разработчиков",
            .uk: "%d лежать поза папками розробників", .de: "%d außerhalb der Herstellerordner",
        ]
        t["task.categories"] = [.en: "Categories in FL", .ru: "Категории в FL", .uk: "Категорії в FL", .de: "Kategorien in FL"]
        t["task.categories.left"] = [
            .en: "%d favourites without a category", .ru: "%d в избранном без категории",
            .uk: "%d в обраному без категорії", .de: "%d Favoriten ohne Kategorie",
        ]
        t["task.pictures"] = [.en: "Pictures in FL", .ru: "Картинки в FL", .uk: "Картинки в FL", .de: "Bilder in FL"]
        t["task.pictures.left"] = [
            .en: "%d plugins without a picture", .ru: "%d плагинов без картинки",
            .uk: "%d плагінів без картинки", .de: "%d Plugins ohne Bild",
        ]
        t["task.sort"] = [.en: "Sort", .ru: "Разложить", .uk: "Розкласти", .de: "Sortieren"]
        t["task.add"] = [.en: "Add", .ru: "Добавить", .uk: "Додати", .de: "Hinzufügen"]
        t["task.done"] = [.en: "All done", .ru: "Готово", .uk: "Готово", .de: "Erledigt"]
        t["task.allDone"] = [.en: "All tasks done", .ru: "Все задания выполнены", .uk: "Усі завдання виконано", .de: "Alle Aufgaben erledigt"]
        t["task.expand"] = [.en: "Show tasks", .ru: "Показать задания", .uk: "Показати завдання", .de: "Aufgaben einblenden"]
        t["task.collapse"] = [.en: "Hide tasks", .ru: "Скрыть задания", .uk: "Сховати завдання", .de: "Aufgaben ausblenden"]
        t["task.undo"] = [.en: "Undo", .ru: "Отменить", .uk: "Скасувати", .de: "Rückgängig"]
        t["sheet.title"] = [
            .en: "Sort plugin folders by developer", .ru: "Разложить плагины по папкам разработчиков",
            .uk: "Розкласти плагіни по папках розробників", .de: "Plugins nach Hersteller in Ordner sortieren",
        ]
        t["sheet.subtitle"] = [
            .en: "These plugins move into their developer's folder. You can undo it at any time.",
            .ru: "Эти плагины переедут в папки своих разработчиков. Откатить можно в любой момент.",
            .uk: "Ці плагіни переїдуть у папки своїх розробників. Скасувати можна будь-коли.",
            .de: "Diese Plugins kommen in den Ordner ihres Herstellers. Das lässt sich jederzeit rückgängig machen.",
        ]
        t["sheet.empty"] = [
            .en: "Every plugin is already in its developer's folder.", .ru: "Все плагины уже лежат в папках разработчиков.",
            .uk: "Усі плагіни вже лежать у папках розробників.", .de: "Alle Plugins liegen schon im Ordner ihres Herstellers.",
        ]
        t["banner.close"] = [.en: "Close", .ru: "Закрыть", .uk: "Закрити", .de: "Schließen"]
        t["flOpen.title"] = [.en: "FL Studio is open", .ru: "FL Studio открыт", .uk: "FL Studio відкритий", .de: "FL Studio ist geöffnet"]
        t["flOpen.text"] = [
            .en: "Changes show up after FL restarts, and when FL closes it may overwrite the favourites.",
            .ru: "Изменения появятся после его перезапуска, а при закрытии FL может перезаписать избранное.",
            .uk: "Зміни з'являться після його перезапуску, а під час закриття FL може перезаписати обране.",
            .de: "Die Änderungen erscheinen nach einem Neustart von FL, und beim Beenden kann FL die Favoriten überschreiben.",
        ]
        t["flOpen.continue"] = [.en: "Continue anyway", .ru: "Всё равно продолжить", .uk: "Однаково продовжити", .de: "Trotzdem fortfahren"]
        t["flOpen.dontAsk"] = [
            .en: "Don't ask again until Plugin Sorter restarts", .ru: "Больше не спрашивать до перезапуска Plugin Sorter",
            .uk: "Більше не питати до перезапуску Plugin Sorter", .de: "Bis zum Neustart von Plugin Sorter nicht mehr fragen",
        ]
        t["gear.recheck"] = [.en: "Check all plugins again", .ru: "Проверить все плагины заново", .uk: "Перевірити всі плагіни заново", .de: "Alle Plugins neu prüfen"]
        t["gear.restore"] = [.en: "Put back favourites removed from FL", .ru: "Вернуть убранное из избранного FL", .uk: "Повернути прибране з обраного FL", .de: "Aus FL entfernte Favoriten zurückholen"]
        t["gear.settings"] = [.en: "Settings…", .ru: "Настройки…", .uk: "Налаштування…", .de: "Einstellungen…"]
        t["settings.language"] = [.en: "Language", .ru: "Язык", .uk: "Мова", .de: "Sprache"]
        t["settings.skin"] = [.en: "Skin", .ru: "Скин", .uk: "Скін", .de: "Skin"]
        t["skin.violet"] = [.en: "Violet", .ru: "Фиолетовый", .uk: "Фіолетовий", .de: "Violett"]
        t["skin.mint"] = [.en: "Mint", .ru: "Мятный", .uk: "М'ятний", .de: "Minze"]
        t["skin.amber"] = [.en: "Amber", .ru: "Янтарный", .uk: "Бурштиновий", .de: "Bernstein"]
        t["skin.ice"] = [.en: "Ice", .ru: "Ледяной", .uk: "Крижаний", .de: "Eis"]
        t["mgr.checking"] = [.en: "Checking", .ru: "Проверяю", .uk: "Перевіряю", .de: "Prüfe"]
        t["mgr.trash"] = [.en: "Move to Trash", .ru: "В Корзину", .uk: "У Кошик", .de: "In den Papierkorb"]
        t["mgr.reveal"] = [.en: "Show in Finder", .ru: "Показать в Finder", .uk: "Показати у Finder", .de: "Im Finder zeigen"]
        t["mgr.cancel"] = [.en: "Cancel", .ru: "Отмена", .uk: "Скасувати", .de: "Abbrechen"]
        t["mgr.confirm"] = [
            .en: "Move “%@” to the Trash?",
            .ru: "Переместить «%@» в Корзину?",
            .uk: "Перемістити «%@» у Кошик?",
            .de: "„%@“ in den Papierkorb legen?",
        ]
        t["mgr.confirmInfo"] = [
            .en: "These files will be moved to the Trash:",
            .ru: "В Корзину будут перемещены файлы:",
            .uk: "У Кошик буде переміщено файли:",
            .de: "Diese Dateien werden in den Papierkorb gelegt:",
        ]
        t["mgr.unchecked"] = [.en: "Not checked", .ru: "Не проверен", .uk: "Не перевірено", .de: "Nicht geprüft"]
        t["mgr.works"] = [.en: "Works", .ru: "Работает", .uk: "Працює", .de: "Funktioniert"]
        t["mgr.checked"] = [
            .en: "Working: %d · warnings: %d · problems: %d",
            .ru: "Работают: %d · предупреждений: %d · проблем: %d",
            .uk: "Працюють: %d · попереджень: %d · проблем: %d",
            .de: "OK: %d · Warnungen: %d · Probleme: %d",
        ]
        t["mgr.trashed"] = [.en: "Moved to Trash: %d", .ru: "В Корзине: %d", .uk: "У Кошику: %d", .de: "Im Papierkorb: %d"]
        t["mgr.vendorData"] = [
            .en: "Developer data: presets, libraries — not deleted with the plugin",
            .ru: "Данные разработчика: пресеты, библиотеки — не удаляются вместе с плагином",
            .uk: "Дані розробника: пресети, бібліотеки — не видаляються разом із плагіном",
            .de: "Herstellerdaten: Presets, Bibliotheken — werden nicht mit dem Plugin gelöscht",
        ]
        t["mgr.turnedOff"] = [.en: "Turned off: %d", .ru: "Выключено: %d", .uk: "Вимкнено: %d", .de: "Ausgeschaltet: %d"]
        t["mgr.turnedOn"] = [.en: "Turned on: %d", .ru: "Включено: %d", .uk: "Увімкнено: %d", .de: "Eingeschaltet: %d"]
        t["row.disable"] = [.en: "Turn off", .ru: "Выключить", .uk: "Вимкнути", .de: "Ausschalten"]
        t["row.enable"] = [.en: "Turn on", .ru: "Включить", .uk: "Увімкнути", .de: "Einschalten"]
        t["row.disableInfo"] = [
            .en: "Projects that use this plugin will open without it until you turn it on again. Nothing is deleted.",
            .ru: "Проекты с этим плагином будут открываться без него, пока вы его не включите. Ничего не удаляется.",
            .uk: "Проєкти з цим плагіном відкриватимуться без нього, доки ви його не ввімкнете. Нічого не видаляється.",
            .de: "Projekte mit diesem Plugin öffnen sich ohne es, bis du es wieder einschaltest. Nichts wird gelöscht.",
        ]
        t["row.disabledNote"] = [
            .en: "Turned off: hosts don't see this plugin. Its files wait in the Disabled folder.",
            .ru: "Выключен: программы не видят этот плагин. Файлы лежат в папке Disabled.",
            .uk: "Вимкнено: програми не бачать цей плагін. Файли лежать у теці Disabled.",
            .de: "Ausgeschaltet: Hosts sehen dieses Plugin nicht. Die Dateien liegen im Ordner Disabled.",
        ]
        t["cleanup.found"] = [
            .en: "Found %d · %@ can be freed", .ru: "Найдено: %d · можно освободить %@",
            .uk: "Знайдено: %d · можна звільнити %@", .de: "Gefunden: %d · %@ lassen sich freigeben",
        ]
        t["cleanup.review"] = [.en: "Review", .ru: "Посмотреть", .uk: "Переглянути", .de: "Ansehen"]
        t["cleanup.title"] = [.en: "Old versions and duplicates", .ru: "Старые версии и дубли", .uk: "Старі версії та дублі", .de: "Alte Versionen und Duplikate"]
        t["cleanup.subtitle"] = [
            .en: "Only suggestions: nothing is ticked until you choose.",
            .ru: "Только предложения: пока вы не выберете, ничего не отмечено.",
            .uk: "Лише пропозиції: доки ви не оберете, нічого не позначено.",
            .de: "Nur Vorschläge: Nichts ist angekreuzt, bis du wählst.",
        ]
        t["cleanup.empty"] = [.en: "Nothing to clean up", .ru: "Чистить нечего", .uk: "Нічого чистити", .de: "Nichts aufzuräumen"]
        t["cleanup.older"] = [.en: "Older versions", .ru: "Старые версии", .uk: "Старі версії", .de: "Ältere Versionen"]
        t["cleanup.copies"] = [.en: "Extra copies", .ru: "Лишние копии", .uk: "Зайві копії", .de: "Überzählige Kopien"]
        t["cleanup.vst2"] = [.en: "VST2 next to VST3", .ru: "VST2 рядом с VST3", .uk: "VST2 поруч із VST3", .de: "VST2 neben VST3"]
        t["cleanup.newer"] = [.en: "Newer version: %@", .ru: "Новая версия: %@", .uk: "Нова версія: %@", .de: "Neuere Version: %@"]
        t["cleanup.inFL"] = [.en: "In FL favourites", .ru: "Есть в избранном FL", .uk: "Є в обраному FL", .de: "In FL-Favoriten"]
        t["cleanup.selected"] = [
            .en: "Selected: %d · %@", .ru: "Отмечено: %d · %@", .uk: "Позначено: %d · %@", .de: "Gewählt: %d · %@",
        ]
        t["cleanup.confirm"] = [
            .en: "Move %d to the Trash?", .ru: "Переместить в Корзину: %d?",
            .uk: "Перемістити у Кошик: %d?", .de: "%d in den Papierkorb legen?",
        ]
        t["cleanup.confirmInfo"] = [
            .en: "Old projects open only with the version you keep, and projects that use a removed one will miss it. These files go to the Trash:",
            .ru: "Старые проекты откроются только с версией, которую вы оставите, а проектам с удалённой версией её будет не хватать. В Корзину уйдут файлы:",
            .uk: "Старі проєкти відкриються лише з версією, яку ви залишите, а проєктам із видаленою версією її бракуватиме. У Кошик підуть файли:",
            .de: "Alte Projekte öffnen sich nur mit der Version, die du behältst; Projekte mit einer entfernten Version vermissen sie. Diese Dateien kommen in den Papierkorb:",
        ]
        t["mgr.fixed"] = [.en: "Fixed, checking again", .ru: "Исправлено, проверяю заново", .uk: "Виправлено, перевіряю знову", .de: "Behoben, prüfe erneut"]
        t["fix.unquarantine"] = [.en: "Remove quarantine", .ru: "Снять карантин", .uk: "Зняти карантин", .de: "Quarantäne aufheben"]
        t["fix.toComponents"] = [.en: "Move back to Components", .ru: "Вернуть в Components", .uk: "Повернути в Components", .de: "Zurück nach Components"]
        t["fix.relocate"] = [.en: "Put %@ back in %@", .ru: "Вернуть %@ в %@", .uk: "Повернути %@ у %@", .de: "%@ zurück nach %@"]
        t["fix.resetAU"] = [.en: "Reset AU cache", .ru: "Сбросить кеш AU", .uk: "Скинути кеш AU", .de: "AU-Cache zurücksetzen"]
        t["issue.noBinary"] = [
            .en: "The plugin's binary is missing",
            .ru: "Нет исполняемого файла плагина",
            .uk: "Немає виконуваного файлу плагіна",
            .de: "Die Plugin-Binärdatei fehlt",
        ]
        t["issue.wrongArch"] = [
            .en: "Built for %@ only, this Mac is %@",
            .ru: "Собран только под %@, а этот Mac — %@",
            .uk: "Зібраний лише під %@, а цей Mac — %@",
            .de: "Nur für %@ gebaut, dieser Mac ist %@",
        ]
        t["issue.rosetta"] = [
            .en: "Intel only: works just in hosts running under Rosetta",
            .ru: "Только Intel: работает лишь в DAW, запущенных через Rosetta",
            .uk: "Лише Intel: працює тільки в DAW, запущених через Rosetta",
            .de: "Nur Intel: läuft nur in Hosts unter Rosetta",
        ]
        t["issue.quarantined"] = [
            .en: "Quarantined: macOS may block it",
            .ru: "В карантине: macOS может его заблокировать",
            .uk: "У карантині: macOS може його заблокувати",
            .de: "In Quarantäne: macOS blockiert es möglicherweise",
        ]
        t["issue.notRegistered"] = [
            .en: "Not registered by macOS: an AU must sit directly in Components",
            .ru: "macOS его не видит: AU должен лежать прямо в Components",
            .uk: "macOS його не бачить: AU має лежати прямо в Components",
            .de: "Von macOS nicht registriert: Eine AU muss direkt in Components liegen",
        ]
        t["issue.validation"] = [.en: "auval: %@", .ru: "auval: %@", .uk: "auval: %@", .de: "auval: %@"]
        t["issue.load"] = [
            .en: "Doesn't load: %@",
            .ru: "Не загружается: %@",
            .uk: "Не завантажується: %@",
            .de: "Lädt nicht: %@",
        ]
        t["issue.timeout"] = [
            .en: "Hung during the check",
            .ru: "Завис во время проверки",
            .uk: "Завис під час перевірки",
            .de: "Hing während der Prüfung",
        ]
        t["fl.capturing"] = [.en: "Capturing", .ru: "Снимаю", .uk: "Знімаю", .de: "Aufnahme"]
        t["fl.retake"] = [.en: "Retake screenshot", .ru: "Переснять скриншот", .uk: "Перезняти скриншот", .de: "Screenshot neu aufnehmen"]
        t["fl.useCard"] = [.en: "Use a card", .ru: "Сделать карточку", .uk: "Зробити картку", .de: "Karte verwenden"]
        t["fl.choose"] = [.en: "Choose image…", .ru: "Выбрать картинку…", .uk: "Вибрати картинку…", .de: "Bild wählen…"]
        t["fl.remove"] = [.en: "Remove picture", .ru: "Удалить картинку", .uk: "Видалити картинку", .de: "Bild entfernen"]
        t["fl.done"] = [
            .en: "Screenshots: %d · cards: %d",
            .ru: "Скриншотов: %d · карточек: %d",
            .uk: "Скриншотів: %d · карток: %d",
            .de: "Screenshots: %d · Karten: %d",
        ]
        t["fl.restart"] = [
            .en: "Restart FL Studio to see the pictures in the browser.",
            .ru: "Перезапустите FL Studio, чтобы картинки появились в браузере.",
            .uk: "Перезапустіть FL Studio, щоб картинки з'явилися в браузері.",
            .de: "Starte FL Studio neu, um die Bilder im Browser zu sehen.",
        ]
        t["fl.removed"] = [.en: "Removed: %d", .ru: "Удалено: %d", .uk: "Видалено: %d", .de: "Entfernt: %d"]
        t["status.noFormats"] = [
            .en: "Select at least one format",
            .ru: "Выберите хотя бы один формат",
            .uk: "Оберіть хоча б один формат",
            .de: "Mindestens ein Format wählen",
        ]
        t["status.undone"] = [.en: "Undo complete", .ru: "Откат выполнен", .uk: "Скасовано", .de: "Rückgängig gemacht"]
        t["status.cancelled"] = [.en: "Cancelled", .ru: "Отменено", .uk: "Скасовано", .de: "Abgebrochen"]
        t["status.willMove"] = [
            .en: "To move: %d",
            .ru: "К перемещению: %d",
            .uk: "До переміщення: %d",
            .de: "Zu verschieben: %d",
        ]
        t["status.moved"] = [.en: "Moved: %d", .ru: "Перемещено: %d", .uk: "Переміщено: %d", .de: "Verschoben: %d"]
        t["status.auRestored"] = [
            .en: "AU restored: %d",
            .ru: "AU возвращено: %d",
            .uk: "AU повернено: %d",
            .de: "AU wiederhergestellt: %d",
        ]
        t["status.failed"] = [.en: "Error: %@", .ru: "Ошибка: %@", .uk: "Помилка: %@", .de: "Fehler: %@"]
        t["note.kept"] = [
            .en: "Kept in place (another plugin needs it): %@",
            .ru: "Оставлен на месте (нужен другому плагину): %@",
            .uk: "Залишено на місці (потрібен іншому плагіну): %@",
            .de: "Bleibt an Ort und Stelle (wird von einem anderen Plugin benötigt): %@",
        ]
        t["note.waves"] = [
            .en: "Skipped (Waves): %@",
            .ru: "Пропущен (Waves): %@",
            .uk: "Пропущено (Waves): %@",
            .de: "Übersprungen (Waves): %@",
        ]
        t["note.unknown"] = [
            .en: "Unknown developer: %@",
            .ru: "Неизвестный разработчик: %@",
            .uk: "Невідомий розробник: %@",
            .de: "Unbekannter Hersteller: %@",
        ]
        t["note.exists"] = [
            .en: "Already exists: %@",
            .ru: "Уже существует: %@",
            .uk: "Вже існує: %@",
            .de: "Existiert bereits: %@",
        ]
        t["note.restored"] = [
            .en: "Restored: %@",
            .ru: "Возвращён: %@",
            .uk: "Повернено: %@",
            .de: "Wiederhergestellt: %@",
        ]
        t["note.skipped"] = [
            .en: "Not restored: %@",
            .ru: "Не возвращён: %@",
            .uk: "Не повернено: %@",
            .de: "Nicht wiederhergestellt: %@",
        ]
        return t
    }()
}
