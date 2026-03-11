import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/client.dart';

import 'sample_list.dart';

Future<void> main() async {
  Jaspr.initializeApp();
  await LocalStorageStore.preload();
  runApp(const SampleList());
}
