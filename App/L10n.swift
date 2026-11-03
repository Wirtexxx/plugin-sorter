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

    private static let table: [String: [Lang: String]] = [
        "subtitle": [
            .en: "Sorts your plugins into developer folders",
            .ru: "Раскладывает плагины по папкам разработчиков",
            .uk: "Розкладає плагіни по теках розробників",
            .de: "Sortiert Plugins in Herstellerordner",
        ],
        "tab.sorter": [.en: "Sorter", .ru: "Сортировка", .uk: "Сортування", .de: "Sortieren"],
        "fl.mode.pictures": [.en: "Pictures", .ru: "Картинки", .uk: "Картинки", .de: "Bilder"],
        "fl.mode.favorites": [.en: "Favourites", .ru: "Избранное", .uk: "Обране", .de: "Favoriten"],
        "fav.title": [.en: "FL Studio favourites", .ru: "Избранное FL Studio", .uk: "Обране FL Studio", .de: "FL-Studio-Favoriten"],
        "fav.hint": [
            .en: "Star the plugins you want in FL's browser and plugin picker; format chips pick VST3, AU or CLAP. Removed favourites are kept and can be put back. Restart FL Studio to see changes.",
            .ru: "Отметьте звездой плагины, которые нужны в браузере и плагин-пикере FL; чипы форматов выбирают VST3, AU или CLAP. Убранное избранное сохраняется, его можно вернуть. Перезапустите FL Studio, чтобы увидеть изменения.",
            .uk: "Позначте зірочкою плагіни, потрібні в браузері та плагін-пікері FL; чипи форматів обирають VST3, AU чи CLAP. Прибране обране зберігається, його можна повернути. Перезапустіть FL Studio, щоб побачити зміни.",
            .de: "Markiere die Plugins mit einem Stern, die im FL-Browser und Plugin-Picker erscheinen sollen; die Format-Chips wählen VST3, AU oder CLAP. Entfernte Favoriten werden aufbewahrt und lassen sich zurückholen. Starte FL Studio neu, um die Änderungen zu sehen.",
        ],
        "fav.favorites": [.en: "Favourites", .ru: "В избранном", .uk: "В обраному", .de: "Favoriten"],
        "fav.installed": [.en: "Scanned", .ru: "Найдено FL", .uk: "Знайдено FL", .de: "Gescannt"],
        "fav.removedCount": [.en: "Deleted", .ru: "Удалённые", .uk: "Видалені", .de: "Gelöscht"],
        "fav.stale": [
            .en: "%d deleted plugins are still in favourites",
            .ru: "Удалённых плагинов в избранном: %d",
            .uk: "Видалених плагінів в обраному: %d",
            .de: "%d gelöschte Plugins sind noch Favoriten",
        ],
        "fav.removeStale": [.en: "Remove them", .ru: "Убрать их", .uk: "Прибрати їх", .de: "Entfernen"],
        "fav.onlyFavorites": [.en: "Favourites only", .ru: "Только избранное", .uk: "Лише обране", .de: "Nur Favoriten"],
        "fav.restore": [.en: "Put back removed", .ru: "Вернуть убранные", .uk: "Повернути прибрані", .de: "Entfernte zurück"],
        "fav.effect": [.en: "Effect", .ru: "Эффект", .uk: "Ефект", .de: "Effekt"],
        "fav.generator": [.en: "Instrument", .ru: "Инструмент", .uk: "Інструмент", .de: "Instrument"],
        "fav.status.removed": [.en: "Removed from favourites: %d", .ru: "Убрано из избранного: %d", .uk: "Прибрано з обраного: %d", .de: "Aus Favoriten entfernt: %d"],
        "fav.status.restored": [.en: "Put back: %d", .ru: "Возвращено: %d", .uk: "Повернено: %d", .de: "Zurückgeholt: %d"],
        "badge.removed": [.en: "Deleted", .ru: "Удалён", .uk: "Видалено", .de: "Gelöscht"],
        "badge.moved": [.en: "Moved", .ru: "Перенесён", .uk: "Перенесено", .de: "Verschoben"],
        "settings.language": [.en: "Language", .ru: "Язык", .uk: "Мова", .de: "Sprache"],
        "settings.skin": [.en: "Skin", .ru: "Скин", .uk: "Скін", .de: "Skin"],
        "skin.violet": [.en: "Violet", .ru: "Фиолетовый", .uk: "Фіолетовий", .de: "Violett"],
        "skin.mint": [.en: "Mint", .ru: "Мятный", .uk: "М'ятний", .de: "Minze"],
        "skin.amber": [.en: "Amber", .ru: "Янтарный", .uk: "Бурштиновий", .de: "Bernstein"],
        "skin.ice": [.en: "Ice", .ru: "Ледяной", .uk: "Крижаний", .de: "Eis"],
        "tab.fl": [.en: "FL Studio", .ru: "FL Studio", .uk: "FL Studio", .de: "FL Studio"],
        "tab.manager": [.en: "Manager", .ru: "Менеджер", .uk: "Менеджер", .de: "Manager"],
        "mgr.title": [
            .en: "Check and remove plugins",
            .ru: "Проверка и удаление плагинов",
            .uk: "Перевірка та видалення плагінів",
            .de: "Plugins prüfen und entfernen",
        ],
        "mgr.hint": [
            .en: "Audio Units are checked with Apple's auval, VST, VST3 and CLAP are test-loaded in a separate process. Click a plugin for details. Deleted plugins go to the Trash.",
            .ru: "Audio Units проверяются утилитой Apple auval, а VST, VST3 и CLAP пробно загружаются в отдельном процессе. Нажмите на плагин, чтобы увидеть подробности. Удалённые плагины попадают в Корзину.",
            .uk: "Audio Units перевіряються утилітою Apple auval, а VST, VST3 і CLAP пробно завантажуються в окремому процесі. Натисніть на плагін, щоб побачити подробиці. Видалені плагіни потрапляють у Кошик.",
            .de: "Audio Units werden mit Apples auval geprüft, VST, VST3 und CLAP in einem eigenen Prozess probehalber geladen. Klicke auf ein Plugin für Details. Gelöschte Plugins landen im Papierkorb.",
        ],
        "mgr.ok": [.en: "Working", .ru: "Работают", .uk: "Працюють", .de: "Funktionieren"],
        "mgr.problems": [.en: "Problems", .ru: "Проблемы", .uk: "Проблеми", .de: "Probleme"],
        "mgr.search": [.en: "Search", .ru: "Поиск", .uk: "Пошук", .de: "Suchen"],
        "mgr.onlyProblems": [.en: "Problems only", .ru: "Только проблемные", .uk: "Лише проблемні", .de: "Nur Probleme"],
        "mgr.checkAll": [.en: "Check all", .ru: "Проверить все", .uk: "Перевірити всі", .de: "Alle prüfen"],
        "mgr.check": [.en: "Check", .ru: "Проверить", .uk: "Перевірити", .de: "Prüfen"],
        "mgr.checking": [.en: "Checking", .ru: "Проверяю", .uk: "Перевіряю", .de: "Prüfe"],
        "mgr.trash": [.en: "Move to Trash", .ru: "В Корзину", .uk: "У Кошик", .de: "In den Papierkorb"],
        "mgr.reveal": [.en: "Show in Finder", .ru: "Показать в Finder", .uk: "Показати у Finder", .de: "Im Finder zeigen"],
        "mgr.cancel": [.en: "Cancel", .ru: "Отмена", .uk: "Скасувати", .de: "Abbrechen"],
        "mgr.confirm": [
            .en: "Move “%@” to the Trash?",
            .ru: "Переместить «%@» в Корзину?",
            .uk: "Перемістити «%@» у Кошик?",
            .de: "„%@“ in den Papierkorb legen?",
        ],
        "mgr.confirmInfo": [
            .en: "These files will be moved to the Trash:",
            .ru: "В Корзину будут перемещены файлы:",
            .uk: "У Кошик буде переміщено файли:",
            .de: "Diese Dateien werden in den Papierkorb gelegt:",
        ],
        "mgr.unchecked": [.en: "Not checked", .ru: "Не проверен", .uk: "Не перевірено", .de: "Nicht geprüft"],
        "mgr.works": [.en: "Works", .ru: "Работает", .uk: "Працює", .de: "Funktioniert"],
        "mgr.checked": [
            .en: "Working: %d · warnings: %d · problems: %d",
            .ru: "Работают: %d · предупреждений: %d · проблем: %d",
            .uk: "Працюють: %d · попереджень: %d · проблем: %d",
            .de: "OK: %d · Warnungen: %d · Probleme: %d",
        ],
        "mgr.trashed": [.en: "Moved to Trash: %d", .ru: "В Корзине: %d", .uk: "У Кошику: %d", .de: "Im Papierkorb: %d"],
        "mgr.bySize": [.en: "By size", .ru: "По размеру", .uk: "За розміром", .de: "Nach Größe"],
        "mgr.onDisk": [.en: "On disk: %@", .ru: "На диске: %@", .uk: "На диску: %@", .de: "Belegt: %@"],
        "mgr.vendorData": [
            .en: "Developer data: presets, libraries — not deleted with the plugin",
            .ru: "Данные разработчика: пресеты, библиотеки — не удаляются вместе с плагином",
            .uk: "Дані розробника: пресети, бібліотеки — не видаляються разом із плагіном",
            .de: "Herstellerdaten: Presets, Bibliotheken — werden nicht mit dem Plugin gelöscht",
        ],
        "mgr.fixed": [.en: "Fixed, checking again", .ru: "Исправлено, проверяю заново", .uk: "Виправлено, перевіряю знову", .de: "Behoben, prüfe erneut"],
        "mgr.canFix": [.en: "This can be fixed", .ru: "Это можно исправить", .uk: "Це можна виправити", .de: "Das lässt sich beheben"],
        "fix.unquarantine": [.en: "Remove quarantine", .ru: "Снять карантин", .uk: "Зняти карантин", .de: "Quarantäne aufheben"],
        "fix.toComponents": [.en: "Move back to Components", .ru: "Вернуть в Components", .uk: "Повернути в Components", .de: "Zurück nach Components"],
        "fix.relocate": [.en: "Put %@ back in %@", .ru: "Вернуть %@ в %@", .uk: "Повернути %@ у %@", .de: "%@ zurück nach %@"],
        "fix.resetAU": [.en: "Reset AU cache", .ru: "Сбросить кеш AU", .uk: "Скинути кеш AU", .de: "AU-Cache zurücksetzen"],
        "fix.resetAUHelp": [
            .en: "Makes macOS rescan Audio Units, e.g. after installing or moving plugins",
            .ru: "macOS заново найдёт Audio Units, например после установки или переноса плагинов",
            .uk: "macOS заново знайде Audio Units, наприклад після встановлення або перенесення плагінів",
            .de: "macOS sucht Audio Units neu, z. B. nach dem Installieren oder Verschieben von Plugins",
        ],
        "issue.noBinary": [
            .en: "The plugin's binary is missing",
            .ru: "Нет исполняемого файла плагина",
            .uk: "Немає виконуваного файлу плагіна",
            .de: "Die Plugin-Binärdatei fehlt",
        ],
        "issue.wrongArch": [
            .en: "Built for %@ only, this Mac is %@",
            .ru: "Собран только под %@, а этот Mac — %@",
            .uk: "Зібраний лише під %@, а цей Mac — %@",
            .de: "Nur für %@ gebaut, dieser Mac ist %@",
        ],
        "issue.rosetta": [
            .en: "Intel only: works just in hosts running under Rosetta",
            .ru: "Только Intel: работает лишь в DAW, запущенных через Rosetta",
            .uk: "Лише Intel: працює тільки в DAW, запущених через Rosetta",
            .de: "Nur Intel: läuft nur in Hosts unter Rosetta",
        ],
        "issue.quarantined": [
            .en: "Quarantined: macOS may block it",
            .ru: "В карантине: macOS может его заблокировать",
            .uk: "У карантині: macOS може його заблокувати",
            .de: "In Quarantäne: macOS blockiert es möglicherweise",
        ],
        "issue.notRegistered": [
            .en: "Not registered by macOS: an AU must sit directly in Components",
            .ru: "macOS его не видит: AU должен лежать прямо в Components",
            .uk: "macOS його не бачить: AU має лежати прямо в Components",
            .de: "Von macOS nicht registriert: Eine AU muss direkt in Components liegen",
        ],
        "issue.validation": [.en: "auval: %@", .ru: "auval: %@", .uk: "auval: %@", .de: "auval: %@"],
        "issue.load": [
            .en: "Doesn't load: %@",
            .ru: "Не загружается: %@",
            .uk: "Не завантажується: %@",
            .de: "Lädt nicht: %@",
        ],
        "issue.timeout": [
            .en: "Hung during the check",
            .ru: "Завис во время проверки",
            .uk: "Завис під час перевірки",
            .de: "Hing während der Prüfung",
        ],
        "fl.title": [
            .en: "Pictures in the FL browser",
            .ru: "Картинки в браузере FL",
            .uk: "Картинки в браузері FL",
            .de: "Bilder im FL-Browser",
        ],
        "fl.hint": [
            .en: "Screenshots come from the AU version of each plugin, plugins that won't open get a card. Drop your own image on any tile or right-click it for more.",
            .ru: "Скриншоты снимаются с AU-версии плагина, а если он не открылся — рисуется карточка. Перетащите свою картинку на любую плитку или нажмите по ней правой кнопкой.",
            .uk: "Скриншоти знімаються з AU-версії плагіна, а якщо він не відкрився — малюється картка. Перетягніть свою картинку на будь-яку плитку або натисніть на неї правою кнопкою.",
            .de: "Screenshots stammen aus der AU-Version jedes Plugins, für Plugins, die sich nicht öffnen, wird eine Karte erstellt. Zieh ein eigenes Bild auf eine Kachel oder klicke sie mit rechts an.",
        ],
        "fl.notFound": [
            .en: "FL Studio plugin database not found in ~/Documents/Image-Line",
            .ru: "База плагинов FL Studio не найдена в ~/Documents/Image-Line",
            .uk: "Базу плагінів FL Studio не знайдено в ~/Documents/Image-Line",
            .de: "FL-Studio-Plugin-Datenbank in ~/Documents/Image-Line nicht gefunden",
        ],
        "fl.withPicture": [.en: "With picture", .ru: "С картинкой", .uk: "З картинкою", .de: "Mit Bild"],
        "fl.missing": [.en: "Without", .ru: "Без картинки", .uk: "Без картинки", .de: "Ohne Bild"],
        "fl.capturing": [.en: "Capturing", .ru: "Снимаю", .uk: "Знімаю", .de: "Aufnahme"],
        "fl.noPicture": [.en: "No picture", .ru: "Нет картинки", .uk: "Немає картинки", .de: "Kein Bild"],
        "fl.showStock": [.en: "FL stock", .ru: "Стоковые FL", .uk: "Стокові FL", .de: "FL-Standard"],
        "fl.generate": [.en: "Add pictures", .ru: "Добавить картинки", .uk: "Додати картинки", .de: "Bilder hinzufügen"],
        "fl.retakeMine": [.en: "Retake mine", .ru: "Переснять мои", .uk: "Перезняти мої", .de: "Meine neu"],
        "fl.removeMine": [.en: "Remove mine", .ru: "Удалить мои", .uk: "Видалити мої", .de: "Meine entfernen"],
        "fl.retake": [.en: "Retake screenshot", .ru: "Переснять скриншот", .uk: "Перезняти скриншот", .de: "Screenshot neu aufnehmen"],
        "fl.useCard": [.en: "Use a card", .ru: "Сделать карточку", .uk: "Зробити картку", .de: "Karte verwenden"],
        "fl.choose": [.en: "Choose image…", .ru: "Выбрать картинку…", .uk: "Вибрати картинку…", .de: "Bild wählen…"],
        "fl.remove": [.en: "Remove picture", .ru: "Удалить картинку", .uk: "Видалити картинку", .de: "Bild entfernen"],
        "fl.done": [
            .en: "Screenshots: %d · cards: %d",
            .ru: "Скриншотов: %d · карточек: %d",
            .uk: "Скриншотів: %d · карток: %d",
            .de: "Screenshots: %d · Karten: %d",
        ],
        "fl.restart": [
            .en: "Restart FL Studio to see the pictures in the browser.",
            .ru: "Перезапустите FL Studio, чтобы картинки появились в браузере.",
            .uk: "Перезапустіть FL Studio, щоб картинки з'явилися в браузері.",
            .de: "Starte FL Studio neu, um die Bilder im Browser zu sehen.",
        ],
        "fl.removed": [.en: "Removed: %d", .ru: "Удалено: %d", .uk: "Видалено: %d", .de: "Entfernt: %d"],
        "badge.screenshot": [.en: "Shot", .ru: "Скрин", .uk: "Скрин", .de: "Shot"],
        "badge.card": [.en: "Card", .ru: "Карточка", .uk: "Картка", .de: "Karte"],
        "badge.custom": [.en: "Custom", .ru: "Своя", .uk: "Своя", .de: "Eigenes"],
        "panel.distribution": [.en: "Distribution", .ru: "Распределение", .uk: "Розподіл", .de: "Verteilung"],
        "meter.plugins": [.en: "Plugins", .ru: "Плагины", .uk: "Плагіни", .de: "Plugins"],
        "meter.vendors": [.en: "Developers", .ru: "Разработчики", .uk: "Розробники", .de: "Hersteller"],
        "meter.formats": [.en: "Formats", .ru: "Форматы", .uk: "Формати", .de: "Formate"],
        "empty.title": [
            .en: "Everything is in order",
            .ru: "Всё уже разложено",
            .uk: "Усе вже розкладено",
            .de: "Alles ist sortiert",
        ],
        "empty.hint": [
            .en: "New plugins will show up here after installation",
            .ru: "Новые плагины появятся здесь после установки",
            .uk: "Нові плагіни з'являться тут після встановлення",
            .de: "Neue Plugins erscheinen hier nach der Installation",
        ],
        "notes": [.en: "Notes (%d)", .ru: "Заметки (%d)", .uk: "Нотатки (%d)", .de: "Hinweise (%d)"],
        "button.undo": [.en: "Undo last", .ru: "Откатить", .uk: "Скасувати", .de: "Rückgängig"],
        "button.refresh": [.en: "Refresh", .ru: "Обновить", .uk: "Оновити", .de: "Aktualisieren"],
        "button.sort": [.en: "Sort", .ru: "Сортировать", .uk: "Сортувати", .de: "Sortieren"],
        "button.done": [.en: "Done", .ru: "Готово", .uk: "Готово", .de: "Fertig"],
        "status.noFormats": [
            .en: "Select at least one format",
            .ru: "Выберите хотя бы один формат",
            .uk: "Оберіть хоча б один формат",
            .de: "Mindestens ein Format wählen",
        ],
        "status.undone": [.en: "Undo complete", .ru: "Откат выполнен", .uk: "Скасовано", .de: "Rückgängig gemacht"],
        "status.cancelled": [.en: "Cancelled", .ru: "Отменено", .uk: "Скасовано", .de: "Abgebrochen"],
        "status.willMove": [
            .en: "To move: %d",
            .ru: "К перемещению: %d",
            .uk: "До переміщення: %d",
            .de: "Zu verschieben: %d",
        ],
        "status.moved": [.en: "Moved: %d", .ru: "Перемещено: %d", .uk: "Переміщено: %d", .de: "Verschoben: %d"],
        "status.auRestored": [
            .en: "AU restored: %d",
            .ru: "AU возвращено: %d",
            .uk: "AU повернено: %d",
            .de: "AU wiederhergestellt: %d",
        ],
        "au.nested": [
            .en: "%d Audio Units are in subfolders. macOS only loads them from the Components folder itself.",
            .ru: "%d Audio Units лежат в подпапках. macOS загружает их только из самой папки Components.",
            .uk: "%d Audio Units лежать у підтеках. macOS завантажує їх лише з самої теки Components.",
            .de: "%d Audio Units liegen in Unterordnern. macOS lädt sie nur direkt aus dem Components-Ordner.",
        ],
        "button.restoreAU": [.en: "Restore AU", .ru: "Вернуть AU", .uk: "Повернути AU", .de: "AU zurück"],
        "status.failed": [.en: "Error: %@", .ru: "Ошибка: %@", .uk: "Помилка: %@", .de: "Fehler: %@"],
        "note.kept": [
            .en: "Kept in place (another plugin needs it): %@",
            .ru: "Оставлен на месте (нужен другому плагину): %@",
            .uk: "Залишено на місці (потрібен іншому плагіну): %@",
            .de: "Bleibt an Ort und Stelle (wird von einem anderen Plugin benötigt): %@",
        ],
        "note.waves": [
            .en: "Skipped (Waves): %@",
            .ru: "Пропущен (Waves): %@",
            .uk: "Пропущено (Waves): %@",
            .de: "Übersprungen (Waves): %@",
        ],
        "note.unknown": [
            .en: "Unknown developer: %@",
            .ru: "Неизвестный разработчик: %@",
            .uk: "Невідомий розробник: %@",
            .de: "Unbekannter Hersteller: %@",
        ],
        "note.exists": [
            .en: "Already exists: %@",
            .ru: "Уже существует: %@",
            .uk: "Вже існує: %@",
            .de: "Existiert bereits: %@",
        ],
        "note.restored": [
            .en: "Restored: %@",
            .ru: "Возвращён: %@",
            .uk: "Повернено: %@",
            .de: "Wiederhergestellt: %@",
        ],
        "note.skipped": [
            .en: "Not restored: %@",
            .ru: "Не возвращён: %@",
            .uk: "Не повернено: %@",
            .de: "Nicht wiederhergestellt: %@",
        ],
    ]
}
