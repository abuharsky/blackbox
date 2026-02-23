import 'package:blackbox_example/sample_list.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPrefsStore.preload();
  runApp(MaterialApp(
    home: SampleList(),
  ));
}
