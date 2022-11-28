import 'package:openapi/api.dart';

class ApiService {
  late ApiClient _apiClient;

  late UserApi userApi;
  late AuthenticationApi authenticationApi;
  late OAuthApi oAuthApi;
  late AlbumApi albumApi;
  late AssetApi assetApi;
  late ServerInfoApi serverInfoApi;
  late DeviceInfoApi deviceInfoApi;

  String? _authToken;

  setEndpoint(String endpoint) {
    _apiClient = ApiClient(basePath: endpoint);
    if (_authToken != null) {
      setAccessToken(_authToken!);
    }
    userApi = UserApi(_apiClient);
    authenticationApi = AuthenticationApi(_apiClient);
    oAuthApi = OAuthApi(_apiClient);
    albumApi = AlbumApi(_apiClient);
    assetApi = AssetApi(_apiClient);
    serverInfoApi = ServerInfoApi(_apiClient);
    deviceInfoApi = DeviceInfoApi(_apiClient);
  }

  setAccessToken(String accessToken) {
    _authToken = accessToken;
    _apiClient.addDefaultHeader('Authorization', 'Bearer $accessToken');
  }

  ApiClient get apiClient => _apiClient;
}
