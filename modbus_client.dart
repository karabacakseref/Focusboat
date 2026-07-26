import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Basit, bağımlılıksız Modbus TCP istemcisi.
/// FX3U gibi PLC'lerle doğrudan Modbus TCP (port 502) üzerinden konuşur.
class ModbusException implements Exception {
  final String message;
  ModbusException(this.message);
  @override
  String toString() => 'ModbusException: $message';
}

class ModbusTcpClient {
  final String host;
  final int port;
  final int unitId;
  final Duration timeout;

  Socket? _socket;
  int _transactionId = 0;
  final Map<int, Completer<Uint8List>> _pending = {};
  final StringBuffer _rxBuffer = StringBuffer();
  final List<int> _rxBytes = [];

  bool get isConnected => _socket != null;

  ModbusTcpClient({
    required this.host,
    this.port = 502,
    this.unitId = 1,
    this.timeout = const Duration(seconds: 3),
  });

  Future<void> connect() async {
    await disconnect();
    _socket = await Socket.connect(host, port, timeout: timeout);
    _socket!.listen(
      _onData,
      onError: (_) => disconnect(),
      onDone: () => disconnect(),
      cancelOnError: true,
    );
  }

  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(ModbusException('Bağlantı kapandı'));
    }
    _pending.clear();
    _rxBytes.clear();
  }

  void _onData(Uint8List data) {
    _rxBytes.addAll(data);
    // MBAP header = 7 bytes (TxId(2) ProtoId(2) Length(2) UnitId(1)) + PDU
    while (_rxBytes.length >= 7) {
      final txId = (_rxBytes[0] << 8) | _rxBytes[1];
      final length = (_rxBytes[4] << 8) | _rxBytes[5];
      final totalLen = 6 + length; // header'ın ilk 6 byte'ı + length alanındaki kalan
      if (_rxBytes.length < totalLen) return; // henüz tam paket gelmedi
      final frame = Uint8List.fromList(_rxBytes.sublist(0, totalLen));
      _rxBytes.removeRange(0, totalLen);
      final completer = _pending.remove(txId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(frame);
      }
    }
  }

  int _nextTxId() {
    _transactionId = (_transactionId + 1) & 0xFFFF;
    return _transactionId;
  }

  Future<Uint8List> _sendRequest(List<int> pdu) async {
    final socket = _socket;
    if (socket == null) throw ModbusException('Bağlı değil');

    final txId = _nextTxId();
    final length = pdu.length + 1; // +1 unitId
    final header = <int>[
      (txId >> 8) & 0xFF, txId & 0xFF, // Transaction ID
      0x00, 0x00, // Protocol ID (her zaman 0)
      (length >> 8) & 0xFF, length & 0xFF, // Length
      unitId, // Unit ID
    ];
    final frame = Uint8List.fromList([...header, ...pdu]);

    final completer = Completer<Uint8List>();
    _pending[txId] = completer;
    socket.add(frame);
    await socket.flush();

    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(txId);
      throw ModbusException('Zaman aşımı: $host:$port yanıt vermedi');
    });
  }

  /// FC 02 - Discrete Inputs oku (sadece okunabilir dijital girişler)
  Future<List<bool>> readDiscreteInputs(int startAddress, int count) async {
    final pdu = [
      0x02,
      (startAddress >> 8) & 0xFF, startAddress & 0xFF,
      (count >> 8) & 0xFF, count & 0xFF,
    ];
    final resp = await _sendRequest(pdu);
    _checkError(resp);
    final byteCount = resp[8];
    final dataBytes = resp.sublist(9, 9 + byteCount);
    return _bytesToBools(dataBytes, count);
  }

  /// FC 01 - Coils oku (dijital çıkışların anlık durumu)
  Future<List<bool>> readCoils(int startAddress, int count) async {
    final pdu = [
      0x01,
      (startAddress >> 8) & 0xFF, startAddress & 0xFF,
      (count >> 8) & 0xFF, count & 0xFF,
    ];
    final resp = await _sendRequest(pdu);
    _checkError(resp);
    final byteCount = resp[8];
    final dataBytes = resp.sublist(9, 9 + byteCount);
    return _bytesToBools(dataBytes, count);
  }

  /// FC 05 - Tek bir coil (çıkış) yaz: true=ON(0xFF00) false=OFF(0x0000)
  Future<void> writeSingleCoil(int address, bool value) async {
    final pdu = [
      0x05,
      (address >> 8) & 0xFF, address & 0xFF,
      value ? 0xFF : 0x00, 0x00,
    ];
    final resp = await _sendRequest(pdu);
    _checkError(resp);
  }

  /// FC 03 - Holding Register(lar) oku (analog değerler)
  Future<List<int>> readHoldingRegisters(int startAddress, int count) async {
    final pdu = [
      0x03,
      (startAddress >> 8) & 0xFF, startAddress & 0xFF,
      (count >> 8) & 0xFF, count & 0xFF,
    ];
    final resp = await _sendRequest(pdu);
    _checkError(resp);
    final byteCount = resp[8];
    final values = <int>[];
    for (int i = 0; i < byteCount; i += 2) {
      values.add((resp[9 + i] << 8) | resp[9 + i + 1]);
    }
    return values;
  }

  /// FC 06 - Tek bir holding register (analog çıkış) yaz
  Future<void> writeSingleRegister(int address, int value) async {
    final pdu = [
      0x06,
      (address >> 8) & 0xFF, address & 0xFF,
      (value >> 8) & 0xFF, value & 0xFF,
    ];
    final resp = await _sendRequest(pdu);
    _checkError(resp);
  }

  void _checkError(Uint8List resp) {
    // resp[7] = function code (veya function|0x80 hata durumunda)
    if (resp.length < 9) {
      throw ModbusException('Geçersiz yanıt (çok kısa)');
    }
    final fc = resp[7];
    if (fc & 0x80 != 0) {
      final exceptionCode = resp[8];
      throw ModbusException('PLC hata kodu döndürdü: 0x${exceptionCode.toRadixString(16)}');
    }
  }

  List<bool> _bytesToBools(List<int> bytes, int count) {
    final result = <bool>[];
    for (int i = 0; i < count; i++) {
      final byteIndex = i ~/ 8;
      final bitIndex = i % 8;
      if (byteIndex >= bytes.length) {
        result.add(false);
        continue;
      }
      result.add((bytes[byteIndex] >> bitIndex) & 0x01 == 1);
    }
    return result;
  }
}
