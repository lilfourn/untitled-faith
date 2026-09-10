import SwiftUI

struct SettingsView: View {
    @Bindable var session: AppSession
    @Binding var profilePhoto: UIImage?
    var beforeAccountDeletion: () async -> Void = {}
    var beforeSignOut: () async -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var showingContribution = false
    @State private var legalDocument: LegalDocument?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 36) {
                        ProfilePhotoPicker(photo: $profilePhoto) { image in
                            guard !session.isDeletingAccount, session.isSignedIn || session.isPreview else {
                                throw CancellationError()
                            }
                            try session.makeProfilePhotoStorage().save(image)
                        }
                            .disabled(session.isDeletingAccount)
                            .padding(.top, 24)

                        UsageSection(session: session, addUsage: { showingContribution = true })

                        VStack(alignment: .leading, spacing: 20) {
                            Toggle("AI answers", isOn: $session.aiSharingAllowed)
                                .disabled(session.hasPendingDeletion)
                            Button("Privacy Policy") { legalDocument = .privacy }
                            Button("Terms of Use") { legalDocument = .terms }
                            Button("Sign out") {
                                Task {
                                    guard await beforeSignOut() else { dismiss(); return }
                                    session.signOut()
                                }
                            }
                            .disabled(session.isDeletingAccount || session.hasPendingDeletion)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if session.hasPendingDeletion {
                            Text("Account deletion is pending. Retry to finish removing your account and this device’s saved data.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Retry account deletion") { Task { await session.resumeAccountDeletion() } }
                                .disabled(session.isDeletingAccount)
                        }

                        Spacer(minLength: 20)

                        Button(role: .destructive) {
                            confirmingDeletion = true
                        } label: {
                            HStack(spacing: 10) {
                                if session.isDeletingAccount { ProgressView() }
                                Text(session.isDeletingAccount ? "Deleting account…" : "Delete account")
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .disabled(!session.isSignedIn || session.isDeletingAccount || session.hasPendingDeletion)

                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: 520)
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .background(AppTheme.background)
            }
            .navigationTitle("Settings")
            .sheet(item: $legalDocument) { LegalDocumentView(document: $0) }
            .fullScreenCover(isPresented: $showingContribution, onDismiss: { session.refreshUsage(force: true) }) { ContributionPaymentSheet(session: session) }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete your account? This removes this device’s saved conversations, profile photo, and sign-in session, and revokes Untitled Faith’s access to your Apple sign-in.", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task {
                        await beforeAccountDeletion()
                        await session.deleteAccount()
                    }
                }
            }
            .alert("Account", isPresented: Binding(
                get: { session.signInError != nil },
                set: { if !$0 { session.signInError = nil } }
            )) {
                Button("OK", role: .cancel) { session.signInError = nil }
            } message: {
                Text(session.signInError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
