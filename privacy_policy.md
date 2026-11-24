# Privacy Policy for Expense Book

**Effective Date:** November 24, 2026  
**Application Name:** Expense Book  
**App Name:** `My Expence Book`  
**Package Name:** `com.myexpense.book`  
**Developer:** Muhammad Faisal Khan  
**Contact Email:** muhammadfaysal.khan7@gmail.com  

---

## 1. Overview
**Expense Book** ("we", "our", or "us") is dedicated to protecting your privacy. This Privacy Policy explains how our application handles information, user data, cloud backups, on-device OCR/Voice entry, device permissions, and advertising when you use the Expense Book mobile application (`com.myexpense.book`).

Expense Book is built on an **Offline-First Architecture**. Your financial records, receipts, categories, budgets, and personal profiles are stored locally on your device by default, with optional encrypted ZIP cloud backup for signed-in Cloud Backup subscribers.

---

## 2. Information We Collect & How It Is Used

### A. Local Financial Data & On-Device OCR / Voice Processing
* **What is stored:** Expense amounts, category classifications, transaction dates, merchant names, notes, receipt photos, family profile tags, and monthly budget limits.
* **Default Storage Location:** Stored in an isolated local SQLite database and app sandbox on your device.
* **On-Device Receipt OCR & 10-Second Voice Input:** Receipt text recognition (Google ML Kit) and voice-to-expense speech recognition run directly on your device. Raw voice audio is not stored on external servers.

### B. Optional Cloud ZIP Backup & Restore (Subscribers & Authorized Accounts)
* **How it works:** If you sign in with Google and activate a Cloud Backup plan (`cloud_backup_monthly_v2` - 100 MB limit, or `cloud_backup_yearly` - 600 MB limit with 7-day free trial), you can back up your database and receipt images as a single compressed ZIP archive (`latest.zip`) to our secure private cloud storage bucket (`user-backups/<uid>/latest.zip`) and schedule automatic backups.
* **Encryption & Access Control:** All cloud backup transmissions use HTTPS/TLS encryption in transit and private, authenticated row-level access controls at rest so only your authenticated Google account UID can upload, download, or delete your backup archive.

### C. Google Authentication
* **What is collected:** Google Account email address, display name, and unique user identifier (UID).
* **Purpose:** Used strictly for secure user authentication, subscription entitlement verification, and scoping your private Cloud ZIP backup.

### D. Device Permissions
* **Microphone (`RECORD_AUDIO`):** Used only when you tap the Voice Expense button to record a 10-second spoken expense entry.
* **Camera / Photos:** Used only when you capture or select a receipt photo for expense attachment or on-device OCR scanning.
* **Notifications & Vibration (`POST_NOTIFICATIONS`, `VIBRATE`):** To deliver scheduled expense logging reminders and notifications.
* **Biometric Security (`USE_BIOMETRIC`, `USE_FINGERPRINT`):** For optional fingerprint/face security app lock.

---

## 3. Advertising & In-App Purchases / Subscriptions

### A. Google Mobile Ads (AdMob)
* Expense Book integrates Google Mobile Ads (`com.google.android.gms.ads`) to serve Banner, Interstitial, and user-initiated Rewarded Video Ads for free-tier users.
* Google AdMob may collect device identifiers (such as Advertising ID) and non-personal diagnostic data in accordance with Google's Privacy Policy.

### B. In-App Purchases & Subscriptions
* **Remove Ads (`remove_ads` - $4.99):** One-time purchase that permanently disables all ads.
* **Cloud Backup Subscriptions (`cloud_backup_monthly_v2` - $0.99/mo for 100 MB, `cloud_backup_yearly` - $5.99/yr for 600 MB):** Includes a 7-day free trial, automatic cloud ZIP backup & restore, 100% ad-free experience, unlimited receipt OCR, and 10 voice entries per day.
* Google Play handles all payment processing; Expense Book never receives your credit card or payment details.

---

## 4. Data Backup, Export, Portability & Deletion (Right to Erasure)
* **Local ZIP Export & Import:** Free and subscribed users can export or import a local ZIP backup file on their device at any time.
* **Account & Cloud Backup Deletion:** You can permanently delete your account, local data, and any stored Cloud ZIP backup archive (`latest.zip` and backup metadata) at any time from **More → Delete Account** inside the app, or by emailing **muhammadfaysal.khan7@gmail.com** / **android.nextlevel@gmail.com**.

---

## 5. Security & Data Retention
* **Encryption in Transit & Isolation:** All cloud backup uploads/downloads use HTTPS/TLS signed URLs valid for a single authenticated UID.
* **Device Lock Protection:** Optional Fingerprint / Face ID / PIN security lock can be enabled to prevent unauthorized access to your expense records.

---

## 6. Children's Privacy
Expense Book does not knowingly collect or solicit personal information from children under the age of 13.

---

## 7. Changes to This Privacy Policy
We may update our Privacy Policy periodically. Any changes will be posted on this page with an updated Effective Date.

---

## 8. Contact Us
If you have any questions or data deletion requests regarding this Privacy Policy, please contact us at:  
* **Developer:** Muhammad Faisal Khan  
* **Email:** [muhammadfaysal.khan7@gmail.com](mailto:muhammadfaysal.khan7@gmail.com) / [android.nextlevel@gmail.com](mailto:android.nextlevel@gmail.com)  
* **GitHub Repository:** [https://github.com/tafaisalkhan/expense_book.git](https://github.com/tafaisalkhan/expense_book.git)
