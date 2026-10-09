# Google Play Store Data Safety & Privacy Form Guide

**Application Name:** Expense Book  
**Package Name:** `com.myexpense.book`  
**Target OS:** Android 5.0+ (API Level 21+)  

---

## 1. Google Play Data Safety Form Questionnaire Answers

### A. Data Collection and Security
- **Does your app collect or share any of the required user data types?**  
  👉 **YES**
- **Is all of the user data collected by your app encrypted in transit?**  
  👉 **YES** (All external network traffic uses TLS/HTTPS encryption).
- **Do you provide a way for users to request that their data be deleted?**  
  👉 **YES** (Users can purge data in Settings or clear app data via Android OS Settings).

---

## 2. Detailed Data Type Declarations

| Data Category | Data Type | Collected? | Shared? | Processing Location | Purpose |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Financial Info** | Financial Transactions, Expense Entries, Budgets | **Yes** | **No** | Local Device Only | App Functionality (Expense Tracking & Budgeting) |
| **Photos & Videos** | Receipt Photos & Images | **Yes** | **No** | Local Device Only | App Functionality (OCR Receipt Scanning & Slip Attachments) |
| **Files & Docs** | PDF Receipt Documents | **Yes** | **No** | Local Device Only | App Functionality (PDF Receipt Import & OCR Processing) |
| **Personal Info** | Name & Email (Google Sign-In) | **Yes** | **No** | Local Device / Secure Auth | Account Management & Authentication |

---

## 3. High-Risk Android Permission Declarations & Justifications

### 1. Camera Permission (`android.permission.CAMERA`)
- **Use Case Category:** Document & Receipt Scanning
- **Justification for Google Play Review:**  
  Allows users to take photos of paper receipts, store bills, and vouchers. Text recognition extracts purchase items, amounts, date, and merchant name on-device.

---

## 4. Privacy Policy URLs for Play Console

When submitting to Google Play Console, paste the following URLs into the **App Content > Privacy Policy** field:

- **Markdown Version:** `https://github.com/tafaisalkhan/expense_book/blob/main/privacy_policy.md`
- **HTML Web Version:** `https://tafaisalkhan.github.io/expense_book/privacy_policy.html` (or hosted web link)
