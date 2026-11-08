import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_emby/src/api/emby_live_tv_api.dart';
import 'package:server_jellyfin/src/api/jellyfin_live_tv_api.dart';

class _Capture extends Interceptor {
  RequestOptions? last;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler h) {
    last = options;
    h.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: {'Items': <dynamic>[], 'TotalRecordCount': 0},
    ));
  }
}

void main() {
  test('Jellyfin : la liste des chaînes ne demande pas le programme en cours', () async {
    final cap = _Capture();
    await JellyfinLiveTvApi(Dio()..interceptors.add(cap)).getChannels(fields: 'ImageTags,UserData');
    expect(cap.last!.path, '/LiveTv/Channels');
    expect(cap.last!.queryParameters['AddCurrentProgram'], false);
    expect(cap.last!.queryParameters['Fields'], 'ImageTags,UserData');
  });

  test('Emby : pareil', () async {
    final cap = _Capture();
    await EmbyLiveTvApi(Dio()..interceptors.add(cap)).getChannels();
    expect(cap.last!.queryParameters['AddCurrentProgram'], false);
  });
}
