import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spielbergo/spielbergo.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  File? _videoFile;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitialisation;
  bool _isPicking = false;

  Future<void> _pickVideo() async {
    setState(() => _isPicking = true);
    final videoFile = await SpielbergoVideoEditor().pickVideo(
      recordTimes: ['10m', '1m', '30s', '15s'],
      defaultRecordTime: '1m',
    );
    if (!mounted) return;
    if (videoFile != null) {
      await _loadVideo(videoFile);
      return;
    }
    setState(() {
      _isPicking = false;
    });
  }

  Future<void> _loadVideo(File file) async {
    final previousController = _videoController;
    final controller = VideoPlayerController.file(file);
    final initialisation = controller.initialize().then((_) async {
      await controller.setLooping(true);
      await controller.play();
    });

    setState(() {
      _videoFile = file;
      _videoController = controller;
      _videoInitialisation = initialisation;
      _isPicking = false;
    });

    await previousController?.dispose();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_videoFile == null) _buildEmptyState() else _buildVideoPlayer(),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _isPicking ? null : _pickVideo,
                    child: Text(_isPicking ? 'Opening...' : 'Record'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: FilledButton(
        onPressed: _isPicking ? null : _pickVideo,
        child: Text(_isPicking ? 'Opening...' : 'Open video editor'),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final controller = _videoController;
    final initialisation = _videoInitialisation;

    if (controller == null || initialisation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<void>(
      future: initialisation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not play video:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }
}
