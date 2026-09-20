import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/repository_path_io.dart';

void main() {
  test('原生库文件置于 Application Support 的非隐藏目录', () async {
    final support = Directory.systemTemp.createTempSync('marginal-support');
    addTearDown(() => support.delete(recursive: true));

    final path = await defaultJsonPath(
      applicationSupportDirectory: () async => support,
    );

    expect(
      path,
      '${support.path}${Platform.pathSeparator}marginal${Platform.pathSeparator}library.json',
    );
    expect(path, isNot(startsWith('.marginal')));
  });
}
