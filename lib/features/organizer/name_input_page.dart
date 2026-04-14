import 'package:flutter/material.dart';

class NameInputPage extends StatefulWidget {
  final String title;
  final String hintText;
  final String actionLabel;
  final String initialValue;
  final String? Function(String value)? validator;

  const NameInputPage({
    super.key,
    required this.title,
    required this.hintText,
    required this.actionLabel,
    this.initialValue = '',
    this.validator,
  });

  @override
  State<NameInputPage> createState() => _NameInputPageState();
}

class _NameInputPageState extends State<NameInputPage> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);

    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: widget.hintText,
                errorText: _errorText,
              ),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}