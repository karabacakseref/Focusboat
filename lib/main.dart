import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:torch_light/torch_light.dart';
import 'io_point.dart';
import 'modbus_client.dart';
import 'storage.dart';
import 'edit_point_dialog.dart';
import 'settings_screen.dart';

void main() {
  runApp(const FocusBoatApp());
}

// ---- Marka renkleri (eski Focus Boat logosundan) ----
const Color kNavy = Color(0xFF0B1F3D);
const Color kTurquoise = Color(0xFF17C3D9);
const Color kBackground = Color(0xFF0A1830);

// Renkli kart paleti (broşürdeki gibi her fonksiyon farklı renk)
const List<Color> kCardPalette = [
  Color(0xFFF2B807), // sarı
  Color(0xFF3D8B4C), // yeşil
  Color(0xFF2E7DD1), // mavi
  Color(0xFFD64545), // kırmızı
  Color(0xFF8E4FC9), // mor
  Color(0xFFE8873A), // turuncu
  Color(0xFF4A5568), // gri-lacivert
  Color(0xFF17A08A), // camgöbeği-yeşil
  kNavy,
  Color(0xFF6EC1E4), // açık mavi
];

Color paletteColor(int index) => kCardPalette[index % kCardPalette.length];

class FocusBoatApp extends StatelessWidget {
  const FocusBoatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Boat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNavy,
          primary: kNavy,
          secondary: kTurquoise,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: kNavy,
          elevation: 0,
          surfaceTintColor: Colors.white,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? kTurquoise : null),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? kTurquoise.withOpacity(0.5) : null),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: kNavy,
          unselectedLabelColor: Colors.grey,
          indicatorColor: kTurquoise,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ---- Sabit adres planı (14 giriş, 10 çıkış, 6 analog) ----
const int kInputCount = 14;
const int kOutputCount = 15;
const int kAnalogCount = 6;

// 40001 tabanlı (Modicon) register adresleme:
// 40001 = register 0. Girişler 40001'den, çıkışlar 40019'dan, analoglar 40050'den başlar.
const int kInputBase = 0; // 40001
const int kOutputBase = 20; // 40021
const int kAnalogBase = 49; // 40050

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
  Timer? _alarmTimer;
  bool _alarmMuted = false;
  final FlutterTts _tts = FlutterTts();
  bool _torchOn = false;

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
    _tts.setLanguage('tr-TR');
    _tts.setSpeechRate(0.45);
    _tts.setVolume(1.0);
    WakelockPlus.enable(); // teknede izlerken ekran kararmasın
    _alarmTimer = Timer.periodic(const Duration(seconds: 6), (_) => _checkAlarm());
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
      await _poll(); // bağlanır bağlanmaz PLC'deki anlık durumu hemen al
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

  List<IOPoint> get _activeAlarms => _inputs.where((p) => p.boolValue).toList();

  void _checkAlarm() async {
    if (_alarmMuted) return;
    final alarms = _activeAlarms;
    if (alarms.isEmpty) return;
    HapticFeedback.vibrate();
    final text = alarms.length == 1
        ? 'Uyarı, ${alarms.first.label}'
        : '${alarms.length} uyarı aktif. ${alarms.map((p) => p.label).join(", ")}';
    await _tts.stop();
    await _tts.speak(text);
  }

  // ---- Test amaçlı manuel alarm tetikleme (Ayarlar ekranından) ----
  void _triggerTestAlarm(IOPoint point) {
    setState(() {
      point.boolValue = true;
      _alarmMuted = false;
    });
    _checkAlarm();
  }

  void _muteAlarmFromSettings() {
    setState(() => _alarmMuted = true);
    _tts.stop();
  }

  void _clearTestAlarms() {
    setState(() {
      for (final p in _inputs) {
        p.boolValue = false;
      }
    });
  }

  Future<void> _poll() async {
    final client = _client;
    if (client == null || !client.isConnected || _pollInFlight) return;
    _pollInFlight = true;
    try {
      // Hepsi Holding Register (40001 tabanlı, FC03) üzerinden okunuyor.
      final inputRegs = await client.readHoldingRegisters(kInputBase, kInputCount);
      final outputRegs = await client.readHoldingRegisters(kOutputBase, kOutputCount);
      final analogRegs = await client.readHoldingRegisters(kAnalogBase, kAnalogCount);
      for (int i = 0; i < kInputCount; i++) {
        _inputs[i].boolValue = inputRegs[i] == 1;
      }
      for (int i = 0; i < kOutputCount; i++) {
        _outputs[i].boolValue = outputRegs[i] == 1;
      }
      for (int i = 0; i < kAnalogCount; i++) {
        _analogs[i].analogValue = analogRegs[i].toDouble();
      }
      if (_activeAlarms.isEmpty) _alarmMuted = false;
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
      await client.writeSingleRegister(kOutputBase + point.address, newValue ? 1 : 0);
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
      await client.writeSingleRegister(kAnalogBase + point.address, value.round());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazma hatası: $e')),
        );
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      if (_torchOn) {
        await TorchLight.disableTorch();
      } else {
        await TorchLight.enableTorch();
      }
      setState(() => _torchOn = !_torchOn);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu cihazda el feneri kullanılamıyor')),
        );
      }
    }
  }

  Future<void> _speakFuelRange() async {
    final tankLiters = _settings.fuelTankLiters;
    final consumption = _settings.fuelConsumptionPer100Km;
    if (tankLiters <= 0 || consumption <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Önce Ayarlar\'dan depo kapasitesini ve ortalama tüketimi gir',
            ),
          ),
        );
      }
      return;
    }
    final fuelPercent = _analogs.first.analogValue.clamp(0, 100);
    final liters = fuelPercent / 100 * tankLiters;
    final rangeKm = liters * 100 / consumption;
    final text = 'Depoda yaklaşık ${liters.toStringAsFixed(0)} litre yakıt var. '
        'Yaklaşık ${rangeKm.toStringAsFixed(0)} kilometre menzil kalmıştır.';
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _alarmTimer?.cancel();
    _tts.stop();
    WakelockPlus.disable();
    _client?.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _client?.isConnected ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      drawer: _buildDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        centerTitle: true,
        title: Image.asset('assets/logo_banner.png', height: 48),
        toolbarHeight: 64,
        actions: [
          IconButton(
            tooltip: 'Bildirimler',
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Şu an yeni bildirim yok')),
              );
            },
          ),
          IconButton(
            tooltip: _editMode ? 'Düzenlemeyi bitir' : 'Etiketleri düzenle',
            icon: Icon(_editMode ? Icons.check : Icons.edit),
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
          IconButton(
            tooltip: 'Bağlantı ayarları',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.settings_ethernet),
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connecting
                          ? Colors.orange
                          : (connected ? Colors.green : Colors.red),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    settings: _settings,
                    connected: connected,
                    connecting: _connecting,
                    connectionError: _connectionError,
                    onReconnect: _connect,
                    testInputs: _inputs,
                    onTriggerTestAlarm: _triggerTestAlarm,
                    onMuteAlarm: _muteAlarmFromSettings,
                    onClearTestAlarms: _clearTestAlarms,
                  ),
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
      ),
      body: Column(
        children: [
          _buildBrandBanner(),
          _buildAlarmBanner(),
          _buildSegmentBar(),
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

  Widget _buildAlarmBanner() {
    final alarms = _activeAlarms;
    if (alarms.isEmpty) return const SizedBox.shrink();
    final text = alarms.length == 1
        ? alarms.first.label
        : '${alarms.length} aktif uyarı: ${alarms.map((p) => p.label).join(", ")}';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: _alarmMuted ? 'Sesi aç' : 'Sustur',
            icon: Icon(_alarmMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
            onPressed: () {
              setState(() => _alarmMuted = !_alarmMuted);
              if (_alarmMuted) _tts.stop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBrandBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [kNavy, Color(0xFF17547A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kTurquoise.withOpacity(0.35), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tekneniz Her An Kontrolünüzde',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 19,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentBar() {
    final tabs = [
      ('Girişler', Icons.sensors),
      ('Çıkışlar', Icons.power_settings_new),
      ('Analoglar', Icons.speed),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: List.generate(tabs.length, (i) {
                final selected = _tabController.index == i;
                final (label, icon) = tabs[i];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tabController.animateTo(i)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? kNavy : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Column(
                        children: [
                          Icon(icon, size: 18, color: selected ? kTurquoise : Colors.grey),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: kNavy,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/logo_icon.png', height: 48, width: 48),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'FOCUS BOAT\nKontrol Sistemleri',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_ethernet, color: kNavy),
              title: const Text('Bağlantı Ayarları'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      settings: _settings,
                      connected: _client?.isConnected ?? false,
                      connecting: _connecting,
                      connectionError: _connectionError,
                      onReconnect: _connect,
                      testInputs: _inputs,
                      onTriggerTestAlarm: _triggerTestAlarm,
                      onMuteAlarm: _muteAlarmFromSettings,
                      onClearTestAlarms: _clearTestAlarms,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(_editMode ? Icons.check : Icons.edit, color: kNavy),
              title: Text(_editMode ? 'Düzenlemeyi bitir' : 'Etiketleri düzenle'),
              onTap: () {
                setState(() => _editMode = !_editMode);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: Icon(
                _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                color: _torchOn ? Colors.amber.shade700 : kNavy,
              ),
              title: Text(_torchOn ? 'El Fenerini Kapat' : 'El Fenerini Aç (Acil Sinyal)'),
              onTap: () {
                _toggleTorch();
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'FocusBoat, teknenizi akıllı sistemlerle donatarak her an tam '
                'kontrol ve güvenlik sağlar.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: _inputs.length,
      itemBuilder: (context, i) {
        final point = _inputs[i];
        return _IoCard(
          color: paletteColor(i),
          icon: point.icon,
          label: point.label,
          active: point.boolValue,
          showEditBadge: _editMode,
          onTap: _editMode
              ? () => showEditPointDialog(context, point, onSaved: () => setState(() {}))
              : null,
        );
      },
    );
  }

  Widget _buildOutputsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: _outputs.length,
      itemBuilder: (context, i) {
        final point = _outputs[i];
        final canToggle = _client?.isConnected ?? false;
        return _IoCard(
          color: paletteColor(i + 3),
          icon: point.icon,
          label: point.label,
          active: point.boolValue,
          showEditBadge: _editMode,
          onTap: _editMode
              ? () => showEditPointDialog(context, point, onSaved: () => setState(() {}))
              : (canToggle ? () => _toggleOutput(point) : null),
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
        final color = paletteColor(i + 6);
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withOpacity(0.35), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: Icon(
                        point.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(point.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (i == 0)
                      IconButton(
                        tooltip: 'Menzili sesli hesapla',
                        icon: const Icon(Icons.record_voice_over, size: 20, color: kNavy),
                        onPressed: _speakFuelRange,
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
                  'Adres: ${point.address}  •  Gösterge (salt okunur)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
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

/// Broşürdeki renkli kart tasarımına benzeyen giriş/çıkış kartı.
class _IoCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool active;
  final bool showEditBadge;
  final VoidCallback? onTap;

  const _IoCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.active,
    required this.showEditBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Varsayılan: beyaz zemin + renkli ikon/çerçeve.
    // Aktif (çıkış açık / giriş tetiklenmiş): renkli zemin + beyaz ikon.
    final fillColor = active ? color : Colors.white;
    final contentColor = active ? Colors.white : color;
    return Material(
      color: fillColor,
      borderRadius: BorderRadius.circular(18),
      elevation: active ? 5 : 2,
      shadowColor: color.withOpacity(0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? Colors.transparent : color.withOpacity(0.45),
              width: 2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, color: contentColor, size: 32),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32, // 2 satırlık sabit alan: kısa/uzun etiketlerde ikon hep aynı hizada kalsın
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: contentColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(Icons.check_circle, size: 18, color: contentColor),
                ),
              if (showEditBadge)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Icon(Icons.edit, size: 14, color: contentColor.withOpacity(0.8)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
