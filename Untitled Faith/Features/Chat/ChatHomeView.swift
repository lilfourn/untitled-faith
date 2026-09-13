import SwiftUI

/// Owns preparation once per signed-in account, outside SwiftUI's view initializers.
struct ChatHomeView: View {
    let session: AppSession
    @State private var prepared: PreparedChat?
    @State private var didLoadFirstVerse = false
    @State private var didWaitForFirstVerse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isReady: Bool {
        prepared != nil && (didLoadFirstVerse || didWaitForFirstVerse)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if let prepared {
                ChatView(session: session, store: prepared.store, scriptureQuoter: prepared.quoter,
                         profilePhoto: prepared.photo, photoLoadFailed: prepared.photoLoadFailed, isReady: isReady,
                         onFirstVerseLoaded: { didLoadFirstVerse = true })
                    .opacity(isReady ? 1 : 0)
                    .allowsHitTesting(isReady)
                    .accessibilityHidden(!isReady)
            }
            if !isReady {
                AppLoadingView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isReady)
        .task {
            guard prepared == nil else { return }
            let storage = session.makeConversationStorage()
            let photos = session.makeProfilePhotoStorage()
            async let quoter = session.makeScriptureQuoter()
            let local = await Task.detached(priority: .userInitiated) {
                (history: Result { try storage.summaries() }, photo: Result { try photos.load() })
            }.value
            let scriptureQuoter = await quoter
            guard !Task.isCancelled else { return }
            let photoLoadFailed: Bool
            if case .failure = local.photo { photoLoadFailed = true }
            else { photoLoadFailed = false }
            prepared = PreparedChat(
                store: ChatStore(service: session.makeAnswerService(), storage: storage,
                                 quoter: scriptureQuoter, initialHistory: local.history),
                quoter: scriptureQuoter, photo: try? local.photo.get(), photoLoadFailed: photoLoadFailed)
        }
        .task(id: prepared != nil) {
            guard prepared != nil else { return }
            // An upper bound for optional content, never a minimum splash-screen duration.
            do { try await Task.sleep(for: .milliseconds(1_500)) }
            catch { return }
            didWaitForFirstVerse = true
        }
    }
}

private struct PreparedChat {
    let store: ChatStore
    let quoter: ScriptureQuoter
    let photo: UIImage?
    let photoLoadFailed: Bool
}
