package com.myexpense.book

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ActivityNotFoundException
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SMS_CHANNEL = "com.myexpense.book/sms_receiver"
    private val SMS_METHOD_CHANNEL = "com.myexpense.book/sms_permissions"
    private var eventSink: EventChannel.EventSink? = null
    private var supportChannel: MethodChannel? = null
    private var voiceChannel: MethodChannel? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private val voiceHandler = Handler(Looper.getMainLooper())
    private var voiceStopRunnable: Runnable? = null
    private var pendingVoiceMaxSeconds: Int = 10
    private var pendingVoiceStartResult: MethodChannel.Result? = null
    private var lastPartialTranscript: String = ""
    private var voiceSessionActive: Boolean = false
    private var appUpdateManager: AppUpdateManager? = null
    private var updatePromptAttemptedThisLaunch = false
    private var installListenerRegistered = false

    private val appUpdateLauncher: ActivityResultLauncher<IntentSenderRequest> =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { _ -> }

    private val installStateUpdatedListener = InstallStateUpdatedListener { state ->
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            runOnUiThread {
                supportChannel?.invokeMethod("onUpdateDownloaded", null)
            }
        }
    }

    private fun openPlayStoreListing() {
        val storeUrl = "https://play.google.com/store/apps/details?id=com.myexpense.book"
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.myexpense.book"))
                    .setPackage("com.android.vending")
            )
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(storeUrl)))
        }
    }

    private fun launchInAppReview(result: MethodChannel.Result) {
        try {
            val manager = ReviewManagerFactory.create(this)
            manager.requestReviewFlow()
                .addOnSuccessListener { reviewInfo ->
                    manager.launchReviewFlow(this, reviewInfo)
                        .addOnCompleteListener {
                            result.success(null)
                        }
                }
                .addOnFailureListener {
                    try {
                        openPlayStoreListing()
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("UNAVAILABLE", "Could not open Google Play review.", null)
                    }
                }
        } catch (_: Exception) {
            try {
                openPlayStoreListing()
                result.success(null)
            } catch (_: Exception) {
                result.error("UNAVAILABLE", "Could not open Google Play review.", null)
            }
        }
    }

    private fun checkForPlayAppUpdate(forcePrompt: Boolean = false) {
        try {
            val manager = appUpdateManager ?: AppUpdateManagerFactory.create(this).also {
                appUpdateManager = it
            }
            if (!installListenerRegistered) {
                manager.registerListener(installStateUpdatedListener)
                installListenerRegistered = true
            }
            manager.appUpdateInfo.addOnSuccessListener { info ->
                if (info.installStatus() == InstallStatus.DOWNLOADED) {
                    supportChannel?.invokeMethod("onUpdateDownloaded", null)
                    return@addOnSuccessListener
                }
                if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                    (forcePrompt || !updatePromptAttemptedThisLaunch)
                ) {
                    val updateType = when {
                        info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE) -> AppUpdateType.FLEXIBLE
                        info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE) -> AppUpdateType.IMMEDIATE
                        else -> null
                    }
                    if (updateType != null) {
                        updatePromptAttemptedThisLaunch = true
                        manager.startUpdateFlowForResult(
                            info,
                            appUpdateLauncher,
                            AppUpdateOptions.newBuilder(updateType).build()
                        )
                    }
                }
            }
        } catch (_: Exception) {
            // Silently ignore on devices without Google Play or sideloaded debug installs.
        }
    }

    private fun cleanupVoiceRecognizer() {
        voiceStopRunnable?.let { voiceHandler.removeCallbacks(it) }
        voiceStopRunnable = null
        voiceSessionActive = false
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
    }

    private fun startVoiceRecognitionSession(maxSeconds: Int, result: MethodChannel.Result?) {
        val clampedSeconds = maxSeconds.coerceIn(1, 10)
        runOnUiThread {
            if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                result?.error(
                    "SPEECH_UNAVAILABLE",
                    "On-device speech recognition is not available on this device.",
                    null
                )
                return@runOnUiThread
            }

            cleanupVoiceRecognizer()
            lastPartialTranscript = ""
            voiceSessionActive = true

            val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
            speechRecognizer = recognizer

            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}

                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?.trim()
                        ?: ""
                    if (partial.isNotEmpty()) {
                        lastPartialTranscript = partial
                        voiceChannel?.invokeMethod("onPartialTranscript", partial)
                    }
                }

                override fun onResults(results: Bundle?) {
                    if (!voiceSessionActive) return
                    voiceStopRunnable?.let { voiceHandler.removeCallbacks(it) }
                    voiceStopRunnable = null
                    voiceSessionActive = false
                    val finalText = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?.trim()
                        .orEmpty()
                        .ifEmpty { lastPartialTranscript }
                    voiceChannel?.invokeMethod("onFinalTranscript", finalText)
                }

                override fun onError(error: Int) {
                    if (!voiceSessionActive) return
                    voiceStopRunnable?.let { voiceHandler.removeCallbacks(it) }
                    voiceStopRunnable = null
                    voiceSessionActive = false
                    if (lastPartialTranscript.isNotEmpty() &&
                        (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                            error == SpeechRecognizer.ERROR_NO_MATCH)
                    ) {
                        voiceChannel?.invokeMethod("onFinalTranscript", lastPartialTranscript)
                        return
                    }
                    val message = when (error) {
                        SpeechRecognizer.ERROR_AUDIO -> "Microphone audio error. Please try again."
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                            "Microphone permission is required for voice expenses."
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "Speech service timed out. Try again or type your expense phrase."
                        SpeechRecognizer.ERROR_NO_MATCH ->
                            "Could not understand speech clearly. Please speak item and amount clearly."
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                            "Speech recognizer is busy. Please wait a second and try again."
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                            "No speech detected within $clampedSeconds seconds. Tap the mic and try again."
                        else -> "Voice recognition could not complete. Please try again."
                    }
                    voiceChannel?.invokeMethod("onVoiceError", message)
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                    1800L
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    1500L
                )
            }

            try {
                recognizer.startListening(intent)
                val stopTask = Runnable {
                    if (voiceSessionActive) {
                        try {
                            speechRecognizer?.stopListening()
                        } catch (_: Exception) {}
                        // Safety fallback if recognizer doesn't deliver onResults promptly
                        voiceHandler.postDelayed({
                            if (voiceSessionActive) {
                                voiceSessionActive = false
                                val fallbackText = lastPartialTranscript.trim()
                                if (fallbackText.isNotEmpty()) {
                                    voiceChannel?.invokeMethod("onFinalTranscript", fallbackText)
                                } else {
                                    voiceChannel?.invokeMethod(
                                        "onVoiceError",
                                        "10-second limit reached with no clear words detected."
                                    )
                                }
                            }
                        }, 1200L)
                    }
                }
                voiceStopRunnable = stopTask
                voiceHandler.postDelayed(stopTask, clampedSeconds * 1000L)
                result?.success(null)
            } catch (e: Exception) {
                cleanupVoiceRecognizer()
                result?.error("VOICE_START_FAILED", e.message ?: "Failed to start listening.", null)
            }
        }
    }

    override fun onDestroy() {
        cleanupVoiceRecognizer()
        if (installListenerRegistered) {
            try {
                appUpdateManager?.unregisterListener(installStateUpdatedListener)
            } catch (_: Exception) {}
            installListenerRegistered = false
        }
        super.onDestroy()
    }

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

        val storeUrl = "https://play.google.com/store/apps/details?id=com.myexpense.book"
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.myexpense.book/support")
        supportChannel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "rateApp" -> launchInAppReview(result)
                    "openPlayStore" -> {
                        openPlayStoreListing()
                        result.success(null)
                    }
                    "shareApp" -> {
                        val share = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, "My Expence Book")
                            putExtra(
                                Intent.EXTRA_TEXT,
                                "Keep your everyday spending organized with My Expence Book. $storeUrl"
                            )
                        }
                        startActivity(Intent.createChooser(share, "Share My Expence Book"))
                        result.success(null)
                    }
                    "checkForAppUpdate" -> {
                        val force = call.argument<Boolean>("force") ?: false
                        checkForPlayAppUpdate(forcePrompt = force)
                        result.success(null)
                    }
                    "completeAppUpdate" -> {
                        appUpdateManager?.completeUpdate()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("UNAVAILABLE", "The requested action could not be opened.", null)
            }
        }

        val vChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.myexpense.book/voice_expense")
        voiceChannel = vChannel
        vChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    val maxSec = (call.argument<Int>("maxSeconds") ?: 10).coerceIn(1, 10)
                    val hasMic = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (hasMic) {
                        startVoiceRecognitionSession(maxSec, result)
                    } else {
                        pendingVoiceMaxSeconds = maxSec
                        pendingVoiceStartResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            102
                        )
                    }
                }
                "stopListening" -> {
                    runOnUiThread {
                        voiceStopRunnable?.let { voiceHandler.removeCallbacks(it) }
                        voiceStopRunnable = null
                        try {
                            speechRecognizer?.stopListening()
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                }
                "cancelListening" -> {
                    runOnUiThread {
                        cleanupVoiceRecognizer()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.myexpense.book/ad_config")
            .setMethodCallHandler { call, result ->
                if (call.method == "getAppId") {
                    @Suppress("DEPRECATION")
                    val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                    result.success(info.metaData?.getString("com.google.android.gms.ads.APPLICATION_ID"))
                } else {
                    result.notImplemented()
                }
            }

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
                    val hasRead = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
                    result.success(hasRead)
                }
                "requestSmsPermission" -> {
                    val hasRead = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
                    if (hasRead) {
                        result.success(true)
                    } else {
                        permissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_SMS),
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
            val hasRead = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(hasRead)
            permissionResult = null
        } else if (requestCode == 102) {
            val hasMic = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            val pending = pendingVoiceStartResult
            pendingVoiceStartResult = null
            if (hasMic) {
                startVoiceRecognitionSession(pendingVoiceMaxSeconds, pending)
            } else {
                pending?.error(
                    "MIC_PERMISSION_DENIED",
                    "Microphone permission is required to record voice expenses.",
                    null
                )
            }
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
