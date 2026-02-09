import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class FileUtils {
  /// Create or Get a folder inside the App's Document Directory
  static Future<String?> createFolderInAppDocDir(String folderName) async {
    // Get Document Directory (External for Android visibility, App Doc for iOS fallback)
    final Directory? appDocDir = await getExternalStorageDirectory();
    final Directory rootDir = appDocDir ?? await getApplicationDocumentsDirectory();

    final Directory appDocDirFolder = Directory('${rootDir.path}/$folderName');

    if (await appDocDirFolder.exists()) {
      return appDocDirFolder.path;
    } else {
      final Directory appDocDirNewFolder = await appDocDirFolder.create(recursive: true);
      return appDocDirNewFolder.path;
    }
  }

  /// Save a fingerprint BMP image to the file system
  /// Structure: .../FingerData/User_{id}/{finger_name}.bmp
  static Future<void> saveUserFingerImage(int userId, String fingerPosName, Uint8List imageBytes) async {
    try {
      // 1. Create/Get "FingerData" folder
      String? rootPath = await createFolderInAppDocDir("FingerData");

      if (rootPath != null) {
        // 2. Create/Get "User_{id}" folder
        String userFolderPath = "$rootPath/User_$userId";
        await Directory(userFolderPath).create(recursive: true);

        // 3. Write File
        File file = File("$userFolderPath/$fingerPosName.bmp");
        await file.writeAsBytes(imageBytes);
        print("Saved to: ${file.path}");
      }
    } catch (e) {
      print("Error saving file: $e");
    }
  }

  /// Delete the entire folder for a specific user
  /// Called when a user is deleted from the database
  static Future<void> deleteUserFolder(int userId) async {
    try {
      String? rootPath = await createFolderInAppDocDir("FingerData");

      if (rootPath != null) {
        Directory userFolder = Directory("$rootPath/User_$userId");

        if (await userFolder.exists()) {
          await userFolder.delete(recursive: true);
          print("Deleted folder: ${userFolder.path}");
        }
      }
    } catch (e) {
      print("Error deleting folder: $e");
    }
  }

  /// Request Storage Permission (Required for Android 10 and below)
  static Future<bool> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }
}