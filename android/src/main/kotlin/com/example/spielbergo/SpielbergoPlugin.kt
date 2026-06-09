package com.example.spielbergo

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** SpielbergoPlugin */
class SpielbergoPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {
    companion object {
        private const val requestPickVideo = 61840
    }

    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "spielbergo")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "pickVideo" -> pickVideo(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickVideo(call: MethodCall, result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no_activity", "Spielbergo needs an active Android activity.", null)
            return
        }
        if (pendingResult != null) {
            result.error("already_active", "Spielbergo video editor is already open.", null)
            return
        }

        val recordTimes = call.argument<List<String>>("recordTimes").orEmpty()
        val intent = Intent(currentActivity, SpielbergoVideoEditorActivity::class.java)
        intent.putStringArrayListExtra(
            SpielbergoVideoEditorActivity.extraRecordTimes,
            ArrayList(recordTimes)
        )
        pendingResult = result
        currentActivity.startActivityForResult(intent, requestPickVideo)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != requestPickVideo) {
            return false
        }

        val result = pendingResult ?: return true
        pendingResult = null
        if (resultCode == Activity.RESULT_OK) {
            result.success(data?.getStringExtra(SpielbergoVideoEditorActivity.extraVideoPath))
        } else {
            result.success(null)
        }
        return true
    }
}
