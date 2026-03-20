import 'dart:convert';
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
    return AttendanceRecord(
      id: map['id'],
      student: Student.fromMap(map['student']),
      timestamp: map['timestamp'] is DateTime
          ? map['timestamp']
          : DateTime.parse(map['timestamp'].toString()),
      type: attendanceType,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  static AttendanceRecord fromJson(Map<String, dynamic> json) =>
      AttendanceRecord.fromMap(json);
}
