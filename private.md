# Privacy Policy for Expense Book

**Effective Date:** October 9, 2026  
**Application:** Expense Book (`com.myexpense.book`)

---

## 1. Overview
At **Expense Book**, we prioritize user data privacy, security, and transparency. This Privacy Policy outlines how our application collects, processes, and protects your information when you use our mobile expense tracking application and OCR document scanner.

---

## 2. Information We Collect & Use

### A. Local Financial Data (Offline-First)
- **What is stored:** Expense amounts, category classifications, transaction dates, merchant names, notes, family profile tags, and monthly budget limits.
- **Storage Location:** Stored exclusively in a local SQLite database on your physical device.
- **Data Transmission:** This data is **never** uploaded to external servers without your explicit manual action (e.g., exporting a local JSON backup file).

### B. Camera & Storage Access (OCR Receipt Scanning)
- **Purpose:** To allow users to capture photos of receipt slips, store bills, and tax invoices, or attach PDF documents for automated item name, total price, merchant, date, and time extraction.
- **Data Handling:** Image optical character recognition (OCR) is performed locally on-device. Images uploaded or processed are strictly stored in local device storage for expense attachment purposes and are never sold or used for advertising.

### C. Google Authentication (Firebase Auth)
- **What is collected:** Google Account email address, display name, and unique user identifier (UID).
- **Purpose:** Used strictly for secure user authentication and account login verification.

### D. Device Permissions
- **Notifications & Vibration (`POST_NOTIFICATIONS`, `VIBRATE`):** To deliver scheduled expense logging reminders and notifications.
- **Biometric Security (`USE_BIOMETRIC`, `USE_FINGERPRINT`):** For optional fingerprint/face security app lock.

---

## 3. Data Sharing & Third-Party Services
- **No Third-Party Data Sales:** We do **NOT** sell, rent, trade, or monetize your personal or financial data under any circumstances.
- **Google Mobile Ads (AdMob):** Expense Book integrates Google Mobile Ads to serve Banner, Interstitial, and Rewarded Ads. Google AdMob may collect non-personal device identifiers in accordance with Google's Privacy Policy. Users can permanently disable all ads via a one-time "Remove Ads" in-app purchase.

---

## 4. Security & Data Retention
We implement industry-standard security measures to safeguard your data:
- **Local Storage Isolation:** All application data is stored in isolated app storage protected by Android system security sandbox boundaries.
- **Device Lock Protection:** Optional Fingerprint / Face ID security lock can be enabled.
- **Data Erasure:** You can flush all local data immediately by clearing app storage or deleting your account in settings.

---

## 5. User Rights & Data Control
You have the right to:
1. Grant or revoke Camera or Storage permissions at any time via OS Settings.
2. Export your expense history and backup database at any time.
3. Delete individual expenses, receipt attachments, or clear all app data permanently via Settings.

---

## 6. Contact Us
For any privacy questions or requests regarding your data, please contact:  
- **Developer:** Muhammad Faisal Khan  
- **Email:** android.nextlevel@gmail.com  
- **GitHub Repository:** https://github.com/tafaisalkhan/expense_book.git
