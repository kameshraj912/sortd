import SwiftUI

/// Sortd's look, repeated here because a widget extension is a separate
/// binary and can't reach the app's asset catalog or `Theme.swift`.
///
/// The rule from the app holds: black and grey for everything structural,
/// colour only where it means "this is where money went". Apple's widget
/// guidance pushes the same way — a widget can be shown tinted or
/// desaturated, so nothing may depend on colour alone to be understood.
enum Sortd {

    // MARK: Neutrals — the same values as the app's Theme.swift

    /// Near-black in light, soft off-white in dark. Pure white on near-black
    /// glows and is tiring to read, so the dark side is #E8E8EA.
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.910, green: 0.910, blue: 0.918, alpha: 1)
        : UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1) })

    static let onInk = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .white })

    /// The empty part of a bar.
    static let track = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 0.24, alpha: 1)
            : UIColor(white: 0.90, alpha: 1)
    })

    static let hairline = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1)
            : UIColor(red: 0.918, green: 0.918, blue: 0.945, alpha: 1)
    })

    /// The four dashes under every page title in the app. Sortd's mark.
    static let brandPalette: [Color] = [
        Color(red: 0.941, green: 0.392, blue: 0.239),
        Color(red: 0.961, green: 0.651, blue: 0.137),
        Color(red: 0.482, green: 0.420, blue: 0.941),
        Color(red: 0.169, green: 0.690, blue: 0.478),
    ]

    /// Card fill and page background, matching the app's Theme.swift, so a
    /// widget looks like a piece of Sortd rather than a system tile.
    static let card = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1)
            : .white
    })

    // MARK: Colours resolved against a known scheme
    //
    // `containerBackground` is read outside the view it decorates, so an
    // adaptive colour there ignores a forced Light or Dark and stays on the
    // system setting — which produced a dark widget's text on a white card,
    // i.e. nothing readable at all. These take the scheme explicitly so the
    // background can never disagree with the content sitting on it.

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.118, green: 0.118, blue: 0.129) : .white
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.910, green: 0.910, blue: 0.918)
            : Color(red: 0.086, green: 0.086, blue: 0.102)
    }

    static func onInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func track(_ scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.24 : 0.90)
    }

    // MARK: Category colour — the app's palette, by raw value

    static func color(forCategory raw: String) -> Color {
        switch raw {
        case "foodDelivery":  Color(red: 0.94, green: 0.39, blue: 0.24)
        case "eatingOut":     Color(red: 0.96, green: 0.65, blue: 0.14)
        case "groceries":     Color(red: 0.13, green: 0.63, blue: 0.42)
        case "transport":     Color(red: 0.31, green: 0.66, blue: 0.87)
        case "subscriptions": Color(red: 0.36, green: 0.29, blue: 0.90)
        case "shopping":      Color(red: 0.90, green: 0.34, blue: 0.60)
        case "entertainment": Color(red: 0.69, green: 0.31, blue: 0.85)
        case "housing":       Color(red: 0.62, green: 0.42, blue: 0.29)
        case "bills":         Color(red: 0.83, green: 0.63, blue: 0.09)
        case "health":        Color(red: 0.90, green: 0.28, blue: 0.30)
        case "travel":        Color(red: 0.08, green: 0.72, blue: 0.65)
        case "education":     Color(red: 0.23, green: 0.44, blue: 0.88)
        case "transfers":     Color(red: 0.39, green: 0.45, blue: 0.55)
        default:              Color(red: 0.58, green: 0.64, blue: 0.72)
        }
    }

    /// The same symbol the app draws for each category (`SpendCategory.symbol`
    /// in Kinds.swift). `SortdWidgetThemeTests` fails if the two drift apart.
    static func symbol(forCategory raw: String) -> String {
        switch raw {
        case "foodDelivery":  "takeoutbag.and.cup.and.straw.fill"
        case "eatingOut":     "fork.knife"
        case "groceries":     "cart.fill"
        case "transport":     "car.fill"
        case "subscriptions": "arrow.triangle.2.circlepath"
        case "shopping":      "bag.fill"
        case "entertainment": "ticket.fill"
        case "housing":       "house.fill"
        case "bills":         "bolt.fill"
        case "health":        "cross.case.fill"
        case "travel":        "airplane"
        case "education":     "graduationcap.fill"
        case "transfers":     "arrow.left.arrow.right"
        default:              "square.grid.2x2.fill"
        }
    }

    // MARK: Budget colours

    /// Sortd's green, the fourth dash of the mark. The ring shows what is
    /// left of the budget in this.
    static let brandGreen = brandPalette[3]

    /// The app's "money out" red (`Color.down` in Theme.swift): the ring's
    /// colour once the month is over budget.
    static let over = Color(UIColor { t in
        let high = t.accessibilityContrast == .high
        return t.userInterfaceStyle == .dark
            ? UIColor(red: high ? 1.00 : 0.96, green: high ? 0.56 : 0.45, blue: high ? 0.57 : 0.46, alpha: 1)
            : UIColor(red: high ? 0.64 : 0.741, green: high ? 0.06 : 0.114, blue: high ? 0.09 : 0.153, alpha: 1)
    })

    // MARK: Card style — matches the style chosen in Settings

    /// A quiet two-stop gradient per style, used behind the big numbers so
    /// the widget belongs to the same app as the cards on Home.
    static func gradient(_ style: String) -> LinearGradient {
        let stops: [Color] = switch style {
        case "glow":     [Color(red: 0.26, green: 0.22, blue: 0.62), Color(red: 0.10, green: 0.09, blue: 0.27)]
        case "mono":     [Color(white: 0.22), Color(white: 0.08)]
        case "minimal":  [Color(white: 0.97), Color(white: 0.92)]
        case "graphite": [Color(red: 0.24, green: 0.25, blue: 0.27), Color(red: 0.11, green: 0.12, blue: 0.13)]
        case "silver":   [Color(red: 0.90, green: 0.90, blue: 0.91), Color(red: 0.76, green: 0.77, blue: 0.79)]
        case "midnight": [Color(red: 0.12, green: 0.16, blue: 0.27), Color(red: 0.05, green: 0.07, blue: 0.13)]
        case "sand":     [Color(red: 0.91, green: 0.87, blue: 0.80), Color(red: 0.82, green: 0.76, blue: 0.67)]
        default:         [Color(red: 0.16, green: 0.17, blue: 0.20), Color(red: 0.07, green: 0.07, blue: 0.09)]
        }
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Text that sits on top of that gradient.
    static func onGradient(_ style: String) -> Color {
        switch style {
        case "minimal", "silver", "sand": .black
        default: .white
        }
    }

    // MARK: Money

    /// Apple: avoid text under 11pt, and let big numbers shrink rather than
    /// wrap. Cents are dropped above 100 so the number stays readable.
    static func money(_ value: Decimal, _ code: String, cents: Bool? = nil) -> String {
        let showCents = cents ?? (abs(value) < 100)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = showCents ? 2 : 0
        f.minimumFractionDigits = showCents ? 2 : 0
        return f.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// An amount as VoiceOver should say it: "5.50 Australian dollars", not
    /// "A$5.50" (which reads as "A dollar sign five point five zero").
    static func spoken(_ value: Decimal, _ code: String, cents: Bool? = nil) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        let natural = f.maximumFractionDigits   // 0 for yen, 2 for dollars
        let digits = (cents ?? (abs(value) < 100)) ? natural : 0
        return value.formatted(.currency(code: code).presentation(.fullName).precision(.fractionLength(digits)))
    }

    /// When a purchase happened, for the line under its amount: the time
    /// today, otherwise "Yesterday" or the weekday and day.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// "in 5d", "tomorrow", "today".
    static func countdown(to date: Date, from now: Date = .now,
                          calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return switch days {
        case ..<0: "overdue"
        case 0: "today"
        case 1: "tomorrow"
        case 2...6: "in \(days)d"
        default: "in \(days / 7)w"
        }
    }
}

/// Where a widget tap goes. The app opens straight at the right place
/// rather than dropping people on Home to find it themselves.
enum SortdLink {
    static let add = URL(string: "sortd://add")!
    static let scan = URL(string: "sortd://scan")!
    static let importing = URL(string: "sortd://import")!
    static let home = URL(string: "sortd://home")!
    static let activity = URL(string: "sortd://activity")!
    static let insights = URL(string: "sortd://insights")!
    static let bills = URL(string: "sortd://bills")!
    static let budget = URL(string: "sortd://budget")!

    /// Opens that purchase's detail (Router.follow, "purchase").
    static func purchase(_ id: UUID) -> URL { URL(string: "sortd://purchase/\(id.uuidString)")! }
}
