import Foundation

enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }
    var title: String { self == .terms ? "Terms of Use" : "Privacy Policy" }

    init?(link: URL) {
        guard link.scheme == "untitledfaith", let host = link.host else { return nil }
        self.init(rawValue: host)
    }

    var sections: [LegalSection] {
        switch self {
        case .privacy:
            return [
                LegalSection(title: "About this preview", body: "This draft describes the Untitled Faith preview. You can sign in with Apple and request AI answers by sending a question. Web search uses an approved list of Bible and commentary sites. We will review this policy before public launch."),
                LegalSection(title: "Data in Untitled Faith", body: "We do not sell your personal information or include advertising trackers. Conversations are saved in this app’s protected storage on your device, separately for each sign-in. They remain when you close the app or sign out. Starting a new conversation keeps previous conversations in the history list. You can reopen or delete them there. Chat files are excluded from device backups and are not synced to other devices. Removing the app removes its local conversations. When sharing is enabled, our service processes questions to answer them; it does not save conversation content in a database or application logs. Cloudflare hosts this service and processes network and request metadata. Our operational logs record a random request identifier, status, and timing."),
                LegalSection(title: "Sign in with Apple", body: "We request your name from Apple and keep only your first name on your account to personalize answers. We do not request your email address or send your family name to our service. Deleting your account removes the saved first name. Our service verifies Apple's credentials and creates an account identified by a random identifier. A hashed Apple identifier links future sign-ins to that account. Your Apple app-specific identifier and session credentials are saved in device-only Keychain storage. The Apple renewal credential is encrypted for our server before being stored on your device. Apple credentials are not sent to inference providers. Sign out removes this device's saved session."),
                LegalSection(title: "Usage and funding records", body: "We store account creation dates, usage dates, request identifiers, token counts, service costs, free-allowance usage, and contribution balances to operate the service and enforce limits. Verified contributions record the payment reference, gross amount, fees, net funding, and reversals. These records contain no question or answer text. Records are stored in our Cloudflare database. Deleting an account removes its sign-in link and disconnects accounting records from the account. Outstanding funding or unsettled requests must be resolved before deletion; contact us for help."),
                LegalSection(title: "Questions and AI answers", body: "When you tap Send, your question, the entire current conversation, and your account’s first name when available are sent through our service hosted by Cloudflare to OpenRouter and Google to generate an AI answer. Anything you include, including personal information, is part of that request. When the assistant searches, OpenRouter sends search queries to Exa; those queries may include details from your conversation. An app-specific identifier is also sent for service operation. We do not send Apple credentials to OpenRouter or Google. The current preview sends requests directly without a separate confirmation popup."),
                LegalSection(title: "Third-party data handling", body: "The service requests Google provider routes through OpenRouter with data collection disabled. This routing setting does not establish a blanket promise that no data is retained. OpenRouter, Google, Cloudflare, and Exa process data under their own policies. The Google routing setting does not determine Exa’s retention practices. Account settings and provider terms must also be verified before public launch. Review the linked policies for details."),
                LegalSection(title: "Your choices", body: "You can review this policy before signing in. AI answers are enabled by default. In chat Settings, turn AI answers off to prevent future requests and cancel an in-progress request where possible. This cannot recall information already sent. This setting is remembered on this device. Use Conversations to delete individual local chats. Use Delete account in Settings to remove this device's saved conversations and sign-in session and revoke Apple authorization. Local conversations on other devices must be deleted on those devices. Previously issued access credentials expire within 15 minutes."),
                LegalSection(title: "Contact", body: "For privacy questions or account-deletion requests, email untitledfaith@gmail.com. This is Untitled Faith’s current public contact address.")
            ]
        case .terms:
            return [
                LegalSection(title: "Using Untitled Faith", body: "Untitled Faith is an app for exploring questions about the Christian faith. By continuing, you agree to use it lawfully and in accordance with these terms. If you do not agree, do not continue."),
                LegalSection(title: "Preview availability", body: "This draft applies to the current preview. Apple sign-in provides access to AI answers when you send a question. Conversations are saved on your device until you delete them. Features may change as we develop the app."),
                LegalSection(title: "Answers and sources", body: "AI-generated answers can contain mistakes or unsupported interpretations. The assistant can search approved Scripture and commentary sites. Displayed quotation blocks are checked against returned search excerpts, which may be incomplete or outdated. Read Bible passages in context and use your own judgment. Scripture and commentary quotations use separate labels and link to their sources. A named pastor or organization does not necessarily endorse Untitled Faith."),
                LegalSection(title: "Your questions", body: "Only submit content you are entitled to share. Do not use the app to abuse others, violate their privacy, break the law, or interfere with the service."),
                LegalSection(title: "Free access and personal funding", body: "Free answers are subject to daily, monthly, and shared funding limits. Additional usage can draw from your personal contribution balance. You may optionally allocate 0–3% of a contribution to the developer as thanks; the choice starts at zero and is included in your total. The remainder becomes usage funding after payment fees. Service usage deducts the provider cost and the cost of acquiring service credits, without a profit markup. Contributed funding carries forward between months. A request may temporarily reserve more than its final cost; the unused amount is released after its cost is confirmed. Provider work already performed may incur a cost even if a response is interrupted. Refunded contributions reverse both usage funding and developer thanks."),
                LegalSection(title: "Privacy and inference", body: "Our Privacy Policy explains how questions are processed by our service, Cloudflare, OpenRouter, Google, and Exa. Sending a question transmits it and the current conversation to the answer service. You can turn AI answers off in Settings."),
                LegalSection(title: "Changes and contact", body: "We will update these draft terms before the live service launches and make the current version available in the app. For questions, contact untitledfaith@gmail.com.")
            ]
        }
    }
}

struct LegalSection: Identifiable {
    let title: String
    let body: String
    var id: String { title }
}
