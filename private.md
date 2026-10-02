# Privacy Policy for MyExpense

**Effective Date:** September 25, 2026  
**Application:** MyExpense (`com.myexpense.app`)

---

## 1. Overview
At **MyExpense**, we prioritize user data privacy, security, and transparency. This Privacy Policy outlines how our application collects, processes, and protects your information when you use our mobile expense tracking application, OCR document scanner, SMS financial auto-categorizer, and map-based geofence notification services.

---

## 2. Information We Collect & Use

### A. Camera & Storage Access (OCR Receipt Scanning)
- **Purpose:** To allow users to capture photos of receipt slips, bills, and tax invoices, or attach PDF documents for automated item name, total price, merchant, date, and time extraction.
- **Data Handling:** Image optical character recognition (OCR) is performed on-device. Images uploaded or processed are strictly stored in local device storage for expense attachment purposes and are never sold or used for advertising.

### B. SMS Permission (`RECEIVE_SMS`, `READ_SMS`)
- **Purpose:** To analyze financial transaction SMS alerts sent by whitelisted banks and payment gateways (e.g., POS card debits, supermarket purchases, petrol pump payments) and automatically present draft expense entries for user review.
- **Data Handling:** SMS messages are read **locally on your device**. Personal SMS conversations are completely ignored. SMS content is **never uploaded** to remote servers or shared with third parties.

### C. Location Services & Geofencing (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`)
- **Purpose:** To provide interactive OpenStreetMap location picking, allow custom marker pinpointing (e.g., Petrol Stations, Supermarkets, Local Markets), and trigger local push notifications reminding you to log an expense when leaving commercial locations.
- **Data Handling:** Location coordinates remain exclusively on your device within local application storage. Live location tracking data is never broadcasted to external tracking servers.

### D. Financial & User Data Storage
- **Local Storage:** All expense entries, custom categories, subcategories, budgets, family member tags, and transaction logs are stored locally on your device in secure SQLite storage.
- **Data Control:** You retain 100% control over your data, with complete ability to edit, delete, export, or wipe all records at any time.

---

## 3. Data Sharing & Third-Party Services
- **No Third-Party Data Sales:** We do **NOT** sell, rent, trade, or monetize your personal or financial data under any circumstances.
- **External Services:** Map tiles are rendered via OpenStreetMap standard public tile layers (`tile.openstreetmap.org`). No sensitive user identity or financial details are passed to map tile providers.

---

## 4. Security Measures
We implement industry-standard security measures to safeguard your data, including local database isolation, permission-scoped Android execution sandboxes, and HTTPS encryption for any optional cloud sync endpoints.

---

## 5. User Rights & Data Deletion
You have the right to:
1. Grant or revoke Camera, Storage, SMS, or Location permissions at any time via system settings.
2. Export your expense history in standard CSV/PDF formats.
3. Delete individual expenses, receipt attachments, or clear all app data permanently via Settings.

---

## 6. Contact Us
For any privacy questions or requests regarding your data, please contact:  
- **Developer:** Muhammad Faisal Khan  
- **Email:** android.nextlevel@gmail.com  
- **Website:** https://github.com/tafaisalkhan/expense_book.git
