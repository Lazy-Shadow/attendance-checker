import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/student.dart';
import '../models/attendance_record.dart';

class AttendanceProvider extends ChangeNotifier {
  List<AttendanceRecord> _records = [];
  final Uuid _uuid = const Uuid();
  String? _currentUserId;

  List<AttendanceRecord> get records => _records;

  List<AttendanceRecord> get timeInRecords =>
      _records.where((r) => r.type == AttendanceType.timeIn).toList();

  List<AttendanceRecord> get timeOutRecords =>
      _records.where((r) => r.type == AttendanceType.timeOut).toList();

  AttendanceProvider() {
    _loadLocalRecords();
  }

  void setUserId(String userId) {
    _currentUserId = userId;
    _loadFromFirestore();
  }

  Future<void> _loadLocalRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('attendance_records');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      _records = jsonList
          .map((e) => AttendanceRecord.fromJsonString(e))
          .toList();
      notifyListeners();
    }
  }

  Future<void> _loadFromFirestore() async {
    if (_currentUserId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('records')
          .orderBy('timestamp', descending: true)
          .get();

      _records = snapshot.docs
          .map((doc) => AttendanceRecord.fromMap(doc.data()))
          .toList();

      _saveLocalRecords();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading from Firestore: $e');
    }
  }

  Future<void> _saveLocalRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(
      _records.map((r) => r.toJsonString()).toList(),
    );
    await prefs.setString('attendance_records', data);
  }

  Future<void> _saveToFirestore(AttendanceRecord record) async {
    if (_currentUserId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('records')
          .doc(record.id)
          .set(record.toMap());
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
    }
  }

  Future<void> _deleteFromFirestore(String recordId) async {
    if (_currentUserId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('records')
          .doc(recordId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting from Firestore: $e');
    }
  }

  void addRecord(Student student, AttendanceType type) {
    final record = AttendanceRecord(
      id: _uuid.v4(),
      student: student,
      timestamp: DateTime.now(),
      type: type,
    );
    _records.insert(0, record);
    _saveLocalRecords();
    _saveToFirestore(record);
    notifyListeners();
  }

  void clearRecords() {
    _records.clear();
    _saveLocalRecords();
    notifyListeners();
  }

  void deleteRecord(String recordId) {
    _records.removeWhere((r) => r.id == recordId);
    _saveLocalRecords();
    _deleteFromFirestore(recordId);
    notifyListeners();
  }
}
