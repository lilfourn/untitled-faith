import SwiftUI

struct ChatView: View {
    let session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: ChatStore
    @State private var showingSettings = false
    // Session-only UI state: never persisted or sent to the backend.
    @State private var profilePhoto: UIImage?
    @State private var showingHistory = false
    @State private var followingAnswer = true
    @State private var sendTask: Task<Void, Never>?

    private let suggestions = [
        Suggestion(title: "Read the Bible", detail: "how do I begin?", question: "How can I begin reading the Bible?"),
        Suggestion(title: "Explore prayer", detail: "what does the Bible say?", question: "What does the Bible say about prayer?"),
        Suggestion(title: "Understand faith", detail: "what does it mean?", question: "What does it mean to have faith?")
    ]

    init(session: AppSession, service: any AnswerService) {
        self.session = session
        _store = State(initialValue: ChatStore(service: service, storage: session.makeConversationStorage(), quoter: session.makeScriptureQuoter()))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(store.conversation.messages) { message in
                            MessageView(message: message)
                                .modifier(AnswerReveal(progress: store.revealingMessageID == message.id ? store.revealProgress : nil))
                        }

                        if let phase = store.loadingPhase {
                            ThinkingText(title: phase.rawValue)
                        }
                        if let error = store.errorMessage {
                            Label(error, systemImage: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
                                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityIdentifier("chat-service-notice")
                        }
                        if let error = store.storageError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(24)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .overlay {
                    if store.conversation.messages.isEmpty {
                        VerseCarousel(verses: HomeVerses.esv)
                            .padding(.horizontal, 40)
                            .allowsHitTesting(false)
                    }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in followingAnswer = false })
                .onChange(of: store.conversation.messages.count) {
                    if followingAnswer { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: store.revealProgress) {
                    if followingAnswer { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: store.conversation.messages.last?.text) {
                    if followingAnswer { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followingAnswer && store.isSending {
                        Button("Latest", systemImage: "arrow.down") {
                            followingAnswer = true
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                    }
                }
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    settingsToolbarItem
                        .sharedBackgroundVisibility(profilePhoto == nil ? .automatic : .hidden)
                } else {
                    settingsToolbarItem
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button("Conversations", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                            .disabled(store.isSending)
                        Button("New conversation", systemImage: "square.and.pencil") {
                            store.newConversation()
                            followingAnswer = true
                        }
                        .disabled(store.conversation.messages.isEmpty || store.isSending)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .sheet(isPresented: $showingHistory) {
                ConversationHistoryView(store: store) { followingAnswer = true }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(session: session, profilePhoto: $profilePhoto, beforeAccountDeletion: {
                    sendTask?.cancel()
                    await sendTask?.value
                })
            }
            .onChange(of: session.aiSharingAllowed) {
                if !session.aiSharingAllowed { sendTask?.cancel() }
            }
            .onDisappear { sendTask?.cancel() }

        }
    }

    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                if let profilePhoto {
                    Image(uiImage: profilePhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
            .accessibilityLabel("Settings")
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if store.conversation.messages.isEmpty {
                suggestionRow
            }
            inputBar
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                stops: [
                    .init(color: AppTheme.background.opacity(0), location: 0),
                    .init(color: AppTheme.background, location: 0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(suggestions) { suggestion in
                    Button {
                        store.draft = suggestion.question
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                            Text(suggestion.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(16)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in (length - 64) / 2 }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    private var inputBar: some View {
        let isActive = store.isSending || store.canSend
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a question…", text: $store.draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.leading, 20)
                .padding(.vertical, 15)
                .accessibilityIdentifier("question-input")
            Button {
                if store.isSending {
                    sendTask?.cancel()
                } else {
                    sendQuestion()
                }
            } label: {
                Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.35)
            .padding([.trailing, .bottom], 7)
            .accessibilityLabel(store.isSending ? "Stop answer" : "Send question")
        }
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
    }

    private func sendQuestion() {
        followingAnswer = true
        sendTask = Task { await store.send(animate: !reduceMotion && !UIAccessibility.isVoiceOverRunning) }
    }
}

private struct Suggestion: Identifiable {
    let title: String
    let detail: String
    let question: String
    var id: String { question }
}
