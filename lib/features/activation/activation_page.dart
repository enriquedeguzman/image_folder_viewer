import 'package:flutter/material.dart';
import '../../services/license_manager.dart';

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final TextEditingController _controller = TextEditingController();
  String _deviceCode = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceCode();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceCode() async {
    final code = await LicenseManager.getDeviceCode();
    if (!mounted) return;
    setState(() {
      _deviceCode = code;
    });
  }

  Future<void> _activate() async {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter activation key')),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    final ok = await LicenseManager.validateKey(value);

    if (!mounted) return;

    setState(() {
      _submitting = false;
    });

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activation successful')),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid activation key')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedFormat = _deviceCode.isEmpty
        ? '05141969e-DEVICECODE'
        : '05141969e-$_deviceCode';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activation Required'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD7DFEA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activate App',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This device needs an activation key to continue using the app.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8E6FA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Code',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _deviceCode.isEmpty ? 'Loading...' : _deviceCode,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFF2F6FD6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'Activation Key',
                    hintText: 'Enter activation key',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Expected format: $expectedFormat',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _activate,
                    child: _submitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Activate'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}