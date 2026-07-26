import 'package:flutter/material.dart';
import 'storage.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _unitCtrl;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.settings.host);
    _portCtrl = TextEditingController(text: widget.settings.port.toString());
    _unitCtrl = TextEditingController(text: widget.settings.unitId.toString());
  }

  Future<void> _save() async {
    widget.settings.host = _hostCtrl.text.trim();
    widget.settings.port = int.tryParse(_portCtrl.text.trim()) ?? 502;
    widget.settings.unitId = int.tryParse(_unitCtrl.text.trim()) ?? 1;
    await Storage.saveSettings(widget.settings);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PLC Bağlantı Ayarları')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'PLC IP Adresi',
                hintText: 'Örn: 192.168.1.101',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(labelText: 'Port (varsayılan 502)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit / Slave ID (varsayılan 1)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Kaydet ve Bağlan'),
            ),
          ],
        ),
      ),
    );
  }
}
