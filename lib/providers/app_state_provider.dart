import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/morfin_service.dart';
import '../database/database_helper.dart';

class AppStateProvider extends ChangeNotifier {
  final MorfinService service = MorfinService();

  bool isConnected = false;
  bool isInitialized = false;
  bool isBusy = false;

  String deviceName = "";
  Map<String, dynamic> deviceDetails = {
    'Make': '-', 'Model': '-', 'SerialNo': '-', 'Width': '-', 'Height': '-'
  };

  int userCount = 0;

  AppStateProvider() {
    _init();
  }

  void _init() {
    service.initializePlugin();
    service.onDeviceChanged = (name, connected) {
      isConnected = connected;
      deviceName = name;
      if (!connected) {
        isInitialized = false;
        deviceDetails = {'Make': '-', 'Model': '-', 'SerialNo': '-', 'Width': '-', 'Height': '-'};
      }
      notifyListeners();
    };
    refreshUserCount();
  }

  Future<void> refreshUserCount() async {
    userCount = await DatabaseHelper.instance.getUserCount();
    notifyListeners();
  }

  Future<void> initSdk() async {
    if (!isConnected) {
      Fluttertoast.showToast(msg: "Please connect a device first");
      return;
    }

    isBusy = true;
    notifyListeners();

    try {
      // 1. Init
      int ret = await service.initDevice(deviceName);

      if (ret == 0) {
        // 2. Get Info
        var info = await service.getDeviceInfo();
        if (info != null) {
          deviceDetails = info;
        }
        isInitialized = true;
        Fluttertoast.showToast(msg: "Device Initialized");
      } else {
        isInitialized = false;
        Fluttertoast.showToast(msg: "Init Failed: $ret");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Error: $e");
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> uninitSdk() async {
    isBusy = true;
    notifyListeners();

    await service.uninitDevice();

    isInitialized = false;
    deviceDetails = {'Make': '-', 'Model': '-', 'SerialNo': '-', 'Width': '-', 'Height': '-'};
    isBusy = false;

    Fluttertoast.showToast(msg: "Device Uninitialized");
    notifyListeners();
  }
}