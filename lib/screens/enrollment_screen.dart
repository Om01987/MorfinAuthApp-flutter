import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../providers/app_state_provider.dart';
import '../database/database_helper.dart';
import '../utils/file_utils.dart';

class EnrollmentScreen extends StatefulWidget {
  @override
  _EnrollmentScreenState createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final TextEditingController _nameController = TextEditingController();

  // State
  String status = "Select a finger to start capture";
  bool isCapturing = false;
  String currentFinger = "";
  Uint8List? livePreviewImage;

  // Data Store
  Map<String, Uint8List> capturedTemplates = {};
  Map<String, Uint8List> capturedImages = {};
  Map<String, String> fingerQualities = {};

  @override
  void dispose() {
    // FIX 1: Safe Dispose Logic
    // We wrap this in a try-catch because sometimes the context is already invalid
    // if the app is shutting down fast.
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);

      // Kill the listeners IMMEDIATELY so no more UI updates try to run
      appState.service.onLivePreview = null;
      appState.service.onCaptureComplete = null;

      // CRITICAL FIX: Only tell the hardware to stop if it is actually connected.
      // If isConnected is false, the device is gone, so calling StopCapture would crash the app.
      if (isCapturing && appState.isConnected) {
        appState.service.stopCapture();
      }
    } catch (e) {
      print("Safe Dispose Error: $e");
    }

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    service.onLivePreview = (errorCode, quality, image) {
      if (mounted && image != null) {
        setState(() {
          livePreviewImage = image;
          status = "Quality: $quality";
        });
      }
    };

    service.onCaptureComplete = (errorCode, quality, nfiq, image) async {
      if (!mounted) return;

      if (errorCode == 0) {
        setState(() => status = "Processing...");
        Uint8List? finalImg = await service.getImage(0); // 0 = BMP
        Uint8List? template = await service.getTemplate(1); // 1 = FMR_V2011

        if (finalImg != null && template != null) {
          setState(() {
            capturedImages[currentFinger] = finalImg;
            capturedTemplates[currentFinger] = template;
            fingerQualities[currentFinger] = "Q:$quality N:$nfiq";
            livePreviewImage = null;
            isCapturing = false;
            status = "Capture Success!";
          });
        } else {
          setState(() {
            isCapturing = false;
            status = "Failed to process data";
          });
        }
      } else {
        setState(() {
          isCapturing = false;
          status = "Capture Failed: Error $errorCode";
        });
      }
    };
  }

  Future<void> _startCapture(String fingerKey) async {
    // 1. Safety Check: Don't start if already capturing
    if (isCapturing) return;

    // 2. Safety Check: Don't start if device is disconnected
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (!appState.isConnected) {
      Fluttertoast.showToast(msg: "Device is disconnected!");
      return;
    }

    setState(() {
      currentFinger = fingerKey;
      isCapturing = true;
      livePreviewImage = null;
      status = "Initializing Sensor...";
    });

    final service = appState.service;
    await service.stopCapture();
    await Future.delayed(Duration(milliseconds: 200));

    if (!mounted) return;
    setState(() => status = "Place finger on sensor...");

    int ret = await service.startCapture(quality: 60, timeout: 10000);
    if (ret != 0) {
      if (mounted) {
        setState(() {
          isCapturing = false;
          status = "Failed to start: $ret";
        });
      }
    }
  }

  Future<void> _handleStop() async {
    final service = Provider.of<AppStateProvider>(context, listen: false).service;
    await service.stopCapture();
    if (mounted) {
      setState(() {
        isCapturing = false;
        status = "Capture Stopped";
      });
    }
  }

  Future<void> _handleReset() async {
    if (isCapturing) await _handleStop();
    setState(() {
      capturedTemplates.clear();
      capturedImages.clear();
      fingerQualities.clear();
      currentFinger = "";
      status = "Reset Complete";
    });
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: "Please enter a name");
      return;
    }
    if (capturedTemplates.isEmpty) {
      Fluttertoast.showToast(msg: "Capture at least one finger");
      return;
    }

    try {
      Map<String, dynamic> userMap = {};
      capturedTemplates.forEach((key, value) {
        userMap[key] = base64Encode(value);
      });

      int userId = await DatabaseHelper.instance.addUser(_nameController.text, userMap);

      if (userId > 0) {
        await FileUtils.requestStoragePermission();
        for (var entry in capturedImages.entries) {
          await FileUtils.saveUserFingerImage(userId, entry.key, entry.value);
        }
        Fluttertoast.showToast(msg: "User Enrolled! ID: $userId");
        if (mounted) Navigator.pop(context);
      } else {
        Fluttertoast.showToast(msg: "Database Error");
      }
    } catch (e) {
      print(e);
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Listen to the AppState (Brain)
    final appState = Provider.of<AppStateProvider>(context);

    // 2. FIX 2: Security Check with Safe Navigation
    // If the brain says "Disconnected", kick the user out safely.
    if (!appState.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 'mounted' check is crucial. It prevents popping if we are already gone.
        if (mounted) {
          // Use popUntil to go back to the FIRST screen (Home)
          // This prevents "Black Screen" issues if you pop the last route.
          Navigator.of(context).popUntil((route) => route.isFirst);
          Fluttertoast.showToast(msg: "Device disconnected");
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text("New Enrollment"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 1),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "User Name",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHandSection("Left Hand", ["left_little", "left_ring", "left_middle", "left_index", "left_thumb"]),
                  SizedBox(height: 20),
                  _buildHandSection("Right Hand", ["right_thumb", "right_index", "right_middle", "right_ring", "right_little"]),
                  SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isCapturing ? Colors.red[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isCapturing ? Colors.red : Colors.grey),
                    ),
                    child: Column(
                      children: [
                        Text(status, style: TextStyle(fontWeight: FontWeight.bold, color: isCapturing ? Colors.red : Colors.black)),
                        if (isCapturing && livePreviewImage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Image.memory(livePreviewImage!, height: 100, gaplessPlayback: true),
                          )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                if (isCapturing)
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _handleStop,
                      child: Text("STOP"),
                    ),
                  )
                else ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _handleReset,
                      child: Text("RESET"),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF0F172A), padding: EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _handleSave,
                      child: Text("SAVE"),
                    ),
                  ),
                ]
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHandSection(String title, List<String> fingerKeys) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: fingerKeys.map((key) => _buildFingerItem(key)).toList(),
        ),
      ],
    );
  }

  Widget _buildFingerItem(String key) {
    String label = key.split('_')[1];
    label = label[0].toUpperCase() + label.substring(1);

    bool isSelected = (currentFinger == key);
    bool hasData = capturedTemplates.containsKey(key);

    Color borderColor = Colors.grey.shade300;
    double borderWidth = 1.0;

    if (hasData) {
      borderColor = Colors.green;
      borderWidth = 2.0;
    } else if (isSelected) {
      borderColor = Colors.blue;
      borderWidth = 2.0;
    }

    Widget content;
    if (hasData) {
      content = Image.memory(capturedImages[key]!, height: 40, width: 30, fit: BoxFit.contain);
    } else {
      content = Icon(Icons.fingerprint, color: Colors.blue, size: 36);
    }

    return GestureDetector(
      onTap: () => _startCapture(key),
      child: Container(
        width: 60,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
            SizedBox(height: 5),
            content,
            SizedBox(height: 4),
            Text(
              hasData ? fingerQualities[key]! : "-",
              style: TextStyle(fontSize: 8, color: hasData ? Colors.green : Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}