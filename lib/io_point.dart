enum PointCategory { input, output, analog }

/// Analog sinyaller okuma (gösterge) veya kontrol (slider ile ayar) olabilir.
enum AnalogMode { display, control }

class IOPoint {
  final PointCategory category;
  final int address; // Modbus adresi (kategori içinde 0'dan başlar)
  String label; // Kullanıcının kendi yazdığı isim (örn: "Sintine Pompası")
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
    this.analogMode = AnalogMode.display,
    this.analogMin = 0,
    this.analogMax = 100,
  });

  String get storageKey => '${category.name}_$address';

  factory IOPoint.defaultFor(PointCategory category, int address) {
    final prefix = switch (category) {
      PointCategory.input => 'Giriş',
      PointCategory.output => 'Çıkış',
      PointCategory.analog => 'Analog',
    };
    return IOPoint(
      category: category,
      address: address,
      label: '$prefix ${address + 1}',
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
