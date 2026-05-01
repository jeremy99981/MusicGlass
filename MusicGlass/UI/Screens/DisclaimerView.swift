import SwiftUI

struct DisclaimerView: View {
    var continueAction: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.deepBackground, Color(red: 0.12, green: 0.05, blue: 0.08), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppSpacing.large) {
                Spacer()
                ArtworkView(url: nil, size: 104, cornerRadius: 28)
                VStack(spacing: AppSpacing.small) {
                    Text("MusicGlass")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Un prototype natif premium pour écouter votre musique.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.74))
                        .multilineTextAlignment(.center)
                }
                Text("Cette app est un client tiers. Elle n’est pas affiliée, approuvée, sponsorisée ni associée à YouTube, Google, Apple ou leurs filiales. Utilisez-la de manière responsable et respectez les conditions des services, les droits d’auteur et la disponibilité régionale.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.large)
                Spacer()
                Button(action: continueAction) {
                    Text("Continuer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(AppColors.accent, in: Capsule())
                .padding(.horizontal, AppSpacing.large)
                .padding(.bottom, AppSpacing.xLarge)
            }
        }
    }
}
