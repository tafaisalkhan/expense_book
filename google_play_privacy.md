# Google Play Privacy & Data Safety Summary

This document provides a concise privacy disclosure formatted specifically for Google Play Console submission and app store listing compliance.

---

## Data Collection & Usage Overview

1. **No External Data Sales:** Expense Book does **not** sell, rent, or share any personal or financial data with third-party advertisers or data brokers.
2. **On-Device Data Processing:**
   - **Local Financial Data:** Stored in a local SQLite database on your physical device.
   - **Receipt OCR Photos & PDFs:** Processed locally using ML Kit to extract items, totals, dates, and times.
3. **User Control & Deletion:** Users can edit or delete any expense record, revoke Android permissions anytime in OS Settings, or wipe all app data completely.

---

## Play Console Data Safety Entries
- **Financial Info:** Collected for App Functionality (Stored locally, Not Shared)
- **Photos & Docs:** Collected for App Functionality (Stored locally, Not Shared)
- **Personal Info:** Name & Email for Identity Verification (Google Sign-In)
- **Encryption in Transit:** Yes (TLS/HTTPS for Google Auth & sync endpoints)
- **Data Deletion Mechanism:** Yes (In-app clear data & local storage wipe)
