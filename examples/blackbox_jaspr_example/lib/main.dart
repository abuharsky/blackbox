import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:blackbox_jaspr_example/account_auth_profile_async/json_codec.dart';
import 'package:jaspr/client.dart';

import 'sample_list.dart';

void main() {
  Jaspr.initializeApp();
  BlackboxPersistence.init(
    LocalStorageStore.instance,
    codecs: const [SessionJsonCodec(), ServiceJsonCodec()],
  );

  runApp(const SampleList());
}
