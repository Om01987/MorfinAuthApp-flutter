import 'dart:convert'; // <--- ADDED THIS IMPORT
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

  // Data Store: Maps finger name (e.g., 'right_index') to its data
  Map<String, Uint8List> capturedTemplates = {};
  Map<String, Uint8List> capturedImages = {}; // For saving to file later
  Map<String, String> fingerQualities = {}; // Display string "Q:80 N:1"

  @override
  void dispose() {
    // Stop capture if user backs out
    if (isCapturing) {
      if (mounted) {
        Provider.of<AppStateProvider>(context, listen: false).service.stopCapture();
      }
    }
    // Clear callbacks to avoid leaks
    if (mounted) {
      var service = Provider.of<AppStateProvider>(context, listen: false).service;
      service.onLivePreview = null;
      service.onCaptureComplete = null;
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to safely access Provider after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // 1. Live Preview Listener
    service.onLivePreview = (errorCode, quality, image) {
      if (mounted && image != null) {
        setState(() {
          livePreviewImage = image;
          status = "Quality: $quality";
        });
      }
    };

    // 2. Capture Complete Listener
    service.onCaptureComplete = (errorCode, quality, nfiq, image) async {
      if (!mounted) return;

      if (errorCode == 0) {
        setState(() => status = "Processing...");

        // A. Get Final Image (BMP) for UI and File Storage
        // 0 = BMP
        Uint8List? finalImg = await service.getImage(0);

        // B. Get Template (FMR V2011) for Database
        // 1 = FMR_V2011
        Uint8List? template = await service.getTemplate(1);

        if (finalImg != null && template != null) {
          setState(() {
            // Store Data
            capturedImages[currentFinger] = finalImg;
            capturedTemplates[currentFinger] = template;
            fingerQualities[currentFinger] = "Q:$quality N:$nfiq";

            // Reset UI
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

  // --- Actions ---

  Future<void> _startCapture(String fingerKey) async {
    if (isCapturing) return;

    // Reset previous data for this finger
    setState(() {
      currentFinger = fingerKey;
      isCapturing = true;
      livePreviewImage = null;
      status = "Initializing Sensor...";
    });

    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // Stop any previous capture just in case
    await service.stopCapture();

    // Wait a bit, then start
    await Future.delayed(Duration(milliseconds: 200));

    if (!mounted) return;
    setState(() => status = "Place finger on sensor...");

    // 60 min quality, 10000ms timeout
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
      // 1. Prepare data for Database
      Map<String, dynamic> userMap = {};

      // Convert raw bytes to Base64 String so they can be stored in SQLite TEXT fields
      capturedTemplates.forEach((key, value) {
        userMap[key] = base64Encode(value);
      });

      // 2. Insert into DB
      int userId = await DatabaseHelper.instance.addUser(_nameController.text, userMap);

      if (userId > 0) {
        // 3. Save Images to File System
        await FileUtils.requestStoragePermission();

        for (var entry in capturedImages.entries) {
          await FileUtils.saveUserFingerImage(userId, entry.key, entry.value);
        }

        Fluttertoast.showToast(msg: "User Enrolled! ID: $userId");
        if (mounted) Navigator.pop(context); // Go back to Home
      } else {
        Fluttertoast.showToast(msg: "Database Error");
      }
    } catch (e) {
      print(e);
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  // --- UI Building Blocks ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("New Enrollment"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 1),
      body: Column(
        children: [
          // Name Input
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

                  // Status & Preview Box
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

          // Bottom Buttons
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
    if (hasData) borderColor = Colors.green;
    if (isSelected) borderColor = Colors.blue;

    return GestureDetector(
      onTap: () => _startCapture(key),
      child: Container(
        width: 60,
        height: 85,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor, width: (isSelected || hasData) ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
            SizedBox(height: 4),
            if (hasData)
              Image.memory(capturedImages[key]!, height: 40, width: 30, fit: BoxFit.contain)
            else
              Icon(Icons.fingerprint, color: isSelected ? Colors.blue : Colors.grey[300], size: 30),

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