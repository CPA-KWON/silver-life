import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled growth models contain real 3D geometry and land after jumping',
    () async {
      final heights = <double>[];
      for (final stage in ['baby', 'junior', 'adult']) {
        final data = await rootBundle.load('assets/pet/models/$stage.glb');
        expect(data.getUint32(0, Endian.little), 0x46546c67);
        expect(data.getUint32(4, Endian.little), 2);
        expect(data.getUint32(8, Endian.little), data.lengthInBytes);
        final jsonLength = data.getUint32(12, Endian.little);
        final jsonBytes = data.buffer.asUint8List(
          data.offsetInBytes + 20,
          jsonLength,
        );
        final gltf = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
        // Self-contained means the APK does not depend on a remote model URL.
        expect((gltf['buffers'] as List).every((b) => b['uri'] == null), true);
        final primitives = (gltf['meshes'] as List).expand(
          (m) => m['primitives'] as List,
        );
        expect(primitives, isNotEmpty);
        for (final p in primitives) {
          final bounds = gltf['accessors'][p['attributes']['POSITION']];
          expect(bounds['max'][2] - bounds['min'][2], greaterThan(0));
          expect(p['attributes']['NORMAL'], isNotNull);
        }
        final animations = gltf['animations'] as List;
        expect(animations.map((a) => a['name']).toSet(), {
          'Idle',
          'Jump',
          'Walk',
          'Eat',
        });
        final jump = animations.singleWhere((a) => a['name'] == 'Jump');
        final channel = (jump['channels'] as List).singleWhere(
          (c) => c['target']['path'] == 'translation',
        );
        final output =
            gltf['accessors'][jump['samplers'][channel['sampler']]['output']];
        final view = gltf['bufferViews'][output['bufferView']];
        final binaryOffset = 20 + jsonLength + 8;
        final offset =
            binaryOffset +
            (view['byteOffset'] as int) +
            (output['byteOffset'] as int? ?? 0);
        final y = List.generate(
          output['count'] as int,
          (i) => data.getFloat32(offset + (i * 3 + 1) * 4, Endian.little),
        );
        expect(y.first, 0);
        expect(y.last, 0);
        expect(y.reduce((a, b) => a > b ? a : b), greaterThan(.2));
        final head = (gltf['nodes'] as List).singleWhere(
          (n) => n['name'] == 'HeadPivot',
        );
        heights.add((head['translation'][1] as num).toDouble());
        final materials = (gltf['materials'] as List)
            .map((m) => m['name'])
            .toSet();
        expect(
          materials.containsAll({'hat_pink', 'knit_green', 'flower_petal'}),
          true,
        );
      }
      expect(heights[0], lessThan(heights[1]));
      expect(heights[1], lessThan(heights[2]));
    },
  );
}
