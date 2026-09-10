import SwiftUI

struct SettingsView: View {
    let session: AppSession
    @Binding var profilePhoto: UIImage?
    var beforeAccountDeletion: () async -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var showingContribution = false

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

                        Spacer(minLength: 40)

                        Button(role: .destructive) {
                            confirmingDeletion = true
                        } label: {
                            HStack(spacing: 10) {
                                if session.isDeletingAccount { ProgressView() }
                                Text(session.isDeletingAccount ? "Deleting account…" : "Delete account")
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .disabled(!session.isSignedIn || session.isDeletingAccount)

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
            .fullScreenCover(isPresented: $showingContribution, onDismiss: { session.refreshUsage(force: true) }) { ContributionWizard() }
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
