/// Yerel bildirimlerin `payload` biçimi (saf — bkz. test/hatirlatma_test.dart).
/// Dokununca açılacak sohbet: `sohbet:{chatId}:{karsiUid}`.
/// (uid'lerde ve chatId'de ':' bulunmaz: chatId = `{uid}_{uid}`.)
library;

String sohbetYuku(String chatId, String karsiUid) => 'sohbet:$chatId:$karsiUid';

({String chatId, String karsiUid})? sohbetYukuCoz(String? yuk) {
  if (yuk == null) return null;
  final p = yuk.split(':');
  if (p.length != 3 || p[0] != 'sohbet' || p[1].isEmpty || p[2].isEmpty) {
    return null;
  }
  return (chatId: p[1], karsiUid: p[2]);
}
