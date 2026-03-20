#!/bin/bash

# Simple Portable Installer Creator
# Creates a ready-to-use app package with OAuth already configured

set -e

echo "📦  Creating portable app package..."
echo "===================================="

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="Unmissable-Ready-To-Use"
PACKAGE_DIR="${PROJECT_DIR}/${PACKAGE_NAME}"
ZIP_NAME="${PROJECT_DIR}/${PACKAGE_NAME}.zip"
APP_BUNDLE_PATH="${PROJECT_DIR}/Unmissable.app"
cd "$PROJECT_DIR"

# Clean previous package
echo "🧹  Cleaning previous package..."
rm -rf "${PACKAGE_DIR}" "${ZIP_NAME}"

# Build latest release first
echo "🏗️  Building latest release..."
"${PROJECT_DIR}/Scripts/build-release.sh"

# Create package structure
echo "📁  Creating package structure..."
mkdir -p "${PACKAGE_DIR}"

# Copy the complete app bundle (with OAuth already configured)
echo "📋  Copying complete app bundle..."
cp -R "${APP_BUNDLE_PATH}" "${PACKAGE_DIR}/"

# Create simple installation README
echo "📖  Creating installation instructions..."
cat > "${PACKAGE_DIR}/README.md" << 'EOF'
# Unmissable - Ready to Use

## 🚀 Quick Installation

1. **Copy to Applications**:
   ```bash
   mv Unmissable.app /Applications/
   ```

2. **First Launch**:
   - Open from Applications folder
   - macOS may ask "Are you sure you want to open this app?"
   - Click "Open" to confirm

3. **Connect Google Calendar**:
   - Click "Connect Google Calendar" 
   - Follow OAuth flow in browser
   - Grant calendar permissions

## ✅ What's Included

- **Complete App**: Unmissable.app with all dependencies
- **OAuth Pre-configured**: Google Calendar integration ready
- **No Setup Required**: Works immediately after copying to Applications

## 🔒 Security

- **Self-Signed**: Safe to use, no Apple Developer account required
- **Local Data**: All calendar data stored locally on your machine
- **No Telemetry**: No data collection or analytics

## 🆘 Troubleshooting

If macOS prevents opening:
1. Go to System Settings > General > Login Items & Extensions
2. Click "Allow" next to Unmissable
3. Or run: `xattr -d com.apple.quarantine /Applications/Unmissable.app`

## 📞 IT Department Info

- **Bundle ID**: com.unmissable.app
- **Signature**: Ad-hoc (self-signed)
- **Permissions**: Calendar access via OAuth 2.0
- **Network**: HTTPS to Google Calendar API only
EOF

# Create simple install script
echo "🔧  Creating install script..."
cat > "${PACKAGE_DIR}/install.sh" << 'EOF'
#!/bin/bash

echo "🚀  Installing Unmissable..."

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌  This app is for macOS only"
    exit 1
fi

# Check if app exists
if [[ ! -d "Unmissable.app" ]]; then
    echo "❌  Unmissable.app not found in current directory"
    exit 1
fi

# Copy to Applications
echo "📱  Copying to Applications folder..."
	if [[ -d "/Applications/Unmissable.app" ]]; then
	    echo "⚠️  Replacing existing version..."
	    if [[ -w "/Applications" ]]; then
	        rm -rf "/Applications/Unmissable.app"
	    else
	        sudo rm -rf "/Applications/Unmissable.app"
	    fi
	fi

	if [[ -w "/Applications" ]]; then
	    cp -R "Unmissable.app" "/Applications/"
	else
	    sudo cp -R "Unmissable.app" "/Applications/"
	fi

# Remove quarantine attribute
echo "🔓  Removing quarantine attribute..."
xattr -d com.apple.quarantine "/Applications/Unmissable.app" 2>/dev/null || true

echo "✅  Installation complete!"
echo ""
echo "🎉  You can now:"
echo "   1. Open Unmissable from Applications folder"
echo "   2. Connect your Google Calendar"
echo "   3. Enjoy unmissable meeting reminders!"

EOF

chmod +x "${PACKAGE_DIR}/install.sh"

# Create compressed package
echo "🗜️  Creating compressed package..."
(cd "$PROJECT_DIR" && zip -r "${ZIP_NAME}" "${PACKAGE_NAME}/")

# Get package size
PACKAGE_SIZE=$(du -sh "${ZIP_NAME}" | cut -f1)

echo ""
echo "✅  Portable package created!"
echo ""
echo "📦  Package: ${ZIP_NAME}"
echo "📏  Size: ${PACKAGE_SIZE}"
echo ""
echo "📋  Contents:"
ls -la "${PACKAGE_DIR}/"
echo ""
echo "🚀  Ready to distribute!"
echo "   1. Send ${ZIP_NAME} to any Mac"
echo "   2. Extract and run ./install.sh"
echo "   3. App works immediately with OAuth pre-configured"
echo ""
echo "🎯  This is a complete, ready-to-use package!"
