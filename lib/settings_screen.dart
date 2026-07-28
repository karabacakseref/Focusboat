import 'package:flutter/material.dart';
import 'storage.dart';
import 'io_point.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final bool connected;
  final bool connecting;
  final String? connectionError;
  final VoidCallback onReconnect;
  final List<IOPoint> testInputs;
  final void Function(IOPoint) onTriggerTestAlarm;
  final VoidCallback onMuteAlarm;
  final VoidCallback onClearTestAlarms;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.connected,
    required this.connecting,
    required this.connectionError,
    required this.onReconnect,
    required this.testInputs,
    required this.onTriggerTestAlarm,
    required this.onMuteAlarm,
    required this.onClearTestAlarms,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _unitCtrl;
  IOPoint? _selectedTestPoint;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.settings.host);
    _portCtrl = TextEditingController(text: widget.settings.port.toString());
    _unitCtrl = TextEditingController(text: widget.settings.unitId.toString());
    if (widget.testInputs.isNotEmpty) {
      _selectedTestPoint = widget.testInputs.first;
    }
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

  Widget _buildAlarmTestCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bug_report, color: Colors.orange),
              SizedBox(width: 8),
              Text('Alarm Testi', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'PLC bağlı olmadan sesli/titreşimli alarmı test edebilirsin.',
            style: TextStyle(color: Colors.grey, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<IOPoint>(
            value: _selectedTestPoint,
            decoration: const InputDecoration(
              labelText: 'Test edilecek uyarı',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: widget.testInputs
                .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                .toList(),
            onChanged: (v) => setState(() => _selectedTestPoint = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.campaign),
                  label: const Text('Alarm Ver'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                  onPressed: _selectedTestPoint == null
                      ? null
                      : () => widget.onTriggerTestAlarm(_selectedTestPoint!),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.volume_off),
                  label: const Text('Sustur'),
                  onPressed: widget.onMuteAlarm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Testi Sıfırla'),
              onPressed: widget.onClearTestAlarms,
            ),
          ),
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
        child: ListView(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildAlarmTestCard(),
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
