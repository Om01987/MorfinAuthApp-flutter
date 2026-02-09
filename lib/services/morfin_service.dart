import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:morfin_auth/morfin_auth_method_channel.dart';

class MorfinService {
  // --- Callbacks for UI Logic ---

  // Triggered when a scanner is plugged/unplugged
  Function(String name, bool isConnected)? onDeviceChanged;

  // Triggered when a capture finishes (Success or Failure)
  Function(int errorCode, int quality, int nfiq, Uint8List? image)? onCaptureComplete;

  // Triggered during capture for live feedback (optional)
  Function(int errorCode, int quality, Uint8List? image)? onLivePreview;

  // This channel listens to events coming FROM Native Android (PassedCallBack)
  static const MethodChannel _callbackChannel = MethodChannel('PassedCallBack');

  /// 1. Initialize the Plugin Listener
  /// This must be called first. It sets up the listeners and prepares the SDK.
  Future<void> initializePlugin() async {
    // Setup the listener for Native -> Flutter events
    _callbackChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'Device_Detection':
          _handleDeviceDetection(call.arguments);
          break;
        case 'complete':
          _handleCaptureComplete(call.arguments);
          break;
        case 'preview':
          _handlePreview(call.arguments);
          break;
      }
    });

    // Call the Native Plugin Initializer (Returns Future<void>)
    await MethodChannelMorfinAuth.GetFingerInitialize();
  }

  /// 2. Initialize the Specific Device (e.g., "MFS100")
  /// Returns 0 if success, other values are error codes.
  Future<int> initDevice(String deviceName) async {
    // OLD (Broken in Plugin): return await MethodChannelMorfinAuth.Init(deviceName);

    // NEW (Working): Use InitWithLock with an empty string as the key.
    // This calls the only initialization method that actually exists in the Java code.
    try {
      return await MethodChannelMorfinAuth.InitWithLock(deviceName, "");
    } catch (e) {
      print("InitWithLock Error: $e");
      return -1; // Return error code if it fails
    }
  }

  /// 3. Uninitialize Device (Release resources)
  Future<int> uninitDevice() async {
    return await MethodChannelMorfinAuth.Uninit();
  }

  /// 4. Get Device Info (Make, Model, Serial, etc.)
  /// Returns a Map or null if parsing fails.
  Future<Map<String, dynamic>?> getDeviceInfo() async {
    try {
      final String jsonString = await MethodChannelMorfinAuth.GetDeviceInfo();
      return jsonDecode(jsonString);
    } catch (e) {
      print("Error parsing device info: $e");
      return null;
    }
  }

  /// 5. Start Capture
  Future<int> startCapture({required int quality, required int timeout}) async {
    // Plugin expects (timeOut, minQuality)
    return await MethodChannelMorfinAuth.StartCapture(timeout, quality);
  }

  /// 6. Stop Capture
  Future<int> stopCapture() async {
    return await MethodChannelMorfinAuth.StopCature();
  }

  /// 7. Get Template (Fingerprint Data)
  /// Call this AFTER 'onCaptureComplete' signals success.
  /// [templateType]: 0 = FMR_V2005, 1 = FMR_V2011 (Standard), 2 = ANSI
  Future<Uint8List?> getTemplate(int templateType) async {
    try {
      // The native method requires a buffer to be passed, even if we grab Base64 later.
      int size = 20000;
      Uint8List buffer = Uint8List(size);

      // 1. Call Native GetTemplate to populate internal state
      int ret = await MethodChannelMorfinAuth.GetTemplate(buffer, size, templateType);

      if (ret == 0) {
        // 2. Fetch the clean Base64 string from Native
        String base64 = await MethodChannelMorfinAuth.GetTemplateBase64();
        return _cleanAndDecodeBase64(base64);
      }
    } catch (e) {
      print("Error getting template: $e");
    }
    return null;
  }

  /// 8. Get Image (Visual Bitmap)
  /// Call this AFTER 'onCaptureComplete' signals success.
  /// [imageType]: 0 = BMP, 1 = JPEG2000, 2 = WSQ
  Future<Uint8List?> getImage(int imageType) async {
    try {
      int size = 500000; // Large buffer for images
      Uint8List buffer = Uint8List(size);

      // compressionRatio 10 is standard
      int ret = await MethodChannelMorfinAuth.GetImage(buffer, size, 10, imageType);

      if (ret == 0) {
        String base64 = await MethodChannelMorfinAuth.GetImageBase64();
        return _cleanAndDecodeBase64(base64);
      }
    } catch (e) {
      print("Error getting image: $e");
    }
    return null;
  }

  /// 9. Match Template (1:1 Verification)
  /// Returns a Match Score (0-100+). Usually > 96 is a match.
  Future<int> matchTemplates({
    required Uint8List liveTemplate,
    required Uint8List storedTemplate,
  }) async {
    try {
      List<int> scoreHolder = [0]; // Helper list for native side

      // Native Match call
      int ret = await MethodChannelMorfinAuth.MatchTemplate(
          liveTemplate,
          storedTemplate,
          scoreHolder,
          1 // FMR_V2011
      );

      if (ret >= 0) {
        // Retrieve the score stored in the native variable
        return await MethodChannelMorfinAuth.GetMatchScore();
      }
    } catch (e) {
      print("Match error: $e");
    }
    return 0;
  }

  // --- Internal Helper Methods ---

  void _handleDeviceDetection(dynamic arguments) {
    if (arguments is String) {
      // Format: "DeviceName,STATUS" (e.g. "MFS100,CONNECTED")
      List<String> parts = arguments.split(',');
      if (parts.length >= 2) {
        String name = parts[0];
        String status = parts[1];
        bool isConnected = (status == "CONNECTED");
        onDeviceChanged?.call(name, isConnected);
      }
    }
  }

  void _handleCaptureComplete(dynamic arguments) {
    if (arguments is String) {
      // Format: "ErrorCode,Quality,NFIQ,Base64Image"
      List<String> parts = arguments.split(',');
      if (parts.length >= 3) {
        int errorCode = int.tryParse(parts[0]) ?? -1;
        int quality = int.tryParse(parts[1]) ?? 0;
        int nfiq = int.tryParse(parts[2]) ?? 0;

        Uint8List? imgBytes;
        // If there's an image string attached (index 3)
        if (parts.length > 3 && parts[3].isNotEmpty) {
          imgBytes = _cleanAndDecodeBase64(parts[3]);
        }

        onCaptureComplete?.call(errorCode, quality, nfiq, imgBytes);
      }
    }
  }

  void _handlePreview(dynamic arguments) {
    if (arguments is String) {
      // Format: "ErrorCode,Quality,Base64Image"
      List<String> parts = arguments.split(',');
      if (parts.length >= 3) {
        int errorCode = int.tryParse(parts[0]) ?? -1;
        int quality = int.tryParse(parts[1]) ?? 0;
        Uint8List? imgBytes = _cleanAndDecodeBase64(parts[2]);

        onLivePreview?.call(errorCode, quality, imgBytes);
      }
    }
  }

  Uint8List? _cleanAndDecodeBase64(String base64Str) {
    try {
      // Remove newlines or whitespace that might break the decoder
      String clean = base64Str.replaceAll(RegExp(r'\s+'), '');
      return base64Decode(clean);
    } catch (e) {
      return null;
    }
  }
}