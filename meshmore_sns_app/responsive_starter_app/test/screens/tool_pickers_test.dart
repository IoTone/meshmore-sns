// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshmore_sns_app/meshcore/discovered_node.dart';
import 'package:meshmore_sns_app/screens/tools/tool_pickers.dart';

/// The tool pickers list every synced contact, which on a full radio is a
/// couple of hundred rows. Two rules are pinned here: the filter, and the shape
/// of the sheet.
void main() {
  DiscoveredNode node(String name, String key) => DiscoveredNode(
        pubKeyHex: key,
        name: name,
        type: 1,
        lastHeardUnix: 0,
        viaAdvert: true,
      );

  final List<DiscoveredNode> nodes = <DiscoveredNode>[
    node('HELTEC-BASE', '615f43aa11'),
    node('K0EHR T-Deck', 'eacc4412bb'),
    node('WIOld', '26f6071fcc'),
  ];

  group('the contact filter', () {
    test('an empty query keeps every row', () {
      expect(filterContacts(nodes, ''), nodes);
      expect(filterContacts(nodes, '   '), nodes);
    });

    test('a name matches anywhere in it, ignoring case', () {
      expect(filterContacts(nodes, 't-deck').single.name, 'K0EHR T-Deck');
      expect(filterContacts(nodes, 'heltec').single.name, 'HELTEC-BASE');
    });

    test('a key matches from its start only, because that is what a user reads',
        () {
      expect(filterContacts(nodes, '26f6').single.name, 'WIOld');
      expect(filterContacts(nodes, '6071'), isEmpty,
          reason: 'a prefix read off another screen is at the start');
    });

    test('a query matching nothing is an empty list, not every row', () {
      expect(filterContacts(nodes, 'zzzz'), isEmpty);
    });
  });

  test('the picker sheet is one shrink-wrapped list', () {
    // Measured on the handset: a Column with an Expanded or Flexible list inside
    // this sheet lays out taller than the sheet's own box, so the rows are
    // painted where nothing can tap them and choosing a contact appears to do
    // nothing at all. `showMmPicker` already proved the working shape, so the
    // sheet is held to it here rather than by a screenshot.
    final String src =
        File('lib/screens/tools/tool_pickers.dart').readAsStringSync();
    final String sheet = src.substring(src.indexOf('class ContactPickerSheet'));
    expect(sheet.contains('shrinkWrap: true'), isTrue,
        reason: 'the list sizes to its content and scrolls inside the sheet');
    expect(sheet.contains('Expanded('), isFalse,
        reason: 'an Expanded list inside the sheet is the broken shape');
    expect(sheet.contains('Flexible('), isFalse,
        reason: 'a Flexible list inside the sheet is the broken shape');
  });
}
