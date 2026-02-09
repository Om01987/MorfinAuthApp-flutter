import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/app_state_provider.dart';
import '../database/database_helper.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Provider.of<AppStateProvider>(context, listen: false).refreshUserCount();

    final appState = Provider.of<AppStateProvider>(context);

    final Color headerBg = Color(0xFF0F172A);
    final Color statusGreen = Color(0xFF22C55E);
    final Color statusRed = Color(0xFFEF4444);
    final Color btnBlue = Color(0xFF0EA5E9);
    final Color btnGrey = Color(0xFF64748B);

    return Scaffold(
      backgroundColor: Color(0xFFF1F5F9),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Header ---
                Container(
                  color: headerBg,
                  padding: EdgeInsets.fromLTRB(24, 60, 24, 80),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("BIOMETRIC AUTH", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text("Dashboard", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Icon(Icons.fingerprint, size: 40, color: appState.isConnected ? statusGreen : statusRed)
                    ],
                  ),
                ),

                // --- Status Card ---
                Transform.translate(
                  offset: Offset(0, -50),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 20),
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: appState.isConnected ? statusGreen : statusRed, shape: BoxShape.circle)),
                            SizedBox(width: 8),
                            Text(
                              appState.isConnected ? "Device Connected (${appState.deviceName})" : "Device Disconnected",
                              style: TextStyle(color: appState.isConnected ? statusGreen : statusRed, fontWeight: FontWeight.bold),
                            )
                          ],
                        ),
                        Divider(height: 32),

                        _detailRow("Make", appState.deviceDetails['Make']),
                        _detailRow("Model", appState.deviceDetails['Model']),
                        _detailRow("Serial", appState.deviceDetails['SerialNo']),

                        _detailRow("W/H", appState.isInitialized
                            ? "${appState.deviceDetails['Width']}x${appState.deviceDetails['Height']}"
                            : "-"
                        ),
                        SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: btnBlue, padding: EdgeInsets.symmetric(vertical: 14)),
                                onPressed: (appState.isConnected && !appState.isInitialized && !appState.isBusy)
                                    ? () => appState.initSdk()
                                    : null,
                                child: appState.isBusy && !appState.isInitialized
                                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text("INIT DEVICE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: btnGrey, padding: EdgeInsets.symmetric(vertical: 14)),
                                onPressed: (appState.isInitialized && !appState.isBusy)
                                    ? () => appState.uninitSdk()
                                    : null,
                                child: appState.isBusy && appState.isInitialized
                                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text("UNINIT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),

                // --- Grid Cards ---
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _gridCard(
                        context,
                        "Capture", "Enroll New User", "👆", Color(0xFFE0F2FE),
                        enabled: appState.isInitialized,
                        onTap: () => Navigator.pushNamed(context, '/enroll'),
                      ),
                      SizedBox(width: 15),
                      _gridCard(
                        context,
                        "Match", "Identify Finger", "🔍", Color(0xFFDCFCE7),
                        enabled: appState.isInitialized,
                        onTap: () => Navigator.pushNamed(context, '/match'),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 30),

                // --- Data Management ---
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Data Management", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          Text("Users: ${appState.userCount}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF0F172A), padding: EdgeInsets.symmetric(vertical: 14)),
                              onPressed: () => Navigator.pushNamed(context, '/users'),
                              child: Text("LIST USERS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: statusRed, padding: EdgeInsets.symmetric(vertical: 14)),
                              onPressed: () => _showDeleteDialog(context, appState),
                              child: Text("DELETE DATA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 10,
            left: 20, right: 20,
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Color(0xFF334155), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)]),
              child: Text(
                appState.isInitialized ? "System Ready." : appState.isConnected ? "Device found! Press INIT." : "Please connect a supported device.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Colors.black, fontSize: 14),
          children: [
            TextSpan(text: "$label: ", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _gridCard(BuildContext context, String title, String subtitle, String icon, Color bg, {required bool enabled, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.6,
          child: Container(
            height: 150,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50, height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Text(icon, style: TextStyle(fontSize: 24)),
                ),
                SizedBox(height: 12),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- CHANGED: Standard Radio Buttons Logic ---
  void _showDeleteDialog(BuildContext context, AppStateProvider appState) {
    // 1. Define the selected value. Default to Option 1.
    int? _selectedValue = 1;

    showDialog(
      context: context,
      builder: (ctx) {
        // 2. Use StatefulBuilder to update radio selection inside Dialog
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Delete Data Options"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<int>(
                    title: Text("Clear Files"),
                    value: 1,
                    groupValue: _selectedValue,
                    onChanged: (int? val) {
                      setState(() => _selectedValue = val);
                    },
                  ),
                  RadioListTile<int>(
                    title: Text("Clear Database"),
                    value: 2,
                    groupValue: _selectedValue,
                    onChanged: (int? val) {
                      setState(() => _selectedValue = val);
                    },
                  ),
                  RadioListTile<int>(
                    title: Text("Clear Both"),
                    value: 3,
                    groupValue: _selectedValue,
                    onChanged: (int? val) {
                      setState(() => _selectedValue = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () async {
                    Navigator.pop(ctx);

                    // Logic based on selection
                    if (_selectedValue == 1 || _selectedValue == 3) {
                      await _deleteLocalFiles();
                    }
                    if (_selectedValue == 2 || _selectedValue == 3) {
                      await DatabaseHelper.instance.clearDatabase();
                    }

                    appState.refreshUserCount();
                  },
                  child: Text("DELETE", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteLocalFiles() async {
    try {
      final Directory? appDocDir = await getExternalStorageDirectory();
      final Directory rootDir = appDocDir ?? await getApplicationDocumentsDirectory();
      final Directory fingerDataDir = Directory('${rootDir.path}/FingerData');

      if (await fingerDataDir.exists()) {
        await fingerDataDir.delete(recursive: true);
        print("FingerData folder deleted.");
      }
    } catch (e) {
      print("Error deleting files: $e");
    }
  }
}