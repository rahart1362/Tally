import SwiftUI
import TallyDesignSystem
import TallySecurity

public struct SettingsView: View {
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @State private var showingBiometricError = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                Text("Settings")
                    .font(.Tally.title)
                    .foregroundColor(Color.Tally.cardBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                
                ScrollView {
                    LazyVStack(spacing: 20) {
                        securitySection
                        integrationsSection
                        accountSection
                        aboutSection
                    }
                    .padding()
                }
            }
            .padding(.top, 16)
            .background(
                VStack(spacing: 0) {
                    Color.Tally.navyBackground
                        .frame(height: 100)
                    Color.Tally.lightGrayBg
                }
                .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
            .alert("Authentication Failed", isPresented: $showingBiometricError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not verify your identity. Please try again.")
            }
        }
    }
    
    // MARK: - Security & Privacy Section
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Security & Privacy", icon: "lock.shield")
            
            VStack(spacing: 0) {
                // Face ID / Touch ID toggle
                if biometricManager.isBiometricAvailable {
                    HStack(spacing: 16) {
                        Image(systemName: biometricManager.biometricIconName)
                            .font(.system(size: 22))
                            .foregroundColor(Color.Tally.calculusBlue)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock with \(biometricManager.biometricName)")
                                .font(.Tally.headline)
                                .foregroundColor(Color.Tally.textPrimary)
                            Text("Require \(biometricManager.biometricName) when opening Tally")
                                .font(.Tally.caption)
                                .foregroundColor(Color.Tally.textSecondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { biometricManager.isBiometricEnabled },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        let success = await biometricManager.enableBiometric()
                                        if !success {
                                            showingBiometricError = true
                                        }
                                    }
                                } else {
                                    biometricManager.disableBiometric()
                                }
                            }
                        ))
                        .tint(Color.Tally.psychologyGreen)
                        .labelsHidden()
                    }
                    .padding(16)
                    
                    Divider().padding(.leading, 64)
                } else {
                    // Device doesn't support biometrics
                    HStack(spacing: 16) {
                        Image(systemName: "lock.slash")
                            .font(.system(size: 22))
                            .foregroundColor(Color.Tally.textSecondary)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Biometric Unlock")
                                .font(.Tally.headline)
                                .foregroundColor(Color.Tally.textSecondary)
                            Text("Not available on this device")
                                .font(.Tally.caption)
                                .foregroundColor(Color.Tally.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    
                    Divider().padding(.leading, 64)
                }
                
                // Data protection info row
                HStack(spacing: 16) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 22))
                        .foregroundColor(Color.Tally.psychologyGreen)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data Protection")
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text("All cached data is encrypted at rest")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.Tally.psychologyGreen)
                }
                .padding(16)
            }
            .background(Color.Tally.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    // MARK: - Integrations Section
    
    @State private var syncCalendar: Bool = true
    @State private var syncMS365: Bool = false
    @State private var syncGoogle: Bool = false
    @State private var pushNotifications: Bool = true
    
    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Integrations & Sync", icon: "arrow.triangle.2.circlepath")
            
            VStack(spacing: 0) {
                // Background Sync
                settingsRow(icon: "clock.arrow.circlepath", iconColor: Color.Tally.biologyPurple, title: "Background Sync", detail: "Optimized (Every 6h)")
                Divider().padding(.leading, 64)
                
                // Calendar Sync Toggle (Apple)
                HStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(Color.Tally.alertRed)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Calendar")
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text("Sync courses & exams to iOS Calendar")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $syncCalendar)
                        .tint(Color.Tally.psychologyGreen)
                        .labelsHidden()
                }
                .padding(16)
                Divider().padding(.leading, 64)
                
                // Calendar Sync Toggle (MS365)
                HStack(spacing: 16) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 22))
                        .foregroundColor(Color.Tally.calculusBlue)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microsoft 365")
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text("Sync to Outlook / School Account")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $syncMS365)
                        .tint(Color.Tally.psychologyGreen)
                        .labelsHidden()
                }
                .padding(16)
                Divider().padding(.leading, 64)
                
                // Calendar Sync Toggle (Google)
                HStack(spacing: 16) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color.Tally.historyOrange)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Workspace")
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text("Sync to Google Calendar")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $syncGoogle)
                        .tint(Color.Tally.psychologyGreen)
                        .labelsHidden()
                }
                .padding(16)
                Divider().padding(.leading, 64)
                
                // Notifications Toggle
                HStack(spacing: 16) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 22))
                        .foregroundColor(Color.Tally.historyOrange)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reminders")
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text("Push notifications 24h before due dates")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $pushNotifications)
                        .tint(Color.Tally.psychologyGreen)
                        .labelsHidden()
                }
                .padding(16)
            }
            .background(Color.Tally.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Account", icon: "person.circle")
            
            VStack(spacing: 0) {
                settingsRow(icon: "building.columns", iconColor: Color.Tally.calculusBlue, title: "Institution", detail: "Canvas LMS")
                Divider().padding(.leading, 64)
                Button(action: {
                    print("Clear Cache tapped")
                }) {
                    settingsRow(icon: "trash", iconColor: Color.Tally.alertRed, title: "Clear Cache", detail: nil, isDestructive: true)
                }
                Divider().padding(.leading, 64)
                Button(action: {
                    do {
                        try KeychainManager.shared.delete(account: "canvas")
                        BiometricAuthManager.shared.disableBiometric()
                        UserDefaults.standard.set(false, forKey: "isLoggedIn")
                    } catch {
                        print("Failed to sign out: \(error)")
                    }
                }) {
                    settingsRow(icon: "rectangle.portrait.and.arrow.right", iconColor: Color.Tally.alertRed, title: "Sign Out", detail: nil, isDestructive: true)
                }
            }
            .background(Color.Tally.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "About", icon: "info.circle")
            
            VStack(spacing: 0) {
                settingsRow(icon: "doc.text", iconColor: Color.Tally.textSecondary, title: "Privacy Policy", detail: nil)
                Divider().padding(.leading, 64)
                settingsRow(icon: "number", iconColor: Color.Tally.textSecondary, title: "Version", detail: "1.0.0")
            }
            .background(Color.Tally.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color.Tally.textSecondary)
            Text(title)
                .font(.Tally.headline)
                .foregroundColor(Color.Tally.textSecondary)
        }
    }
    
    private func settingsRow(icon: String, iconColor: Color, title: String, detail: String?, isDestructive: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 32)
            
            Text(title)
                .font(.Tally.headline)
                .foregroundColor(isDestructive ? Color.Tally.alertRed : Color.Tally.textPrimary)
            
            Spacer()
            
            if let detail = detail {
                Text(detail)
                    .font(.Tally.caption)
                    .foregroundColor(Color.Tally.textSecondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.Tally.textSecondary)
        }
        .padding(16)
    }
}

