import SwiftUI

struct ChatView: View {
    let session: AppSession
    private let scriptureQuoter: ScriptureQuoter
    private let onFirstVerseLoaded: () -> Void
    private let isReady: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store: ChatStore
    @State private var showingSettings = false
    @State private var profilePhoto: UIImage?
    @State private var showingPhotoLoadError = false
    @State private var showingHistory = false
    @State private var followingAnswer = true
    @State private var composerFocused = false
    @State private var composerSelection = NSRange(location: 0, length: 0)
    @State private var dismissedMention: VerseMentionQuery?
    @State private var sendTask: Task<Void, Never>?
    @State private var confirmingDiscard = false

    private let suggestions = [
        Suggestion(title: "Read the Bible", detail: "how do I begin?", question: "How can I begin reading the Bible?"),
        Suggestion(title: "Explore prayer", detail: "what does the Bible say?", question: "What does the Bible say about prayer?"),
        Suggestion(title: "Understand faith", detail: "what does it mean?", question: "What does it mean to have faith?")
    ]

    init(session: AppSession, store: ChatStore, scriptureQuoter: ScriptureQuoter,
         profilePhoto: UIImage?, photoLoadFailed: Bool, isReady: Bool, onFirstVerseLoaded: @escaping () -> Void) {
        self.session = session
        self.scriptureQuoter = scriptureQuoter
        self.onFirstVerseLoaded = onFirstVerseLoaded
        self.isReady = isReady
        _store = State(initialValue: store)
        _profilePhoto = State(initialValue: profilePhoto)
        _showingPhotoLoadError = State(initialValue: photoLoadFailed)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    conversationContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .overlay {
                    if store.conversation.messages.isEmpty {
                        VerseCarousel(draw: { lastReference in
                            await HomeVerses.random(excluding: lastReference, quoter: scriptureQuoter)
                        }, onFirstLoad: onFirstVerseLoaded)
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
            .modifier(ChatHaptics(isSending: store.isSending, revealProgress: store.revealProgress,
                                  isVisible: isReady && !showingSettings && !showingHistory && !showingPhotoLoadError))
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
                }, beforeSignOut: {
                    sendTask?.cancel()
                    await sendTask?.value
                    return store.ensureSaved()
                })
            }
            .confirmationDialog("Discard the changes that could not be saved?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard unsaved changes", role: .destructive) { store.discardUnsavedChanges() }
            }
            .onChange(of: store.isSending) {
                if !store.isSending { session.refreshUsage(force: true) }
            }
            .onChange(of: store.draftRevision) {
                composerSelection = NSRange(location: 0, length: 0)
                dismissedMention = nil
            }
            .alert("Add usage to continue", isPresented: Binding(
                get: { store.usageLimitMessage != nil },
                set: { if !$0 { store.usageLimitMessage = nil } }
            ), presenting: store.usageLimitMessage) { _ in
                Button("Open Settings") {
                    composerFocused = false
                    showingSettings = true
                }
                Button("Not now", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .onDisappear { sendTask?.cancel() }
            .alert("Couldn’t load saved photo", isPresented: Binding(
                get: { isReady && showingPhotoLoadError },
                set: { showingPhotoLoadError = $0 }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try reopening the app or choose a new profile photo in Settings.")
            }

        }
    }

    private var conversationContent: some View {
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
                Button("Retry answer", systemImage: "arrow.clockwise") {
                    Task { if await store.checkRetry() { sendQuestion(retrying: true) } }
                }
                    .accessibilityIdentifier("retry-answer")
            }
            if store.isCheckingRetry { ProgressView("Checking previous request…") }
            if let error = store.storageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if store.hasUnsavedChanges {
                Button("Retry saving") { store.retrySave() }
                Button("Discard unsaved changes", role: .destructive) { confirmingDiscard = true }
                    .disabled(store.isSending)
            }
            Color.clear.frame(height: 1).id("bottom")
        }
        .padding(24)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
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
            if let mention = activeMention {
                VerseMentionPicker(query: mention.text, select: { selectVerse($0, for: mention) },
                                   dismiss: { dismissedMention = mention })
                    .padding(.horizontal, 16)
            } else if store.conversation.messages.isEmpty && store.draftScripture.isEmpty && store.draft.isEmpty {
                suggestionRow
            }
            if !store.draftScripture.isEmpty {
                ScriptureAttachments(citations: store.draftScripture, remove: store.removeScripture)
                    .padding(.horizontal, 16)
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
                        composerSelection = NSRange(location: suggestion.question.utf16.count, length: 0)
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
        let selection = Binding(get: { composerSelection }, set: {
            if revision == store.draftRevision { composerSelection = $0 }
        })
        let focused = Binding(get: { composerFocused }, set: {
            if revision == store.draftRevision { composerFocused = $0 }
        })
        return HStack(alignment: .bottom, spacing: 8) {
            ComposerTextView(text: draft, selection: selection, focused: focused)
                .id(revision)
                .overlay(alignment: .topLeading) {
                    if store.draft.isEmpty {
                        Text("Ask a question or @ a verse…")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 20).padding(.top, 15)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
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
        if !retrying, let mention = activeMention {
            guard let bible = BibleStore.bundled,
                  let citation = VerseSearch(bible: bible).exactResult(for: mention.text) else {
                store.errorMessage = "Choose a verse from the search results before sending."
                return
            }
            guard selectVerse(citation, for: mention) else { return }
        }
        guard let task = store.startSend(animate: !reduceMotion && !UIAccessibility.isVoiceOverRunning,
                                        retrying: retrying) else { return }
        followingAnswer = true
        composerFocused = false
        sendTask = task
    }

    private var activeMention: VerseMentionQuery? {
        guard composerFocused,
              let mention = VerseMentionQuery.active(in: store.draft, selection: composerSelection),
              mention != dismissedMention else { return nil }
        return mention
    }

    @discardableResult
    private func selectVerse(_ citation: ScriptureCitation, for mention: VerseMentionQuery) -> Bool {
        guard activeMention == mention,
              let insertion = mention.inserting(citation.reference, in: store.draft),
              store.attachScripture(citation, revision: store.draftRevision) else { return false }
        store.updateDraft(insertion.text, revision: store.draftRevision)
        composerSelection = insertion.selection
        dismissedMention = nil
        composerFocused = true
        return true
    }
}

private struct Suggestion: Identifiable {
    let title: String
    let detail: String
    let question: String
    var id: String { question }
}
