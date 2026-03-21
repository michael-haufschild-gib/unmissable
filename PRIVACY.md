# Privacy Policy for Unmissable

**Effective Date:** August 15, 2025

## Overview

Unmissable is a macOS desktop application that helps you manage calendar events and meeting reminders. This privacy policy explains how we handle your data.

## Data We Access

### Google Calendar Data
- **Calendar events** (titles, times, locations, attendees)
- **Meeting links** (Google Meet, Zoom, etc.)
- **Account email** for identification purposes

### Apple Calendar Data (via EventKit)
- **Calendar events** from calendars configured in macOS (iCloud, Exchange, CalDAV)
- No account credentials are accessed — authorization is handled by macOS system permissions

### Local Data Storage
- Calendar data is stored locally on your Mac
- Meeting preferences and app settings
- OAuth tokens (encrypted in macOS Keychain)

## How We Use Your Data

- **Display upcoming meetings** in the app interface
- **Show meeting reminders** at configured times
- **Enable quick joining** of online meetings
- **Sync calendar changes** from Google Calendar

## Data Sharing

**We do not share your data with third parties.** All data remains:
- On your local device
- Between your device and Google's servers (direct connection)
- Never transmitted to our servers or any third-party services

## Data Security

- OAuth tokens stored securely in macOS Keychain
- Direct encrypted connections to Google APIs
- No data transmission to external servers
- Calendar data stored in a local SQLite database within Application Support

## Your Rights

- **Access:** View your data within the app
- **Delete:** Uninstall the app to remove all local data
- **Revoke:** Disconnect Google Calendar access anytime
- **Control:** Manage which calendars are synced

## Third-Party Services

Unmissable connects to:
- **Google Calendar API** (to read your calendar events)
- **Google OAuth 2.0** (for secure authentication)
- **Apple EventKit** (to read calendars configured in macOS System Settings)
- **Sparkle** (to check for application updates)

Google connections are governed by Google's privacy policies. Apple Calendar access uses macOS system permissions.

## Contact

For privacy questions or concerns:

- **Project**: <https://github.com/michael-h-patrianna/unmissable>
- **Issues**: Submit via GitHub Issues

## Changes

We'll update this policy as needed. Continued use constitutes acceptance of changes.

---

**Last Updated:** August 15, 2025
