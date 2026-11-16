import 'dart:io';

import 'package:dio/dio.dart';

import '../../data/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code = 'UNKNOWN', this.statusCode});
  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => message;
}

class OfflineException extends ApiException {
  OfflineException([String message = '无法连接服务器，请检查网络与接口地址']) : super(message);
}

class AuthRequiredException extends ApiException {
  AuthRequiredException([String message = '需要登录后访问'])
      : super(message, code: 'AUTH_REQUIRED', statusCode: 401);
}

class ApiClient {
  ApiClient({required String baseUrl, String? token, String? deviceId})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 120),
          headers: {
            'Accept': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            'X-Device-ID': deviceId ?? 'mobile',
          },
        ));

  final Dio _dio;
  String get baseUrl => _dio.options.baseUrl;

  String absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final origin = Uri.parse(baseUrl).origin;
    return '$origin$path';
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _request(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? data, Map<String, dynamic>? query}) =>
      _request(() => _dio.post<dynamic>(path, data: data, queryParameters: query));

  Future<dynamic> put(String path, {Object? data}) =>
      _request(() => _dio.put<dynamic>(path, data: data));

  Future<dynamic> delete(String path) => _request(() => _dio.delete<dynamic>(path));

  Future<dynamic> _request(Future<Response<dynamic>> Function() send) async {
    try {
      final response = await send();
      final body = response.data;
      if (body is Map && body['success'] == false) {
        final error = body['error'];
        throw ApiException(
          error is Map ? (error['message'] as String? ?? '请求失败') : '请求失败',
          code: error is Map ? (error['code'] as String? ?? 'UNKNOWN') : 'UNKNOWN',
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body.containsKey('data')) return body['data'];
      return body;
    } on DioException catch (error) {
      final response = error.response;
      final body = response?.data;
      if (body is Map && body['error'] is Map) {
        final detail = body['error'] as Map;
        final message = detail['message'] as String? ?? '请求失败';
        if (response?.statusCode == 401) {
          throw AuthRequiredException(message);
        }
        throw ApiException(message, code: detail['code'] as String? ?? 'UNKNOWN', statusCode: response?.statusCode);
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.error is SocketException) {
        throw OfflineException();
      }
      if (response?.statusCode == 401) throw AuthRequiredException();
      throw ApiException(
        response == null
            ? '网络请求失败：${error.message ?? '未知错误'}'
            : '请求失败（状态码 ${response.statusCode}）',
        statusCode: response?.statusCode,
      );
    }
  }

  Future<bool> health() async {
    try {
      final data = await _dio.get<dynamic>('/system/health',
          options: Options(receiveTimeout: const Duration(seconds: 4)));
      final body = data.data;
      return body is Map && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> info() async {
    final data = await get('/system/info');
    return (data as Map).cast<String, dynamic>();
  }

  Future<AuthResult> login(String username, String password) async {
    final data = await post('/auth/login', data: {'username': username, 'password': password});
    return AuthResult.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<AuthResult> register(String username, String password, String displayName) async {
    final data = await post('/auth/register', data: {
      'username': username,
      'password': password,
      'display_name': displayName,
    });
    return AuthResult.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> registerDevice({
    required String deviceId,
    required String name,
    required String platform,
    String? appVersion,
  }) async {
    await post('/devices/register', data: {
      'name': name,
      'platform': platform,
      'fingerprint': deviceId,
      'app_version': appVersion,
    });
  }

  Future<List<Book>> books({String? query}) async {
    final data = await get('/books', query: {
      if (query != null && query.isNotEmpty) 'q': query,
      'page': 1,
      'page_size': 100,
    });
    final items = (data as Map)['items'] as List? ?? const [];
    return items.whereType<Map>().map((e) => Book.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<Book> book(String bookId) async {
    final data = await get('/books/$bookId');
    return Book.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<ChapterSummary>> chapters(String bookId) async {
    final data = await get('/books/$bookId/chapters');
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => ChapterSummary.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ChapterContent> chapterContent(String chapterId) async {
    final data = await get('/chapters/$chapterId/content');
    return ChapterContent.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<TranslationStatus> translationStatus(String chapterId) async {
    final data = await get('/chapters/$chapterId/translation-status');
    return TranslationStatus.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<TaskInfo> translateChapter(String chapterId, {bool retranslate = false}) async {
    final data = await post('/translations/chapter/$chapterId', data: {'retranslate': retranslate});
    return TaskInfo.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<TaskInfo> task(String taskId) async {
    final data = await get('/tasks/$taskId');
    return TaskInfo.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<TaskInfo>> tasks() async {
    final data = await get('/tasks', query: {'page': 1, 'page_size': 100});
    final items = (data as Map)['items'] as List? ?? const [];
    return items.whereType<Map>().map((e) => TaskInfo.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<TaskInfo> cancelTask(String taskId) async {
    final data = await post('/tasks/$taskId/cancel');
    return TaskInfo.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Map<String, dynamic>> saveProgress({
    required String bookId,
    required String deviceId,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    required double positionRatio,
  }) async {
    final data = await put('/reading-progress', data: {
      'book_id': bookId,
      'device_id': deviceId,
      'chapter_id': chapterId,
      'paragraph_id': paragraphId,
      'sentence_id': sentenceId,
      'position_ratio': positionRatio.clamp(0, 1),
    });
    return (data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> progress(String bookId, String deviceId) async {
    final data = await get('/reading-progress/$bookId', query: {'device_id': deviceId});
    if (data is Map && data['progress'] is Map) {
      return (data['progress'] as Map).cast<String, dynamic>();
    }
    return null;
  }

  Future<List<Annotation>> annotations({String? bookId}) async {
    final data = await get('/annotations', query: {
      if (bookId != null) 'book_id': bookId,
      'page_size': 500,
    });
    final items = (data as Map)['items'] as List? ?? const [];
    return items.whereType<Map>().map((e) => Annotation.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<Annotation> createAnnotation(Map<String, dynamic> payload) async {
    final data = await post('/annotations', data: payload);
    return Annotation.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> deleteAnnotation(String id) async {
    await delete('/annotations/$id');
  }

  Future<List<Bookmark>> bookmarks({String? bookId}) async {
    final data = await get('/bookmarks', query: {if (bookId != null) 'book_id': bookId});
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => Bookmark.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Bookmark> createBookmark(Map<String, dynamic> payload) async {
    final data = await post('/bookmarks', data: payload);
    return Bookmark.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> deleteBookmark(String id) async {
    await delete('/bookmarks/$id');
  }

  Future<Book> importBook({
    required String filename,
    required List<int> bytes,
    String? title,
    String? author,
    String? dynasty,
    String? category,
    String? tags,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (title != null && title.isNotEmpty) 'title': title,
      if (author != null && author.isNotEmpty) 'author': author,
      if (dynasty != null && dynasty.isNotEmpty) 'dynasty': dynasty,
      if (category != null && category.isNotEmpty) 'category': category,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    });
    final data = await post('/books/import', data: form);
    return Book.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<HistoricalEntity>> entities({String? query}) async {
    final data = await get('/entities', query: {
      if (query != null && query.isNotEmpty) 'q': query,
      'page_size': 100,
    });
    final items = (data as Map)['items'] as List? ?? const [];
    return items.whereType<Map>().map((e) => HistoricalEntity.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<HistoricalEntity> entity(String id) async {
    final data = await get('/entities/$id');
    return HistoricalEntity.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<HistoricalEvent>> events({String? query}) async {
    final data = await get('/events', query: {
      if (query != null && query.isNotEmpty) 'q': query,
      'page_size': 100,
    });
    final items = (data as Map)['items'] as List? ?? const [];
    return items.whereType<Map>().map((e) => HistoricalEvent.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<HistoricalEvent> event(String id) async {
    final data = await get('/events/$id');
    return HistoricalEvent.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<AssistantAnswer> assistant({
    required String question,
    String? bookId,
    String? chapterId,
    String? paragraphId,
    String? sentenceId,
    String? sessionId,
  }) async {
    final data = await post('/assistant/chat', data: {
      'question': question,
      'book_id': bookId,
      'chapter_id': chapterId,
      'paragraph_id': paragraphId,
      'sentence_id': sentenceId,
      'session_id': sessionId,
    });
    return AssistantAnswer.fromJson((data as Map).cast<String, dynamic>());
  }
}

class AuthResult {
  const AuthResult({required this.token, required this.username, this.displayName});
  final String token;
  final String username;
  final String? displayName;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AuthResult(
      token: json['token'] as String? ?? '',
      username: user['username'] as String? ?? '',
      displayName: user['display_name'] as String?,
    );
  }
}
