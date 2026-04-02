import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  final AudioPlayer _player = AudioPlayer();

  String? _audioPath;
  double _volume = 0.9;
  int _keyboardSlaps = 0;
  int _trackpadSlaps = 0;
  String _lastZone = 'None yet';

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

  Future<void> _onZoneSlap(String zone) async {
    if (_audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose your own slap audio file first.'),
        ),
      );
      return;
    }

    setState(() {
      _lastZone = zone;
      if (zone == 'Keyboard area') {
        _keyboardSlaps++;
      } else {
        _trackpadSlaps++;
      }
    });

    await _playSlapSound();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _keyboardSlaps + _trackpadSlaps;
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
                  width: 300,
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
            Text(
              'Tap/click a zone to simulate a slap.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _SlapZone(
                      title: 'Keyboard area',
                      color: Colors.blueGrey.shade100,
                      onSlap: () => _onZoneSlap('Keyboard area'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _SlapZone(
                      title: 'Trackpad area',
                      color: Colors.teal.shade100,
                      onSlap: () => _onZoneSlap('Trackpad area'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Total slaps: $total • Keyboard: $_keyboardSlaps • '
                  'Trackpad: $_trackpadSlaps • Last zone: $_lastZone',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlapZone extends StatelessWidget {
  const _SlapZone({
    required this.title,
    required this.onSlap,
    required this.color,
  });

  final String title;
  final VoidCallback onSlap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSlap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black26),
        ),
        child: Center(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
