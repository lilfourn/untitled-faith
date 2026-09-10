import ImageIO
import PhotosUI
import SwiftUI

struct ProfilePhotoPicker: View {
    @Binding var photo: UIImage?
    @State private var selection: PhotosPickerItem?
    @State private var isLoading = false
    @State private var showingError = false

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(AppTheme.surface)
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 52, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.background)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accent, in: Circle())
                        .overlay(Circle().stroke(AppTheme.background, lineWidth: 3))
                }

                if isLoading {
                    ProgressView("Loading photo…")
                } else {
                    Text(photo == nil ? "Add profile photo" : "Change photo")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo == nil ? "Add profile photo" : "Change profile photo")
        .task(id: selection) { await loadPhoto() }
        .alert("Couldn’t load photo", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please choose another photo or try again.")
        }
    }

    @MainActor
    private func loadPhoto() async {
        guard let selection else { return }
        isLoading = true
        showingError = false
        defer {
            if self.selection == selection { isLoading = false }
        }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw PhotoError.unreadable
            }
            try Task.checkCancellation()
            // Retain only a small decoded thumbnail in memory, with no file or cloud writes.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512
                  ] as CFDictionary) else { throw PhotoError.unreadable }
            photo = UIImage(cgImage: thumbnail)
            self.selection = nil
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            showingError = true
            self.selection = nil
            isLoading = false
        }
    }

    private enum PhotoError: Error {
        case unreadable
    }
}
