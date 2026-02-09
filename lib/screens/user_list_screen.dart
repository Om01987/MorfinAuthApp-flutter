import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../database/database_helper.dart';
import '../utils/file_utils.dart';

class UserListScreen extends StatefulWidget {
  @override
  _UserListScreenState createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<Map<String, dynamic>> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    final data = await DatabaseHelper.instance.getAllUsersLite();
    setState(() {
      users = data;
      isLoading = false;
    });
  }

  // --- Update Name Logic ---
  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    TextEditingController _controller = TextEditingController(text: user['user_name']);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Edit User Name"),
        content: TextField(
          controller: _controller,
          decoration: InputDecoration(labelText: "Name", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (_controller.text.isNotEmpty) {
                await DatabaseHelper.instance.updateUserName(user['id'], _controller.text);
                Navigator.pop(ctx);
                _fetchUsers();
                Fluttertoast.showToast(msg: "Name Updated");
              }
            },
            child: Text("UPDATE"),
          )
        ],
      ),
    );
  }

  // --- Delete Logic ---
  Future<void> _deleteUser(int id) async {
    // 1. Delete from DB
    await DatabaseHelper.instance.deleteUser(id);

    // 2. Delete from File System
    await FileUtils.deleteUserFolder(id);

    _fetchUsers();
    Fluttertoast.showToast(msg: "User Deleted");
  }

  Future<void> _confirmDelete(int id, String name) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete User?"),
        content: Text("Are you sure you want to delete '$name'?\nThis cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteUser(id);
            },
            child: Text("DELETE", style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Registered Users"), backgroundColor: Color(0xFF0F172A), foregroundColor: Colors.white),
      backgroundColor: Color(0xFFF1F5F9),
      body: Column(
        children: [
          // --- Table Header ---
          Container(
            padding: EdgeInsets.symmetric(vertical: 15, horizontal: 10),
            color: Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text("ID", style: _headerStyle)),
                Expanded(flex: 3, child: Text("Name", style: _headerStyle)),
                Expanded(flex: 2, child: Text("Action", style: _headerStyle, textAlign: TextAlign.center)),
              ],
            ),
          ),

          // --- User List ---
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : users.isEmpty
                ? Center(child: Text("No users found", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                final isEven = index % 2 == 0;

                return Container(
                  color: isEven ? Colors.white : Colors.grey[50],
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: Text("${user['id']}", style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text("${user['user_name']}", style: TextStyle(fontSize: 16))),
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Edit Button
                            InkWell(
                              onTap: () => _showEditDialog(user),
                              child: Container(
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                                child: Icon(Icons.edit, size: 18, color: Colors.blue),
                              ),
                            ),
                            SizedBox(width: 15),
                            // Delete Button
                            InkWell(
                              onTap: () => _confirmDelete(user['id'], user['user_name']),
                              child: Container(
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                                child: Icon(Icons.delete, size: 18, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  TextStyle get _headerStyle => TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14);
}