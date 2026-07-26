import 'dart:async';
import 'package:flutter/material.dart';
import 'io_point.dart';
import 'modbus_client.dart';
import 'storage.dart';
import 'edit_point_dialog.dart';
import 'settings_screen.dart';

void main() {
  runApp(const FocusBoatApp());
}

class FocusBoatApp extends StatelessWidget {
  const FocusBoatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Boat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0B5D8C),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ---- Sabit adres planı (14 giriş, 10 çıkış, 6 analog) ----
const int kInputCount = 14;
const int kOutputCount = 10;
const int kAnalogCount = 6;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  AppSettings _settings = AppSettings();
  ModbusTcpClient? _client;
  bool _connecting = false;
  String? _connectionError;

  bool _editMode = false;
  Timer? _pollTimer;
  bool _pollInFlight = false;

  final List<IOPoint> _inputs = List.generate(
      kInputCount, (i) => IOPoint.defaultFor(PointCategory.input, i));
  final List<IOPoint> _outputs = List.generate(
      kOutputCount, (i) => IOPoint.defaultFor(PointCategory.output, i));
  final List<IOPoint> _analogs = List.generate(
      kAnalogCount, (i) => IOPoint.defaultFor(PointCategory.analog, i));

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _settings = await Storage.loadSettings();
    await Storage.loadPointOverrides(_inputs);
    await Storage.loadPointOverrides(_outputs);
    await Storage.loadPointOverrides(_analogs);
    if (mounted) setState(() {});
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
    final client = ModbusTcpClient(
      host: _settings.host,
      port: _settings.port,
      unitId: _settings.unitId,
    );
    try {
      await client.connect();
      _client = client;
      _startPolling();
    } catch (e) {
      _connectionError = 'Bağlanamadı: $e';
      _client = null;
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => _poll());
  }

  Future<void> _poll() async {
    final client = _client;
    if (client == null || !client.isConnected || _pollInFlight) return;
    _pollInFlight = true;
    try {
      final inputVals = await client.readDiscreteInputs(0, kInputCount);
      final outputVals = await client.readCoils(0, kOutputCount);
      final analogVals = await client.readHoldingRegisters(0, kAnalogCount);
      for (int i = 0; i < kInputCount; i++) {
        _inputs[i].boolValue = inputVals[i];
      }
      for (int i = 0; i < kOutputCount; i++) {
        _outputs[i].boolValue = outputVals[i];
      }
      for (int i = 0; i < kAnalogCount; i++) {
        _analogs[i].analogValue = analogVals[i].toDouble();
      }
      if (mounted) setState(() {});
    } catch (e) {
      // Bağlantı koptuysa yeniden bağlanmayı dener
      _pollTimer?.cancel();
      _client = null;
      if (mounted) {
        setState(() => _connectionError = 'Bağlantı koptu: $e');
      }
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _connect();
      });
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _toggleOutput(IOPoint point) async {
    final client = _client;
    if (client == null) return;
    final newValue = !point.boolValue;
    setState(() => point.boolValue = newValue); // anında geri bildirim
    try {
      await client.writeSingleCoil(point.address, newValue);
    } catch (e) {
      setState(() => point.boolValue = !newValue); // hata varsa geri al
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazma hatası: $e')),
        );
      }
    }
  }

  Future<void> _writeAnalog(IOPoint point, double value) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.writeSingleRegister(point.address, value.round());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazma hatası: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client?.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _client?.isConnected ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Boat'),
        actions: [
          IconButton(
            tooltip: _editMode ? 'Düzenlemeyi bitir' : 'Etiketleri düzenle',
            icon: Icon(_editMode ? Icons.check : Icons.edit),
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
          IconButton(
            tooltip: 'Bağlantı ayarları',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(settings: _settings),
                ),
              );
              if (changed == true) {
                _pollTimer?.cancel();
                await _client?.disconnect();
                _connect();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Girişler'),
            Tab(text: 'Çıkışlar'),
            Tab(text: 'Analoglar'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildStatusBar(connected),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInputsTab(),
                _buildOutputsTab(),
                _buildAnalogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(bool connected) {
    Color color;
    String text;
    if (_connecting) {
      color = Colors.orange;
      text = '${_settings.host}:${_settings.port} — bağlanıyor…';
    } else if (connected) {
      color = Colors.green;
      text = '${_settings.host}:${_settings.port} — bağlı';
    } else {
      color = Colors.red;
      text = _connectionError ?? 'Bağlı değil';
    }
    return Container(
      width: double.infinity,
      color: color.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color.withOpacity(0.9))),
          ),
          if (!connected && !_connecting)
            TextButton(onPressed: _connect, child: const Text('Yeniden bağlan')),
        ],
      ),
    );
  }

  Widget _buildInputsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _inputs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final point = _inputs[i];
        return Card(
          child: ListTile(
            leading: Icon(
              point.boolValue ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: point.boolValue ? Colors.green : Colors.grey,
            ),
            title: Text(point.label),
            subtitle: Text('Adres: ${point.address}  •  Salt okunur giriş'),
            trailing: _editMode ? const Icon(Icons.edit, size: 18) : null,
            onTap: _editMode
                ? () => showEditPointDialog(context, point, onSaved: () => setState(() {}))
                : null,
          ),
        );
      },
    );
  }

  Widget _buildOutputsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _outputs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final point = _outputs[i];
        return Card(
          child: ListTile(
            title: Text(point.label),
            subtitle: Text('Adres: ${point.address}  •  Çıkış (aç/kapa)'),
            trailing: Switch(
              value: point.boolValue,
              onChanged: (_client?.isConnected ?? false)
                  ? (_) => _toggleOutput(point)
                  : null,
            ),
            onTap: _editMode
                ? () => showEditPointDialog(context, point, onSaved: () => setState(() {}))
                : null,
            leading: _editMode ? const Icon(Icons.edit, size: 18) : null,
          ),
        );
      },
    );
  }

  Widget _buildAnalogsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _analogs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final point = _analogs[i];
        final isControl = point.analogMode == AnalogMode.control;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(point.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (_editMode)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => showEditPointDialog(context, point,
                            onSaved: () => setState(() {})),
                      ),
                  ],
                ),
                Text(
                  'Adres: ${point.address}  •  '
                  '${isControl ? "Kontrol (kaydırıcı)" : "Gösterge (salt okunur)"}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                if (isControl)
                  Row(
                    children: [
                      Text(point.analogMin.toStringAsFixed(0)),
                      Expanded(
                        child: Slider(
                          value: point.analogValue.clamp(point.analogMin, point.analogMax),
                          min: point.analogMin,
                          max: point.analogMax,
                          onChanged: (v) => setState(() => point.analogValue = v),
                          onChangeEnd: (v) => _writeAnalog(point, v),
                        ),
                      ),
                      Text(point.analogMax.toStringAsFixed(0)),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      point.analogValue.toStringAsFixed(0),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
