import SwiftUI

struct ChatView: View {
    let session: AppSession
    private let scriptureQuoter: ScriptureQuoter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: ChatStore
    @State private var showingSettings = false
    @State private var profilePhoto: UIImage?
    @State private var showingPhotoLoadError = false
    @State private var showingHistory = false
    @State private var followingAnswer = true
    @FocusState private var composerFocused: Bool
    @State private var sendTask: Task<Void, Never>?

    private let suggestions = [
        Suggestion(title: "Read the Bible", detail: "how do I begin?", question: "How can I begin reading the Bible?"),
        Suggestion(title: "Explore prayer", detail: "what does the Bible say?", question: "What does the Bible say about prayer?"),
        Suggestion(title: "Understand faith", detail: "what does it mean?", question: "What does it mean to have faith?")
    ]

    init(session: AppSession, service: any AnswerService) {
        self.session = session
        let quoter = session.makeScriptureQuoter()
        scriptureQuoter = quoter
        _store = State(initialValue: ChatStore(service: service, storage: session.makeConversationStorage(), quoter: quoter))
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
                        if store.canRetry {
                            Button("Retry answer", systemImage: "arrow.clockwise") { sendQuestion(retrying: true) }
                                .accessibilityIdentifier("retry-answer")
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
                        VerseCarousel { lastReference in
                            await HomeVerses.random(excluding: lastReference, quoter: scriptureQuoter)
                        }
                            .padding(.horizontal, 40)
                            .allowsHitTesting(false)
                    }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in followingAnswer = false })
                .onChange(of: store.conversation.messages.count) {
                    if followingAnswer { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: store.errorMessage) {
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
                    HStack(spacing: 0) {
                        Button { showingHistory = true } label: {
                            compactToolbarIcon("clock")
                        }
                        .accessibilityLabel("Conversations")
                        .disabled(store.isSending)
                        Button {
                            store.newConversation()
                            followingAnswer = true
                        } label: {
                            compactToolbarIcon("square.and.pencil")
                        }
                        .accessibilityLabel("New conversation")
                        .disabled(store.conversation.messages.isEmpty || store.isSending)
                    }
                    .buttonStyle(.plain)
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
            .onChange(of: store.isSending) {
                if !store.isSending { session.refreshUsage(force: true) }
            }
            .onChange(of: session.aiSharingAllowed) {
                if !session.aiSharingAllowed { sendTask?.cancel() }
            }
            .onDisappear { sendTask?.cancel() }
            .task {
                do { profilePhoto = try session.makeProfilePhotoStorage().load() }
                catch { showingPhotoLoadError = true }
            }
            .alert("Couldn’t load saved photo", isPresented: $showingPhotoLoadError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try reopening the app or choose a new profile photo in Settings.")
            }

        }
    }

    private func compactToolbarIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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
        let revision = store.draftRevision
        let draft = Binding(get: { store.draft }, set: { store.updateDraft($0, revision: revision) })
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a question…", text: draft, axis: .vertical)
                .id(revision)
                .focused($composerFocused)
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

    private func sendQuestion(retrying: Bool = false) {
        guard let task = store.startSend(animate: !reduceMotion && !UIAccessibility.isVoiceOverRunning,
                                        retrying: retrying) else { return }
        followingAnswer = true
        composerFocused = false
        sendTask = task
    }
}

private struct Suggestion: Identifiable {
    let title: String
    let detail: String
    let question: String
    var id: String { question }
}
