import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DifficultyLevel {
  easy,
  medium,
  hard,
}

extension DifficultyLevelX on DifficultyLevel {
  String get label {
    switch (this) {
      case DifficultyLevel.easy:
        return 'Easy';
      case DifficultyLevel.medium:
        return 'Medium';
      case DifficultyLevel.hard:
        return 'Hard';
    }
  }

  int get pairCount {
    switch (this) {
      case DifficultyLevel.easy:
        return 6;
      case DifficultyLevel.medium:
        return 8;
      case DifficultyLevel.hard:
        return 10;
    }
  }

  int get crossAxisCount {
    switch (this) {
      case DifficultyLevel.easy:
        return 3;
      case DifficultyLevel.medium:
        return 4;
      case DifficultyLevel.hard:
        return 4;
    }
  }

  String get bestScoreKey {
    switch (this) {
      case DifficultyLevel.easy:
        return 'memory_best_easy';
      case DifficultyLevel.medium:
        return 'memory_best_medium';
      case DifficultyLevel.hard:
        return 'memory_best_hard';
    }
  }
}

class MemoryCardModel {
  final int pairId;
  final String symbol;
  bool isFaceUp;
  bool isMatched;

  MemoryCardModel({
    required this.pairId,
    required this.symbol,
    this.isFaceUp = false,
    this.isMatched = false,
  });
}

class MemoryGamePage extends StatefulWidget {
  const MemoryGamePage({super.key});

  @override
  State<MemoryGamePage> createState() => _MemoryGamePageState();
}

class _MemoryGamePageState extends State<MemoryGamePage> {
  static const Color _blue = Color(0xFF2F6FD6);
  static const Color _blueSoft = Color(0xFFDCEBFF);
  static const Color _gold = Color(0xFFD4A017);
  static const Color _goldSoft = Color(0xFFFFF4CC);

  final List<String> _symbols = const [
    '💊',
    '💉',
    '🩺',
    '🌡️',
    '🧪',
    '🔬',
    '🏥',
    '🧬',
    '🫀',
    '🩹',
  ];

  DifficultyLevel _difficulty = DifficultyLevel.easy;
  List<MemoryCardModel> _cards = [];

  int _moves = 0;
  int _matches = 0;
  int _seconds = 0;
  int _score = 0;
  int _bestScore = 0;

  int? _first;
  int? _second;

  bool _busy = false;
  Timer? _timer;

  late ConfettiController _confettiMatch;
  late ConfettiController _confettiWin;

  @override
  void initState() {
    super.initState();

    _confettiMatch = ConfettiController(
      duration: const Duration(milliseconds: 600),
    );
    _confettiWin = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    _loadBestScore().then((_) {
      _startGame();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confettiMatch.dispose();
    _confettiWin.dispose();
    super.dispose();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _bestScore = prefs.getInt(_difficulty.bestScoreKey) ?? 0;
    });
  }

  Future<void> _saveBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_difficulty.bestScoreKey, _score);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _seconds++;
        _score = _calculateScore();
      });
    });
  }

  void _startGame() {
    _timer?.cancel();

    final random = Random();
    final chosen = _symbols.take(_difficulty.pairCount).toList();

    final cards = <MemoryCardModel>[];
    for (int i = 0; i < chosen.length; i++) {
      cards.add(MemoryCardModel(pairId: i, symbol: chosen[i]));
      cards.add(MemoryCardModel(pairId: i, symbol: chosen[i]));
    }

    cards.shuffle(random);

    setState(() {
      _cards = cards;
      _moves = 0;
      _matches = 0;
      _seconds = 0;
      _score = 0;
      _first = null;
      _second = null;
      _busy = false;
    });
  }

  int _calculateScore() {
    final base = _matches * 100;
    final movePenalty = _moves * 5;
    final timePenalty = _seconds * 2;
    return max(0, base + 400 - movePenalty - timePenalty);
  }

  Future<void> _tapCard(int index) async {
    if (_busy) return;
    if (index < 0 || index >= _cards.length) return;

    final card = _cards[index];
    if (card.isMatched || card.isFaceUp) return;

    if (_moves == 0 && _seconds == 0 && _first == null) {
      _startTimer();
    }

    setState(() {
      card.isFaceUp = true;
    });

    if (_first == null) {
      _first = index;
      return;
    }

    _second = index;
    _moves++;

    final firstCard = _cards[_first!];
    final secondCard = _cards[_second!];

    if (firstCard.pairId == secondCard.pairId) {
      _confettiMatch.play();

      setState(() {
        firstCard.isMatched = true;
        secondCard.isMatched = true;
        _matches++;
        _score = _calculateScore();
      });

      _first = null;
      _second = null;

      if (_matches == _difficulty.pairCount) {
        _timer?.cancel();
        _score = _calculateScore();

        if (_score > _bestScore) {
          _bestScore = _score;
          await _saveBestScore();
        }

        _confettiWin.play();

        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          _showWinDialog();
        });
      }
    } else {
      _busy = true;

      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      setState(() {
        firstCard.isFaceUp = false;
        secondCard.isFaceUp = false;
      });

      _first = null;
      _second = null;
      _busy = false;

      setState(() {
        _score = _calculateScore();
      });
    }
  }

  void _showWinDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'You Win 🎉',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _blue,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Moves', '$_moves'),
            _row('Time', '$_seconds sec'),
            _row('Score', '$_score'),
            _row('Best Score', '$_bestScore'),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _startGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  Widget _row(String a, String b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              a,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            b,
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            color: _blue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _difficultyChip(DifficultyLevel d) {
    final selected = _difficulty == d;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(d.label),
        selected: selected,
        selectedColor: _blueSoft,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? _blue : _gold.withOpacity(0.45),
        ),
        labelStyle: TextStyle(
          color: selected ? _blue : const Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
        onSelected: (_) async {
          setState(() {
            _difficulty = d;
          });
          await _loadBestScore();
          _startGame();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double progress =
    _difficulty.pairCount == 0 ? 0.0 : _matches / _difficulty.pairCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Game'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _gold),
            onPressed: _startGame,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF7FAFF),
              Color(0xFFFFFBF2),
              Color(0xFFF9FBFF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _blueSoft),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _info('Moves', '$_moves')),
                          Expanded(child: _info('Time', '$_seconds')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _info('Score', '$_score')),
                          Expanded(child: _info('Best', '$_bestScore')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: progress,
                          backgroundColor: _blueSoft,
                          valueColor:
                          const AlwaysStoppedAnimation<Color>(_gold),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _difficultyChip(DifficultyLevel.easy),
                    _difficultyChip(DifficultyLevel.medium),
                    _difficultyChip(DifficultyLevel.hard),
                  ],
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _cards.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _difficulty.crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.95,
                    ),
                    itemBuilder: (context, i) {
                      final card = _cards[i];
                      final isOpen = card.isFaceUp || card.isMatched;

                      return GestureDetector(
                        onTap: () => _tapCard(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: card.isMatched
                                  ? const [
                                Color(0xFFFFF4CC),
                                Color(0xFFFFFBF2),
                              ]
                                  : isOpen
                                  ? const [
                                Color(0xFFF8FBFF),
                                Color(0xFFEAF4FF),
                              ]
                                  : const [
                                Color(0xFFE8F3FF),
                                Color(0xFFFFFBF2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: card.isMatched
                                  ? _gold
                                  : _gold.withOpacity(0.25),
                              width: card.isMatched ? 1.6 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: card.isFaceUp || card.isMatched
                                ? Text(
                              card.symbol,
                              style: const TextStyle(fontSize: 40),
                            )
                                : const Icon(
                              Icons.psychology,
                              color: _blue,
                              size: 34,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                child: ConfettiWidget(
                  confettiController: _confettiMatch,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  numberOfParticles: 15,
                  colors: const [
                    _blue,
                    _gold,
                    Color(0xFFDCEBFF),
                    Color(0xFFFFF4CC),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                child: ConfettiWidget(
                  confettiController: _confettiWin,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  numberOfParticles: 25,
                  colors: const [
                    _blue,
                    _gold,
                    Color(0xFFDCEBFF),
                    Color(0xFFFFF4CC),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}