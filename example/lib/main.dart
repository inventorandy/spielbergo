import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spielbergo/spielbergo.dart';

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
  bool _isPicking = false;

  Future<void> _pickVideo() async {
    setState(() => _isPicking = true);
    final videoFile = await SpielbergoVideoEditor().pickVideo(
      recordTimes: ['10m', '1m', '30s', '15s'],
    );
    if (!mounted) return;
    setState(() {
      _videoFile = videoFile;
      _isPicking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Spielbergo example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: _isPicking ? null : _pickVideo,
                  child: Text(_isPicking ? 'Opening...' : 'Open video editor'),
                ),
                const SizedBox(height: 24),
                Text(
                  _videoFile == null
                      ? 'No video selected.'
                      : 'Video file:\n${_videoFile!.path}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
