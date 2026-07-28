import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'io_point.dart';

class AppSettings {
  String host;
  int port;
  int unitId;
  double fuelTankLiters; // Depo kapasitesi (litre)
  double fuelConsumptionPer100Km; // Ortalama tüketim (L/100km)

  AppSettings({
    this.host = '192.168.1.101',
    this.port = 502,
    this.unitId = 1,
    this.fuelTankLiters = 0,
    this.fuelConsumptionPer100Km = 0,
  });
}

class Storage {
  static const _kHost = 'plc_host';
  static const _kPort = 'plc_port';
  static const _kUnitId = 'plc_unit_id';
  static const _kFuelTank = 'fuel_tank_liters';
  static const _kFuelConsumption = 'fuel_consumption_per_100km';
  static const _kPointsPrefix = 'point_';

  static Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      host: prefs.getString(_kHost) ?? '192.168.1.101',
      port: prefs.getInt(_kPort) ?? 502,
      unitId: prefs.getInt(_kUnitId) ?? 1,
      fuelTankLiters: prefs.getDouble(_kFuelTank) ?? 0,
      fuelConsumptionPer100Km: prefs.getDouble(_kFuelConsumption) ?? 0,
    );
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, settings.host);
    await prefs.setInt(_kPort, settings.port);
    await prefs.setInt(_kUnitId, settings.unitId);
    await prefs.setDouble(_kFuelTank, settings.fuelTankLiters);
    await prefs.setDouble(_kFuelConsumption, settings.fuelConsumptionPer100Km);
  }

  static Future<void> loadPointOverrides(List<IOPoint> points) async {
    final prefs = await SharedPreferences.getInstance();
    for (final point in points) {
      final raw = prefs.getString('$_kPointsPrefix${point.storageKey}');
      if (raw != null) {
        try {
          point.applyJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          // bozuk veri varsa yoksay, varsayılan etiket kalır
        }
      }
    }
  }

  static Future<void> savePoint(IOPoint point) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_kPointsPrefix${point.storageKey}',
      jsonEncode(point.toJson()),
    );
  }
}
