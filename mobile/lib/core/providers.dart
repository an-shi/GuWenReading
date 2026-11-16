import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/local_database.dart';

/// Overridden in `main()` after opening the database.
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  throw UnimplementedError('localDatabaseProvider must be overridden');
});
