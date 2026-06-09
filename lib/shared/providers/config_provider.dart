import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_service.dart';
import '../models/configuration_model.dart';

final configProvider =
    FutureProvider.family<ChildConfiguration?, String>((ref, childId) {
  return getConfiguration(childId);
});
