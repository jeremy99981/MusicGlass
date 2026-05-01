import SwiftUI

struct LyricsScreen: View {
    @StateObject var viewModel: LyricsViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    HStack(spacing: AppSpacing.medium) {
                        ArtworkView(url: viewModel.track.bestThumbnailURL, size: 68, cornerRadius: AppRadius.small)
                        VStack(alignment: .leading) {
                            Text(viewModel.track.title)
                                .font(.headline)
                            Text(viewModel.track.artistLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, AppSpacing.medium)

                    if viewModel.isLoading {
                        LoadingSkeleton(rows: 7)
                    } else if let error = viewModel.errorMessage, viewModel.lyrics == nil {
                        ErrorStateView(message: error) { viewModel.load() }
                    } else if let lyrics = viewModel.lyrics {
                        lyricsText(lyrics)
                    }
                }
                .padding(.vertical, AppSpacing.medium)
            }
            .navigationTitle("Paroles")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.load() }
        }
    }

    @ViewBuilder
    private func lyricsText(_ lyrics: Lyrics) -> some View {
        if lyrics.syncedLines.isEmpty {
            Text(lyrics.plainText)
                .font(.title3.weight(.semibold))
                .lineSpacing(8)
                .padding(.horizontal, AppSpacing.medium)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                ForEach(lyrics.syncedLines) { line in
                    Text(line.text)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, AppSpacing.medium)
        }
    }
}
