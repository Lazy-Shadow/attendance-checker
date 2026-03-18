import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student.dart';
import '../models/attendance_record.dart';

class Day {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<AttendanceRecord> records;

  Day({
    required this.id,
    required this.name,
    required this.createdAt,
    List<AttendanceRecord>? records,
  }) : records = records ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'records': records.map((r) => r.toJsonString()).toList(),
  };

  factory Day.fromJson(Map<String, dynamic> json) {
    return Day(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      records: (json['records'] as List?)?.map((r) => AttendanceRecord.fromJsonString(r)).toList() ?? [],
    );
  }
}

class DayProvider extends ChangeNotifier {
  List<Day> _days = [];
  String? _selectedId;

  List<Day> get days => _days;
  String? get selectedId => _selectedId;
  Day? get selectedDay {
    if (_selectedId == null || _days.isEmpty) return null;
    try {
      return _days.firstWhere((d) => d.id == _selectedId);
    } catch (e) {
      return _days.first;
    }
  }

  DayProvider() { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('days');
    if (data != null) {
      _days = (jsonDecode(data) as List).map((e) => Day.fromJson(e)).toList();
      if (_days.isNotEmpty) _selectedId = _days.first.id;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('days', jsonEncode(_days.map((d) => d.toJson()).toList()));
  }

  void create(String name) {
    final day = Day(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
    );
    _days.add(day);
    _selectedId ??= day.id;
    _save();
    notifyListeners();
  }

  void rename(String id, String newName) {
    final i = _days.indexWhere((d) => d.id == id);
    if (i != -1) {
      _days[i] = Day(
        id: id,
        name: newName,
        createdAt: _days[i].createdAt,
        records: _days[i].records,
      );
      _save();
      notifyListeners();
    }
  }

  void delete(String id) {
    _days.removeWhere((d) => d.id == id);
    if (_selectedId == id) {
      _selectedId = _days.isNotEmpty ? _days.first.id : null;
    }
    _save();
    notifyListeners();
  }

  void select(String id) {
    _selectedId = id;
    notifyListeners();
  }

  void clearRecords(String id) {
    final i = _days.indexWhere((d) => d.id == id);
    if (i != -1) {
      _days[i].records.clear();
      _save();
      notifyListeners();
    }
  }

  void deleteRecord(String dayId, String recordId) {
    final i = _days.indexWhere((d) => d.id == dayId);
    if (i != -1) {
      _days[i].records.removeWhere((r) => r.id == recordId);
      _save();
      notifyListeners();
    }
  }

  bool hasTimeIn(String dayId, String studentId) {
    final dayIndex = _days.indexWhere((d) => d.id == dayId);
    if (dayIndex == -1) return false;
    return _days[dayIndex].records.any(
      (r) => r.student.id == studentId && r.type == AttendanceType.timeIn
    );
  }

  bool hasTimeOut(String dayId, String studentId) {
    final dayIndex = _days.indexWhere((d) => d.id == dayId);
    if (dayIndex == -1) return false;
    return _days[dayIndex].records.any(
      (r) => r.student.id == studentId && r.type == AttendanceType.timeOut
    );
  }

  void addRecord(String dayId, AttendanceRecord record) {
    final i = _days.indexWhere((d) => d.id == dayId);
    if (i != -1) {
      _days[i].records.insert(0, record);
      _save();
      notifyListeners();
    }
  }
}
