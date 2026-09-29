package com.myexpense.book

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        for (sms in messages) {
            val sender = sms.displayOriginatingAddress ?: sms.originatingAddress ?: ""
            val body = sms.messageBody ?: ""

            if (sender.isNotEmpty() && body.isNotEmpty()) {
                val smsKey = "live_${sender}_${body.hashCode()}"

                // Check if this live SMS was already read/processed previously by MyExpense
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val rawProcessed = prefs.getString("flutter.processed_sms_keys_v1", "[]") ?: "[]"
                var isAlreadyProcessed = false
                try {
                    val processedArray = JSONArray(rawProcessed)
                    for (i in 0 until processedArray.length()) {
                        if (processedArray.getString(i) == smsKey) {
                            isAlreadyProcessed = true
                            break
                        }
                    }
                } catch (_: Exception) {}

                if (isAlreadyProcessed) continue

                // 1. Broadcast to running MainActivity (if app is running/in foreground)
                val smsIntent = Intent(ACTION_SMS_RECEIVED).apply {
                    putExtra(EXTRA_SENDER, sender)
                    putExtra(EXTRA_BODY, body)
                    setPackage(context.packageName)
                }
                context.sendBroadcast(smsIntent)

                // 2. Check if SMS is from a whitelisted sender or contains financial transaction indicators
                if (isFinancialOrWhitelistedSms(context, sender, body)) {
                    // Save to pending SMS state file in SharedPreferences so app reads it when opened
                    savePendingSmsToStateFile(context, sender, body)

                    // Post a system notification so user is notified even when app is CLOSED!
                    showSmsNotification(context, sender, body)
                }
            }
        }
    }

    private fun isFinancialOrWhitelistedSms(context: Context, sender: String, body: String): Boolean {
        val cleanSender = sender.trim().lowercase()
        val digitsSender = cleanSender.replace(Regex("[^0-9]"), "")
        val lowerBody = body.lowercase()

        // Fetch whitelisted senders from FlutterSharedPreferences
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val rawJsonList = prefs.getString("flutter.sms_whitelisted_senders", null)

        var isWhitelisted = false
        if (!rawJsonList.isNullOrEmpty()) {
            try {
                val jsonArray = JSONArray(rawJsonList)
                for (i in 0 until jsonArray.length()) {
                    val allowed = jsonArray.getString(i).trim().lowercase()
                    val digitsAllowed = allowed.replace(Regex("[^0-9]"), "")

                    if (cleanSender == allowed ||
                        cleanSender.contains(allowed) ||
                        allowed.contains(cleanSender) ||
                        (digitsAllowed.length >= 3 && digitsSender.length >= 3 &&
                         (digitsSender == digitsAllowed || digitsSender.endsWith(digitsAllowed) || digitsAllowed.endsWith(digitsSender)))
                    ) {
                        isWhitelisted = true
                        break
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // Standard financial keywords check (bank name, Rs, PKR, debited, credited, paid, transaction, etc.)
        val hasFinancialKeyword = lowerBody.contains("debited") ||
                lowerBody.contains("credited") ||
                lowerBody.contains("paid") ||
                lowerBody.contains("transaction") ||
                lowerBody.contains("spent") ||
                lowerBody.contains("transfer") ||
                lowerBody.contains("a/c") ||
                lowerBody.contains("rs") ||
                lowerBody.contains("pkr") ||
                lowerBody.contains("pos") ||
                lowerBody.contains("atm")

        val knownBankSenders = listOf("meezan", "hbl", "easypaisa", "jazzcash", "ubl", "mcb", "alfalah", "allied", "8257", "9220")
        val isKnownBankSender = knownBankSenders.any { cleanSender.contains(it) }

        return isWhitelisted || (isKnownBankSender && hasFinancialKeyword) || (hasFinancialKeyword && (cleanSender.length <= 11 && !cleanSender.contains(" ")))
    }

    private fun savePendingSmsToStateFile(context: Context, sender: String, body: String) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val existingJson = prefs.getString("flutter.pending_sms_notifications_v1", "[]") ?: "[]"
            val jsonArray = JSONArray(existingJson)

            val newItem = JSONObject().apply {
                put("id", "sms_${System.currentTimeMillis()}")
                put("sender", sender)
                put("body", body)
                put("timestamp", System.currentTimeMillis())
                put("isRead", false)
            }
            jsonArray.put(newItem)

            prefs.edit().putString("flutter.pending_sms_notifications_v1", jsonArray.toString()).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showSmsNotification(context: Context, sender: String, body: String) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val channelId = "sms_expense_channel"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "SMS Expense Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications for incoming financial transaction SMS when app is closed."
                    enableVibration(true)
                    setShowBadge(true)
                }
                notificationManager.createNotificationChannel(channel)
            }

            // Launch MainActivity when user clicks the notification
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("route", "/share-sms")
                putExtra("initial_sms_body", body)
                putExtra("initial_sms_sender", sender)
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                System.currentTimeMillis().toInt(),
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Preview snippet
            val previewText = if (body.length > 90) body.substring(0, 90) + "..." else body

            val notification = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("💳 Bank Transaction SMS ($sender)")
                .setContentText(previewText)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()

            notificationManager.notify(sender.hashCode() + (System.currentTimeMillis() % 1000).toInt(), notification)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    companion object {
        const val ACTION_SMS_RECEIVED = "com.myexpense.book.SMS_RECEIVED"
        const val EXTRA_SENDER = "sender"
        const val EXTRA_BODY = "body"
    }
}
