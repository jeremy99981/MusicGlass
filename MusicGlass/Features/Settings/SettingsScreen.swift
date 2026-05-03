import SwiftUI

struct SettingsScreen: View {
    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingLogin = false
    @AppStorage("musicglass.loginFlowInProgress") private var loginFlowInProgress = false
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
                            loginFlowInProgress = true
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
            .onAppear {
                if loginFlowInProgress, !authService.isAuthenticated {
                    showingLogin = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                // If the login sheet was closed by an app switch, reopen it on return.
                if loginFlowInProgress, !showingLogin, !authService.isAuthenticated {
                    showingLogin = true
                }
            }
            .sheet(isPresented: $showingLogin) {
                NavigationStack {
                    LoginWebView(onLoginSuccess: { cookies, dataSyncId, visitorData in
                        authService.saveAuthData(cookies: cookies, dataSyncId: dataSyncId, visitorData: visitorData)
                        loginFlowInProgress = false
                    }, isPresented: $showingLogin)
                    .navigationTitle("Connexion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") {
                                loginFlowInProgress = false
                                showingLogin = false
                            }
                        }
                    }
                }
            }
        }
    }
}
