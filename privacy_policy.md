# Privacy Policy for Expense Book

**Effective Date:** September 29, 2026  
**Application Name:** Expense Book  
**Package Name:** `com.myexpense.book`  
**Developer:** Tafaisalkhan  

---

## 1. Overview
**Expense Book** ("we", "our", or "us") is dedicated to protecting your privacy. This Privacy Policy explains how our application handles information, user data, device permissions, and advertising when you use the Expense Book mobile application.

Expense Book is built on an **Offline-First Architecture**. Your financial records, receipts, categories, budgets, and personal profiles are stored locally on your device by default.

---

## 2. Information We Collect & How It Is Used

### A. Local Financial Data (Offline-First)
* **What is stored:** Expense amounts, category classifications, transaction dates, merchant names, notes, family profile tags, and monthly budget limits.
* **Storage Location:** Stored exclusively in a local SQLite database on your device.
* **Data Transmission:** This data is **never** uploaded to external servers without your explicit manual action (e.g., exporting a local backup file).

### B. Google Authentication (Firebase Auth)
* **What is collected:** Google Account email address, display name, and unique user identifier (UID).
* **Purpose:** Used strictly for secure user authentication and account login verification.

### C. SMS Reading & Auto-Parsing Permission (`READ_SMS`, `RECEIVE_SMS`)
* **Purpose:** Allows the app to auto-detect bank transaction SMS notifications from user-whitelisted senders (e.g., bank debit/credit alerts).
* **Processing:** All SMS parsing occurs **100% locally on your device**. Raw SMS text is never transmitted to external servers.
* **User Control:** SMS parsing requires explicit user approval before any transaction is saved. Users can add or remove whitelisted senders at any time.

### D. Location & Geofencing Permission (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`)
* **Purpose:** Triggers optional post-visit expense reminders when you enter or exit specified commercial areas (e.g., Petrol Stations, Supermarkets, Hospitals).
* **Processing:** Location coordinates are calculated **strictly on-device** using Android Location Services. Your real-time location is never tracked, stored on cloud servers, or shared with third parties.

---

## 3. Advertising & In-App Purchases

### A. Google Mobile Ads (AdMob)
* Expense Book integrates Google Mobile Ads (`com.google.android.gms.ads`) to serve Banner, Interstitial, and Rewarded Video Ads.
* Google AdMob may collect device identifiers (such as Advertising ID) and non-personal diagnostic data in accordance with Google's Privacy Policy.

### B. "Remove Ads" In-App Purchase (`remove_ads`)
* Users can make a one-time in-app purchase (`remove_ads` - $4.99) via Google Play Billing to permanently remove all banner, interstitial, and rewarded ads across the entire application.

---

## 4. Data Backup, Export & Portability
* **Download Data:** Users can export their entire financial database and settings into a local JSON backup file (`myexpense_data_backup_<timestamp>.json`).
* **Restore Data:** Users can import this backup file on any device to restore their records.
* **User Sovereignty:** You have complete control over your data files and can save, transfer, or delete them at your discretion.

---

## 5. Security & Data Retention
* **Local Storage Security:** All application data is stored in isolated app storage protected by Android system security sandbox boundaries.
* **Device Lock Protection:** Optional Fingerprint / Face ID / PIN security lock can be enabled to prevent unauthorized access to your expense records.
* **Data Erasure:** You can flush all local data immediately by selecting "Sign Out" or "Delete Account" in the app settings.

---

## 6. Children's Privacy
Expense Book does not knowingly collect or solicit personal information from children under the age of 13.

---

## 7. Changes to This Privacy Policy
We may update our Privacy Policy periodically. Any changes will be posted on this page with an updated Effective Date.

---

## 8. Contact Us
If you have any questions or suggestions regarding this Privacy Policy, please contact us at:  
* **GitHub Repository:** [https://github.com/tafaisalkhan/expense_book.git](https://github.com/tafaisalkhan/expense_book.git)
