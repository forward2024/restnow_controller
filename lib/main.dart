import 'package:flutter/material.dart' as flutter;
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';

void main() {
  flutter.runApp(const MyApp());
}

class MyApp extends flutter.StatelessWidget {
  const MyApp({super.key});

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.MaterialApp(
      title: 'BLE Controller Emulator',
      theme: flutter.ThemeData(
        primarySwatch: flutter.Colors.blue,
      ),
      home: const BLEPeripheral(),
    );
  }
}

class BLEPeripheral extends flutter.StatefulWidget {
  const BLEPeripheral({super.key});

  @override
  _BLEPeripheralState createState() => _BLEPeripheralState();
}

class _BLEPeripheralState extends flutter.State<BLEPeripheral> {
  late ble.PeripheralManager _peripheralManager;
  bool _isAdvertising = false;
  String _status = 'Disconnected';
  List<String> _log = [];

  final flutter.TextEditingController _nameController =
      flutter.TextEditingController();
  final flutter.TextEditingController _uuidController =
      flutter.TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeBLE();
  }

  void _updateLog(String message) {
    setState(() {
      if (_log.length >= 7) {
        _log.removeAt(0);
      }
      _log.add(message);
    });
    print(message);
  }

  Future<void> _initializeBLE() async {
    try {
      _updateLog('Запуск перевірки дозволів...');
      await _checkPermissions();

      _peripheralManager = ble.PeripheralManager();
      _updateLog('PeripheralManager ініціалізований.');

      _updateLog('Запуск ініціалізації GATT сервісів...');
      await _setUpGATTServices();

      _peripheralManager.connectionStateChanged.listen((event) {
        setState(() {
          if (event.state == ble.ConnectionState.connected) {
            _status = 'Connected';
            _updateLog('Пристрій підключено: ${event.central}');
          } else if (event.state == ble.ConnectionState.disconnected) {
            _status = 'Disconnected';
            _updateLog('Пристрій відключено: ${event.central}');
          }
        });
      });

      _peripheralManager.characteristicReadRequested.listen((event) async {
        _updateLog('Запит на читання характеристики від ${event.central}');
        await _peripheralManager.respondReadRequestWithValue(
          event.request,
          value: Uint8List.fromList([0x01, 0x02, 0x03]),
        );
      });

      _peripheralManager.characteristicWriteRequested.listen((event) async {
        _updateLog('Запит на запис характеристики від ${event.central}');
        await _peripheralManager.respondWriteRequest(event.request);
      });
    } catch (e) {
      _updateLog('Помилка ініціалізації BLE: $e');
    }
  }

  Future<void> _setUpGATTServices() async {
    try {
      _updateLog('Початок налаштування GATT сервісу...');

      ble.GATTCharacteristic characteristic = ble.GATTCharacteristic.mutable(
        uuid: ble.UUID.fromString('UUID_Characteristic'),
        properties: [
          ble.GATTCharacteristicProperty.read,
          ble.GATTCharacteristicProperty.write
        ],
        permissions: [
          ble.GATTCharacteristicPermission.read,
          ble.GATTCharacteristicPermission.write
        ],
        descriptors: [],
      );

      ble.GATTService gattService = ble.GATTService(
        uuid: ble.UUID.fromString('123e4567-e89b-12d3-a456-426614174000'),
        isPrimary: true,
        includedServices: [],
        characteristics: [characteristic],
      );

      _updateLog(
          'Додаємо GATT сервіс з UUID: 123e4567-e89b-12d3-a456-426614174000');

      await _peripheralManager.addService(gattService);

      _updateLog('GATT сервіси успішно налаштовані.');
    } catch (e) {
      _updateLog('Помилка налаштування GATT сервісів: $e');
    }
  }

  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect
    ].request();

    if (statuses[Permission.bluetoothAdvertise]?.isDenied ?? true) {
      _updateLog('Необхідний дозвіл на рекламу Bluetooth.');
    }
    if (statuses[Permission.bluetoothConnect]?.isDenied ?? true) {
      _updateLog('Необхідний дозвіл на підключення через Bluetooth.');
    }
  }

  void _toggleAdvertising(bool value) async {
    setState(() {
      _isAdvertising = value;
    });

    if (value) {
      try {
        _updateLog('Початок реклами BLE...');
        String name = _nameController.text;
        String uuidString = _uuidController.text;

        if (name.isEmpty || uuidString.isEmpty) {
          throw const FormatException("Назва або UUID не може бути порожнім");
        }

        ble.UUID uuid = ble.UUID.fromString(uuidString);

        await _peripheralManager.startAdvertising(
          ble.Advertisement(
            name: name,
            serviceUUIDs: [uuid],
          ),
        );
        _updateLog('Реклама BLE успішно почалась.');
      } catch (e) {
        _updateLog('Помилка реклами BLE: $e');
        setState(() {
          _isAdvertising = false;
        });
      }
    } else {
      await _peripheralManager.stopAdvertising();
      _updateLog('Реклама BLE зупинена.');
    }
  }

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return flutter.Scaffold(
      appBar:
          flutter.AppBar(title: const flutter.Text('BLE Controller Emulator')),
      body: flutter.Padding(
        padding: const flutter.EdgeInsets.all(16.0),
        child: flutter.Column(
          crossAxisAlignment: flutter.CrossAxisAlignment.start,
          children: [
            flutter.TextField(
              controller: _nameController,
              decoration: const flutter.InputDecoration(
                  labelText: 'Назва BLE-з\'єднання'),
            ),
            flutter.TextField(
              controller: _uuidController,
              decoration: const flutter.InputDecoration(labelText: 'UUID'),
            ),
            flutter.SwitchListTile(
              title: const flutter.Text('Увімкнути рекламу BLE'),
              value: _isAdvertising,
              onChanged: (value) => _toggleAdvertising(value),
            ),
            flutter.Text('Статус: $_status'),
            const flutter.SizedBox(height: 20),
            const flutter.Text('Останні події:'),
            flutter.Expanded(
              child: flutter.ListView(
                children: _log
                    .map((line) => flutter.Align(
                        alignment: flutter.Alignment.centerRight,
                        child: flutter.Text(line)))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _peripheralManager.stopAdvertising();
    super.dispose();
  }
}
