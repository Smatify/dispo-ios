import Foundation
import CoreNFC
import SwiftUI
import Combine

class NFCManager: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published var isScanning = false
    @Published var scannedTagID: String?
    @Published var scannedCMAC: String?
    @Published var errorMessage: String?
    @Published var lastScanResult: NFCScanResult?
    
    private var nfcSession: NFCTagReaderSession?
    
    struct NFCScanResult {
        let tagID: String
        let cmac: String?
        let timestamp: Date
    }
    
    func startScanning() {
        guard NFCTagReaderSession.readingAvailable else {
            #if targetEnvironment(simulator)
            errorMessage = "NFC reading is not available in the simulator. Please test on a physical device."
            #else
            errorMessage = "NFC reading is not available. Please ensure:\n1. NFC capability is enabled in Xcode\n2. App is signed with proper provisioning profile\n3. Device supports NFC (iPhone 7 or later)"
            #endif
            return
        }
        
        isScanning = true
        errorMessage = nil
        scannedTagID = nil
        scannedCMAC = nil
        
        // Create NFC session
        nfcSession = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self)
        nfcSession?.alertMessage = "Hold your iPhone near the NFC tag"
        nfcSession?.begin()
    }
    
    func stopScanning() {
        nfcSession?.invalidate(errorMessage: "Scan cancelled")
        nfcSession = nil
        isScanning = false
    }
    
    // MARK: - NFCTagReaderSessionDelegate
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session became active - no action needed
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.isScanning = false
            self.nfcSession = nil
            
            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled:
                    // User cancelled - not an error
                    break
                case .readerSessionInvalidationErrorSystemIsBusy:
                    self.errorMessage = "System is busy. Please try again."
                case .readerSessionInvalidationErrorSessionTimeout:
                    self.errorMessage = "Session timed out. Please try again."
                default:
                    self.errorMessage = "NFC error: \(error.localizedDescription)"
                }
            } else {
                self.errorMessage = "NFC error: \(error.localizedDescription)"
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag detected")
            return
        }
        
        session.connect(to: tag) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to connect to tag: \(error.localizedDescription)"
                    self.isScanning = false
                }
                session.invalidate(errorMessage: "Connection failed")
                return
            }
            
            // Handle different tag types
            // NTAG424 uses MiFare interface
            switch tag {
            case .miFare(let miFareTag):
                self.handleMiFareTag(miFareTag, session: session)
            case .iso15693(let iso15693Tag):
                self.handleISO15693Tag(iso15693Tag, session: session)
            case .feliCa(let feliCaTag):
                self.handleFeliCaTag(feliCaTag, session: session)
            case .iso7816(let iso7816Tag):
                self.handleISO7816Tag(iso7816Tag, session: session)
            @unknown default:
                DispatchQueue.main.async {
                    self.errorMessage = "Unsupported tag type"
                    self.isScanning = false
                }
                session.invalidate(errorMessage: "Unsupported tag type")
            }
        }
    }
    
    // MARK: - Tag Type Handlers
    
    private func handleISO15693Tag(_ tag: NFCISO15693Tag, session: NFCTagReaderSession) {
        // NTAG424 uses ISO15693 protocol
        readNTAG424Data(tag: tag, session: session)
    }
    
    private func handleMiFareTag(_ tag: NFCMiFareTag, session: NFCTagReaderSession) {
        // NTAG424 tags use MiFare interface
        readNTAG424FromMiFare(tag: tag, session: session)
    }
    
    private func handleFeliCaTag(_ tag: NFCFeliCaTag, session: NFCTagReaderSession) {
        DispatchQueue.main.async {
            self.errorMessage = "FeliCa tags are not supported"
            self.isScanning = false
        }
        session.invalidate(errorMessage: "Unsupported tag type")
    }
    
    private func handleISO7816Tag(_ tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        DispatchQueue.main.async {
            self.errorMessage = "ISO7816 tags are not supported"
            self.isScanning = false
        }
        session.invalidate(errorMessage: "Unsupported tag type")
    }
    
    // MARK: - NTAG424 Specific Reading
    
    private func readNTAG424Data(tag: NFCISO15693Tag, session: NFCTagReaderSession) {
        // Read UID (Tag ID) - stored in block 0
        // NTAG424 UID is 7 bytes
        tag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber: 0) { [weak self] data, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to read tag ID: \(error.localizedDescription)"
                    self.isScanning = false
                }
                session.invalidate(errorMessage: "Read failed")
                return
            }
            
            guard data.count >= 4 else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid tag data"
                    self.isScanning = false
                }
                session.invalidate(errorMessage: "Invalid data")
                return
            }
            
            // Extract UID from the data
            // NTAG424 UID is typically in the first 7 bytes
            let uidData = data.prefix(7)
            let tagID = uidData.map { String(format: "%02X", $0) }.joined()
            
            // Try to read CMAC
            // CMAC is typically stored in the file system or can be read from specific blocks
            // For NTAG424, CMAC might be in block 0x85 (File 5) or calculated after authentication
            self.readCMAC(tag: tag, session: session, tagID: tagID)
        }
    }
    
    private func readNTAG424FromMiFare(tag: NFCMiFareTag, session: NFCTagReaderSession) {
        // NTAG424 UID is stored in the tag identifier (7 bytes)
        let tagID = tag.identifier.map { String(format: "%02X", $0) }.joined()
        
        // For NTAG424, CMAC is stored in File 5 (CMAC file)
        // To read CMAC, we typically need to authenticate first with a key
        // CMAC file starts at block 0x85 (File 5 header)
        // We'll try to read it, but it may require authentication
        
        // Try reading block 0x85 (File 5 header) where CMAC might be accessible
        tag.sendMiFareCommand(commandPacket: Data([0x30, 0x85])) { [weak self] response, error in
            guard let self = self else { return }
            
            var cmac: String? = nil
            
            if response.count >= 16 {
                // NTAG424 CMAC is 8 bytes
                // It might be in the response data
                // Try extracting from different positions
                if response.count >= 8 {
                    // Try last 8 bytes
                    let potentialCMAC = response.suffix(8)
                    // Check if it looks like valid CMAC (not all zeros)
                    if !potentialCMAC.allSatisfy({ $0 == 0 }) {
                        cmac = potentialCMAC.map { String(format: "%02X", $0) }.joined()
                    }
                }
            }
            
            // If we couldn't read CMAC, it likely requires authentication
            DispatchQueue.main.async {
                self.scannedTagID = tagID
                self.scannedCMAC = cmac
                self.lastScanResult = NFCScanResult(tagID: tagID, cmac: cmac, timestamp: Date())
                self.isScanning = false
            }
            
            let message = cmac != nil ? "Tag read successfully" : "Tag ID read (CMAC requires authentication)"
            session.invalidate(errorMessage: message)
        }
    }
    
    private func readCMAC(tag: NFCISO15693Tag, session: NFCTagReaderSession, tagID: String) {
        // NTAG424 CMAC reading requires authentication
        // CMAC is typically stored in File 5 (block 0x85) or can be calculated
        // For now, we'll try to read from common CMAC locations
        
        // Try reading block 0x85 (File 5 header) where CMAC might be stored
        tag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber: 0x85) { [weak self] data, error in
            guard let self = self else { return }
            
            var cmac: String? = nil
            
            if data.count >= 16 {
                // CMAC is typically 8 bytes, might be in the data
                // Extract last 8 bytes as potential CMAC
                let cmacData = data.suffix(8)
                cmac = cmacData.map { String(format: "%02X", $0) }.joined()
            }
            
            DispatchQueue.main.async {
                self.scannedTagID = tagID
                self.scannedCMAC = cmac
                self.lastScanResult = NFCScanResult(tagID: tagID, cmac: cmac, timestamp: Date())
                self.isScanning = false
            }
            
            session.invalidate(errorMessage: cmac != nil ? "Tag read successfully" : "Tag ID read (CMAC requires authentication)")
        }
    }
}

