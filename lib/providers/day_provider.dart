import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_record.dart';

class Day {
  final String id;
  final String name;
  final DateTime createdAt;
  List<AttendanceRecord> records;

  Day({
    required this.id,
    required this.name,
    required this.createdAt,
    List<AttendanceRecord>? records,
  }) : records = records ?? [];

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'createdAt': Timestamp.fromDate(createdAt),
    'records': records.map((r) => r.toMap()).toList(),
  };

  factory Day.fromMap(Map<String, dynamic> map) {
    return Day(
      id: map['id'],
      name: map['name'],
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      records:
          (map['records'] as List<dynamic>?)
              ?.map(
                (r) => AttendanceRecord.fromMap(Map<String, dynamic>.from(r)),
              )
              .toList() ??
          [],
    );
  }

  factory Day.fromJson(Map<String, dynamic> json) {
    return Day(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      records:
          (json['records'] as List<dynamic>?)
              ?.map(
                (r) => AttendanceRecord.fromMap(Map<String, dynamic>.from(r)),
              )
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'records': records.map((r) => r.toJson()).toList(),
  };
}

class DayProvider extends ChangeNotifier {
  List<Day> _days = [];
  String? _selectedDayId;
  bool _isLoading = true;
  bool _isOnline = true;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Day> get days => _days;
  String? get selectedDayId => _selectedDayId;
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;

  Day? get selectedDay => _selectedDayId != null
      ? _days.firstWhere(
          (d) => d.id == _selectedDayId,
          orElse: () => _days.first,
        )
      : _days.isNotEmpty
      ? _days.first
      : null;

  DayProvider() {
    _loadDays();
    _initConnectivity();
  }

  void _initConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline =
          result.isNotEmpty && !result.contains(ConnectivityResult.none);

      if (wasOffline && _isOnline) {
        _syncPendingActions();
      }
      notifyListeners();
    });
  }

  Future<void> _loadDays() async {
    _isLoading = true;
    notifyListeners();

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      _isOnline =
          connectivityResult.isNotEmpty &&
          !connectivityResult.contains(ConnectivityResult.none);

      if (_isOnline) {
        final snapshot = await _firestore.collection('attendance_days').get();
        _days = snapshot.docs.map((doc) => Day.fromMap(doc.data())).toList();
        _days.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _cacheLocally();
      } else {
        _loadFromCache();
      }

      if (_days.isNotEmpty) {
        _selectedDayId = _days.first.id;
      }
    } catch (e) {
      debugPrint('Error loading days: $e');
      _loadFromCache();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _cacheLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final daysJson = _days.map((d) => d.toJson()).toList();
      await prefs.setString('cached_days', jsonEncode(daysJson));
      await prefs.setString('last_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Error caching days locally: $e');
    }
  }

  void _loadFromCache() {
    try {
      SharedPreferences.getInstance().then((prefs) {
        final cachedData = prefs.getString('cached_days');
        if (cachedData != null) {
          final List<dynamic> decoded = jsonDecode(cachedData);
          _days = decoded.map((json) => Day.fromJson(json)).toList();
          _days.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      });
    } catch (e) {
      debugPrint('Error loading from cache: $e');
    }
  }

  Future<void> _syncPendingActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingData = prefs.getString('pending_actions');

      if (pendingData != null && pendingData.isNotEmpty) {
        final List<dynamic> pending = jsonDecode(pendingData);

        for (final action in pending) {
          await _executeAction(Map<String, dynamic>.from(action));
        }

        await prefs.remove('pending_actions');
        await _loadDays();
      }
    } catch (e) {
      debugPrint('Error syncing pending actions: $e');
    }
  }

  Future<void> _executeAction(Map<String, dynamic> action) async {
    final type = action['type'] as String;
    final dayId = action['dayId'] as String;

    switch (type) {
      case 'add_record':
        final record = AttendanceRecord.fromMap(
          Map<String, dynamic>.from(action['record']),
        );
        await _addRecordToFirestore(dayId, record);
        break;
      case 'remove_record':
        await _removeRecordFromFirestore(
          dayId,
          action['studentId'] as String,
          action['attendanceType'] as String,
        );
        break;
      case 'create_day':
        final day = Day.fromJson(Map<String, dynamic>.from(action['day']));
        await _firestore
            .collection('attendance_days')
            .doc(day.id)
            .set(day.toMap());
        break;
      case 'delete_day':
        await _firestore.collection('attendance_days').doc(dayId).delete();
        break;
      case 'clear_records':
        await _firestore.collection('attendance_days').doc(dayId).update({
          'records': [],
        });
        break;
    }
  }

  Future<void> _addRecordToFirestore(
    String dayId,
    AttendanceRecord record,
  ) async {
    final doc = await _firestore.collection('attendance_days').doc(dayId).get();
    if (doc.exists) {
      final day = Day.fromMap(doc.data()!);
      day.records.insert(0, record);
      await _firestore.collection('attendance_days').doc(dayId).update({
        'records': day.records.map((r) => r.toMap()).toList(),
      });
    }
  }

  Future<void> _removeRecordFromFirestore(
    String dayId,
    String studentId,
    String type,
  ) async {
    final doc = await _firestore.collection('attendance_days').doc(dayId).get();
    if (doc.exists) {
      final day = Day.fromMap(doc.data()!);
      day.records.removeWhere(
        (r) => r.student.id == studentId && r.type.name == type,
      );
      await _firestore.collection('attendance_days').doc(dayId).update({
        'records': day.records.map((r) => r.toMap()).toList(),
      });
    }
  }

  Future<void> createDay(String name) async {
    final dayId = DateTime.now().millisecondsSinceEpoch.toString();
    final day = Day(id: dayId, name: name, createdAt: DateTime.now());

    if (_isOnline) {
      try {
        await _firestore
            .collection('attendance_days')
            .doc(dayId)
            .set(day.toMap());
      } catch (e) {
        _addPendingAction({'type': 'create_day', 'day': day.toJson()});
      }
    } else {
      _addPendingAction({'type': 'create_day', 'day': day.toJson()});
    }

    _days.insert(0, day);
    if (_selectedDayId == null) {
      _selectedDayId = dayId;
    }
    await _cacheLocally();
    notifyListeners();
  }

  Future<void> deleteDay(String id) async {
    if (_isOnline) {
      try {
        await _firestore.collection('attendance_days').doc(id).delete();
      } catch (e) {
        _addPendingAction({'type': 'delete_day', 'dayId': id});
      }
    } else {
      _addPendingAction({'type': 'delete_day', 'dayId': id});
    }

    _days.removeWhere((d) => d.id == id);
    if (_selectedDayId == id) {
      _selectedDayId = _days.isNotEmpty ? _days.first.id : null;
    }
    await _cacheLocally();
    notifyListeners();
  }

  void selectDay(String id) {
    _selectedDayId = id;
    notifyListeners();
  }

  Future<void> renameDay(String id, String newName) async {
    final index = _days.indexWhere((d) => d.id == id);
    if (index != -1) {
      final updatedDay = Day(
        id: _days[index].id,
        name: newName,
        createdAt: _days[index].createdAt,
        records: _days[index].records,
      );

      if (_isOnline) {
        try {
          await _firestore
              .collection('attendance_days')
              .doc(id)
              .update(updatedDay.toMap());
        } catch (e) {
          debugPrint('Error updating day: $e');
        }
      }

      _days[index] = updatedDay;
      await _cacheLocally();
      notifyListeners();
    }
  }

  bool hasTimeIn(String dayId, String studentId) {
    final dayIndex = _days.indexWhere((d) => d.id == dayId);
    if (dayIndex == -1) return false;
    return _days[dayIndex].records.any(
      (r) => r.student.id == studentId && r.type == AttendanceType.timeIn,
    );
  }

  bool hasTimeOut(String dayId, String studentId) {
    final dayIndex = _days.indexWhere((d) => d.id == dayId);
    if (dayIndex == -1) return false;
    return _days[dayIndex].records.any(
      (r) => r.student.id == studentId && r.type == AttendanceType.timeOut,
    );
  }

  Future<void> addRecordToDay(String dayId, AttendanceRecord record) async {
    final index = _days.indexWhere((d) => d.id == dayId);
    if (index != -1) {
      _days[index].records.insert(0, record);
      notifyListeners();

      if (_isOnline) {
        try {
          await _firestore.collection('attendance_days').doc(dayId).update({
            'records': _days[index].records.map((r) => r.toMap()).toList(),
          });
        } catch (e) {
          _addPendingAction({
            'type': 'add_record',
            'dayId': dayId,
            'record': record.toJson(),
          });
        }
      } else {
        _addPendingAction({
          'type': 'add_record',
          'dayId': dayId,
          'record': record.toJson(),
        });
      }

      await _cacheLocally();
    }
  }

  Future<void> removeRecord(
    String dayId,
    String studentId,
    AttendanceType type,
  ) async {
    final index = _days.indexWhere((d) => d.id == dayId);
    if (index != -1) {
      _days[index].records.removeWhere(
        (r) => r.student.id == studentId && r.type == type,
      );
      notifyListeners();

      if (_isOnline) {
        try {
          await _firestore.collection('attendance_days').doc(dayId).update({
            'records': _days[index].records.map((r) => r.toMap()).toList(),
          });
        } catch (e) {
          _addPendingAction({
            'type': 'remove_record',
            'dayId': dayId,
            'studentId': studentId,
            'attendanceType': type.name,
          });
        }
      } else {
        _addPendingAction({
          'type': 'remove_record',
          'dayId': dayId,
          'studentId': studentId,
          'attendanceType': type.name,
        });
      }

      await _cacheLocally();
    }
  }

  void deleteRecord(String dayId, String recordId) {
    final index = _days.indexWhere((d) => d.id == dayId);
    if (index != -1) {
      _days[index].records.removeWhere((r) => r.id == recordId);
      _cacheLocally();
      notifyListeners();
    }
  }

  Future<void> clearDayRecords(String dayId) async {
    final index = _days.indexWhere((d) => d.id == dayId);
    if (index != -1) {
      _days[index].records.clear();

      if (_isOnline) {
        try {
          await _firestore.collection('attendance_days').doc(dayId).update({
            'records': [],
          });
        } catch (e) {
          _addPendingAction({'type': 'clear_records', 'dayId': dayId});
        }
      } else {
        _addPendingAction({'type': 'clear_records', 'dayId': dayId});
      }

      await _cacheLocally();
      notifyListeners();
    }
  }

  Future<void> _addPendingAction(Map<String, dynamic> action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingData = prefs.getString('pending_actions');
      List<dynamic> pending = [];

      if (pendingData != null && pendingData.isNotEmpty) {
        pending = jsonDecode(pendingData);
      }

      pending.add({...action, 'timestamp': DateTime.now().toIso8601String()});

      await prefs.setString('pending_actions', jsonEncode(pending));
    } catch (e) {
      debugPrint('Error adding pending action: $e');
    }
  }

  Future<String?> exportToExcel(String dayId) async {
    final dayIndex = _days.indexWhere((d) => d.id == dayId);
    if (dayIndex == -1) return null;

    final day = _days[dayIndex];
    final excel = Excel.createExcel();

    final timeInSheet = excel['Time In'];
    final timeOutSheet = excel['Time Out'];
    final allSheet = excel['All Records'];

    void addHeaderRow(Sheet sheet) {
      sheet.appendRow([
        TextCellValue('No.'),
        TextCellValue('Full Name'),
        TextCellValue('Program'),
        TextCellValue('Year'),
        TextCellValue('Time'),
        TextCellValue('Type'),
      ]);
    }

    void addRecords(Sheet sheet, List<AttendanceRecord> recs) {
      final timeFormat = DateFormat('h:mm a');
      final dateFormat = DateFormat('MMM dd, yyyy');
      for (var i = 0; i < recs.length; i++) {
        final record = recs[i];
        sheet.appendRow([
          TextCellValue('${i + 1}'),
          TextCellValue(record.student.fullName),
          TextCellValue(record.student.program),
          TextCellValue(record.student.year),
          TextCellValue(
            '${dateFormat.format(record.timestamp)} ${timeFormat.format(record.timestamp)}',
          ),
          TextCellValue(
            record.type == AttendanceType.timeIn ? 'Time In' : 'Time Out',
          ),
        ]);
      }
    }

    addHeaderRow(timeInSheet);
    addRecords(
      timeInSheet,
      day.records.where((r) => r.type == AttendanceType.timeIn).toList(),
    );

    addHeaderRow(timeOutSheet);
    addRecords(
      timeOutSheet,
      day.records.where((r) => r.type == AttendanceType.timeOut).toList(),
    );

    addHeaderRow(allSheet);
    addRecords(allSheet, day.records);

    try {
      Directory? directory;
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final exportDir = Directory('${extDir.path}/Exports');
          if (!await exportDir.exists()) {
            await exportDir.create(recursive: true);
          }
          directory = exportDir;
        } else {
          directory = await getApplicationDocumentsDirectory();
        }
      } else {
        directory =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      final fileName = '${day.name.replaceAll(' ', '_')}_attendance.xlsx';
      final file = File('${directory.path}/$fileName');

      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        return file.path;
      }
    } catch (e) {
      debugPrint('Error exporting to Excel: $e');
    }
    return null;
  }
}
