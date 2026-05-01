import SwiftUI

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct ErrorStateView: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Réessayer", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct LoadingSkeleton: View {
    var rows: Int = 6

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: AppSpacing.medium) {
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .fill(.secondary.opacity(0.16))
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.16)).frame(height: 13)
                        RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.12)).frame(width: 150, height: 11)
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .padding()
    }
}
