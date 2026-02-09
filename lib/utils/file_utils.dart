import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class FileUtils {
  static Future<String?> createFolderInAppDocDir(String folderName) async {
    // Get Document Directory
    final Directory? appDocDir = await getExternalStorageDirectory();
    // Fallback for iOS or if external is unavailable
    final Directory rootDir = appDocDir ?? await getApplicationDocumentsDirectory();

    final Directory appDocDirFolder = Directory('${rootDir.path}/$folderName');

    if (await appDocDirFolder.exists()) {
      return appDocDirFolder.path;
    } else {
      final Directory appDocDirNewFolder = await appDocDirFolder.create(recursive: true);
      return appDocDirNewFolder.path;
    }
  }

  static Future<void> saveUserFingerImage(int userId, String fingerPosName, Uint8List imageBytes) async {
    try {
      // 1. Create/Get "FingerData" folder
      String? rootPath = await createFolderInAppDocDir("FingerData");

      // 2. Create/Get "User_{id}" folder
      String userFolderPath = "$rootPath/User_$userId";
      await Directory(userFolderPath).create(recursive: true);

      // 3. Write File
      File file = File("$userFolderPath/$fingerPosName.bmp");
      await file.writeAsBytes(imageBytes);
      print("Saved to: ${file.path}");
    } catch (e) {
      print("Error saving file: $e");
    }
  }

  static Future<bool> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }
}