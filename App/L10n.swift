import Foundation

enum Lang: String, CaseIterable, Identifiable {
    case en, ru, uk, de

    var id: String { rawValue }

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
        case .failed(let error): return self("status.failed", error)
        }
    }

    func note(_ note: Note) -> String {
        switch note.kind {
        case .waves:    return self("note.waves", note.text)
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
        "status.failed": [.en: "Error: %@", .ru: "Ошибка: %@", .uk: "Помилка: %@", .de: "Fehler: %@"],
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
