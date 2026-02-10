import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../database/database_helper.dart';

class MatchingScreen extends StatefulWidget {
  @override
  _MatchingScreenState createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  // UI State
  String status = "Ready to Match";
  String resultText = "";
  Color statusColor = Colors.black;
  bool isScanning = false;
  Uint8List? livePreviewImage;

  // The list of column names in your DB representing fingers
  final List<String> fingerColumns = [
    'left_thumb', 'left_index', 'left_middle', 'left_ring', 'left_little',
    'right_thumb', 'right_index', 'right_middle', 'right_ring', 'right_little'
  ];

  @override
  void initState() {
    super.initState();
    // Setup listeners after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  @override
  void dispose() {
    // Stop capture if leaving screen
    if (isScanning) {
      if (mounted) {
        Provider.of<AppStateProvider>(context, listen: false).service.stopCapture();
      }
    }
    // Clean up listeners
    if (mounted) {
      var service = Provider.of<AppStateProvider>(context, listen: false).service;
      service.onLivePreview = null;
      service.onCaptureComplete = null;
    }
    super.dispose();
  }

  void _setupListeners() {
    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // 1. Live Preview
    service.onLivePreview = (errorCode, quality, image) {
      if (mounted && image != null) {
        setState(() {
          livePreviewImage = image;
          status = "Quality: $quality";
        });
      }
    };

    // 2. Capture Complete
    service.onCaptureComplete = (errorCode, quality, nfiq, image) async {
      if (!mounted) return;

      if (errorCode == 0) {
        setState(() => status = "Processing...");

        // Get the live template to match against DB
        // 1 = FMR_V2011 (Standard Template format)
        Uint8List? liveTemplate = await service.getTemplate(1);

        // Also get the image for display
        Uint8List? finalImg = await service.getImage(0);

        if (liveTemplate != null) {
          if (finalImg != null) {
            setState(() => livePreviewImage = finalImg);
          }
          // Start the 1:N Matching Loop
          await _perform1NMatching(liveTemplate);
        } else {
          _updateStatus("Template generation failed", Colors.red);
        }
      } else {
        _updateStatus("Capture Failed: $errorCode", Colors.red);
      }

      setState(() => isScanning = false);
    };
  }

  // Matching Logic (Cursor Style)
  Future<void> _perform1NMatching(Uint8List liveTemplate) async {
    setState(() {
      status = "Searching Database...";
      resultText = "";
    });

    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // 1. Fetch all users (Simulates getting the Cursor)
    List<Map<String, dynamic>> users = await DatabaseHelper.instance.getAllUsers();

    if (users.isEmpty) {
      _updateStatus("Database is empty", Colors.orange);
      return;
    }

    bool matchFound = false;
    int bestScore = 0;
    String matchedName = "";
    int matchedId = -1;

    // 2. Iterate through Users (Row by Row)
    for (var user in users) {
      // 3. Iterate through Fingers for this User
      for (String fingerCol in fingerColumns) {
        String? b64Template = user[fingerCol];

        if (b64Template != null && b64Template.isNotEmpty) {
          try {
            // Decode stored template
            Uint8List storedTemplate = base64Decode(b64Template);

            // Native Match Call
            int score = await service.matchTemplates(
                liveTemplate: liveTemplate,
                storedTemplate: storedTemplate
            );

            // Logic: Immediate stop on high match (Standard logic)
            if (score >= 96) {
              matchFound = true;
              bestScore = score;
              matchedName = user['user_name'];
              matchedId = user['id'];
              break; // Break finger loop
            }
          } catch (e) {
            print("Error matching $fingerCol for user ${user['id']}: $e");
          }
        }
      }
      if (matchFound) break; // Break user loop (Cursor stop)
    }

    // 4. Show Result
    if (matchFound) {
      _updateStatus("Match Found!", Colors.green);
      _showResultDialog(matchedName, matchedId, bestScore);
    } else {
      _updateStatus("No Match Found", Colors.red);
    }
  }

  // --- UI Actions ---

  Future<void> _startCapture() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      livePreviewImage = null;
      status = "Place Finger...";
      resultText = "";
      statusColor = Colors.black;
    });

    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // Safety stop
    await service.stopCapture();
    await Future.delayed(Duration(milliseconds: 200));

    // Start
    int ret = await service.startCapture(quality: 60, timeout: 10000);
    if (ret != 0) {
      _updateStatus("Failed to start scanner: $ret", Colors.red);
      setState(() => isScanning = false);
    }
  }

  void _updateStatus(String msg, Color color) {
    if (mounted) {
      setState(() {
        status = msg;
        statusColor = color;
      });
    }
  }

  void _showResultDialog(String name, int id, int score) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 50),
            SizedBox(height: 10),
            Text("Authentication Success"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("User: $name", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("ID: $id", style: TextStyle(fontSize: 16)),
            Divider(),
            Text("Match Score: $score", style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text("Identify User"),
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Preview Box
            Container(
              width: 160,
              height: 200,
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                      color: isScanning ? Colors.blue : (statusColor == Colors.green ? Colors.green : Colors.grey),
                      width: 2
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)]
              ),
              child: livePreviewImage != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(livePreviewImage!, fit: BoxFit.contain, gaplessPlayback: true),
              )
                  : Icon(Icons.fingerprint, size: 80, color: Colors.grey[300]),
            ),
            SizedBox(height: 20),

            // Status Text
            Text(
              status,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: statusColor
              ),
            ),
            SizedBox(height: 40),

            // Scan Button
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isScanning ? Colors.grey : Color(0xFF0EA5E9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: isScanning ? null : _startCapture,
                icon: isScanning
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(Icons.search, color: Colors.white),
                label: Text(
                  isScanning ? "SCANNING..." : "START MATCH",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}