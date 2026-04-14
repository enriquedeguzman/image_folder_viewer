import 'package:flutter/material.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  String _input = '0';
  String _output = '0';
  double _firstValue = 0;
  String _operator = '';
  bool _shouldResetInput = false;

  void _press(String value) {
    setState(() {
      if (value == 'C') {
        _input = '0';
        _output = '0';
        _firstValue = 0;
        _operator = '';
        _shouldResetInput = false;
        return;
      }

      if (value == '⌫') {
        if (_shouldResetInput) {
          _input = '0';
          _output = '0';
          _shouldResetInput = false;
          return;
        }

        if (_input.length > 1) {
          _input = _input.substring(0, _input.length - 1);
        } else {
          _input = '0';
        }
        _output = _input;
        return;
      }

      if (value == '+' || value == '-' || value == '×' || value == '÷') {
        _firstValue = double.tryParse(_input) ?? 0;
        _operator = value;
        _shouldResetInput = true;
        _output = _formatNumber(_firstValue);
        return;
      }

      if (value == '=') {
        final secondValue = double.tryParse(_input) ?? 0;
        double result = _firstValue;

        switch (_operator) {
          case '+':
            result = _firstValue + secondValue;
            break;
          case '-':
            result = _firstValue - secondValue;
            break;
          case '×':
            result = _firstValue * secondValue;
            break;
          case '÷':
            result = secondValue == 0 ? 0 : _firstValue / secondValue;
            break;
        }

        _input = _formatNumber(result);
        _output = _input;
        _operator = '';
        _shouldResetInput = true;
        return;
      }

      if (value == '.') {
        if (_shouldResetInput) {
          _input = '0.';
          _shouldResetInput = false;
          _output = _input;
          return;
        }
        if (!_input.contains('.')) {
          _input += '.';
        }
        _output = _input;
        return;
      }

      if (_shouldResetInput) {
        _input = value;
        _shouldResetInput = false;
      } else {
        _input = _input == '0' ? value : _input + value;
      }

      _output = _input;
    });
  }

  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  Widget _calcButton(
      String text, {
        required Color textColor,
        required Color borderColor,
        required Color fillColor,
        required double height,
        double fontSize = 24,
      }) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: fillColor,
            foregroundColor: textColor,
            elevation: 0,
            shadowColor: Colors.black.withOpacity(0.05),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: borderColor, width: 1.1),
            ),
          ),
          onPressed: () => _press(text),
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg1 = Color(0xFFF8FAFC);
    const bg2 = Color(0xFFEFF6FF);

    const numFill = Color(0xFFFFFFFF);
    const numBorder = Color(0xFFDCE7F3);

    const opFill = Color(0xFFEAF3FF);
    const opBorder = Color(0xFFD4E5FF);

    const equalFill = Color(0xFFA5C8FF);
    const equalBorder = Color(0xFF8BB7FF);

    const clearFill = Color(0xFFFFF3F2);
    const clearBorder = Color(0xFFF7D1CC);

    const backFill = Color(0xFFFFF8E8);
    const backBorder = Color(0xFFF4DE9A);

    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 600;
    final panelWidth = isTablet ? 620.0 : double.infinity;
    final buttonHeight = isTablet ? 78.0 : 60.0;
    final displayFont = isTablet ? 60.0 : 42.0;
    final smallDisplayFont = isTablet ? 24.0 : 18.0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        centerTitle: true,
        title: const Text('Calculator'),
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [bg1, bg2],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: panelWidth),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        minHeight: isTablet ? 160 : 110,
                      ),
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 24 : 16,
                        isTablet ? 24 : 16,
                        isTablet ? 24 : 16,
                        isTablet ? 24 : 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.82),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFDCE7F3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _operator.isEmpty
                                ? ''
                                : '${_formatNumber(_firstValue)} $_operator',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: smallDisplayFont,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              _output,
                              style: TextStyle(
                                fontSize: displayFont,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _calcButton(
                            'C',
                            textColor: const Color(0xFFE76F51),
                            borderColor: clearBorder,
                            fillColor: clearFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '⌫',
                            textColor: const Color(0xFFB88900),
                            borderColor: backBorder,
                            fillColor: backFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '÷',
                            textColor: const Color(0xFF3B82F6),
                            borderColor: opBorder,
                            fillColor: opFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '×',
                            textColor: const Color(0xFF3B82F6),
                            borderColor: opBorder,
                            fillColor: opFill,
                            height: buttonHeight,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _calcButton(
                            '7',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '8',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '9',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '-',
                            textColor: const Color(0xFF3B82F6),
                            borderColor: opBorder,
                            fillColor: opFill,
                            height: buttonHeight,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _calcButton(
                            '4',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '5',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '6',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '+',
                            textColor: const Color(0xFF3B82F6),
                            borderColor: opBorder,
                            fillColor: opFill,
                            height: buttonHeight,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _calcButton(
                            '1',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '2',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '3',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '=',
                            textColor: Colors.white,
                            borderColor: equalBorder,
                            fillColor: equalFill,
                            height: buttonHeight,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _calcButton(
                            '0',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '00',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                            fontSize: 20,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '.',
                            textColor: const Color(0xFF334155),
                            borderColor: numBorder,
                            fillColor: numFill,
                            height: buttonHeight,
                          ),
                        ),
                        Expanded(
                          child: _calcButton(
                            '⌫',
                            textColor: const Color(0xFFB88900),
                            borderColor: backBorder,
                            fillColor: backFill,
                            height: buttonHeight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
