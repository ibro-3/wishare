import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wishare/core/crypto/certificate_manager.dart';
import 'package:wishare/core/network/mdns_responder.dart';

void main() {
  test('parses a PTR question and builds a DNS-SD response', () async {
    final identity = await CertificateManager.create(name: 'Test device');
    final query = BytesBuilder(copy: false)
      ..add(const [0x12, 0x34, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
      ..add(MDnsProtocol.encodeName(MDnsProtocol.serviceName))
      ..add(const [0, MDnsProtocol.ptr, 0, 1]);

    final question = MDnsProtocol.parseQuestion(query.takeBytes());
    expect(question, isNotNull);
    expect(question!.id, 0x1234);
    expect(question.name, MDnsProtocol.serviceName);
    expect(question.type, MDnsProtocol.ptr);
    expect(question.isWishareQuery, isTrue);

    final response = MDnsProtocol.buildResponse(
      question: question,
      ptrTarget: '${identity.id}.${MDnsProtocol.serviceName}',
      identity: identity,
      address: '192.168.1.20',
      port: 45821,
    );

    expect(response[2], 0x84); // response + authoritative
    expect((response[4] << 8) | response[5], 1); // questions
    expect((response[6] << 8) | response[7], 1); // answers
    expect((response[10] << 8) | response[11], 3); // SRV + TXT + A

    final text = utf8.decode(response, allowMalformed: true);
    expect(text, contains(identity.id));
    expect(text, contains('fp=${identity.fingerprint}'));
    expect(text, contains('port=45821'));
    expect(response, contains(0xC0)); // name compression pointer
    final ip = InternetAddress('192.168.1.20').rawAddress;
    expect(response.sublist(response.length - 4), ip);
  });

  test('ignores responses and unrelated questions', () {
    final responseHeader = Uint8List.fromList([
      0,
      1,
      0x84,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
    expect(MDnsProtocol.parseQuestion(responseHeader), isNull);

    final unrelated = BytesBuilder(copy: false)
      ..add(const [0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
      ..add(MDnsProtocol.encodeName('_http._tcp.local'))
      ..add(const [0, MDnsProtocol.ptr, 0, 1]);
    final question = MDnsProtocol.parseQuestion(unrelated.takeBytes());
    expect(question?.isWishareQuery, isFalse);
  });
}
