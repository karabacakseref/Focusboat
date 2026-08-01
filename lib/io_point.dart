import 'package:flutter/material.dart';

enum PointCategory { input, output, analog }

/// Analog sinyaller okuma (gösterge) veya kontrol (slider ile ayar) olabilir.
enum AnalogMode { display, control }

// Broşürdeki gerçek fonksiyon isimleri ve ikonları — varsayılan etiketler.
// Kullanıcı düzenleme modundan istediği gibi değiştirebilir.
const List<_DefaultMeta> _inputDefaults = [
  _DefaultMeta('Akü ve Batarya Takibi', Icons.battery_full),
  _DefaultMeta('Başlatma Aküsü', Icons.battery_charging_full),
  _DefaultMeta('Servis Aküsü', Icons.battery_std),
  _DefaultMeta('Sintine Yüksek Su Uyarısı', Icons.water),
  _DefaultMeta('Sıcaklık Takibi', Icons.thermostat),
  _DefaultMeta('Nem Takibi', Icons.opacity),
  _DefaultMeta('Duman Tespiti', Icons.smoke_free),
  _DefaultMeta('İzinsiz Giriş Tespiti', Icons.security),
  _DefaultMeta('Arıza (Fault)', Icons.warning_amber_rounded),
  _DefaultMeta('Haberleşme Durumu', Icons.wifi),
  _DefaultMeta('PLC Çalışıyor (Run)', Icons.memory),
  _DefaultMeta('Yakıt Seviye Uyarısı', Icons.local_gas_station),
  _DefaultMeta('Temiz Su Uyarısı', Icons.water_drop),
  _DefaultMeta('Kirli Su Uyarısı', Icons.invert_colors),
];

const List<_DefaultMeta> _outputDefaults = [
  _DefaultMeta('Sintine Pompası', Icons.water),
  _DefaultMeta('İskele Lambası', Icons.lightbulb),
  _DefaultMeta('Hidrofor Pompa', Icons.plumbing),
  _DefaultMeta('Irgat Motoru İleri', Icons.arrow_upward),
  _DefaultMeta('Irgat Motoru Geri', Icons.arrow_downward),
  _DefaultMeta('İç Aydınlatma', Icons.lightbulb_outline),
  _DefaultMeta('Buzdolabı', Icons.kitchen),
  _DefaultMeta('Fan', Icons.air),
  _DefaultMeta('Korna', Icons.campaign),
  _DefaultMeta('Çıkış 9', Icons.power),
  _DefaultMeta('Çıkış 10', Icons.power),
  _DefaultMeta('Priz 1', Icons.electrical_services),
  _DefaultMeta('Priz 2', Icons.electrical_services),
  _DefaultMeta('Priz 3', Icons.electrical_services),
];

const List<_DefaultMeta> _analogDefaults = [
  _DefaultMeta('Yakıt Seviyesi (%)', Icons.local_gas_station),
  _DefaultMeta('Su Deposu Seviyesi (%)', Icons.water_drop),
  _DefaultMeta('Batarya Voltajı (V)', Icons.bolt),
  _DefaultMeta('Motor Sıcaklığı (°C)', Icons.thermostat),
  _DefaultMeta('Güneş Paneli Üretimi', Icons.wb_sunny),
  _DefaultMeta('Rüzgar Hızı', Icons.air),
];

class _DefaultMeta {
  final String label;
  final IconData icon;
  const _DefaultMeta(this.label, this.icon);
}

class IOPoint {
  final PointCategory category;
  final int address; // Modbus adresi (kategori içinde 0'dan başlar)
  String label; // Kullanıcının kendi yazdığı isim (örn: "Sintine Pompası")
  final IconData icon; // Varsayılan fonksiyon ikonu
  AnalogMode analogMode; // sadece analog için anlamlı
  double analogMin;
  double analogMax;

  // Çalışma zamanı durumu (kalıcı değil, sadece anlık gösterim)
  bool boolValue = false;
  double analogValue = 0;

  IOPoint({
    required this.category,
    required this.address,
    required this.label,
    this.icon = Icons.sensors,
    this.analogMode = AnalogMode.display,
    this.analogMin = 0,
    this.analogMax = 100,
  });

  String get storageKey => '${category.name}_$address';

  factory IOPoint.defaultFor(PointCategory category, int address) {
    final list = switch (category) {
      PointCategory.input => _inputDefaults,
      PointCategory.output => _outputDefaults,
      PointCategory.analog => _analogDefaults,
    };
    if (address < list.length) {
      final meta = list[address];
      return IOPoint(
        category: category,
        address: address,
        label: meta.label,
        icon: meta.icon,
      );
    }
    // Liste dışında kalan adresler için genel isim + kategoriye uygun ikon
    final prefix = switch (category) {
      PointCategory.input => 'Giriş',
      PointCategory.output => 'Çıkış',
      PointCategory.analog => 'Analog',
    };
    final fallbackIcon = switch (category) {
      PointCategory.input => Icons.sensors,
      PointCategory.output => Icons.electrical_services,
      PointCategory.analog => Icons.speed,
    };
    return IOPoint(
      category: category,
      address: address,
      label: '$prefix ${address + 1}',
      icon: fallbackIcon,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'analogMode': analogMode.name,
        'analogMin': analogMin,
        'analogMax': analogMax,
      };

  void applyJson(Map<String, dynamic> json) {
    label = json['label'] as String? ?? label;
    final modeStr = json['analogMode'] as String?;
    if (modeStr != null) {
      analogMode = AnalogMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AnalogMode.display,
      );
    }
    analogMin = (json['analogMin'] as num?)?.toDouble() ?? analogMin;
    analogMax = (json['analogMax'] as num?)?.toDouble() ?? analogMax;
  }
}
