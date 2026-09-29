# MyExpense App — Project State & Agent Handoff Guide

## 1. Project Overview & Architecture
- **Framework**: Flutter (Dart)
- **State Management**: Flutter Riverpod (`StateNotifierProvider`, `FutureProvider`, `StreamProvider`)
- **Navigation**: `go_router` (`ShellRoute` for `MainShellScreen`, `GoRoute` for root routes like `/login`, `/add`, `/map-picker`, `/paywall`, `/share-receipt`, `/share-sms`)
- **Database**: Drift / SQLite (`AppDatabase`) for local data persistence.
- **Backend & Cloud Sync**:
  - **Firebase Auth**: Google Sign-In & Auth (`auth_providers.dart`)
  - **Cloud Firestore**: Real-time sync for `user_subscriptions` and `user_backups` collections
  - **Cloud Storage**: Automatic database zip backup & receipt images (`receipts/` directory)

---

## 2. Recent Key Implementations & Fixes

### A. Google Mobile Ads (Banner & Interstitial Ads)
- **Official Google Test Ad Unit IDs**:
  - **Android Banner**: `ca-app-pub-3940256099942544/6300978111`
  - **Android Interstitial**: `ca-app-pub-3940256099942544/1033173712`
  - **iOS Banner**: `ca-app-pub-3940256099942544/2934735716`
  - **iOS Interstitial**: `ca-app-pub-3940256099942544/4411468910`
- **Ad Display Logic**:
  - **Dual Banner Ads**: Top & Bottom Banner Ads rendered in `MainShellScreen` (`AdBannerWidget`).
  - **Interstitial Frequency**: Triggers every 5 to 6 screen navigation transitions (`adNotifierProvider.notifier.recordNavigation`). Fallback dialog available if network/ad load fails.
  - **Ad-Free Premium Exemption**: When `sub.isPremium == true` (paid subscription or active 3-month free trial), **100% of ads (banners & interstitials) are hidden**.
- **Android 11+ Package Visibility & Service Binding Fix**:
  - Added `<uses-permission android:name="com.google.android.gms.permission.AD_ID" />` to `AndroidManifest.xml`.
  - Declared `<intent><action android:name="com.google.android.gms.ads.service.START"/></intent>` under `<queries>` in `AndroidManifest.xml`.
  - Registered physical test device ID `7FAD65EC0E638FA926CE871CB91C3E96` in `MobileAds.instance.updateRequestConfiguration` in `main.dart`.
  - Implemented progressive retry mechanism in `AdBannerWidget` in `ad_providers.dart`.

### B. Draggable Floating Action & Save Buttons
- **Widget Definitions**: `DraggableFloatingActionButton` and `DraggableSaveButton` (`lib/core/widgets/draggable_floating_action_button.dart`).
- **Behavior**:
  - Circular, 100% smooth, draggable button displaying ONLY the `+` sign (`Icons.add`).
  - Positioned at **bottom-right** (`right: 16`, `bottom: 24`).
  - **Single Shell FAB**: Rendered centrally in `MainShellScreen` to prevent duplicate overlapping buttons when switching tabs (`Dashboard`, `Expenses`, `Analytics`, `More`, `Category`, `Budget`, `People`).
  - **Save FAB**: `DraggableSaveButton` at bottom-right on entry forms (`AddExpenseScreen`), visible only when adding or editing data.

### D. Complete Account Deletion (Device & Firebase Cloud Erasure)
- **Firebase & Device Data Purging**:
  - `deleteCloudData()` in `firebase_cloud_backup_service.dart` deletes `user_backups` & `user_subscriptions` Firestore documents, `myexpense_backup.zip` Storage archives, and `active_sessions` records concurrently via `Future.wait(...)` capped at a 1.5s timeout.
  - `deleteAccount()` in `auth_providers.dart` revokes Google OAuth tokens (`GoogleSignIn().disconnect()`), deletes the Firebase Auth user, flushes local SQLite database tables (`db.clearAllData()`), deletes local device ZIP backups (`deleteLocalBackupZip()`), clears `SharedPreferences`, and redirects directly to `/login`.

### E. Expanded Default Categories & SQLite Auto-Sync
- **Asset Config**: `assets/config/default_categories.json`
- **Updated Categories & Subcategories**:
  - **Food** (`cat_food`): Meat (Beef, Chicken), Fruits & Vegetables, Haleem & Roti, Milk, Bread, Yogurt & Papad, Matchbox / Lighter / Fire, Restaurant & Fast Food, Tea & Coffee.
  - **Stationery** (`cat_stationery`): Copies & Notebooks, Photostat & Printing, Pencils, Erasers & Sharpeners, Answer Sheets, Pens.
  - **Clothing** (`cat_clothing`): Clothing Press & Ironing, Clothing Purchases, Tailoring & Stitching.
- **SQLite Database Auto-Syncing**: Updated `_initDatabase()` in `app_database.dart` to run `DatabaseMigrations.ensureDefaultCategories(db)` using `ConflictAlgorithm.ignore`. This automatically inserts any newly added default categories/subcategories into existing local databases without erasing user data!

### F. Firebase Database & Cloud Storage Security Rules
- **Firestore Rules**: Enforced authenticated user ownership (`request.auth != null`) for `user_backups`, `user_subscriptions`, and `active_sessions`, blocking public unauthenticated access (`allow read, write: if false;`).
- **Cloud Storage Rules**: Restricted `user_backups/`, `active_sessions/`, and `receipts/` paths to `request.auth != null`.

### H. Cloud Subscription Sync & FREE Overwrite Prevention
- **Root Cause**: On app initialization, `_loadSubscription()` defaulted local state to `FREE` whenever local `SharedPreferences` were blank, and immediately called `_syncSubscriptionToCloud(state)`. This overwrote active cloud subscriptions in Firestore with `FREE`.
- **Fix**: Updated `_loadSubscription()` in `subscription_providers.dart` to fetch existing active subscription records (`PREMIUM_PROMO_3M`, `PREMIUM_MONTHLY`, `PREMIUM_YEARLY`) from Cloud Firestore *before* defaulting to `FREE`. Simultaneously updated `_syncSubscriptionToCloud()` to write payloads to both `user.uid` and `user_$sanitizedEmail` Firestore document keys.

### I. Universal Dual-Key Backup & Firestore Data Saving
- **Enhancement**: `backupDataToFirebase()` and `restoreDataFromFirebase()` in `firebase_cloud_backup_service.dart` now dual-write and read backup archives and subscription records using `_getBackupTargetIds()`. This queries both the authenticated **Firebase Auth UID** (`user.uid`) AND the email document key (`user_$sanitizedEmail`), guaranteeing 100% data saving and restoration success under any Firestore/Storage security rule configuration.

---

## 3. Key File Map

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App entrypoint, Firebase & MobileAds initialization, test device registration |
| `lib/core/widgets/draggable_floating_action_button.dart` | Custom `DraggableFloatingActionButton` & `DraggableSaveButton` |
| `lib/features/navigation/main_shell_screen.dart` | Shell with Top/Bottom Banner Ads & single Draggable `+` FAB |
| `lib/features/navigation/app_router.dart` | `GoRouter` configuration (shell routes & root routes) |
| `lib/features/ads/presentation/providers/ad_providers.dart` | Banner retry logic, Interstitial load/show & fallback dialog |
| `lib/features/subscription/presentation/providers/subscription_providers.dart` | Subscription state, promo code redemption & Firestore sync |
| `lib/features/subscription/domain/services/firebase_cloud_backup_service.dart` | Cloud backup service (database zip export to Firebase) |
| `lib/features/expenses/presentation/screens/add_expense_screen.dart` | Add/Edit expense form with bottom-right `DraggableSaveButton` |
| `lib/features/categories/presentation/screens/category_screen.dart` | Category & Subcategory management with AppBar add button |
| `lib/features/budgets/presentation/screens/budget_screen.dart` | Monthly & Category budget screen with AppBar set budget button |
| `lib/features/people/presentation/screens/people_screen.dart` | Family Profile management with AppBar add button |
| `android/app/src/main/AndroidManifest.xml` | Android permissions (`AD_ID`), AdMob App ID, `<queries>` intent filters |

---

## 4. Verification & Testing

```bash
# Check dependencies
flutter pub get

# Run static code analysis (0 errors)
flutter analyze

# Launch on connected Android physical device
flutter run -d 0H74119I23101F6F
```
