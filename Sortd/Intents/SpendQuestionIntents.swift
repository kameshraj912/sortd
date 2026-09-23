import AppIntents
import SwiftData

// Questions you can ask Siri or use in Shortcuts. None of them open the app.

/// Time span for "How much have I spent…?".
nonisolated enum SpendPeriodOption: String, AppEnum {
    case today, week, month

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [SpendPeriodOption: DisplayRepresentation] = [
        .today: "today",
        .week: "this week",
        .month: "this month",
    ]

    var period: SpendSummary.Period {
        switch self {
        case .today: .today
        case .week: .week
        case .month: .month
        }
    }
}

/// `SpendCategory` as something Siri and Shortcuts can offer as a choice.
nonisolated enum SpendCategoryOption: String, AppEnum {
    case foodDelivery, eatingOut, groceries, transport, subscriptions, shopping, entertainment
    case housing, bills, health, travel, education, transfers, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let caseDisplayRepresentations: [SpendCategoryOption: DisplayRepresentation] = [
        .foodDelivery: "Food Delivery",
        .eatingOut: "Eating Out",
        .groceries: "Groceries",
        .transport: "Transport",
        .subscriptions: "Subscriptions",
        .shopping: "Shopping",
        .entertainment: "Entertainment",
        .housing: "Rent & Housing",
        .bills: "Bills",
        .health: "Health",
        .travel: "Travel",
        .education: "Education",
        .transfers: "Transfers",
        .other: "Other",
    ]

    var category: SpendCategory { SpendCategory(rawValue: rawValue) ?? .other }
}

/// Shared data access for the question intents.
enum SpendQuestions {
    static var budget: Double { UserDefaults.standard.double(forKey: "monthlyBudget") }

    static func transactions() throws -> [Transaction] {
        let context = SortdStore.container.mainContext
        return try context.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))
    }
}

struct SpentThisPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Have I Spent"
    static let description = IntentDescription(
        "Tells you how much you've spent today, this week or this month, for everything or one category.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false
    // Spending is private: Siri must not answer on a locked phone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Period", default: .month)
    var period: SpendPeriodOption

    @Parameter(title: "Category", description: "Leave empty for all spending.")
    var category: SpendCategoryOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Amount spent \(\.$period)") {
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let purchases = try SpendQuestions.transactions().map(SpendSummary.Purchase.init)
        let answer = SpendSummary.spent(purchases, period: period.period, category: category?.category,
                                        budget: SpendQuestions.budget, currency: Money.home)
        return .result(value: answer.total.double, dialog: "\(answer.text)")
    }
}

struct BudgetLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Budget Left"
    static let description = IntentDescription(
        "Tells you how much of this month's budget is left.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false
    // Spending is private: Siri must not answer on a locked phone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let purchases = try SpendQuestions.transactions().map(SpendSummary.Purchase.init)
        let answer = SpendSummary.budgetLeft(purchases, budget: SpendQuestions.budget, currency: Money.home)
        return .result(value: answer.left.double, dialog: "\(answer.text)")
    }
}

struct UpcomingBillsIntent: AppIntent {
    static let title: LocalizedStringResource = "Upcoming Bills"
    static let description = IntentDescription(
        "Tells you the next 3 repeat payments due in the next 14 days.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false
    // Spending is private: Siri must not answer on a locked phone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Subscriptions & bills is Sortd Pro, in the app and here.
        guard ProStore.shared.isPro else {
            let text = "Upcoming bills are part of Sortd Pro. Open Sortd to see it."
            return .result(value: text, dialog: "\(text)")
        }
        let items = try SpendQuestions.transactions()
        let text = SpendSummary.upcomingBills(items.recurring(), hasPurchases: !items.isEmpty)
        return .result(value: text, dialog: "\(text)")
    }
}

struct LastPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Last Purchase"
    static let description = IntentDescription(
        "Tells you your most recent purchase.",
        categoryName: "Spending"
    )
    static let openAppWhenRun = false
    // Spending is private: Siri must not answer on a locked phone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let purchases = try SpendQuestions.transactions().map(SpendSummary.Purchase.init)
        let text = SpendSummary.lastPurchase(purchases)
        return .result(value: text, dialog: "\(text)")
    }
}
