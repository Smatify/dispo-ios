# Fahrdienst iOS App - Ride Service Dispatching PoC

A proof-of-concept iOS app for ride service dispatching with location tracking and shift management.

## Features

### 1. Permissions Introduction
- Step-by-step introduction explaining why each permission is needed:
  - **Notifications**: For ride requests and updates
  - **Critical Notifications**: For urgent dispatches (works in Do Not Disturb)
  - **Precise Location (Always)**: For continuous tracking during shifts

### 2. Authentication
- Login screen with email and password
- Forgot password functionality
- Registration screen
- Session persistence

### 3. Main Screen
- **Start/Stop Shift** button
- Real-time location tracking when shift is active
- Debug information display:
  - Shift status
  - Current latitude/longitude
  - Speed
  - Number of updates sent
  - Last update timestamp

### 4. Location Tracking
- Continuous location updates when shift is active
- Sends location data to API based on:
  - **Distance threshold**: 50 meters minimum
  - **Time threshold**: 30 seconds minimum
- Transmits: latitude, longitude, speed, and battery percentage
- Works in background

### 5. Live Activity
- Dynamic Island and Lock Screen widget
- Shows shift status, update count, and last update time
- Updates in real-time

## Setup Instructions

### Prerequisites
- Xcode 15.0 or later
- iOS 17.0+ deployment target (for Live Activities)
- Apple Developer account (for running on device)

### Configuration

1. **Create Xcode Project**
   - Open Xcode
   - Create a new iOS App project
   - Set the project name to "Fahrdienst"
   - Choose SwiftUI as the interface
   - Copy all files from this directory into your Xcode project

2. **Enable Capabilities**
   - In Xcode, select your target
   - Go to "Signing & Capabilities"
   - Add:
     - Background Modes → Check:
       - Location updates
       - Remote notifications (if available)
   - Note: If "Push Notifications" capability is not available in your Xcode version, the entitlements file already contains the necessary configuration

3. **Configure Entitlements File**
   - The project includes `Fahrdienst.entitlements` file with `aps-environment` already configured
   - In Xcode, select your target
   - Go to "Build Settings"
   - Search for "Code Signing Entitlements"
   - Set it to `Fahrdienst.entitlements` (or the correct path relative to your project)
   - The entitlements file contains the `aps-environment` key required for push notifications
   - **Important**: Make sure the entitlements file is added to your Xcode project (drag it into the project navigator if needed)

4. **Configure Info.plist**
   - Ensure `Info.plist` includes the location usage descriptions
   - The file is already configured with necessary keys

5. **Update API Endpoint**
   - Open `Services/APIConfiguration.swift`
   - Update `baseURL` with your actual API endpoint (e.g., "https://api.yourdomain.com")
   - Update `locationUpdateEndpoint` if your API uses a different path
   - The app will now send real JSON data to your API endpoint

6. **Test on Device**
   - Location services require a physical device
   - Connect your iPhone/iPad
   - Select your device as the run destination
   - Build and run

## Project Structure

```
ios_app/
├── FahrdienstApp.swift          # App entry point
├── ContentView.swift            # Root view with navigation logic
├── Views/
│   ├── PermissionsIntroductionView.swift
│   ├── LoginView.swift
│   └── MainView.swift
├── Managers/
│   ├── AuthenticationManager.swift
│   └── LocationManager.swift
├── Services/
│   ├── APIService.swift
│   └── APIConfiguration.swift
├── Widgets/
│   └── ShiftStatusWidget.swift
└── Info.plist
```

## API Integration

The app sends real JSON data to your API endpoint. To configure:

1. **Update API Configuration**
   - Open `Services/APIConfiguration.swift`
   - Update `baseURL` with your actual API endpoint
   - Update `locationUpdateEndpoint` if needed

2. **JSON Format**
   The app sends POST requests with the following JSON structure:
   ```json
   {
     "latitude": 37.7749,
     "longitude": -122.4194,
     "speed": 5.2,
     "timestamp": "2024-01-01T12:00:00Z",
     "batteryPercentage": 82,
     "isLocationPermissionGranted": true,
     "isLowPowerModeEnabled": false,
     "isBatteryCharging": true
   }
   ```
   - `latitude`: Double (decimal degrees)
   - `longitude`: Double (decimal degrees)
   - `speed`: Double (meters per second)
   - `timestamp`: String (ISO8601 format)

3. **Authentication**
   - The auth token is automatically included in the `Authorization` header as a Bearer token
   - Format: `Authorization: Bearer <token>`
   - The token is generated during login and stored securely
   - Your API can use this token to identify which driver the location data belongs to

4. **Request Details**
   - Method: POST
   - Content-Type: application/json
   - Endpoint: `{baseURL}/location/update`
   - Expected response: HTTP 200-299 status codes

### Push Notifications

The app is configured to receive push notifications. Here's how it works:

#### Client-Side Setup (Already Implemented)

1. **Device Token Registration**
   - When the user logs in, the app automatically registers for push notifications
   - The device token is sent to your backend API at `{baseURL}/device/register`
   - Request format:
     ```json
     {
       "deviceToken": "abc123...",
       "platform": "ios",
       "timestamp": "2024-01-01T12:00:00Z"
     }
     ```
   - Headers: `Authorization: Bearer <token>`

2. **Notification Handling**
   - The app handles notifications in foreground, background, and when app is closed
   - Custom notification data can be included in the payload

#### Backend Setup (You Need to Implement)

To send push notifications to users, you need to:

1. **Store Device Tokens**
   - When you receive a device token at `/device/register`, store it in your database
   - Associate it with the user (using the auth token from the Authorization header)
   - Update the token if the user logs in from a different device

2. **Send Push Notifications via Apple Push Notification Service (APNs)**
   
   **Option A: Using APNs HTTP/2 API** (Recommended)
   - Use your Apple Developer credentials to authenticate with APNs
   - Send POST requests to `https://api.push.apple.com/3/device/{deviceToken}`
   - Include your APNs authentication key or certificate
   
   **Example notification payload:**
   ```json
   {
     "aps": {
       "alert": {
         "title": "New Ride Request",
         "body": "You have a new ride request nearby"
       },
       "sound": "default",
       "badge": 1
     },
     "rideRequestId": "12345",
     "type": "ride_request"
   }
   ```
   
   **Option B: Using a Push Notification Service**
   - Use services like Firebase Cloud Messaging (FCM), Pusher, or OneSignal
   - These services handle APNs communication for you
   - Easier to set up but may have additional costs

3. **Notification Types You Can Send**
   - **Ride Requests**: Alert driver about new ride requests
   - **Shift Reminders**: Remind driver to start/stop shift
   - **System Updates**: Important app updates or announcements
   - **Critical Alerts**: Urgent dispatches (requires special entitlement from Apple)

#### Testing Push Notifications

1. **Development Testing**
   - Use Xcode's push notification testing (requires physical device)
   - Use tools like Pusher or APNs Tester apps
   - Test with sandbox APNs environment

2. **Production**
   - Requires Apple Developer account
   - Need to configure APNs certificates/keys in Apple Developer portal
   - Use production APNs endpoint: `https://api.push.apple.com`

#### Important Notes

- **APNs Certificate/Key**: You need to generate an APNs authentication key or certificate in Apple Developer portal
- **Device Token Format**: The token is a hex string (64 characters)
- **Token Updates**: Device tokens can change, so update your database when you receive a new token
- **Background Notifications**: The app handles background notifications automatically
- **Custom Data**: You can include custom fields in the notification payload (e.g., `rideRequestId`, `type`) which the app will process

## Troubleshooting

### "Multiple commands produce Info.plist" Error

If you encounter this build error, it means `Info.plist` is being copied multiple times during the build process. To fix:

1. **Open your Xcode project**
2. **Select your target** (Fahrdienst) in the Project Navigator
3. **Go to "Build Phases" tab**
4. **Expand "Copy Bundle Resources"**
5. **Look for `Info.plist` in the list**
6. **If `Info.plist` is listed there, remove it** (select it and press Delete, or click the "-" button)
   - Note: `Info.plist` should NOT be in "Copy Bundle Resources" because Xcode automatically processes it when specified in build settings
7. **Verify the Info.plist path in Build Settings:**
   - Go to "Build Settings" tab
   - Search for "Info.plist File" (or `INFOPLIST_FILE`)
   - Ensure it's set to `Info.plist` (or the correct relative path like `Fahrdienst/Info.plist`)
8. **Clean build folder:** Product → Clean Build Folder (Shift+Cmd+K)
9. **Rebuild the project**

**Why this happens:** Xcode automatically processes `Info.plist` based on the `INFOPLIST_FILE` build setting. If it's also added to "Copy Bundle Resources", Xcode tries to copy it twice, causing the conflict.

### Push Notifications Not Supported with Free Apple Developer Account

**Important**: Free Apple Developer accounts (personal teams) do NOT support push notifications. You need a **paid Apple Developer Program membership ($99/year)** to use push notifications.

**Option 1: Remove Push Notifications for Development (Free Account)**
If you're using a free Apple Developer account and want to test the app without push notifications:

1. **Temporarily remove the aps-environment from entitlements:**
   - Open `Fahrdienst.entitlements` in Xcode
   - Remove or comment out these lines:
     ```xml
     <key>aps-environment</key>
     <string>development</string>
     ```
   - Or delete the entire entitlements file if you're not using any other entitlements
   - The app will work fine, but push notifications will be disabled

2. **Remove entitlements from Build Settings:**
   - Go to Build Settings → Code Signing Entitlements
   - Clear the value (leave it empty)
   - Clean and rebuild

3. **The app will continue to work** - all other features (location tracking, authentication, etc.) will function normally
   - Push notification registration will fail gracefully with a warning message

**Option 2: Upgrade to Paid Apple Developer Account**
To enable push notifications:
1. Sign up for Apple Developer Program at https://developer.apple.com/programs/
2. Cost: $99/year
3. After enrollment, push notifications will work automatically

### "no valid aps-environment entitlement" Error

If you encounter this error when registering for push notifications:

1. **Add Entitlements File to Xcode Project**
   - In Xcode, right-click your project folder in the navigator
   - Select "Add Files to [Project Name]..."
   - Navigate to and select `Fahrdienst.entitlements`
   - Make sure "Copy items if needed" is checked
   - Ensure your target is checked
   - Click "Add"

2. **Link Entitlements File in Build Settings**
   - Select your target in Xcode
   - Go to "Build Settings" tab
   - Search for "Code Signing Entitlements"
   - Set the value to `Fahrdienst.entitlements` (or the full path if needed)
   - The path should be relative to your project root (e.g., `Fahrdienst.entitlements`)

3. **Verify Entitlements File Content**
   - Open `Fahrdienst.entitlements` in Xcode
   - It should contain:
     ```xml
     <key>aps-environment</key>
     <string>development</string>
     ```
   - If it's missing, add it manually

4. **Manual Setup (If Push Notifications Capability Not Available)**
   - The entitlements file already has the `aps-environment` key
   - You don't need the "Push Notifications" capability if you manually configure the entitlements file
   - Just make sure the entitlements file is linked in Build Settings (step 2)

5. **For Production**
   - Change `aps-environment` from `development` to `production` in the entitlements file
   - This is required for App Store builds

6. **Clean and Rebuild**
   - Product → Clean Build Folder (Shift+Cmd+K)
   - Rebuild the project
   - Make sure you're testing on a physical device (simulator doesn't support push notifications)

### Provisioning Profile Errors with Free Account

If you see errors like:
- "Personal development teams do not support the Push Notifications capability"
- "Provisioning profile doesn't include the Push Notifications capability"

**Solution**: You have two options:

1. **Remove push notifications** (for free account development):
   - Remove `aps-environment` from `Fahrdienst.entitlements` or delete the entitlements file
   - Clear "Code Signing Entitlements" in Build Settings
   - The app will work without push notifications

2. **Upgrade to paid Apple Developer account** ($99/year):
   - Enables push notifications
   - Required for App Store distribution anyway
   - Sign up at https://developer.apple.com/programs/

## Notes

- This is a PoC (Proof of Concept) - production code would need:
  - Proper error handling
  - Secure credential storage (Keychain)
  - Token-based authentication
  - API error handling and retry logic
  - Network reachability checks
  - Battery optimization considerations

## License

Private project - All rights reserved

