import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

String dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class CalendarNoteEntry {
  final String date;
  final String note;
  final String? audioPath;

  const CalendarNoteEntry({
    required this.date,
    required this.note,
    this.audioPath,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'note': note,
    'audioPath': audioPath,
  };

  factory CalendarNoteEntry.fromJson(Map<String, dynamic> json) {
    return CalendarNoteEntry(
      date: (json['date'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      audioPath: json['audioPath']?.toString(),
    );
  }

  CalendarNoteEntry copyWith({
    String? date,
    String? note,
    String? audioPath,
    bool clearAudio = false,
  }) {
    return CalendarNoteEntry(
      date: date ?? this.date,
      note: note ?? this.note,
      audioPath: clearAudio ? null : (audioPath ?? this.audioPath),
    );
  }
}

class CalendarNotesPage extends StatefulWidget {
  const CalendarNotesPage({super.key});

  @override
  State<CalendarNotesPage> createState() => _CalendarNotesPageState();
}

class _CalendarNotesPageState extends State<CalendarNotesPage> {
  final TextEditingController _noteController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  SharedPreferences? _prefs;
  Map<String, CalendarNoteEntry> _entries = {};

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentRecordingPath;

  final Map<String, String> _holidays = {
    '2026-01-01': 'New Year\'s Day',
    '2026-04-09': 'Araw ng Kagitingan',
    '2026-04-02': 'Maundy Thursday',
    '2026-04-03': 'Good Friday',
    '2026-05-01': 'Labor Day',
    '2026-06-12': 'Independence Day',
    '2026-08-31': 'National Heroes Day',
    '2026-11-01': 'All Saints\' Day',
    '2026-11-30': 'Bonifacio Day',
    '2026-12-25': 'Christmas Day',
    '2026-12-30': 'Rizal Day',
  };

  String get _selectedKey => dateKey(_selectedDay);

  CalendarNoteEntry get _currentEntry =>
      _entries[_selectedKey] ??
          CalendarNoteEntry(
            date: _selectedKey,
            note: '',
            audioPath: null,
          );

  String? get _selectedHolidayName => _holidays[_selectedKey];

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString('calendar_entries') ?? '{}';
    final decodedRaw = jsonDecode(raw);
    final decoded =
    decodedRaw is Map<String, dynamic> ? decodedRaw : <String, dynamic>{};

    final map = <String, CalendarNoteEntry>{};
    decoded.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        map[key] = CalendarNoteEntry.fromJson(value);
      } else if (value is Map) {
        map[key] = CalendarNoteEntry.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    });

    _entries = map;
    _noteController.text = _currentEntry.note;

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveEntries() async {
    final data = _entries.map((key, value) => MapEntry(key, value.toJson()));
    await _prefs?.setString('calendar_entries', jsonEncode(data));
  }

  List<CalendarNoteEntry> _eventsForDay(DateTime day) {
    final entry = _entries[dateKey(day)];
    if (entry == null) return [];
    if (entry.note.trim().isEmpty &&
        (entry.audioPath == null || entry.audioPath!.isEmpty)) {
      return [];
    }
    return [entry];
  }

  Future<void> _saveCurrentNote() async {
    final existing = _currentEntry;
    final updated = existing.copyWith(
      note: _noteController.text.trim(),
      audioPath: _currentRecordingPath ?? existing.audioPath,
    );

    if (updated.note.isEmpty &&
        (updated.audioPath == null || updated.audioPath!.isEmpty)) {
      _entries.remove(_selectedKey);
    } else {
      _entries[_selectedKey] = updated;
    }

    await _saveEntries();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry saved')),
    );
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/voice_${_selectedKey}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _audioRecorder.start(
      const RecordConfig(),
      path: path,
    );

    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _currentRecordingPath = path;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _audioRecorder.stop();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      if (path != null) {
        _currentRecordingPath = path;
      }
    });

    if (path != null) {
      final existing = _currentEntry.copyWith(
        note: _noteController.text.trim(),
        audioPath: path,
      );

      _entries[_selectedKey] = existing;
      await _saveEntries();

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice saved')),
      );
    }
  }

  Future<void> _playAudio() async {
    final audioPath = _currentRecordingPath ?? _currentEntry.audioPath;
    if (audioPath == null || audioPath.isEmpty) return;

    final file = File(audioPath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio file not found')),
      );
      return;
    }

    await _audioPlayer.setFilePath(audioPath);
    await _audioPlayer.play();
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
    });
  }

  Future<void> _deleteAudio() async {
    final path = _currentRecordingPath ?? _currentEntry.audioPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final existing = _currentEntry.copyWith(clearAudio: true);
    if (existing.note.isEmpty) {
      _entries.remove(_selectedKey);
    } else {
      _entries[_selectedKey] = existing;
    }

    _currentRecordingPath = null;
    await _saveEntries();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEntry = _currentEntry;
    final effectiveAudioPath = _currentRecordingPath ?? currentEntry.audioPath;
    final hasAudio = effectiveAudioPath != null && effectiveAudioPath.isNotEmpty;

    final sortedEntries = _entries.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        titleSpacing: 0,
        title: const Text('Calendar Notes'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          TableCalendar<CalendarNoteEntry>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
            eventLoader: _eventsForDay,
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.monday,
            holidayPredicate: (day) => _holidays.containsKey(dateKey(day)),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                _currentRecordingPath = null;
                _noteController.text =
                (_entries[dateKey(selectedDay)]?.note ?? '');
              });
            },
            calendarStyle: const CalendarStyle(
              markerDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              holidayTextStyle: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
              holidayDecoration: BoxDecoration(
                color: Color(0x22FF0000),
                shape: BoxShape.circle,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final key = dateKey(day);
                final isHoliday = _holidays.containsKey(key);
                if (!isHoliday) return null;

                return Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(0.12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selected Date: $_selectedKey',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          if (_selectedHolidayName != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.celebration,
                                      color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Holiday: $_selectedHolidayName',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _noteController,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Note',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _isRecording ? null : _startRecording,
                                icon: const Icon(Icons.mic),
                                label: const Text('Record'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _isRecording ? _stopRecording : null,
                                icon: const Icon(Icons.stop),
                                label: const Text('Stop'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed:
                                hasAudio && !_isPlaying ? _playAudio : null,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _isPlaying ? _stopAudio : null,
                                icon: const Icon(Icons.pause),
                                label: const Text('Stop Play'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: hasAudio ? _deleteAudio : null,
                                icon: const Icon(Icons.delete),
                                label: const Text('Delete Voice'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _saveCurrentNote,
                                  icon: const Icon(Icons.save),
                                  label: const Text('Save Entry'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isRecording
                                ? 'Recording...'
                                : hasAudio
                                ? 'Voice note attached'
                                : 'No voice note yet',
                            style: TextStyle(
                              color: _isRecording ? Colors.red : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Saved Dates',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_entries.isEmpty)
                            const Text('No saved notes yet')
                          else
                            ...sortedEntries.map(
                                  (e) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  _holidays.containsKey(e.key)
                                      ? Icons.celebration
                                      : Icons.event_note,
                                  color: _holidays.containsKey(e.key)
                                      ? Colors.red
                                      : null,
                                ),
                                title: Text(e.key),
                                subtitle: Text(
                                  e.value.note.isEmpty
                                      ? '(Voice only)'
                                      : e.value.note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: e.value.audioPath != null
                                    ? const Icon(Icons.mic, size: 18)
                                    : null,
                                onTap: () {
                                  final parts = e.key.split('-');
                                  final dt = DateTime(
                                    int.parse(parts[0]),
                                    int.parse(parts[1]),
                                    int.parse(parts[2]),
                                  );
                                  setState(() {
                                    _selectedDay = dt;
                                    _focusedDay = dt;
                                    _currentRecordingPath = null;
                                    _noteController.text = e.value.note;
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}