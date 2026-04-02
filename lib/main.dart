import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SlapMacApp());
}

class SlapMacApp extends StatelessWidget {
  const SlapMacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SlapMac',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const SlapPadPage(),
    );
  }
}

class SlapPadPage extends StatefulWidget {
  const SlapPadPage({super.key});

  @override
  State<SlapPadPage> createState() => _SlapPadPageState();
}

class _SlapPadPageState extends State<SlapPadPage> {
  static const MethodChannel _methodChannel = MethodChannel('slapmac/monitoring');
  static const EventChannel _eventChannel = EventChannel('slapmac/events');

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<dynamic>? _monitorSubscription;
  String? _audioPath;
  double _volume = 0.9;
  int _slapCount = 0;
  String _lastEvent = 'None yet';
  String _monitoringStatus = 'Starting accelerometer slap monitoring...';

  @override
  void initState() {
    super.initState();
    _startHardwareMonitoring();
  }

  Future<void> _startHardwareMonitoring() async {
    try {
      final response = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
        'startMonitoring',
      );
      final started = response?['started'] == true;

      setState(() {
        _monitoringStatus = started
            ? 'Monitoring chassis impacts (no keyboard/trackpad input needed).'
            : 'Accelerometer unavailable on this Mac. Slap detection is disabled.';
      });
    } on MissingPluginException {
      setState(() {
        _monitoringStatus =
            'Native monitoring unavailable in this environment (tests/web/etc).';
      });
    } on PlatformException catch (error) {
      setState(() {
        _monitoringStatus = 'Could not start monitoring: ${error.message}';
      });
    }

    _monitorSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String) {
        _onHardwareSlap(event);
      }
    });
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    );

    final selectedPath = result?.files.single.path;
    if (selectedPath == null) {
      return;
    }

    setState(() => _audioPath = selectedPath);
  }

  Future<void> _playSlapSound() async {
    if (_audioPath == null) {
      return;
    }

    await _player.setVolume(_volume);
    await _player.play(DeviceFileSource(_audioPath!));
  }

  Future<void> _onHardwareSlap(String eventName) async {
    if (!mounted || _audioPath == null) {
      return;
    }

    setState(() {
      _lastEvent = eventName;
      _slapCount++;
    });

    await _playSlapSound();
  }

  @override
  void dispose() {
    _monitorSubscription?.cancel();
    _methodChannel.invokeMethod('stopMonitoring');
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chosenAudioLabel = _audioPath == null
        ? 'No file selected'
        : 'Selected: ${_audioPath!.split('/').last}';

    return Scaffold(
      appBar: AppBar(title: const Text('SlapMac')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.audio_file),
                  label: const Text('Choose slap audio'),
                ),
                SizedBox(
                  width: 360,
                  child: Text(
                    chosenAudioLabel,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: Row(
                    children: [
                      const Text('Volume'),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          min: 0,
                          max: 1,
                          divisions: 10,
                          label: _volume.toStringAsFixed(1),
                          onChanged: (value) {
                            setState(() => _volume = value);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _audioPath == null ? null : _playSlapSound,
                  child: const Text('Preview sound'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _monitoringStatus,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Detection model: high-pass + STA/LTA + CUSUM + kurtosis + '
                  'peak/MAD voting. Trigger fires when enough algorithms agree.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Detected slaps: $_slapCount • Last event: $_lastEvent',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
