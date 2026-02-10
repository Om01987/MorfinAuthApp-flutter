import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../providers/app_state_provider.dart';
import '../database/database_helper.dart';

class MatchingScreen extends StatefulWidget {
  @override
  _MatchingScreenState createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  // UI State
  String status = "Ready to Match";
  Color statusColor = Colors.grey;
  bool isScanning = false;
  bool stopScanning = false;
  Uint8List? livePreviewImage;

  // Data
  List<Map<String, dynamic>> matchedResults = [];

  // Database Columns
  final List<String> fingerColumns = [
    'left_thumb', 'left_index', 'left_middle', 'left_ring', 'left_little',
    'right_thumb', 'right_index', 'right_middle', 'right_ring', 'right_little'
  ];

  Timer? _debounceTimer; // To throttle preview updates if needed

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  @override
  void dispose() {
    stopScanning = true;
    _debounceTimer?.cancel();
    // Safety check: Only try to stop capture if provider/service is still valid
    if (mounted) {
      try {
        Provider.of<AppStateProvider>(context, listen: false).service.stopCapture();
      } catch (e) {
        print("Error stopping capture on dispose: $e");
      }
    }
    super.dispose();
  }

  void _setupListeners() {
    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // 1. Live Preview
    // We only update if we are actively scanning and haven't finished a capture yet.
    service.onLivePreview = (errorCode, quality, image) {
      if (mounted && image != null && isScanning) {
        setState(() {
          livePreviewImage = image;
          status = "Quality: $quality";
          statusColor = Colors.blue;
        });
      }
    };

    // 2. Capture Complete
    service.onCaptureComplete = (errorCode, quality, nfiq, image) async {
      if (!mounted || stopScanning) return;

      if (errorCode == 0) {
        setState(() => status = "Processing...");

        // Fetch Template & Image
        Uint8List? liveTemplate = await service.getTemplate(1); // FMR_V2011
        Uint8List? finalImg = await service.getImage(0); // BMP

        if (liveTemplate != null) {
          // Freeze the final image on screen
          if (finalImg != null) {
            setState(() => livePreviewImage = finalImg);
          }
          await _performMatching(liveTemplate);
        } else {
          // Template failed (bad capture?), treat as no-match cycle
          _handleResetCycle("Capture Error", false);
        }
      } else if (errorCode == -2019) {
        // Timeout -> Clear everything and retry immediately
        _handleTimeout();
      } else {
        // Other Errors -> Show error, wait, then retry
        _updateStatus("Error: $errorCode", Colors.red);
        // We do NOT clear list here, just retry
        Future.delayed(Duration(seconds: 2), () => _startCaptureLoop());
      }
    };
  }

  // --- Logic Control ---

  void _startScanningSession() {
    setState(() {
      stopScanning = false;
      isScanning = true;
      matchedResults.clear();
      livePreviewImage = null; // Reset to blue icon state
    });
    _startCaptureLoop();
  }

  void _stopScanningSession() async {
    setState(() {
      stopScanning = true;
      isScanning = false;
      status = "Scanning Stopped";
      statusColor = Colors.grey;
      livePreviewImage = null; // Reset to grey icon
    });
    final service = Provider.of<AppStateProvider>(context, listen: false).service;
    await service.stopCapture();
  }

  Future<void> _startCaptureLoop() async {
    if (stopScanning || !mounted) return;

    setState(() {
      status = "Place Finger...";
      statusColor = Colors.black;
      // CRITICAL CHANGE: We do NOT clear matchedResults here.
      // We only clear the list if it's a "Timeout" reset or a new session start.
      // We DO clear the preview to show the "Ready" state.
      livePreviewImage = null;
    });

    final service = Provider.of<AppStateProvider>(context, listen: false).service;

    // Stop previous capture to be safe
    await service.stopCapture();
    await Future.delayed(Duration(milliseconds: 100));

    // Start
    int ret = await service.startCapture(quality: 60, timeout: 10000);

    if (ret != 0) {
      _updateStatus("Start Failed: $ret", Colors.red);
      Future.delayed(Duration(seconds: 2), () => _startCaptureLoop());
    }
  }

  void _handleTimeout() {
    if (!mounted) return;
    print("Timeout - Resetting UI and Retrying");
    setState(() {
      matchedResults.clear(); // Clear list on Timeout
      livePreviewImage = null; // Clear image -> Show Blue/Grey Icon
      status = "Timeout. Retrying...";
      statusColor = Colors.orange;
    });
    _startCaptureLoop(); // Restart immediately
  }

  // --- Matching Logic ---

  Future<void> _performMatching(Uint8List liveTemplate) async {
    final service = Provider.of<AppStateProvider>(context, listen: false).service;
    List<Map<String, dynamic>> users = await DatabaseHelper.instance.getAllUsers();

    if (users.isEmpty) {
      _handleResetCycle("Database Empty", false);
      return;
    }

    // Clear previous matches for this new scan!
    // "if new successful capture happens and matching is to be done -> clear list"
    setState(() {
      matchedResults.clear();
    });

    int matchCount = 0;

    // Scan all users
    for (var user in users) {
      for (String fingerCol in fingerColumns) {
        String? b64Template = user[fingerCol];
        if (b64Template != null && b64Template.isNotEmpty) {
          try {
            Uint8List storedTemplate = base64Decode(b64Template);
            int score = await service.matchTemplates(
                liveTemplate: liveTemplate,
                storedTemplate: storedTemplate);

            if (score >= 96) {
              _addMatchResult(user['user_name'], user['id'], score);
              matchCount++;
              break; // Found this user, move to next user
            }
          } catch (e) {
            print("Match error: $e");
          }
        }
      }
    }

    if (matchCount > 0) {
      _handleResetCycle("Found $matchCount Matches", true);
    } else {
      _handleResetCycle("No Match Found", false);
    }
  }

  void _addMatchResult(String name, int id, int score) {
    setState(() {
      // Add to top of list
      matchedResults.insert(0, {
        'name': name,
        'id': id,
        'score': score,
        'time': DateTime.now().toString().substring(11, 19)
      });
    });
  }

  // Handles the "Show Result -> Wait 2s -> Reset" cycle
  void _handleResetCycle(String msg, bool isSuccess) {
    if (!mounted) return;

    setState(() {
      status = msg;
      statusColor = isSuccess ? Colors.green : Colors.red;
    });

    Future.delayed(Duration(seconds: 2), () {
      if (!stopScanning && mounted) {
        // We do NOT clear the list here.
        // Logic: matched result should stay until next successful capture starts matching logic
        _startCaptureLoop();
      }
    });
  }

  void _updateStatus(String msg, Color color) {
    if (mounted) setState(() {
      status = msg;
      statusColor = color;
    });
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    // 1. Listen to the AppState (Brain)
    final appState = Provider.of<AppStateProvider>(context);

    // 2. Safety Navigation (Copied from EnrollmentScreen)
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
      backgroundColor: Color(0xFFF5F5F5), // Light Grey bg like RN
      appBar: AppBar(
        title: Text("Biometric Match"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 1. Preview Section (Top Center)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 20),
            color: Colors.white,
            child: Column(
              children: [
                // Image Box
                Container(
                  width: 120,
                  height: 150,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: _buildPreviewContent(),
                ),
                SizedBox(height: 15),
                // Status Text
                Text(
                  status,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor),
                ),
              ],
            ),
          ),

          SizedBox(height: 10),

          // 2. Control Button
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                    isScanning ? Colors.red : Color(0xFF2196F3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 2),
                onPressed:
                isScanning ? _stopScanningSession : _startScanningSession,
                child: Text(
                  isScanning ? "STOP SCANNING" : "START MATCHING",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
              ),
            ),
          ),

          SizedBox(height: 10),

          // 3. Matched List
          Expanded(
            child: matchedResults.isEmpty
                ? (isScanning
                ? Center(
                child: Text("Place finger on sensor...",
                    style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic)))
                : SizedBox())
                : ListView.builder(
              padding: EdgeInsets.all(10),
              itemCount: matchedResults.length,
              itemBuilder: (context, index) {
                final item = matchedResults[index];
                return Container(
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 2,
                            offset: Offset(0, 1))
                      ]),
                  child: Row(
                    children: [
                      // Icon Box
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: Color(0xFFE8F5E9),
                            shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Icon(Icons.check,
                            color: Color(0xFF4CAF50), size: 24),
                      ),
                      SizedBox(width: 15),
                      // Name & ID
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'],
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                            Text("User ID: ${item['id']}",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      // Score
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("SCORE",
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold)),
                          Text("${item['score']}",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2196F3))),
                        ],
                      )
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (livePreviewImage != null) {
      return Image.memory(livePreviewImage!,
          fit: BoxFit.contain, gaplessPlayback: true);
    } else {
      // Placeholder Icon
      return Icon(Icons.fingerprint,
          size: 60,
          color: isScanning
              ? Colors.blue.withOpacity(0.5)
              : Colors.grey.withOpacity(0.5));
    }
  }
}