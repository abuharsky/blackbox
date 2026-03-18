import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:blackbox_jaspr_example/account_auth_profile_async/boxes/models.dart';
import 'package:blackbox_jaspr_example/account_auth_profile_async/json_codec.dart';
import 'package:jaspr/client.dart';

import 'sample_list.dart';

Future<void> main() async {
  Jaspr.initializeApp();
  await LocalStorageStore.preload();

  BlackboxPersistence.registerCodec<Session?>(SessionJsonCodec());
  BlackboxPersistence.registerCodec<Service?>(ServiceJsonCodec());

  runApp(const SampleList());
}
