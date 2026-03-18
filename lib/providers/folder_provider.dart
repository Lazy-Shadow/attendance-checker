import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student.dart';

class UploadedFile {
  final String id;
  final String name;
  final String path;
  final String type;
  final DateTime uploadedAt;

  UploadedFile({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'type': type,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      type: json['type'],
      uploadedAt: DateTime.parse(json['uploadedAt']),
    );
  }
}

class Folder {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<Student> students;
  final List<UploadedFile> files;

  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    List<Student>? students,
    List<UploadedFile>? files,
  })  : students = students ?? [],
        files = files ?? [];

  String get fileName => name.replaceAll(' ', '_');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'students': students.map((s) => s.toJsonString()).toList(),
    'files': files.map((f) => f.toJson()).toList(),
  };

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      students: (json['students'] as List?)?.map((s) => Student.fromJsonString(s)).toList() ?? [],
      files: (json['files'] as List?)?.map((f) => UploadedFile.fromJson(f)).toList() ?? [],
    );
  }
}

class FolderProvider extends ChangeNotifier {
  List<Folder> _folders = [];
  String? _selectedId;

  List<Folder> get folders => _folders;
  String? get selectedId => _selectedId;
  Folder? get selectedFolder {
    if (_selectedId == null || _folders.isEmpty) return null;
    try {
      return _folders.firstWhere((f) => f.id == _selectedId);
    } catch (e) {
      return _folders.first;
    }
  }

  FolderProvider() { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('folders');
    if (data != null) {
      _folders = (jsonDecode(data) as List).map((e) => Folder.fromJson(e)).toList();
      if (_folders.isNotEmpty) _selectedId = _folders.first.id;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('folders', jsonEncode(_folders.map((f) => f.toJson()).toList()));
  }

  void create(String name) {
    final folder = Folder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
    );
    _folders.add(folder);
    _selectedId ??= folder.id;
    _save();
    notifyListeners();
  }

  void rename(String id, String newName) {
    final i = _folders.indexWhere((f) => f.id == id);
    if (i != -1) {
      _folders[i] = Folder(
        id: id,
        name: newName,
        createdAt: _folders[i].createdAt,
        students: _folders[i].students,
        files: _folders[i].files,
      );
      _save();
      notifyListeners();
    }
  }

  void delete(String id) {
    _folders.removeWhere((f) => f.id == id);
    if (_selectedId == id) {
      _selectedId = _folders.isNotEmpty ? _folders.first.id : null;
    }
    _save();
    notifyListeners();
  }

  void select(String id) {
    _selectedId = id;
    notifyListeners();
  }

  void addStudent(String folderId, Student student) {
    final i = _folders.indexWhere((f) => f.id == folderId);
    if (i != -1) {
      _folders[i].students.add(student);
      _save();
      notifyListeners();
    }
  }

  void addFile(String folderId, UploadedFile file) {
    final i = _folders.indexWhere((f) => f.id == folderId);
    if (i != -1) {
      _folders[i].files.add(file);
      _save();
      notifyListeners();
    }
  }

  void removeStudent(String folderId, String studentId) {
    final i = _folders.indexWhere((f) => f.id == folderId);
    if (i != -1) {
      _folders[i].students.removeWhere((s) => s.id == studentId);
      _save();
      notifyListeners();
    }
  }

  void updateStudent(String folderId, Student updatedStudent) {
    final i = _folders.indexWhere((f) => f.id == folderId);
    if (i != -1) {
      final studentIndex = _folders[i].students.indexWhere((s) => s.id == updatedStudent.id);
      if (studentIndex != -1) {
        _folders[i].students[studentIndex] = updatedStudent;
        _save();
        notifyListeners();
      }
    }
  }

  void removeFile(String folderId, String fileId) {
    final i = _folders.indexWhere((f) => f.id == folderId);
    if (i != -1) {
      final file = _folders[i].files.firstWhere((f) => f.id == fileId, orElse: () => UploadedFile(id: '', name: '', path: '', type: '', uploadedAt: DateTime.now()));
      if (file.path.isNotEmpty) {
        final fileToDelete = File(file.path);
        if (fileToDelete.existsSync()) {
          fileToDelete.deleteSync();
        }
      }
      _folders[i].files.removeWhere((f) => f.id == fileId);
      _save();
      notifyListeners();
    }
  }

  Future<String> getDownloadPath() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir.path;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  Future<void> downloadFolder(BuildContext context, Folder folder) async {
    try {
      final path = await getDownloadPath();
      final folderDir = Directory('$path/${folder.fileName}_QRCodes');
      if (await folderDir.exists()) await folderDir.delete(recursive: true);
      await folderDir.create();

      for (final student in folder.students) {
        final image = await QrPainter(
          data: student.studentNumber,
          version: QrVersions.auto,
        ).toImage(300);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        await File('${folderDir.path}/${student.fileName}.png').writeAsBytes(bytes);
      }

      final manifest = folder.students.map((s) => '${s.fullName}\n${s.program} ${s.year}').join('\n---\n');
      await File('${folderDir.path}/manifest.txt').writeAsString(manifest);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to Downloads/${folder.fileName}_QRCodes'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
    }
  }
}
