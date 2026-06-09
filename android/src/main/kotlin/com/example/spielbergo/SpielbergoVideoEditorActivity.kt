package com.example.spielbergo

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.media.MediaExtractor
import android.media.MediaMuxer
import android.net.Uri
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.VideoView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

class SpielbergoVideoEditorActivity : AppCompatActivity() {
    companion object {
        const val extraRecordTimes = "spielbergo.recordTimes"
        const val extraDefaultRecordTime = "spielbergo.defaultRecordTime"
        const val extraVideoPath = "spielbergo.videoPath"
        private const val permissionRequestCode = 4105
    }

    private val clipFiles = mutableListOf<File>()
    private val clipDurationsMs = mutableListOf<Long>()
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var selectedLensFacing = CameraSelector.LENS_FACING_FRONT
    private var camera: Camera? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var activeRecording: Recording? = null
    private var activeClipFile: File? = null
    private var isStoppingRecording = false
    private var timer: CountDownTimer? = null
    private var recordStartedAt = 0L
    private var committedDurationMs = 0L
    private var activeClipDurationMs = 0L
    private var maxDurationMs = 15_000L
    private var frontLightEnabled = false
    private lateinit var root: FrameLayout
    private lateinit var previewOverlay: FrameLayout
    private lateinit var previewView: PreviewView
    private lateinit var videoView: VideoView
    private lateinit var closeButton: ImageButton
    private lateinit var switchButton: ImageButton
    private lateinit var flashButton: ImageButton
    private lateinit var durationRow: LinearLayout
    private lateinit var recordButton: RecordButton
    private lateinit var countdownText: TextView
    private lateinit var deleteButton: ImageButton
    private lateinit var doneButton: ImageButton
    private lateinit var backButton: ImageButton
    private lateinit var nextButton: TextView
    private lateinit var frontLight: View
    private var previewClipIndex = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        val durations = intent.getStringArrayListExtra(extraRecordTimes).orEmpty()
        val availableDurations = durations.ifEmpty { listOf("15s") }
        val defaultRecordTime = intent.getStringExtra(extraDefaultRecordTime)
        val selectedRecordTime =
            if (defaultRecordTime != null && availableDurations.contains(defaultRecordTime)) defaultRecordTime
            else availableDurations.first()
        maxDurationMs = parseDurationMs(selectedRecordTime)
        buildUi(availableDurations, selectedRecordTime)
        if (hasPermissions()) {
            previewView.post { bindCamera() }
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO),
                permissionRequestCode
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        timer?.cancel()
        activeRecording?.close()
        cameraExecutor.shutdown()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode && hasPermissions()) {
            previewView.post { bindCamera() }
        } else {
            finishCancelled()
        }
    }

    private fun hasPermissions(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun buildUi(durations: List<String>, selectedRecordTime: String) {
        root = FrameLayout(this).also {
            it.setBackgroundColor(Color.BLACK)
            setContentView(it)
        }

        val display = resources.displayMetrics
        val availableWidth = display.widthPixels - dp(28)
        val availableHeight = display.heightPixels - dp(150)
        val previewHeight = min((availableWidth * 16f / 9f).toInt(), availableHeight)
        val previewWidth = (previewHeight * 9f / 16f).toInt()

        previewView = PreviewView(this).also {
            it.scaleType = PreviewView.ScaleType.FILL_CENTER
            it.clipToOutline = true
            it.outlineProvider = roundedOutline(dp(14).toFloat())
        }
        videoView = VideoView(this).also {
            it.visibility = View.GONE
            it.clipToOutline = true
            it.outlineProvider = roundedOutline(dp(14).toFloat())
        }
        val previewParams = FrameLayout.LayoutParams(previewWidth, previewHeight, Gravity.CENTER)
        root.addView(previewView, previewParams)
        root.addView(videoView, previewParams)

        frontLight = View(this).also {
            it.setBackgroundColor(Color.WHITE)
            it.alpha = 0.82f
            it.visibility = View.GONE
        }
        root.addView(frontLight, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        previewOverlay = FrameLayout(this)
        root.addView(previewOverlay, FrameLayout.LayoutParams(previewWidth, previewHeight, Gravity.CENTER))

        closeButton = imageButton(R.drawable.spielbergo_close)
        previewOverlay.addView(closeButton, topStartParams())
        closeButton.setOnClickListener { confirmExit() }

        switchButton = imageButton(R.drawable.spielbergo_switch_camera)
        flashButton = imageButton(R.drawable.spielbergo_no_flash)
        previewOverlay.addView(switchButton, topEndParams(0))
        previewOverlay.addView(flashButton, topEndParams(52))
        switchButton.setOnClickListener { switchCamera() }
        flashButton.setOnClickListener { toggleLight() }

        durationRow = LinearLayout(this).also {
            it.gravity = Gravity.CENTER
            it.orientation = LinearLayout.HORIZONTAL
        }
        durations.forEachIndexed { index, label ->
            durationRow.addView(durationOption(label, label == selectedRecordTime || (index == 0 && selectedRecordTime.isBlank())))
        }
        root.addView(durationRow, bottomCenterParams(dp(96), ViewGroup.LayoutParams.WRAP_CONTENT, dp(40)))

        recordButton = RecordButton(this).also {
            it.background = null
            it.setBackgroundColor(Color.TRANSPARENT)
            it.stateListAnimator = null
            it.setWillNotDraw(false)
        }
        root.addView(recordButton, bottomCenterParams(dp(74), dp(74), dp(32)))
        recordButton.setOnClickListener {
            if (activeRecording == null) startRecording() else stopRecording()
        }

        countdownText = label("00:00", 16).also { it.visibility = View.GONE }
        root.addView(countdownText, bottomOffsetParams(dp(38), dp(78)))

        deleteButton = imageButton(R.drawable.spielbergo_delete_clip).also { it.visibility = View.GONE }
        doneButton = imageButton(R.drawable.spielbergo_checkmark_circle).also { it.visibility = View.GONE }
        root.addView(deleteButton, bottomOffsetParams(dp(42), -dp(38), dp(44)))
        root.addView(doneButton, bottomOffsetParams(dp(38), -dp(84), dp(58)))
        deleteButton.setOnClickListener { confirmDeleteLastClip() }
        doneButton.setOnClickListener { showEditor() }

        backButton = imageButton(R.drawable.spielbergo_chevron_left).also { it.visibility = View.GONE }
        previewOverlay.addView(backButton, topStartParams())
        backButton.setOnClickListener { showRecorder() }

        nextButton = TextView(this).also {
            it.text = "Next"
            it.textSize = 16f
            it.gravity = Gravity.CENTER
            it.setTextColor(Color.BLACK)
            it.typeface = android.graphics.Typeface.DEFAULT_BOLD
            it.background = roundedBackground(Color.WHITE, dp(7).toFloat())
            it.visibility = View.GONE
        }
        val nextParams = FrameLayout.LayoutParams(previewWidth, dp(44), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
        nextParams.bottomMargin = dp(16)
        root.addView(nextButton, nextParams)
        nextButton.setOnClickListener { exportAndFinish() }

        refreshRecorderUi()
    }

    private fun durationOption(label: String, selected: Boolean): TextView =
        label(label, 14).also { view ->
            view.typeface = android.graphics.Typeface.DEFAULT_BOLD
            view.gravity = Gravity.CENTER
            view.setPadding(dp(12), dp(4), dp(12), dp(4))
            styleDurationOption(view, selected)
            view.setOnClickListener {
                maxDurationMs = parseDurationMs(label)
                for (i in 0 until durationRow.childCount) {
                    styleDurationOption(durationRow.getChildAt(i) as TextView, false)
                }
                styleDurationOption(view, true)
                updateCountdown(remainingMs())
            }
        }

    private fun styleDurationOption(view: TextView, selected: Boolean) {
        view.setTextColor(if (selected) Color.BLACK else Color.WHITE)
        view.alpha = 1f
        view.background = if (selected) roundedBackground(Color.WHITE, dp(10).toFloat()) else null
    }

    private fun bindCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val selector = CameraSelector.Builder().requireLensFacing(selectedLensFacing).build()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            val recorder = Recorder.Builder()
                .setQualitySelector(
                    QualitySelector.from(
                        Quality.HD,
                        FallbackStrategy.higherQualityOrLowerThan(Quality.HD)
                    )
                )
                .build()
            videoCapture = VideoCapture.withOutput(recorder)
            provider.unbindAll()
            camera = provider.bindToLifecycle(this, selector, preview, videoCapture)
            applyBackTorch(false)
        }, ContextCompat.getMainExecutor(this))
    }

    @SuppressLint("MissingPermission")
    private fun startRecording() {
        val capture = videoCapture ?: return
        val remaining = remainingMs()
        if (remaining <= 0) return
        val file = File.createTempFile("spielbergo_clip_", ".mp4", cacheDir)
        activeClipFile = file
        isStoppingRecording = false
        recordStartedAt = System.currentTimeMillis()
        activeRecording = capture.output
            .prepareRecording(this, FileOutputOptions.Builder(file).build())
            .withAudioEnabled()
            .start(ContextCompat.getMainExecutor(this)) { event ->
                if (event is VideoRecordEvent.Finalize) {
                    val clip = activeClipFile
                    if (!event.hasError() && clip != null && clip.exists() && clip.length() > 0) {
                        clipFiles.add(clip)
                        clipDurationsMs.add(activeClipDurationMs)
                    } else {
                        clip?.delete()
                    }
                    activeClipFile = null
                    activeClipDurationMs = 0L
                    activeRecording = null
                    isStoppingRecording = false
                    refreshRecorderUi()
                }
            }
        timer?.cancel()
        timer = object : CountDownTimer(remaining, 50L) {
            override fun onTick(millisUntilFinished: Long) {
                val elapsed = System.currentTimeMillis() - recordStartedAt
                recordButton.progress = ((committedDurationMs + elapsed).toFloat() / maxDurationMs).coerceIn(0f, 1f)
                updateCountdown(millisUntilFinished)
            }

            override fun onFinish() {
                stopRecording()
            }
        }.start()
        refreshRecordingUi()
    }

    private fun stopRecording() {
        if (isStoppingRecording) return
        isStoppingRecording = true
        timer?.cancel()
        val elapsed = System.currentTimeMillis() - recordStartedAt
        activeClipDurationMs = elapsed
        committedDurationMs = (committedDurationMs + elapsed).coerceAtMost(maxDurationMs)
        activeRecording?.stop()
        recordButton.progress = committedDurationMs.toFloat() / maxDurationMs
    }

    private fun switchCamera() {
        selectedLensFacing =
            if (selectedLensFacing == CameraSelector.LENS_FACING_FRONT) CameraSelector.LENS_FACING_BACK
            else CameraSelector.LENS_FACING_FRONT
        frontLightEnabled = false
        frontLight.visibility = View.GONE
        flashButton.setImageResource(R.drawable.spielbergo_no_flash)
        bindCamera()
    }

    private fun toggleLight() {
        if (selectedLensFacing == CameraSelector.LENS_FACING_BACK) {
            val enable = camera?.cameraInfo?.torchState?.value != androidx.camera.core.TorchState.ON
            applyBackTorch(enable)
        } else {
            frontLightEnabled = !frontLightEnabled
            frontLight.visibility = if (frontLightEnabled) View.VISIBLE else View.GONE
            flashButton.setImageResource(
                if (frontLightEnabled) R.drawable.spielbergo_flash else R.drawable.spielbergo_no_flash
            )
        }
    }

    private fun applyBackTorch(enable: Boolean) {
        camera?.cameraControl?.enableTorch(enable)
        flashButton.setImageResource(if (enable) R.drawable.spielbergo_flash else R.drawable.spielbergo_no_flash)
    }

    private fun showEditor() {
        if (clipFiles.isEmpty()) return
        previewView.visibility = View.GONE
        videoView.visibility = View.VISIBLE
        closeButton.visibility = View.GONE
        switchButton.visibility = View.GONE
        flashButton.visibility = View.GONE
        durationRow.visibility = View.GONE
        recordButton.visibility = View.GONE
        deleteButton.visibility = View.GONE
        doneButton.visibility = View.GONE
        countdownText.visibility = View.GONE
        backButton.visibility = View.VISIBLE
        nextButton.visibility = View.VISIBLE
        previewClipIndex = 0
        playNextPreviewClip()
    }

    private fun showRecorder() {
        videoView.stopPlayback()
        videoView.visibility = View.GONE
        previewView.visibility = View.VISIBLE
        backButton.visibility = View.GONE
        nextButton.visibility = View.GONE
        refreshRecorderUi()
    }

    private fun playNextPreviewClip() {
        if (clipFiles.isEmpty() || videoView.visibility != View.VISIBLE) return
        val file = clipFiles[previewClipIndex % clipFiles.size]
        previewClipIndex += 1
        videoView.setVideoURI(Uri.fromFile(file))
        videoView.setOnCompletionListener { playNextPreviewClip() }
        videoView.start()
    }

    private fun exportAndFinish() {
        if (clipFiles.isEmpty()) {
            finishCancelled()
            return
        }
        nextButton.isEnabled = false
        nextButton.text = "Preparing..."
        Thread {
            val output = File.createTempFile("spielbergo_video_", ".mp4", cacheDir)
            val result = try {
                AndroidClipExporter.concatenate(clipFiles, output)
                output
            } catch (_: Throwable) {
                clipFiles.first().copyTo(output, overwrite = true)
                output
            }
            clipFiles.forEach { it.delete() }
            runOnUiThread {
                setResult(Activity.RESULT_OK, Intent().putExtra(extraVideoPath, result.absolutePath))
                finish()
            }
        }.start()
    }

    private fun confirmExit() {
        AlertDialog.Builder(this)
            .setTitle("Discard video?")
            .setMessage("This will delete your recorded clips.")
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Discard") { _, _ -> finishCancelled() }
            .show()
    }

    private fun confirmDeleteLastClip() {
        if (clipFiles.isEmpty()) return
        AlertDialog.Builder(this)
            .setTitle("Delete last clip?")
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Delete") { _, _ ->
                val file = clipFiles.removeLast()
                val duration = clipDurationsMs.removeLastOrNull() ?: 0L
                file.delete()
                committedDurationMs = (committedDurationMs - duration).coerceAtLeast(0L)
                recordButton.progress = committedDurationMs.toFloat() / maxDurationMs
                refreshRecorderUi()
            }
            .show()
    }

    private fun finishCancelled() {
        activeRecording?.close()
        clipFiles.forEach { it.delete() }
        activeClipFile?.delete()
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    private fun refreshRecordingUi() {
        closeButton.visibility = View.GONE
        switchButton.visibility = View.GONE
        flashButton.visibility = View.GONE
        durationRow.visibility = View.GONE
        deleteButton.visibility = View.GONE
        doneButton.visibility = View.GONE
        countdownText.visibility = View.VISIBLE
        recordButton.mode = RecordButton.Mode.STOP
    }

    private fun refreshRecorderUi() {
        closeButton.visibility = View.VISIBLE
        switchButton.visibility = View.VISIBLE
        flashButton.visibility = View.VISIBLE
        durationRow.visibility = View.VISIBLE
        countdownText.visibility = View.GONE
        recordButton.visibility = View.VISIBLE
        recordButton.mode = if (clipFiles.isEmpty()) RecordButton.Mode.EMPTY else RecordButton.Mode.READY
        deleteButton.visibility = if (clipFiles.isEmpty()) View.GONE else View.VISIBLE
        doneButton.visibility = if (clipFiles.isEmpty()) View.GONE else View.VISIBLE
        updateCountdown(remainingMs())
    }

    private fun remainingMs(): Long = (maxDurationMs - committedDurationMs).coerceAtLeast(0L)

    private fun updateCountdown(ms: Long) {
        val totalSeconds = (ms / 1000L).coerceAtLeast(0L)
        countdownText.text = "%02d:%02d".format(totalSeconds / 60, totalSeconds % 60)
    }

    private fun parseDurationMs(label: String): Long {
        val trimmed = label.trim().lowercase()
        val amount = trimmed.dropLast(1).toLongOrNull() ?: 15L
        return if (trimmed.endsWith("m")) amount * 60_000L else amount * 1_000L
    }

    private fun imageButton(drawableRes: Int): ImageButton =
        ImageButton(this).also {
            it.setImageResource(drawableRes)
            it.background = null
            it.setBackgroundColor(Color.TRANSPARENT)
            it.scaleType = ImageView.ScaleType.CENTER_INSIDE
            it.adjustViewBounds = true
            it.setPadding(dp(8), dp(8), dp(8), dp(8))
        }

    private fun label(text: String, size: Int): TextView =
        TextView(this).also {
            it.text = text
            it.textSize = size.toFloat()
            it.setTextColor(Color.WHITE)
        }

    private fun topStartParams(): FrameLayout.LayoutParams =
        FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).also {
            it.topMargin = dp(18)
            it.leftMargin = dp(12)
        }

    private fun topEndParams(offset: Int): FrameLayout.LayoutParams =
        FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).also {
            it.topMargin = dp(18 + offset)
            it.rightMargin = dp(12)
        }

    private fun bottomCenterParams(width: Int, height: Int, bottom: Int): FrameLayout.LayoutParams =
        FrameLayout.LayoutParams(width, height, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).also {
            it.bottomMargin = bottom
        }

    private fun bottomOffsetParams(bottom: Int, rightOffset: Int, size: Int = dp(48)): FrameLayout.LayoutParams =
        FrameLayout.LayoutParams(size, size, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).also {
            it.bottomMargin = bottom
            it.marginStart = rightOffset
        }

    private fun roundedBackground(color: Int, radius: Float) =
        android.graphics.drawable.GradientDrawable().also {
            it.setColor(color)
            it.cornerRadius = radius
        }

    private fun roundedOutline(radius: Float): ViewOutlineProvider =
        object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, radius)
            }
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}

private class RecordButton(context: android.content.Context) : View(context) {
    enum class Mode { EMPTY, READY, STOP }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        setBackgroundColor(Color.TRANSPARENT)
        background = null
    }
    var mode = Mode.EMPTY
        set(value) {
            field = value
            invalidate()
        }
    var progress = 0f
        set(value) {
            field = value
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)
        super.onDraw(canvas)
        val size = min(width, height).toFloat()
        val center = size / 2f
        paint.style = Paint.Style.FILL
        paint.color = Color.WHITE
        canvas.drawCircle(center, center, size * 0.47f, paint)

        paint.color = Color.rgb(220, 0, 0)
        when (mode) {
            Mode.EMPTY -> Unit
            Mode.READY -> canvas.drawCircle(center, center, size * 0.31f, paint)
            Mode.STOP -> canvas.drawRoundRect(
                center - size * 0.18f,
                center - size * 0.18f,
                center + size * 0.18f,
                center + size * 0.18f,
                size * 0.07f,
                size * 0.07f,
                paint
            )
        }

        if (progress > 0f) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = size * 0.055f
            paint.strokeCap = Paint.Cap.ROUND
            val inset = size * 0.08f
            canvas.drawArc(RectF(inset, inset, size - inset, size - inset), -90f, progress * 360f, false, paint)
        }
    }
}

private object AndroidClipExporter {
    fun concatenate(inputs: List<File>, output: File) {
        if (inputs.size == 1) {
            inputs.first().copyTo(output, overwrite = true)
            return
        }

        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var videoTrack = -1
        var audioTrack = -1
        var videoOffsetUs = 0L
        var audioOffsetUs = 0L
        var started = false

        inputs.forEachIndexed { index, file ->
            val extractor = MediaExtractor()
            extractor.setDataSource(file.absolutePath)
            val trackMap = mutableMapOf<Int, Int>()
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/")) {
                    if (index == 0) videoTrack = muxer.addTrack(format)
                    trackMap[i] = videoTrack
                } else if (mime.startsWith("audio/")) {
                    if (index == 0) audioTrack = muxer.addTrack(format)
                    trackMap[i] = audioTrack
                }
            }
            if (!started) {
                muxer.start()
                started = true
            }
            trackMap.keys.forEach { track ->
                extractor.seekTo(0L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                extractor.selectTrack(track)
                val targetTrack = trackMap[track] ?: return@forEach
                val offset = if (targetTrack == videoTrack) videoOffsetUs else audioOffsetUs
                val duration = copyTrack(extractor, muxer, targetTrack, offset)
                if (targetTrack == videoTrack) videoOffsetUs += duration else audioOffsetUs += duration
                extractor.unselectTrack(track)
            }
            extractor.release()
        }

        muxer.stop()
        muxer.release()
    }

    private fun copyTrack(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        targetTrack: Int,
        offsetUs: Long
    ): Long {
        val buffer = ByteBuffer.allocate(2 * 1024 * 1024)
        val info = android.media.MediaCodec.BufferInfo()
        var firstUs = -1L
        var lastUs = 0L
        while (true) {
            info.offset = 0
            info.size = extractor.readSampleData(buffer, 0)
            if (info.size < 0) break
            val sampleTime = extractor.sampleTime
            if (firstUs < 0) firstUs = sampleTime
            info.presentationTimeUs = offsetUs + sampleTime - firstUs
            info.flags = extractor.sampleFlags
            muxer.writeSampleData(targetTrack, buffer, info)
            lastUs = sampleTime - firstUs
            extractor.advance()
        }
        return lastUs
    }
}
