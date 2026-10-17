import 'dart:io';

import 'package:jni/jni.dart';

/// A selection for one destination, including Android's exclusion/PAC rules.
final class SystemProxySelection {
  const SystemProxySelection._(this.directive, this.httpProxy);

  static const direct = SystemProxySelection._('DIRECT', null);
  final String directive;
  final Uri? httpProxy;
  bool get isDirect => httpProxy == null;
}

/// Reads the live platform selector. No proxy address or route is cached.
SystemProxySelection systemProxyFor(Uri uri) {
  if (!Platform.isAndroid || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return SystemProxySelection.direct;
  }
  return _androidProxy.select(uri);
}

final _androidProxy = _AndroidProxySelector();

final class _AndroidProxySelector {
  final _selector = JClass.forName('java/net/ProxySelector');
  final _uri = JClass.forName('java/net/URI');
  final _list = JClass.forName('java/util/List');
  final _proxy = JClass.forName('java/net/Proxy');
  final _address = JClass.forName('java/net/InetSocketAddress');

  late final _getDefault = _selector.staticMethodId(
    'getDefault',
    '()Ljava/net/ProxySelector;',
  );
  late final _select = _selector.instanceMethodId(
    'select',
    '(Ljava/net/URI;)Ljava/util/List;',
  );
  late final _newUri = _uri.constructorId('(Ljava/lang/String;)V');
  late final _size = _list.instanceMethodId('size', '()I');
  late final _get = _list.instanceMethodId('get', '(I)Ljava/lang/Object;');
  late final _type = _proxy.instanceMethodId(
    'type',
    r'()Ljava/net/Proxy$Type;',
  );
  late final _socketAddress = _proxy.instanceMethodId(
    'address',
    '()Ljava/net/SocketAddress;',
  );
  late final _host = _address.instanceMethodId(
    'getHostString',
    '()Ljava/lang/String;',
  );
  late final _port = _address.instanceMethodId('getPort', '()I');

  SystemProxySelection select(Uri destination) => using((arena) {
    final selector = _getDefault.callNullable(_selector, JObject.type, []);
    if (selector == null) return SystemProxySelection.direct;
    selector.releasedBy(arena);
    final text = destination.toString().toJString()..releasedBy(arena);
    final uri = _newUri.call<JObject>(_uri, [text])..releasedBy(arena);
    final proxies = _select.call(selector, JObject.type, [uri])
      ..releasedBy(arena);
    final count = _size.call(proxies, jint.type, []);
    final directives = <String>[];
    Uri? selected;
    for (var index = 0; index < count; index++) {
      final proxy = _get.call(proxies, JObject.type, [JValueInt(index)])
        ..releasedBy(arena);
      final type = _type.call(proxy, JObject.type, [])..releasedBy(arena);
      final name = type.toString();
      if (name == 'DIRECT') {
        if (directives.isEmpty) return SystemProxySelection.direct;
        directives.add('DIRECT');
      } else if (name == 'HTTP') {
        final address = _socketAddress.call(proxy, JObject.type, [])
          ..releasedBy(arena);
        final host = _host
            .call(address, JString.type, [])
            .toDartString(releaseOriginal: true);
        final port = _port.call(address, jint.type, []);
        if (host.isEmpty || port < 1 || port > 65535) {
          throw const FormatException('Invalid Android system proxy');
        }
        final endpoint = Uri(scheme: 'http', host: host, port: port);
        selected ??= endpoint;
        directives.add('PROXY ${endpoint.authority}');
      } else {
        throw UnsupportedError('Android system proxy type: $name');
      }
    }
    return selected == null
        ? SystemProxySelection.direct
        : SystemProxySelection._(directives.join('; '), selected);
  });
}
