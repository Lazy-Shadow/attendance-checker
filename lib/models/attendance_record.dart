import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student.dart';

enum AttendanceType { timeIn, timeOut }

class AttendanceRecord {
  final String id;
  final Student student;
  final DateTime timestamp;
  final AttendanceType type;

  AttendanceRecord({
    required this.id,
    required this.student,
    required this.timestamp,
    required this.type,
  });

  String toJsonString() => jsonEncode({
    'id': id,
    'student': student.toJsonString(),
    'timestamp': timestamp.toIso8601String(),
    'type': type.name,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'student': student.toMap(),
    'timestamp': timestamp,
    'type': type.name,
  };

  factory AttendanceRecord.fromJsonString(String jsonString) {
    final map = jsonDecode(jsonString);
    return AttendanceRecord.fromMap(map);
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String?;
    final attendanceType =
        typeStr != null && AttendanceType.values.any((e) => e.name == typeStr)
        ? AttendanceType.values.firstWhere((e) => e.name == typeStr)
        : AttendanceType.timeIn;

    DateTime parseTimestamp(dynamic value) {
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    }

    return AttendanceRecord(
      id: map['id'],
      student: Student.fromMap(map['student']),
      timestamp: parseTimestamp(map['timestamp']),
      type: attendanceType,
    );
  }

  Map<String, dynamic> toJson() {
    final map = toMap();
    map['timestamp'] = (map['timestamp'] as DateTime).toIso8601String();
    return map;
  }

  static AttendanceRecord fromJson(Map<String, dynamic> json) =>
      AttendanceRecord.fromMap(json);
}
