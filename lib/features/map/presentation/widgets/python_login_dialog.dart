import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class PythonLoginDialog extends StatefulWidget {
  final Function(Map<String, dynamic> data) onLoginSuccess;

  const PythonLoginDialog({super.key, required this.onLoginSuccess});

  @override
  State<PythonLoginDialog> createState() => _PythonLoginDialogState();
}

class _PythonLoginDialogState extends State<PythonLoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _jsonController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isLoading = false;
  bool _showManualInput = true;
  String _log = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _jsonController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _runPythonScript() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _log = 'Error: Username dan Password harus diisi.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _log =
          'Menjalankan script python...\nMohon tunggu browser terbuka (jika headless=False)...';
    });

    try {
      // Path script absolut sesuai environment user
      const scriptPath = '/Users/nasrul/flutter/direktori/lib/login.py';

      final args = [
        scriptPath,
        _usernameController.text,
        _passwordController.text,
      ];

      if (_otpController.text.isNotEmpty) {
        args.add(_otpController.text);
      }

      // Coba jalankan python3. Pastikan python3 ada di path atau gunakan full path jika perlu.
      // Di macOS, biasanya /usr/bin/python3 atau /opt/homebrew/bin/python3
      // Kita coba 'python3' dulu.
      final result = await Process.run(
        'python3',
        args,
        runInShell: true,
        workingDirectory: '/Users/nasrul/flutter/direktori', // Set working dir
      );

      if (result.exitCode != 0) {
        setState(() {
          _log =
              'Error (Exit Code ${result.exitCode}):\nStderr: ${result.stderr}\nStdout: ${result.stdout}';
        });
      } else {
        setState(() {
          _log = 'Script selesai. Mencoba parsing output...\n';
        });
        _parseOutput(result.stdout.toString());
      }
    } catch (e) {
      setState(() {
        _log =
            'Exception saat menjalankan script: $e\n\nTips: Pastikan python3 terinstall dan dapat diakses.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _parseOutput(String output) {
    try {
      final startMarker = '---JSON_START---';
      final endMarker = '---JSON_END---';

      final startIndex = output.indexOf(startMarker);
      final endIndex = output.indexOf(endMarker);

      if (startIndex != -1 && endIndex != -1) {
        final jsonStr = output
            .substring(startIndex + startMarker.length, endIndex)
            .trim();
        final data = jsonDecode(jsonStr);

        if (data['status'] == 'success') {
          widget.onLoginSuccess(data);
          if (mounted) Navigator.of(context).pop();
        } else {
          setState(() {
            _log += '\nStatus login tidak sukses: ${data['status']}';
          });
        }
      } else {
        setState(() {
          _log +=
              '\nTidak menemukan marker JSON di output. Coba jalankan manual dan paste hasilnya di tab "Manual JSON".\nOutput:\n$output';
        });
      }
    } catch (e) {
      setState(() {
        _log += '\nError parsing JSON: $e';
      });
    }
  }

  void _processManualJson() {
    String text = _jsonController.text.trim();
    if (text.isEmpty) return;

    // Jika user paste raw output termasuk marker, kita coba parse
    if (text.contains('---JSON_START---')) {
      _parseOutput(text);
      return;
    }

    // Jika user paste JSON murni
    try {
      final data = jsonDecode(text);
      widget.onLoginSuccess(data);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _log = 'Gagal parse JSON manual: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Login via Python Script'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Metode ini menjalankan script python untuk login dan mengambil cookies.',
              ),
              const SizedBox(height: 10),

              // Tabs-like toggle
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _showManualInput = false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_showManualInput
                            ? Colors.blue
                            : Colors.grey[300],
                        foregroundColor: !_showManualInput
                            ? Colors.white
                            : Colors.black,
                      ),
                      child: const Text('Auto Run'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _showManualInput = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showManualInput
                            ? Colors.blue
                            : Colors.grey[300],
                        foregroundColor: _showManualInput
                            ? Colors.white
                            : Colors.black,
                      ),
                      child: const Text('Manual JSON'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (!_showManualInput) ...[
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username (SSO)',
                  ),
                ),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                TextField(
                  controller: _otpController,
                  decoration: const InputDecoration(
                    labelText: 'OTP (Jika perlu, kosongkan jika tidak)',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _runPythonScript,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Jalankan Script'),
                  ),
                ),
              ] else ...[
                const Text(
                  'Jalankan perintah ini di terminal:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: const SelectableText(
                    'python3 lib/login.py <username> <password> [otp]',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Lalu paste output JSON di bawah:'),
                TextField(
                  controller: _jsonController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '{"status": "success", "cookie_header": ...}',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _processManualJson,
                    icon: const Icon(Icons.check),
                    label: const Text('Proses JSON'),
                  ),
                ),
              ],

              if (_log.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'Log:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  height: 100,
                  padding: const EdgeInsets.all(8),
                  color: Colors.black12,
                  child: SingleChildScrollView(
                    child: Text(
                      _log,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
