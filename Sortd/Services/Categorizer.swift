import Foundation

/// Picks a category from the merchant name. Raj's own corrections (learned
/// rules) always win over the built-in list.
enum Categorizer {
    /// Checked in order, so "uber eats" is matched before "uber".
    /// Short needles are space-padded so "iga" doesn't match "cigar".
    static let builtIn: [(needle: String, category: SpendCategory)] = [
        // Rent and housing (student accommodation)
        ("iglu", .housing), ("scape", .housing), ("unilodge", .housing), ("urbanest", .housing),
        ("realestate", .housing), ("strata", .housing),
        // Food delivery
        ("ubereats", .foodDelivery), ("uber eats", .foodDelivery), ("uber *eats", .foodDelivery),
        ("doordash", .foodDelivery), ("menulog", .foodDelivery), ("deliveroo", .foodDelivery),
        ("foodpanda", .foodDelivery), ("grabfood", .foodDelivery), ("grab food", .foodDelivery),
        // Subscriptions
        ("netflix", .subscriptions), ("spotify", .subscriptions), ("apple.com/bill", .subscriptions),
        ("youtube", .subscriptions), ("disney", .subscriptions), ("stan.com.au", .subscriptions),
        ("openai", .subscriptions), ("chatgpt", .subscriptions), ("anthropic", .subscriptions),
        ("claude.ai", .subscriptions), ("icloud", .subscriptions), ("github", .subscriptions),
        ("notion", .subscriptions), ("amazon prime", .subscriptions), ("binge", .subscriptions),
        ("adobe", .subscriptions), ("microsoft", .subscriptions), ("google one", .subscriptions),
        // Transport
        ("uber", .transport), ("didi", .transport), (" ola ", .transport), ("grab", .transport),
        ("gojek", .transport), ("ptv", .transport), ("myki", .transport), ("transport for", .transport),
        ("simplygo", .transport), ("comfortdelgro", .transport), (" cdg ", .transport),
        ("7-eleven fuel", .transport), (" shell ", .transport), (" bp ", .transport), ("ampol", .transport),
        ("parking", .transport), ("citylink", .transport), ("linkt", .transport),
        // Groceries
        ("woolworths", .groceries), ("coles", .groceries), ("aldi", .groceries), (" iga ", .groceries),
        ("harris farm", .groceries), ("fairprice", .groceries), ("cold storage", .groceries),
        ("sheng siong", .groceries), ("giant", .groceries), ("don don donki", .groceries),
        ("costco", .groceries),
        // Eating out
        ("mcdonald", .eatingOut), ("kfc", .eatingOut), ("hungry jack", .eatingOut),
        ("subway", .eatingOut), ("domino", .eatingOut), ("pizza", .eatingOut),
        ("grill'd", .eatingOut), ("grilld", .eatingOut), ("guzman", .eatingOut), ("nando", .eatingOut),
        ("starbucks", .eatingOut), ("gloria jean", .eatingOut), ("coffee", .eatingOut),
        ("cafe", .eatingOut), ("café", .eatingOut), ("espresso", .eatingOut), ("bakery", .eatingOut),
        ("sushi", .eatingOut), ("ramen", .eatingOut), ("kitchen", .eatingOut), ("restaurant", .eatingOut),
        (" bar ", .eatingOut), (" pub ", .eatingOut), ("hotel", .travel), ("boost juice", .eatingOut),
        ("chatime", .eatingOut), ("gong cha", .eatingOut), ("koi the", .eatingOut),
        ("ya kun", .eatingOut), ("toast box", .eatingOut), ("kopitiam", .eatingOut),
        ("hawker", .eatingOut), ("food", .eatingOut), ("burger", .eatingOut), ("noodle", .eatingOut),
        // Shopping
        ("kmart", .shopping), ("target", .shopping), ("big w", .shopping), ("jb hi-fi", .shopping),
        ("jb hifi", .shopping), ("officeworks", .shopping), ("bunnings", .shopping), ("ikea", .shopping),
        ("uniqlo", .shopping), ("amazon", .shopping), ("shopee", .shopping), ("lazada", .shopping),
        ("apple store", .shopping), ("myer", .shopping), ("david jones", .shopping),
        ("chemist warehouse", .health), ("priceline", .health), ("guardian", .health), ("watsons", .health),
        ("pharmacy", .health), ("medical", .health), ("dental", .health), ("clinic", .health),
        // Entertainment
        ("hoyts", .entertainment), ("village cinema", .entertainment), ("event cinema", .entertainment),
        ("golden village", .entertainment), ("ticketek", .entertainment), ("ticketmaster", .entertainment),
        ("steam", .entertainment), ("playstation", .entertainment), ("nintendo", .entertainment),
        // Bills
        ("telstra", .bills), ("optus", .bills), ("vodafone", .bills), ("singtel", .bills),
        ("starhub", .bills), ("origin energy", .bills), (" agl ", .bills), ("sp services", .bills),
        // Travel
        ("qantas", .travel), ("jetstar", .travel), ("virgin australia", .travel),
        ("singapore airlines", .travel), ("scoot", .travel), ("airbnb", .travel), ("booking.com", .travel),
        ("agoda", .travel), ("expedia", .travel),
        // Education
        ("unimelb", .education), ("university of melbourne", .education), ("co-op bookshop", .education),
        ("coursera", .education), ("udemy", .education),
        // More places seen in Raj's receipts (Sep 2026)
        ("amaysim", .bills), ("eight telecom", .bills), ("circles.life", .bills), ("gomo", .bills),
        ("nordvpn", .subscriptions), ("setapp", .subscriptions), ("cloudflare", .subscriptions),
        ("speechify", .subscriptions), ("justdone", .subscriptions), ("canva", .subscriptions),
        ("ticktick", .subscriptions), ("cleanmy", .subscriptions), ("apple music", .subscriptions), ("chatgpt", .subscriptions),
        ("emergency", .health), ("hospital", .health), ("supps", .health), (" cwh ", .health),
        ("honda", .transport), ("toyota", .transport), ("ez-link", .transport),
        ("zipair", .travel), ("trip.com", .travel), ("duty free", .travel), ("changi", .travel),
        ("ntuc", .groceries), ("grocery", .groceries), ("ww metro", .groceries), ("7-eleven", .groceries),
        ("general store", .groceries), ("bws", .groceries), ("liquor", .groceries), ("dan murphy", .groceries),
        ("mustafa", .shopping), ("muji", .shopping), ("daiso", .shopping), ("new balance", .shopping),
        ("ralph lauren", .shopping), ("giordano", .shopping), ("wallet shop", .shopping), ("laox", .shopping),
        ("academy brand", .shopping), ("vintage", .shopping), ("wh smith", .shopping), ("uniqlo", .shopping),
        ("all blue", .shopping), ("nike", .shopping), ("adidas", .shopping), ("zara", .shopping),
        ("h&m", .shopping), ("cotton on", .shopping), ("rebel sport", .shopping),
        ("nourish", .eatingOut), ("bhavan", .eatingOut), ("biryani", .eatingOut), ("kebab", .eatingOut),
        ("el jannah", .eatingOut), ("ayam", .eatingOut), ("marrybrown", .eatingOut), ("krispy", .eatingOut),
        ("tikka", .eatingOut), ("mess", .eatingOut), ("grill", .eatingOut), ("five guys", .eatingOut),
        ("shake shack", .eatingOut), ("deli", .eatingOut), ("poulet", .eatingOut), ("wee nam kee", .eatingOut),
        ("happy valley", .eatingOut), ("soul origin", .eatingOut), ("crepe", .eatingOut), ("kopi", .eatingOut),
        ("bagus", .eatingOut), ("yeast", .eatingOut), ("thai", .eatingOut), ("rempah", .eatingOut),
        ("bitterjoy", .eatingOut), ("indian", .eatingOut), ("bento", .eatingOut), ("pizzeria", .eatingOut),
        ("dumpling", .eatingOut), ("donq", .eatingOut), ("bakehouse", .eatingOut), ("tasty", .eatingOut),
        ("espr", .eatingOut), ("beverage", .eatingOut), ("vendworks", .eatingOut), ("altavend", .eatingOut),
        ("cocacola", .eatingOut), ("bubble tea", .eatingOut), ("mcd", .eatingOut),
        ("flashpay", .transfers), ("top up", .transfers), ("topup", .transfers), ("top-up", .transfers),
        ("transfer to", .transfers), ("youtrip top", .transfers), (" wise ", .transfers), ("revolut", .transfers),
    ]

    static func category(for merchant: String, learned: [String: SpendCategory] = [:]) -> SpendCategory {
        let key = MerchantName.key(merchant)
        if let hit = learned[key] { return hit }
        let lower = " " + merchant.lowercased() + " "
        for rule in builtIn where lower.contains(rule.needle) {
            return rule.category
        }
        return .other
    }
}
