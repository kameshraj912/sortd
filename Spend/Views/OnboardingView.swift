import SwiftUI
import SwiftData
import UserNotifications

/// First launch: a short guided setup. Everything that can be filled in for
/// the user is (currency from the phone, bank details from a preset list),
/// every step can be skipped, and anything skipped can be done later in
/// Settings. Apple Pay setup checks itself: it turns green on the first tap.
struct OnboardingView: View {
    static let doneKey = "onboardingDone"

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @AppStorage(Money.homeKey) private var home = Money.detectedHome
    @AppStorage("monthlyBudget") private var budget: Double = 0
    @AppStorage(Reminders.enabledKey) private var reminders = false
    @AppStorage(OnboardingView.doneKey) private var done = false

    enum Step: Int, CaseIterable { case welcome, currency, cards, cardDetails, applePay, email, budget, reminders, finish }
    #if DEBUG
    @State private var step: Step = Step(rawValue: Int(ProcessInfo.processInfo.environment["SPEND_ONBOARD_STEP"] ?? "") ?? 0) ?? .welcome
    #else
    @State private var step: Step = .welcome
    #endif
    @State private var forward = true
    @State private var showingGuide = false
    @State private var customBudget = ""
    @State private var showAllBanks = false
    @State private var editing: CardInfo?
    @State private var connectingGmail = false
    @State private var gmail = GmailSync.accounts
    @FocusState private var budgetFocused: Bool

    private var book: CardBook { .shared }
    private var region: String { Locale.current.region?.identifier ?? "AU" }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                page
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .background(Color.page)
        .sheet(item: $editing) { CardEditor(original: $0) }
        .sheet(isPresented: $connectingGmail, onDismiss: { gmail = GmailSync.accounts }) { ConnectGmailSheet() }
        .sheet(isPresented: $showingGuide) {
            NavigationStack { SetupGuideView(isPresentedAsSheet: true) }
        }
        .sensoryFeedback(.selection, trigger: step)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            if step != .welcome && step != .finish {
                Button { go(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            // Progress: one segment per real step.
            HStack(spacing: 4) {
                ForEach(1..<Step.finish.rawValue, id: \.self) { i in
                    Capsule()
                        .fill(i <= step.rawValue ? Color.brandPalette[(i - 1) % Color.brandPalette.count] : Color.track)
                        .frame(height: 4)
                }
            }
            .opacity(step == .welcome || step == .finish ? 0 : 1)
            .accessibilityHidden(true)
            if step != .welcome && step != .finish && step != .cardDetails {
                Button("Skip") { go(1) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .tint(Color.ink)
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button(action: primaryAction) {
                Text(primaryTitle).primaryPill(enabled: step != .cardDetails || detailsComplete)
            }
            .buttonStyle(.plain)
            .disabled(step == .cardDetails && !detailsComplete)
            if step == .welcome {
                Button("Explore with sample data") {
                    DemoData.load(in: context)
                    finish()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ink)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(Color.page)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .cardDetails: detailsComplete ? "Continue" : missingDigitsText
        case .applePay: tapConnected ? "Continue" : "I'll Do This Later"
        case .email: gmail.isEmpty ? "I'll Do This Later" : "Continue"
        case .reminders: reminders ? "Continue" : "Not Now"
        case .finish: "Start Using Sortd"
        default: "Continue"
        }
    }

    private func primaryAction() {
        step == .finish ? finish() : go(1)
    }

    private func go(_ delta: Int) {
        budgetFocused = false
        forward = delta > 0
        withAnimation(.snappy) {
            var next = Step(rawValue: min(max(step.rawValue + delta, 0), Step.finish.rawValue)) ?? .finish
            if next == .cardDetails, book.active.isEmpty { next = Step(rawValue: next.rawValue + delta) ?? .finish }
            step = next
        }
    }

    private func finish() {
        Task { await FXService.rebase(to: home, in: context) }
        done = true
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .currency: currency
        case .cards: cards
        case .cardDetails: cardDetails
        case .applePay: applePay
        case .email: emailPage
        case .budget: budgetPage
        case .reminders: remindersPage
        case .finish: finishPage
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            BrandBar(width: 14, height: 3)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 15, style: .continuous))
                .padding(.top, 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                // Wordmark: lowercase, heavy, tight, with the four category colours under it.
                VStack(alignment: .leading, spacing: 6) {
                    Text("sortd")
                        .font(.system(size: 40, weight: .heavy))
                        .tracking(-1.2)
                    HStack(spacing: 3) {
                        ForEach([SpendCategory.foodDelivery, .eatingOut, .subscriptions, .groceries], id: \.self) {
                            Capsule().fill($0.color).frame(width: 22, height: 4)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sortd")
                Text("Your spending, logged by itself.")
                    .font(.body).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("wave.3.right", "Apple Pay taps log themselves", "Pay as usual. Each tap lands in Sortd in a second.", Color.brandPalette[0])
                feature("square.stack", "Every card, every currency", "Debit, credit and travel cards, converted at the day's rate.", Color.brandPalette[1])
                feature("arrow.triangle.2.circlepath", "Bills and subscriptions, predicted", "See what's due before it's charged.", Color.brandPalette[2])
                feature("lock", "Private by design", "No bank logins. Your data stays on your iPhone.", Color.brandPalette[3])
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 26)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currency: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Your currency", "Totals and budgets are shown in this. Purchases in other currencies are converted at that day's rate.")
            VStack(spacing: 0) {
                currencyRow(Money.detectedHome, note: "From your iPhone")
                ForEach(["AUD", "SGD", "USD", "GBP", "EUR", "MYR", "NZD"].filter { $0 != Money.detectedHome }, id: \.self) {
                    Divider().padding(.leading, 16)
                    currencyRow($0, note: nil)
                }
            }
            .surface(radius: 16)
            Menu {
                ForEach(Money.supported, id: \.self) { code in
                    Button("\(code) · \(name(of: code))") { home = code }
                }
            } label: {
                Label("Other currencies", systemImage: "globe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)
        }
    }

    private func name(of code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    private func currencyRow(_ code: String, note: String?) -> some View {
        Button { home = code } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(code) · \(name(of: code))").foregroundStyle(Color.ink)
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if home == code {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(home == code ? .isSelected : [])
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Your cards", "Tap the banks you pay with. Have two cards from one bank? Tap it twice. Debit or credit comes next.")
            if !book.active.isEmpty {
                // What's picked so far, as removable chips.
                FlowLayout(spacing: 8) {
                    ForEach(book.active) { info in
                        HStack(spacing: 6) {
                            Text(info.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Button {
                                let id = info.id
                                let used = ((try? context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.cardRaw == id }))) ?? 0) > 0
                                book.remove(info, hasPurchases: used)
                            } label: {
                                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44).contentShape(.rect)
                            }
                            .padding(.vertical, -12)
                            .accessibilityLabel("Remove \(info.name)")
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 10)
                        .padding(.vertical, 8)
                        .background(Color.card, in: .capsule)
                    }
                }
                .padding(.bottom, 20)
            }
            // Only the user's own countries: the phone's region and the
            // currency picked on the step before. Everything else is one tap away.
            ForEach(myCountries, id: \.self) { country in
                bankGroup(Locale.current.localizedString(forRegionCode: country) ?? country,
                          BankPreset.all.filter { $0.country == country })
            }
            bankGroup("Works anywhere", BankPreset.all.filter { $0.country.isEmpty })
            if showAllBanks {
                ForEach(otherCountries, id: \.self) { country in
                    bankGroup(Locale.current.localizedString(forRegionCode: country) ?? country,
                              BankPreset.all.filter { $0.country == country })
                }
            } else if !otherCountries.isEmpty {
                Button("Banks in other countries") { withAnimation(.snappy) { showAllBanks = true } }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 44)
            }
        }
    }

    /// "Add digits for 2 more cards" — says how many are left, since the
    /// missing one may be further down the list.
    private var missingDigitsText: String {
        let n = book.active.filter { $0.last4.isEmpty }.count
        return n == 1 ? "Add digits for 1 more card" : "Add digits for \(n) more cards"
    }

    /// Every card has its card-number digits: that's how bank emails and
    /// receipts find it.
    private var detailsComplete: Bool {
        book.active.allSatisfy { !$0.last4.isEmpty }
    }

    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Card details", "The last 4 digits are how Sortd matches bank emails and receipts to the right card. Only the last 4 — never the full number.")
            VStack(spacing: 16) {
                ForEach(book.active) { info in
                    CardDetailForm(info: info)
                }
            }
        }
    }

    /// Bank name, or the user's own name for the card once renamed.
    private func rowTitle(_ info: CardInfo) -> String {
        let generated = info.name.hasPrefix(info.bank) && !info.bank.isEmpty
        return generated ? BankPreset.short(info.bank) + numberSuffix(info) : info.name
    }

    /// Two cards from one bank can only be told apart on receipts by their
    /// last 4 digits.
    private func needsDigits(_ info: CardInfo) -> Bool {
        info.allLast4.isEmpty && book.active.filter { $0.bank == info.bank && !info.bank.isEmpty }.count > 1
    }

    private func rowDetail(_ info: CardInfo) -> String {
        if !info.allLast4.isEmpty { return info.allLast4.map { "•• \($0)" }.joined(separator: " · ") }
        return needsDigits(info) ? "Add last 4 digits" : "Tap to rename"
    }

    /// " 2" for the second debit (or credit) card from the same bank.
    private func numberSuffix(_ info: CardInfo) -> String {
        guard let n = info.name.split(separator: " ").last, Int(n) != nil else { return "" }
        return " \(n)"
    }

    private var myCountries: [String] {
        var list = [region]
        if let fromCurrency = CardEditor.country(for: home), !list.contains(fromCurrency) { list.append(fromCurrency) }
        return list.filter { c in BankPreset.all.contains { $0.country == c } }
    }

    private var otherCountries: [String] {
        var seen: [String] = []
        for p in BankPreset.all where !p.country.isEmpty && !myCountries.contains(p.country) && !seen.contains(p.country) {
            seen.append(p.country)
        }
        return seen
    }

    private func bankGroup(_ title: String, _ banks: [BankPreset]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(banks) { bank in
                    let count = book.active.filter { $0.bank == bank.name }.count
                    let added = count > 0
                    Button {
                        // Every tap adds one more card from this bank, named
                        // "DBS", "DBS 2", "DBS 3"… Debit or credit is chosen on
                        // the next page, with the digits and a nickname.
                        let mine = book.active.filter { $0.bank == bank.name }
                        let next = (mine.compactMap { Int($0.name.split(separator: " ").last ?? "") }.max() ?? (mine.isEmpty ? 0 : 1)) + 1
                        var card = bank.card(credit: false)
                        card.name = next > 1 ? "\(bank.shortName) \(next)" : bank.shortName
                        card.shortName = card.name
                        book.upsert(card)
                    } label: {
                        HStack(spacing: 6) {
                            if added { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                            Text(bank.name).font(.subheadline.weight(.medium))
                            if count > 1 { Text("×\(count)").font(.caption.weight(.bold)) }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .chip(selected: added)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(added ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }

    /// The first purchase that came from an Apple Pay tap.
    private var firstTap: Transaction? { transactions.first { $0.seenIn.contains(.tap) } }
    private var tapConnected: Bool { firstTap != nil }

    private var applePay: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Log Apple Pay taps", "A one-time setup in Apple's Shortcuts app. Apple doesn't let apps do this part for you, so it takes about two minutes.")
            if let link = ShortcutLink.url {
                // Easy way: add the ready-made shortcut, then point the automation at it.
                VStack(alignment: .leading, spacing: 16) {
                    Button { openURL(link) } label: {
                        Label("Add the Sortd shortcut", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(Color.onBrand)
                            .background(Color.brand, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    miniStep(1, "Tap Add Shortcut", "Shortcuts opens with “Log to Sortd” ready to add.")
                    miniStep(2, "Open it in Shortcuts", "Check Automation is on under “When Any Card is tapped”.")
                    miniStep(3, "Pay with Apple Pay", "Your next tap shows up in Sortd. That's it.")
                }
                .padding(16)
                .surface(radius: 16)
                .padding(.bottom, 14)
                Text("Or set it up by hand").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 16) {
                if #available(iOS 27.0, *) {
                    miniStep(1, "Shortcuts → + → Edit", "Tap Automation, search wallet, tap Wallet.")
                    miniStep(2, "Add Sortd's Log Purchase", "Search Sortd at the bottom and tap it.")
                    miniStep(3, "Fill the 3 blue words", "Tap each → Select Variable → Transaction, then tap it again and pick Amount, Merchant, or Card or Pass. It should look like this:")
                } else {
                    miniStep(1, "Shortcuts → Automation → +", "Tap Wallet, choose your cards, then Run Immediately and Next.")
                    miniStep(2, "Create New Shortcut", "Search Sortd and tap Log Purchase.")
                    miniStep(3, "Fill the 3 blue words", "Tap each one, pick Shortcut Input, then tap it again and pick the same name. It should look like this:")
                }
                actionMock.padding(.leading, 38)
            }
            .padding(16)
            .surface(radius: 16)

            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.onBrand)
                        .background(Color.brand, in: .capsule)
                }
                Button { showingGuide = true } label: {
                    Text("Detailed Steps")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.ink)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            // Checks itself: turns green as soon as a tap arrives.
            HStack(spacing: 12) {
                if let t = firstTap {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.up)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected").font(.headline)
                        Text("Logged \(Money.format(t.amount, t.currencyCode)) at \(t.merchant)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for your first tap").font(.headline)
                        Text("Pay for anything with Apple Pay and it shows up here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 16)
            .padding(.top, 14)
            .animation(.snappy, value: tapConnected)
            .sensoryFeedback(.success, trigger: tapConnected)
        }
    }

    /// What the finished Shortcuts action looks like, so people can check theirs.
    private var actionMock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image("BrandIcon").resizable().frame(width: 20, height: 20)
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
                Text("Log Purchase").font(.footnote.weight(.semibold))
            }
            // Same wording as the real action in Shortcuts.
            FlowLayout(spacing: 4) {
                Text("Log").font(.footnote)
                token("Amount")
                Text("at").font(.footnote)
                token("Merchant")
                Text("on").font(.footnote)
                token("Card or Pass")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.page, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Log Amount at Merchant on Card or Pass")
    }

    /// A Shortcuts variable token (blue, like in the Shortcuts app).
    private func token(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: 0.2, green: 0.47, blue: 0.96), in: .rect(cornerRadius: 5))
    }

    private func miniStep(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 26, height: 26)
                .background(Color.ink, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emailPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Email receipts", "Connect Gmail and Sortd adds purchases from receipts and bank alerts — delivery, rides, app stores, online shops. Read-only, on this iPhone.")
            if !gmail.isEmpty {
                VStack(spacing: 0) {
                    ForEach(gmail) { a in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.up)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.email).lineLimit(1)
                                Text(a.lastResult ?? "Connected").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                    }
                }
                .surface(radius: 16)
                .padding(.bottom, 14)
            }
            Button { connectingGmail = true } label: {
                Label(gmail.isEmpty ? "Connect Gmail" : "Connect Another Gmail", systemImage: "envelope")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(gmail.isEmpty ? Color.onBrand : Color.ink)
                    .background(gmail.isEmpty ? Color.brand : Color.clear, in: .capsule)
                    .overlay(Capsule().strokeBorder(gmail.isEmpty ? .clear : Color.secondary.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var budgetPresets: [Double] {
        // Round numbers for the currency (yen and rupiah need bigger ones).
        let base: Double = ["JPY": 100, "KRW": 1000, "IDR": 10000, "INR": 50, "PHP": 40, "THB": 25, "HUF": 250, "ISK": 100][home] ?? 1
        return [500, 1000, 1500, 2000, 3000].map { $0 * base }
    }

    private var budgetPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Monthly budget", "Sortd shows what's left each day, after bills that are still due. Change it any time.")

            // One big amount, typed or picked.
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol(home))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $customBudget)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(.numberPad)
                        .focused($budgetFocused)
                        .fixedSize()
                        .onChange(of: customBudget) { _, text in
                            budget = Double(text.filter(\.isNumber)) ?? 0
                        }
                }
                .onTapGesture { budgetFocused = true }
                Text(budget > 0
                     ? "About \(Money.format(Decimal(budget / 30), home, cents: false)) a day"
                     : "No budget set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .surface(radius: 20)
            .animation(.snappy, value: budget)

            FlowLayout(spacing: 8) {
                ForEach(budgetPresets, id: \.self) { value in
                    Button {
                        budget = value
                        customBudget = String(Int(value))
                        budgetFocused = false
                    } label: {
                        Text(Money.format(Decimal(value), home, cents: false))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .chip(selected: budget == value)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)

            Button("No budget for now") {
                budget = 0
                customBudget = ""
                budgetFocused = false
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .padding(.top, 4)
        }
        .onAppear { if budget > 0, customBudget.isEmpty { customBudget = String(Int(budget)) } }
    }

    private var remindersPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Heads-up before bills", "A notification at 9 am the day before a subscription or bill is due. Nothing leaves your iPhone.")
            HStack(spacing: 14) {
                Image(systemName: reminders ? "bell.badge.fill" : "bell")
                    .font(.title2).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Netflix tomorrow").font(.headline)
                    Text("\(Money.format(18.99, home)) on your card. Monthly.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 16)
            .accessibilityLabel("Example reminder: Netflix tomorrow")

            Button {
                Task { reminders = await Reminders.requestPermission() }
            } label: {
                Label(reminders ? "Reminders On" : "Turn On Reminders",
                      systemImage: reminders ? "checkmark" : "bell")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(reminders ? Color.ink : Color.onBrand)
                    .background(reminders ? Color.clear : Color.brand, in: .capsule)
                    .overlay(Capsule().strokeBorder(reminders ? Color.hairline : .clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(reminders)
            .padding(.top, 16)
        }
    }

    private var finishPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("You're set", "Here's what's ready. Anything skipped is in Settings.")
            VStack(spacing: 0) {
                check("Currency", home, ok: true)
                Divider().padding(.leading, 52)
                check("Cards", book.active.isEmpty ? "Added as you pay" : "\(book.active.count) added", ok: !book.active.isEmpty)
                Divider().padding(.leading, 52)
                check("Apple Pay logging", tapConnected ? "Connected" : "Set up later", ok: tapConnected)
                Divider().padding(.leading, 52)
                check("Email receipts", gmail.isEmpty ? "Not connected" : gmail.map(\.email).joined(separator: ", "), ok: !gmail.isEmpty)
                Divider().padding(.leading, 52)
                check("Budget", budget > 0 ? Money.format(Decimal(budget), home, cents: false) + " a month" : "None", ok: budget > 0)
                Divider().padding(.leading, 52)
                check("Reminders", reminders ? "On" : "Off", ok: reminders)
            }
            .surface(radius: 16)
        }
    }

    private func check(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(ok ? Color.up : Color.secondary)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}


/// Debit or credit, told apart without colour so it never clashes with the
/// category colours: debit is outlined, credit is filled.
struct CardTypeBadge: View {
    let isCredit: Bool

    var body: some View {
        Text(isCredit ? "Credit" : "Debit")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(isCredit ? Color.white : Color.ink)
            .background(isCredit ? Color.creditFill : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.5), lineWidth: 1))
    }
}

/// One card's details during setup: a small card preview, then name,
/// type, and the two sets of last-4 digits. Saves as you type.
struct CardDetailForm: View {
    let info: CardInfo
    @State private var name: String
    @State private var isCredit: Bool
    @State private var digits: String
    @State private var payDigits: String
    @State private var showHelp = false

    init(info: CardInfo) {
        self.info = info
        _name = State(initialValue: info.name)
        _isCredit = State(initialValue: info.isCredit)
        _digits = State(initialValue: info.last4.first ?? "")
        _payDigits = State(initialValue: info.applePayLast4?.first ?? "")
    }

    private var missing: Bool { CardEditor.fours(digits).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                preview
                VStack(alignment: .leading, spacing: 8) {
                    // Looks like a field so people know they can call it
                    // something they'll recognise ("Groceries card").
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nickname").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            TextField("e.g. Groceries card", text: $name)
                                .font(.headline)
                                .submitLabel(.done)
                            Image(systemName: "pencil")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.page, in: .rect(cornerRadius: 9, style: .continuous))
                    }
                    Picker("Type", selection: $isCredit) {
                        Text("Debit").tag(false)
                        Text("Credit").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(14)

            Divider().padding(.leading, 14)
            digitRow("Card number", text: $digits, required: true)
            Divider().padding(.leading, 14)
            digitRow("Apple Pay number", text: $payDigits, required: false)

            Button {
                withAnimation(.snappy) { showHelp.toggle() }
            } label: {
                Label(showHelp ? "Hide" : "Where do I find these?", systemImage: "questionmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if showHelp {
                Text("Card number: the last 4 digits printed on your card or in your bank app. Apple Pay number: Wallet › this card › ••• › Card Details › Device Account Number. Apple Pay pays with that number, so receipts for Apple Pay purchases often show it instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .surface(radius: 18)
        .onChange(of: name) { save() }
        .onChange(of: isCredit) { _, credit in
            // Keep an automatic name in step with the switch ("… Debit" → "… Credit");
            // a name the user typed is left alone.
            let from = credit ? "Debit" : "Credit", to = credit ? "Credit" : "Debit"
            if name.contains(from), name.hasPrefix(info.bank), !info.bank.isEmpty {
                name = name.replacingOccurrences(of: from, with: to)
            }
            save()
        }
        .onChange(of: digits) { save() }
        .onChange(of: payDigits) { save() }
    }

    /// Credit cards are dark, debit cards light: the same rule everywhere.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BankPreset.short(info.bank.isEmpty ? name : info.bank))
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(missing ? "•• ····" : "•• \(CardEditor.fours(digits)[0])")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .opacity(0.8)
        }
        .foregroundStyle(isCredit ? Color.white : Color.ink)
        .padding(8)
        .frame(width: 92, height: 58, alignment: .leading)
        .background(isCredit ? Color.creditFill : Color.page, in: .rect(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isCredit ? .clear : Color.secondary.opacity(0.35), lineWidth: 1))
        .animation(.snappy, value: isCredit)
        .accessibilityHidden(true)
    }

    private func digitRow(_ title: String, text: Binding<String>, required: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(required ? "Required" : "Optional")
                    .font(.caption)
                    .foregroundStyle(required && missing ? Color.orange : Color.secondary)
            }
            Spacer()
            TextField("Last 4", text: text)
                .keyboardType(.numberPad)
                .onChange(of: text.wrappedValue) { _, new in
                    let clean = String(new.filter(\.isNumber).prefix(4))
                    if clean != new { text.wrappedValue = clean }
                }
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 90)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private func save() {
        var c = info
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        c.name = trimmed.isEmpty ? info.name : trimmed
        c.shortName = c.name
        c.isCredit = isCredit
        c.last4 = CardEditor.fours(digits)
        let pay = CardEditor.fours(payDigits)
        c.applePayLast4 = pay.isEmpty ? nil : pay
        // Nicknames are for the user; Wallet matching keeps the bank's words.
        let bankWords = Set(BankPreset.match(info.bank)?.words ?? [])
        c.walletWords.removeAll { $0 == info.name.lowercased() && !bankWords.contains($0) }
        CardBook.shared.upsert(c)
    }
}
