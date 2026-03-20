import 'package:blackbox/blackbox.dart';
import 'package:blackbox_example/account_auth_profile_async/json_codec.dart';
import 'package:blackbox_example/sample_list.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPrefsStore.preload();

  BlackboxPersistence.init(
    SharedPrefsStore.instance,
    codecs: const [
      SessionJsonCodec(),
      ServiceJsonCodec(),
    ],
  );

  runApp(MaterialApp(
    home: SampleList(),
  ));
}
