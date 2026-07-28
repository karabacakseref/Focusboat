import 'package:flutter/material.dart';
import 'storage.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
  });

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

  Widget _buildStatusCard() {
    Color color;
    String text;
    if (widget.connecting) {
      color = Colors.orange;
      text = 'Bağlanıyor…';
    } else if (widget.connected) {
      color = Colors.green;
      text = 'Bağlı: ${widget.settings.host}:${widget.settings.port}';
    } else {
      color = Colors.red;
      text = widget.connectionError ?? 'Bağlı değil';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color.withOpacity(0.9)))),
          if (!widget.connected && !widget.connecting)
            TextButton(onPressed: widget.onReconnect, child: const Text('Yeniden bağlan')),
        ],
      ),
    );
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
            _buildStatusCard(),
            const SizedBox(height: 20),
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
