# Focus Boat — Flutter Modbus TCP Uygulaması

Android ve iOS'ta çalışan, doğrudan Modbus TCP ile FX3U PLC'ye bağlanan
native uygulama. Aradaki köprü cihazı yok — sadece **PLC + WiFi router**.

## İçerik

- `lib/modbus_client.dart` — Harici kütüphane kullanmadan `dart:io` Socket
  üzerinden yazılmış Modbus TCP istemcisi (Read Coils, Read Discrete Inputs,
  Read Holding Registers, Write Single Coil, Write Single Register).
- `lib/io_point.dart` — Giriş/Çıkış/Analog veri modeli.
- `lib/storage.dart` — Etiketleri ve bağlantı ayarlarını telefonda kalıcı
  saklama (`shared_preferences`, internet gerekmez).
- `lib/edit_point_dialog.dart` — Etiket düzenleme ve analog mod (gösterge/
  kontrol) seçim ekranı.
- `lib/settings_screen.dart` — PLC IP / Port / Unit ID ayar ekranı.
- `lib/main.dart` — Ana uygulama: 3 sekme (Girişler / Çıkışlar / Analoglar),
  canlı okuma (900ms'de bir), düzenleme modu.

## Kurulum (senin bilgisayarında)

1. Flutter SDK kurulu olmalı: https://docs.flutter.dev/get-started/install
2. Yeni bir proje oluştur ve bu dosyalarla birleştir:

```bash
flutter create focus_boat
cd focus_boat
# Bu paketten gelen pubspec.yaml ve lib/ klasörünü,
# yeni oluşan projenin üzerine kopyala (üzerine yaz)
flutter pub get
```

3. Telefonunu USB ile bağla veya emülatör aç:

```bash
flutter run
```

4. APK üretmek için (Android):

```bash
flutter build apk --release
# çıktı: build/app/outputs/flutter-apk/app-release.apk
```

5. iOS için (Mac + Xcode gerekir):

```bash
flutter build ios --release
```

## Varsayılan adres planı

| Kategori | Modbus Fonksiyon | Adres Aralığı |
|---|---|---|
| 14 Giriş | Read Discrete Inputs (FC02) | 0–13 |
| 10 Çıkış | Read/Write Coils (FC01/FC05) | 0–9 |
| 6 Analog | Read/Write Holding Registers (FC03/FC06) | 0–5 |

Bu adresler PLC programındaki gerçek adreslerle eşleşmiyorsa,
`main.dart` içindeki `readDiscreteInputs(0, ...)`, `readCoils(0, ...)`,
`readHoldingRegisters(0, ...)` çağrılarındaki başlangıç adreslerini
değiştirmen yeterli.

## Kullanım

- Uygulama açılışta ayarlarda kayıtlı IP'ye (varsayılan `192.168.1.101:502`)
  otomatik bağlanır.
- Sağ üstteki **kalem ikonu** düzenleme modunu açar — bu moddayken her
  satıra dokunarak ismini değiştirebilir, analog sinyalin gösterge mi
  kontrol mü olacağını seçebilirsin. Bu ayarlar telefonda kalıcı saklanır.
- Sağ üstteki **ağ ikonu** ile PLC IP/Port/Unit ID değiştirilir.
- Bağlantı koparsa uygulama 3 saniyede bir otomatik yeniden bağlanmayı
  dener.

## Notlar

- İnternet gerekmez; sadece teknenin yerel WiFi ağına bağlı olman yeterli.
- Analog "kontrol" modunda kaydırıcı bıraktığın anda (sürükleme sırasında
  değil) PLC'ye tek bir yazma isteği gönderilir — gereksiz trafik olmaz.
- Modbus adres numaralandırması bu kodda 0 tabanlıdır (Modbus protokol
  standardı). PLC yazılımında (GX Works) "40001" gibi 1 tabanlı gösterim
  görürsen, gerçek adres bundan 1 çıkarılarak bulunur (40001 → register 0).
