import SwiftUI
import CoreLocation

struct MainView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var nfcManager: NFCManager
    @State private var showLogoutAlert = false
    @State private var showNFCResult = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Fahrdienst Dispatch")
                        .font(.title)
                        .fontWeight(.bold)
                    Text(authManager.currentUser?.email ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Shift Button
                Button(action: {
                    if locationManager.isShiftActive {
                        locationManager.stopShift()
                    } else {
                        locationManager.startShift()
                    }
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: locationManager.isShiftActive ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                        Text(locationManager.isShiftActive ? "Stop Shift" : "Start Shift")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(locationManager.isShiftActive ? Color.red : Color.green)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .disabled(locationManager.isRequestingLocationPermission)
                
                if locationManager.isRequestingLocationPermission {
                    Text("Please grant location permission in Settings")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // NFC Scan Button
                Button(action: {
                    nfcManager.startScanning()
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill")
                            .font(.system(size: 40))
                        Text("Scan NFC Tag")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.blue)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .disabled(nfcManager.isScanning)
                
                // NFC Scan Results
                if let result = nfcManager.lastScanResult {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NFC Tag Scanned")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        DebugRow(label: "Tag ID", value: result.tagID)
                        if let cmac = result.cmac {
                            DebugRow(label: "CMAC", value: cmac)
                        } else {
                            DebugRow(label: "CMAC", value: "Not available (requires authentication)")
                        }
                        DebugRow(label: "Scanned At", value: DateFormatter.timeFormatter.string(from: result.timestamp))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                }
                
                if let errorMessage = nfcManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                if nfcManager.isScanning {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Scanning for NFC tag...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                }
                
                // Debug Info
                if locationManager.isShiftActive {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Debug Info")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        DebugRow(label: "Status", value: locationManager.isShiftActive ? "Active" : "Inactive")
                        DebugRow(label: "Latitude", value: String(format: "%.6f", locationManager.lastLocation?.coordinate.latitude ?? 0))
                        DebugRow(label: "Longitude", value: String(format: "%.6f", locationManager.lastLocation?.coordinate.longitude ?? 0))
                        DebugRow(label: "Speed", value: String(format: "%.2f m/s", locationManager.lastLocation?.speed ?? 0))
                        DebugRow(label: "Updates Sent", value: "\(locationManager.updateCount)")
                        DebugRow(label: "Last Update", value: locationManager.lastUpdateTime ?? "Never")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showLogoutAlert = true
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    locationManager.stopShift()
                    authManager.logout()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
    }
}

struct DebugRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

