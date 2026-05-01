import SwiftUI

struct SettingsScreen: View {
    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogin = false
    @ObservedObject private var authService: AuthService

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _authService = ObservedObject(wrappedValue: viewModel.authService)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compte YouTube Music") {
                    if authService.isAuthenticated {
                        LabeledContent("Statut", value: "Connecté")
                        Button(role: .destructive) {
                            authService.clear()
                        } label: {
                            Text("Se déconnecter")
                        }
                    } else {
                        LabeledContent("Statut", value: "Non connecté")
                        Button {
                            showingLogin = true
                        } label: {
                            Text("Se connecter à YouTube Music")
                        }
                    }
                }

                Section("Apparence") {
                    Picker("Thème", selection: $viewModel.theme) {
                        Text("Système").tag("System")
                        Text("Clair").tag("Light")
                        Text("Sombre").tag("Dark")
                    }
                    Picker("Qualité audio", selection: $viewModel.audioQuality) {
                        Text("Auto").tag("Auto")
                        Text("Élevée").tag("High")
                        Text("Économie de données").tag("Data Saver")
                    }
                }

                Section("Cache") {
                    LabeledContent("Taille du cache", value: viewModel.cacheSizeText)
                    Button(role: .destructive) {
                        viewModel.clearCache()
                    } label: {
                        Label("Vider le cache", systemImage: "trash")
                    }
                }

                Section("Débogage") {
                    Toggle("Journaux de débogage", isOn: $viewModel.debugLogsEnabled)
                }

                Section("À propos") {
                    LabeledContent("Version", value: "1.0 MVP")
                    Text("MusicGlass est un prototype de client musical tiers. Il n’est pas affilié à YouTube, Google, Apple ni à leurs filiales. Aucun identifiant ni secret d’API n’est intégré dans l’app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
            .task { viewModel.loadCacheSize() }
            .sheet(isPresented: $showingLogin) {
                LoginWebView(onLoginSuccess: { cookies, dataSyncId, visitorData in
                    authService.saveAuthData(cookies: cookies, dataSyncId: dataSyncId, visitorData: visitorData)
                }, isPresented: $showingLogin)
            }
        }
    }
}
