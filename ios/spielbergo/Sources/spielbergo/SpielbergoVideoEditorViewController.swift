import AVFoundation
import AVKit
import UIKit

final class SpielbergoVideoEditorViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
  var onComplete: ((String?) -> Void)?

  private let recordTimes: [String]
  private let selectedRecordTime: String
  private let session = AVCaptureSession()
  private let movieOutput = AVCaptureMovieFileOutput()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var currentCameraPosition: AVCaptureDevice.Position = .front
  private var clipUrls: [URL] = []
  private var clipDurations: [TimeInterval] = []
  private var activeClipUrl: URL?
  private var maxDuration: TimeInterval
  private var committedDuration: TimeInterval = 0
  private var activeClipDuration: TimeInterval = 0
  private var recordingStartedAt: Date?
  private var timer: Timer?
  private var previewPlayer: AVQueuePlayer?
  private var previewLooper: AVPlayerLooper?

  private let previewContainer = UIView()
  private let closeButton = UIButton(type: .system)
  private let switchButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .system)
  private let durationStack = UIStackView()
  private let recordButton = RecordButton()
  private let countdownLabel = UILabel()
  private let deleteButton = UIButton(type: .system)
  private let doneButton = UIButton(type: .system)
  private let backButton = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private let frontLightView = UIView()
  private let playerView = UIView()

  init(recordTimes: [String], defaultRecordTime: String?) {
    let availableRecordTimes = recordTimes.isEmpty ? ["15s"] : recordTimes
    let selectedRecordTime =
      defaultRecordTime.flatMap { availableRecordTimes.contains($0) ? $0 : nil } ?? availableRecordTimes[0]
    self.recordTimes = availableRecordTimes
    self.selectedRecordTime = selectedRecordTime
    self.maxDuration = SpielbergoVideoEditorViewController.parseDuration(selectedRecordTime)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureUi()
    requestPermissionsAndStart()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = previewContainer.bounds
    if previewLayer?.connection?.isVideoOrientationSupported == true {
      previewLayer?.connection?.videoOrientation = .portrait
    }
    previewPlayerLayer()?.frame = playerView.bounds
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    timer?.invalidate()
    if session.isRunning {
      session.stopRunning()
    }
  }

  private func configureUi() {
    previewContainer.backgroundColor = .black
    previewContainer.layer.cornerRadius = 14
    previewContainer.clipsToBounds = true
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewContainer)

    playerView.backgroundColor = .black
    playerView.layer.cornerRadius = 14
    playerView.clipsToBounds = true
    playerView.isHidden = true
    playerView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playerView)

    frontLightView.backgroundColor = .white
    frontLightView.alpha = 0.82
    frontLightView.isHidden = true
    frontLightView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(frontLightView)

    configureIcon(closeButton, imageName: "close")
    configureIcon(switchButton, imageName: "switch-camera")
    configureIcon(flashButton, imageName: "no-flash")
    configureIcon(deleteButton, imageName: "delete-clip")
    configureIcon(doneButton, imageName: "checkmark-circle")
    configureIcon(backButton, imageName: "chevron-left")
    closeButton.addTarget(self, action: #selector(confirmExit), for: .touchUpInside)
    switchButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
    flashButton.addTarget(self, action: #selector(toggleLight), for: .touchUpInside)
    deleteButton.addTarget(self, action: #selector(confirmDeleteLastClip), for: .touchUpInside)
    doneButton.addTarget(self, action: #selector(showEditor), for: .touchUpInside)
    backButton.addTarget(self, action: #selector(showRecorder), for: .touchUpInside)

    [closeButton, switchButton, flashButton, deleteButton, doneButton, backButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview($0)
    }

    durationStack.axis = .horizontal
    durationStack.alignment = .center
    durationStack.distribution = .equalSpacing
    durationStack.spacing = 18
    durationStack.translatesAutoresizingMaskIntoConstraints = false
    recordTimes.enumerated().forEach { index, label in
      let button = UIButton(type: .system)
      button.setTitle(label, for: .normal)
      button.titleLabel?.font = .boldSystemFont(ofSize: 14)
      button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
      button.tag = index
      styleDurationButton(button, selected: label == selectedRecordTime || (index == 0 && selectedRecordTime.isEmpty))
      button.addTarget(self, action: #selector(selectDuration(_:)), for: .touchUpInside)
      durationStack.addArrangedSubview(button)
    }
    view.addSubview(durationStack)

    recordButton.translatesAutoresizingMaskIntoConstraints = false
    recordButton.backgroundColor = .clear
    recordButton.isOpaque = false
    recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
    view.addSubview(recordButton)

    countdownLabel.textColor = .white
    countdownLabel.font = .boldSystemFont(ofSize: 16)
    countdownLabel.text = "00:00"
    countdownLabel.isHidden = true
    countdownLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(countdownLabel)

    nextButton.setTitle("Next", for: .normal)
    nextButton.setTitleColor(.black, for: .normal)
    nextButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
    nextButton.backgroundColor = .white
    nextButton.layer.cornerRadius = 7
    nextButton.isHidden = true
    nextButton.translatesAutoresizingMaskIntoConstraints = false
    nextButton.addTarget(self, action: #selector(exportAndFinish), for: .touchUpInside)
    view.addSubview(nextButton)

    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      previewContainer.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -28),
      previewContainer.heightAnchor.constraint(equalTo: previewContainer.widthAnchor, multiplier: 16 / 9),
      previewContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      previewContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -8),

      playerView.widthAnchor.constraint(equalTo: previewContainer.widthAnchor),
      playerView.heightAnchor.constraint(equalTo: previewContainer.heightAnchor),
      playerView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
      playerView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),

      frontLightView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      frontLightView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      frontLightView.topAnchor.constraint(equalTo: view.topAnchor),
      frontLightView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      closeButton.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
      closeButton.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 18),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

      switchButton.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
      switchButton.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 18),
      switchButton.widthAnchor.constraint(equalToConstant: 44),
      switchButton.heightAnchor.constraint(equalToConstant: 44),

      flashButton.trailingAnchor.constraint(equalTo: switchButton.trailingAnchor),
      flashButton.topAnchor.constraint(equalTo: switchButton.bottomAnchor, constant: 8),
      flashButton.widthAnchor.constraint(equalToConstant: 44),
      flashButton.heightAnchor.constraint(equalToConstant: 44),

      durationStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      durationStack.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -12),

      recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      recordButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
      recordButton.widthAnchor.constraint(equalToConstant: 74),
      recordButton.heightAnchor.constraint(equalToConstant: 74),

      countdownLabel.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 18),
      countdownLabel.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),

      deleteButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 22),
      deleteButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
      deleteButton.widthAnchor.constraint(equalToConstant: 44),
      deleteButton.heightAnchor.constraint(equalToConstant: 44),

      doneButton.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 6),
      doneButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
      doneButton.widthAnchor.constraint(equalToConstant: 58),
      doneButton.heightAnchor.constraint(equalToConstant: 58),

      backButton.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
      backButton.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 18),
      backButton.widthAnchor.constraint(equalToConstant: 44),
      backButton.heightAnchor.constraint(equalToConstant: 44),

      nextButton.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
      nextButton.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
      nextButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
      nextButton.heightAnchor.constraint(equalToConstant: 44)
    ])

    refreshRecorderUi()
  }

  private func requestPermissionsAndStart() {
    AVCaptureDevice.requestAccess(for: .video) { videoAllowed in
      AVCaptureDevice.requestAccess(for: .audio) { audioAllowed in
        DispatchQueue.main.async {
          if videoAllowed && audioAllowed {
            self.configureSession()
          } else {
            self.finishCancelled()
          }
        }
      }
    }
  }

  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .high
    session.inputs.forEach { session.removeInput($0) }

    guard
      let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
      let videoInput = try? AVCaptureDeviceInput(device: camera),
      let audio = AVCaptureDevice.default(for: .audio),
      let audioInput = try? AVCaptureDeviceInput(device: audio),
      session.canAddInput(videoInput),
      session.canAddInput(audioInput)
    else {
      session.commitConfiguration()
      return
    }

    session.addInput(videoInput)
    session.addInput(audioInput)
    if session.outputs.isEmpty && session.canAddOutput(movieOutput) {
      session.addOutput(movieOutput)
    }
    if movieOutput.connection(with: .video)?.isVideoOrientationSupported == true {
      movieOutput.connection(with: .video)?.videoOrientation = .portrait
    }
    session.commitConfiguration()

    if previewLayer == nil {
      let layer = AVCaptureVideoPreviewLayer(session: session)
      layer.videoGravity = .resizeAspectFill
      previewContainer.layer.insertSublayer(layer, at: 0)
      previewLayer = layer
    }

    DispatchQueue.global(qos: .userInitiated).async {
      self.session.startRunning()
    }
  }

  @objc private func toggleRecording() {
    movieOutput.isRecording ? stopRecording() : startRecording()
  }

  private func startRecording() {
    let remaining = remainingDuration()
    guard remaining > 0, !movieOutput.isRecording else { return }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("spielbergo_clip_\(UUID().uuidString)")
      .appendingPathExtension("mov")
    activeClipUrl = url
    recordingStartedAt = Date()
    movieOutput.maxRecordedDuration = CMTime(seconds: remaining, preferredTimescale: 600)
    movieOutput.startRecording(to: url, recordingDelegate: self)
    refreshRecordingUi()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      self?.tickRecordingProgress()
    }
  }

  private func stopRecording() {
    timer?.invalidate()
    if let started = recordingStartedAt {
      activeClipDuration = Date().timeIntervalSince(started)
      committedDuration = min(maxDuration, committedDuration + activeClipDuration)
    }
    movieOutput.stopRecording()
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    if error == nil {
      clipUrls.append(outputFileURL)
      clipDurations.append(activeClipDuration)
    } else {
      try? FileManager.default.removeItem(at: outputFileURL)
    }
    activeClipUrl = nil
    activeClipDuration = 0
    recordingStartedAt = nil
    refreshRecorderUi()
  }

  private func tickRecordingProgress() {
    guard let started = recordingStartedAt else { return }
    let elapsed = Date().timeIntervalSince(started)
    recordButton.progress = min(1, CGFloat((committedDuration + elapsed) / maxDuration))
    let remaining = remainingDuration() - elapsed
    updateCountdown(remaining)
    if remaining <= 0 {
      stopRecording()
    }
  }

  @objc private func selectDuration(_ sender: UIButton) {
    guard recordTimes.indices.contains(sender.tag) else { return }
    maxDuration = Self.parseDuration(recordTimes[sender.tag])
    durationStack.arrangedSubviews.enumerated().forEach { index, view in
      if let button = view as? UIButton {
        styleDurationButton(button, selected: index == sender.tag)
      }
    }
    updateCountdown(remainingDuration())
  }

  private func styleDurationButton(_ button: UIButton, selected: Bool) {
    button.setTitleColor(selected ? .black : .white, for: .normal)
    button.backgroundColor = selected ? .white : .clear
    button.layer.cornerRadius = 10
    button.layer.masksToBounds = true
  }

  @objc private func switchCamera() {
    currentCameraPosition = currentCameraPosition == .front ? .back : .front
    frontLightView.isHidden = true
    setFlashIcon(enabled: false)
    configureSession()
  }

  @objc private func toggleLight() {
    guard currentCameraPosition == .back else {
      frontLightView.isHidden.toggle()
      setFlashIcon(enabled: !frontLightView.isHidden)
      return
    }
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
          device.hasTorch
    else { return }
    try? device.lockForConfiguration()
    device.torchMode = device.torchMode == .on ? .off : .on
    setFlashIcon(enabled: device.torchMode == .on)
    device.unlockForConfiguration()
  }

  private func setFlashIcon(enabled: Bool) {
    let image = loadIcon(named: enabled ? "flash" : "no-flash")?.withRenderingMode(.alwaysOriginal)
    flashButton.setImage(image, for: .normal)
  }

  @objc private func showEditor() {
    guard !clipUrls.isEmpty else { return }
    previewContainer.isHidden = true
    playerView.isHidden = false
    closeButton.isHidden = true
    switchButton.isHidden = true
    flashButton.isHidden = true
    durationStack.isHidden = true
    recordButton.isHidden = true
    deleteButton.isHidden = true
    doneButton.isHidden = true
    countdownLabel.isHidden = true
    backButton.isHidden = false
    nextButton.isHidden = false
    playPreview()
  }

  @objc private func showRecorder() {
    previewPlayer?.pause()
    previewPlayerLayer()?.removeFromSuperlayer()
    previewPlayer = nil
    previewLooper = nil
    playerView.isHidden = true
    previewContainer.isHidden = false
    refreshRecorderUi()
  }

  private func playPreview() {
    let composition = AVMutableComposition()
    guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      return
    }
    var audioTrack: AVMutableCompositionTrack?
    var cursor = CMTime.zero
    clipUrls.forEach { url in
      let asset = AVURLAsset(url: url)
      if let sourceVideo = asset.tracks(withMediaType: .video).first {
        try? videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceVideo, at: cursor)
        videoTrack.preferredTransform = sourceVideo.preferredTransform
      }
      if let sourceAudio = asset.tracks(withMediaType: .audio).first {
        if audioTrack == nil {
          audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        try? audioTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: sourceAudio, at: cursor)
      }
      cursor = cursor + asset.duration
    }
    let item = AVPlayerItem(asset: composition)
    let queue = AVQueuePlayer()
    previewLooper = AVPlayerLooper(player: queue, templateItem: item)
    previewPlayer = queue
    let layer = AVPlayerLayer(player: queue)
    layer.videoGravity = .resizeAspectFill
    layer.frame = playerView.bounds
    playerView.layer.addSublayer(layer)
    queue.play()
  }

  @objc private func exportAndFinish() {
    nextButton.isEnabled = false
    nextButton.setTitle("Preparing...", for: .normal)
    exportClips { [weak self] url in
      guard let self else { return }
      self.clipUrls.forEach { try? FileManager.default.removeItem(at: $0) }
      self.dismiss(animated: true) {
        self.onComplete?(url?.path)
      }
    }
  }

  private func exportClips(completion: @escaping (URL?) -> Void) {
    guard !clipUrls.isEmpty else {
      completion(nil)
      return
    }
    let composition = AVMutableComposition()
    guard let outputVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      completion(nil)
      return
    }
    var outputAudioTrack: AVMutableCompositionTrack?
    var cursor = CMTime.zero
    clipUrls.forEach { url in
      let asset = AVURLAsset(url: url)
      if let video = asset.tracks(withMediaType: .video).first {
        try? outputVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: video, at: cursor)
        outputVideoTrack.preferredTransform = video.preferredTransform
      }
      if let audio = asset.tracks(withMediaType: .audio).first {
        if outputAudioTrack == nil {
          outputAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        try? outputAudioTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audio, at: cursor)
      }
      cursor = cursor + asset.duration
    }

    let outputUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent("spielbergo_video_\(UUID().uuidString)")
      .appendingPathExtension("mp4")
    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
      completion(nil)
      return
    }
    exporter.outputURL = outputUrl
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.exportAsynchronously {
      DispatchQueue.main.async {
        completion(exporter.status == .completed ? outputUrl : nil)
      }
    }
  }

  @objc private func confirmExit() {
    let alert = UIAlertController(title: "Discard video?", message: "This will delete your recorded clips.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
      self?.finishCancelled()
    })
    present(alert, animated: true)
  }

  @objc private func confirmDeleteLastClip() {
    guard !clipUrls.isEmpty else { return }
    let alert = UIAlertController(title: "Delete last clip?", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
      guard let self else { return }
      let url = self.clipUrls.removeLast()
      let duration = self.clipDurations.popLast() ?? 0
      try? FileManager.default.removeItem(at: url)
      self.committedDuration = max(0, self.committedDuration - duration)
      self.recordButton.progress = CGFloat(self.committedDuration / self.maxDuration)
      self.refreshRecorderUi()
    })
    present(alert, animated: true)
  }

  private func finishCancelled() {
    clipUrls.forEach { try? FileManager.default.removeItem(at: $0) }
    if let activeClipUrl {
      try? FileManager.default.removeItem(at: activeClipUrl)
    }
    dismiss(animated: true) { [weak self] in
      self?.onComplete?(nil)
    }
  }

  private func refreshRecordingUi() {
    closeButton.isHidden = true
    switchButton.isHidden = true
    flashButton.isHidden = true
    durationStack.isHidden = true
    deleteButton.isHidden = true
    doneButton.isHidden = true
    countdownLabel.isHidden = false
    recordButton.mode = .stop
  }

  private func refreshRecorderUi() {
    closeButton.isHidden = false
    switchButton.isHidden = false
    flashButton.isHidden = false
    durationStack.isHidden = false
    recordButton.isHidden = false
    countdownLabel.isHidden = true
    backButton.isHidden = true
    nextButton.isHidden = true
    recordButton.mode = clipUrls.isEmpty ? .empty : .ready
    deleteButton.isHidden = clipUrls.isEmpty
    doneButton.isHidden = clipUrls.isEmpty
    updateCountdown(remainingDuration())
  }

  private func remainingDuration() -> TimeInterval {
    max(0, maxDuration - committedDuration)
  }

  private func updateCountdown(_ duration: TimeInterval) {
    let seconds = max(0, Int(duration))
    countdownLabel.text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  private func configureIcon(_ button: UIButton, imageName: String) {
    let image = loadIcon(named: imageName)?.withRenderingMode(.alwaysOriginal)
    button.setImage(image, for: .normal)
    button.backgroundColor = .clear
    button.imageView?.contentMode = .scaleAspectFit
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
  }

  private func loadIcon(named name: String) -> UIImage? {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for: SpielbergoVideoEditorViewController.self)
    #endif
    return UIImage(named: name, in: bundle, compatibleWith: nil)
      ?? UIImage(contentsOfFile: bundle.path(forResource: name, ofType: "png") ?? "")
  }

  private func previewPlayerLayer() -> AVPlayerLayer? {
    playerView.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
  }

  private static func parseDuration(_ label: String) -> TimeInterval {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let amount = Double(trimmed.dropLast()) ?? 15
    return trimmed.hasSuffix("m") ? amount * 60 : amount
  }
}

private final class RecordButton: UIControl {
  enum Mode { case empty, ready, stop }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    backgroundColor = .clear
    isOpaque = false
  }

  var mode: Mode = .empty {
    didSet { setNeedsDisplay() }
  }
  var progress: CGFloat = 0 {
    didSet { setNeedsDisplay() }
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.clear(rect)
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    context.setFillColor(UIColor.white.cgColor)
    context.addArc(center: center, radius: size * 0.47, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    context.setFillColor(UIColor(red: 0.86, green: 0, blue: 0, alpha: 1).cgColor)
    switch mode {
    case .empty:
      break
    case .ready:
      context.addArc(center: center, radius: size * 0.31, startAngle: 0, endAngle: .pi * 2, clockwise: false)
      context.fillPath()
    case .stop:
      let side = size * 0.36
      UIBezierPath(
        roundedRect: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
        cornerRadius: size * 0.07
      ).fill()
    }

    guard progress > 0 else { return }
    context.setStrokeColor(UIColor(red: 0.86, green: 0, blue: 0, alpha: 1).cgColor)
    context.setLineWidth(size * 0.055)
    context.setLineCap(.round)
    let radius = size * 0.39
    context.addArc(
      center: center,
      radius: radius,
      startAngle: -.pi / 2,
      endAngle: -.pi / 2 + (.pi * 2 * progress),
      clockwise: false
    )
    context.strokePath()
  }
}
