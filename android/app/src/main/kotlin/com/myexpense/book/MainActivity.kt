package com.myexpense.book

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SMS_CHANNEL = "com.myexpense.book/sms_receiver"
    private val SMS_METHOD_CHANNEL = "com.myexpense.book/sms_permissions"
    private var eventSink: EventChannel.EventSink? = null

    private val localSmsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == SmsReceiver.ACTION_SMS_RECEIVED) {
                val sender = intent.getStringExtra(SmsReceiver.EXTRA_SENDER) ?: ""
                val body = intent.getStringExtra(SmsReceiver.EXTRA_BODY) ?: ""

                val map = mapOf(
                    "sender" to sender,
                    "body" to body,
                    "timestamp" to System.currentTimeMillis()
                )
                eventSink?.success(map)
            }
        }
    }

    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkSmsPermission" -> {
                    val hasReceive = ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
                    val hasRead = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
                    result.success(hasReceive && hasRead)
                }
                "requestSmsPermission" -> {
                    val hasReceive = ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
                    val hasRead = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
                    if (hasReceive && hasRead) {
                        result.success(true)
                    } else {
                        permissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS),
                            101
                        )
                    }
                }
                "readWhitelistedInboxSms" -> {
                    val allowedSenders = call.argument<List<String>>("allowedSenders") ?: emptyList()
                    // Run SMS content provider query on background worker thread to prevent UI freezing/hanging!
                    Thread {
                        val messages = readWhitelistedInboxSms(allowedSenders)
                        runOnUiThread {
                            result.success(messages)
                        }
                    }.start()
                }
                "getPendingSmsNotifications" -> {
                    try {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val pendingJson = prefs.getString("flutter.pending_sms_notifications_v1", "[]") ?: "[]"
                        // Clear pending once fetched
                        prefs.edit().remove("flutter.pending_sms_notifications_v1").apply()
                        result.success(pendingJson)
                    } catch (e: Exception) {
                        result.success("[]")
                    }
                }
                "getInitialNotificationSms" -> {
                    val body = intent?.getStringExtra("initial_sms_body")
                    val sender = intent?.getStringExtra("initial_sms_sender")
                    if (!body.isNullOrEmpty()) {
                        result.success(mapOf("body" to body, "sender" to (sender ?: "")))
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101) {
            val hasReceive = ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
            val hasRead = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
            val isGranted = hasReceive && hasRead
            permissionResult?.success(isGranted)
            permissionResult = null
        }
    }

    private fun readWhitelistedInboxSms(allowedSenders: List<String>): List<Map<String, Any>> {
        val resultList = mutableListOf<Map<String, Any>>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
            println("MyExpense SMS Debug: READ_SMS permission not granted")
            return resultList
        }

        // Calculate install day start timestamp (00:00:00 of the date app was installed)
        val installTime = try {
            packageManager.getPackageInfo(packageName, 0).firstInstallTime
        } catch (e: Exception) {
            System.currentTimeMillis()
        }

        val calendar = java.util.Calendar.getInstance().apply {
            timeInMillis = if (installTime > 0) installTime else System.currentTimeMillis()
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val installDayStart = calendar.timeInMillis

        try {
            val projection = arrayOf("_id", "address", "body", "date", "read", "type")
            var cursor: android.database.Cursor? = null

            try {
                val inboxUri = android.net.Uri.parse("content://sms/inbox")
                val selection = "(read = 0 OR read IS NULL) AND date >= ?"
                val selectionArgs = arrayOf(installDayStart.toString())
                cursor = contentResolver.query(inboxUri, projection, selection, selectionArgs, "date DESC LIMIT 300")
            } catch (e: Exception) {
                println("MyExpense SMS Debug: content://sms/inbox query failed, falling back to content://sms: ${e.message}")
            }

            if (cursor == null || cursor.count == 0) {
                cursor?.close()
                val genericUri = android.net.Uri.parse("content://sms")
                val selection = "(type = 1 OR type IS NULL) AND (read = 0 OR read IS NULL) AND date >= ?"
                val selectionArgs = arrayOf(installDayStart.toString())
                cursor = contentResolver.query(genericUri, projection, selection, selectionArgs, "date DESC LIMIT 300")
            }

            cursor?.use { c ->
                val idIdx = c.getColumnIndex("_id")
                val addressIdx = c.getColumnIndex("address")
                val bodyIdx = c.getColumnIndex("body")
                val dateIdx = c.getColumnIndex("date")
                val readIdx = c.getColumnIndex("read")

                while (c.moveToNext()) {
                    val smsId = if (idIdx != -1) c.getString(idIdx) else ""
                    val address = if (addressIdx != -1) c.getString(addressIdx) else ""
                    val body = if (bodyIdx != -1) c.getString(bodyIdx) else ""
                    val date = if (dateIdx != -1) c.getLong(dateIdx) else System.currentTimeMillis()
                    val read = if (readIdx != -1) c.getInt(readIdx) else 0

                    // STRICT UNREAD FILTER: Skip any SMS that has already been read by the user (read == 1)
                    if (read == 1) {
                        continue
                    }

                    // STRICT DATE FILTER: Ignore any historical SMS received before the app install date
                    if (date < installDayStart) {
                        continue
                    }

                    if (!address.isNullOrEmpty() && !body.isNullOrEmpty()) {
                        val cleanAddress = address.trim().lowercase()
                        val digitsAddress = cleanAddress.replace(Regex("[^0-9]"), "")

                        val matches = allowedSenders.isEmpty() || allowedSenders.any { s ->
                            val cleanAllowed = s.trim().lowercase()
                            val digitsAllowed = cleanAllowed.replace(Regex("[^0-9]"), "")

                            cleanAddress == cleanAllowed ||
                            cleanAddress.contains(cleanAllowed) ||
                            cleanAllowed.contains(cleanAddress) ||
                            (digitsAllowed.length >= 3 && digitsAddress.length >= 3 &&
                             (digitsAddress == digitsAllowed || digitsAddress.endsWith(digitsAllowed) || digitsAllowed.endsWith(digitsAddress)))
                        }

                        if (matches) {
                            val smsKey = "${smsId}_${cleanAddress}_${date}_${body.hashCode()}"
                            resultList.add(mapOf(
                                "id" to smsId,
                                "key" to smsKey,
                                "sender" to address,
                                "body" to body,
                                "date" to date,
                                "read" to read
                            ))
                        }
                    }
                }
            }
        } catch (e: Exception) {
            println("MyExpense SMS Debug: Failed to query SMS inbox: ${e.message}")
            e.printStackTrace()
        }

        return resultList
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(SmsReceiver.ACTION_SMS_RECEIVED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(localSmsReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(localSmsReceiver, filter)
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(localSmsReceiver)
        } catch (_: Exception) {}
    }
}
