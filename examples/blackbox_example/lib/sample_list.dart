import 'package:blackbox_example/account_auth_profile_async/ui/services_page.dart';
import 'package:blackbox_example/counter_sync_async/counter_root.dart';
import 'package:flutter/material.dart';

class SampleList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Select sample"),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text("Simple counter (Sync + Async)"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CounterRoot(),
                ),
              );
            },
          ),
          //
          ListTile(
            title: Text("Account + Auth + Profile (ASYNC)"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ServicesPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
