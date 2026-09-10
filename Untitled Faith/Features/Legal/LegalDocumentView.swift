import SwiftUI

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Draft · September 9, 2026")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text(section.body)
                                .textSelection(.enabled)
                        }
                    }

                    if document == .privacy {
                        VStack(alignment: .leading, spacing: 16) {
                            Link("OpenRouter Privacy Policy", destination: URL(string: "https://openrouter.ai/privacy")!)
                            Link("OpenRouter Data Collection", destination: URL(string: "https://openrouter.ai/docs/guides/privacy/data-collection")!)
                            Link("Model Provider Data Policies", destination: URL(string: "https://openrouter.ai/docs/guides/privacy/provider-logging")!)
                            Link("Google Privacy Policy", destination: URL(string: "https://policies.google.com/privacy")!)
                            Link("Cloudflare Privacy Policy", destination: URL(string: "https://www.cloudflare.com/privacypolicy/")!)
                        }
                        .font(.subheadline)
                    }

                    Link("Email Untitled Faith", destination: URL(string: "mailto:untitledfaith@gmail.com")!)
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
