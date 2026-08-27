import SwiftUI
import TallyDesignSystem
import TallySecurity

public struct SettingsView: View {
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @State private var showingBiometricError = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
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
            .navigationBarHidden(true)
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
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Account", icon: "person.circle")
            
            VStack(spacing: 0) {
                settingsRow(icon: "building.columns", iconColor: Color.Tally.calculusBlue, title: "Institution", detail: "Canvas LMS")
                Divider().padding(.leading, 64)
                settingsRow(icon: "arrow.triangle.2.circlepath", iconColor: Color.Tally.historyOrange, title: "Sync Frequency", detail: "Every 10s")
                Divider().padding(.leading, 64)
                settingsRow(icon: "trash", iconColor: Color.Tally.alertRed, title: "Clear Cache", detail: nil, isDestructive: true)
                Divider().padding(.leading, 64)
                settingsRow(icon: "rectangle.portrait.and.arrow.right", iconColor: Color.Tally.alertRed, title: "Sign Out", detail: nil, isDestructive: true)
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
