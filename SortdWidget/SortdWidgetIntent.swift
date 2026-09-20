import AppIntents
import SwiftUI
import WidgetKit

/// What you can change after long-pressing a Sortd widget and tapping
/// "Edit Widget".
///
/// Apple's guidance is to let people configure a widget when the useful
/// content differs per person — the Stocks widget's symbols, the Calendar
/// widget's calendar. Here that's two things: which number you want in front
/// of you, and whether the tile should be light, dark or follow the phone.
///
/// Everything else stays fixed. Options are a cost as well as a feature, and
/// a widget with ten switches is a settings screen with rounded corners.

// MARK: - Look

enum SortdLook: String, AppEnum {
    case auto, light, dark

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Look" }

    static var caseDisplayRepresentations: [SortdLook: DisplayRepresentation] {
        [
            .auto: DisplayRepresentation(title: "Automatic",
                                         subtitle: "Follows your iPhone"),
            .light: DisplayRepresentation(title: "Light", subtitle: "Always white"),
            .dark: DisplayRepresentation(title: "Dark", subtitle: "Always dark"),
        ]
    }

    /// Nil means "leave it to the system", which is what Automatic wants.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Which number

enum SortdPeriod: String, AppEnum {
    case today, week, month

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }

    static var caseDisplayRepresentations: [SortdPeriod: DisplayRepresentation] {
        [
            .today: DisplayRepresentation(title: "Today"),
            .week: DisplayRepresentation(title: "This week"),
            .month: DisplayRepresentation(title: "This month"),
        ]
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .month: "This month"
        }
    }

    func total(_ s: WidgetSummary) -> Decimal {
        switch self {
        case .today: s.today
        case .week: s.week
        case .month: s.month
        }
    }

    /// The limit that number should be read against. Nil when there isn't
    /// one, and then the widget says so rather than inventing a target.
    func limit(_ s: WidgetSummary) -> Decimal? {
        switch self {
        case .today: s.dayAllowance
        case .week: s.dayAllowance.map { $0 * 7 }
        case .month: s.budget
        }
    }
}

// MARK: - Intents

struct SpendingConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Spending" }
    static var description: IntentDescription {
        IntentDescription("Pick which total to show and how the widget looks.")
    }

    @Parameter(title: "Show", default: .today)
    var period: SortdPeriod

    @Parameter(title: "Look", default: .auto)
    var look: SortdLook
}

struct LookConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Appearance" }
    static var description: IntentDescription {
        IntentDescription("Choose how the widget looks.")
    }

    @Parameter(title: "Look", default: .auto)
    var look: SortdLook
}

// MARK: - Timelines

struct SpendingEntry: TimelineEntry {
    var date: Date
    var summary: WidgetSummary?
    var configuration: SpendingConfiguration

    static var sample: SpendingEntry {
        SpendingEntry(date: .now, summary: SortdEntry.sample.summary,
                      configuration: SpendingConfiguration())
    }
}

struct SpendingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry { .sample }

    func snapshot(for configuration: SpendingConfiguration, in context: Context) async -> SpendingEntry {
        context.isPreview
            ? SpendingEntry(date: .now, summary: SortdEntry.sample.summary, configuration: configuration)
            : SpendingEntry(date: .now, summary: WidgetSummary.read(), configuration: configuration)
    }

    func timeline(for configuration: SpendingConfiguration, in context: Context) async -> Timeline<SpendingEntry> {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        let entry = SpendingEntry(date: .now, summary: WidgetSummary.read(), configuration: configuration)
        return Timeline(entries: [entry], policy: .after(midnight))
    }
}

struct LookEntry: TimelineEntry {
    var date: Date
    var summary: WidgetSummary?
    var configuration: LookConfiguration

    static var sample: LookEntry {
        LookEntry(date: .now, summary: SortdEntry.sample.summary, configuration: LookConfiguration())
    }
}

struct LookProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LookEntry { .sample }

    func snapshot(for configuration: LookConfiguration, in context: Context) async -> LookEntry {
        context.isPreview
            ? LookEntry(date: .now, summary: SortdEntry.sample.summary, configuration: configuration)
            : LookEntry(date: .now, summary: WidgetSummary.read(), configuration: configuration)
    }

    func timeline(for configuration: LookConfiguration, in context: Context) async -> Timeline<LookEntry> {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        let entry = LookEntry(date: .now, summary: WidgetSummary.read(), configuration: configuration)
        return Timeline(entries: [entry], policy: .after(midnight))
    }
}
