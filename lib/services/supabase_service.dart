import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  static SupabaseService get instance => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://kwvocuwougbupmqwwhzd.supabase.co',
      publishableKey: 'sb_publishable_0bZ8zCP9FMSBYuTcpAveIA_lT1sFcAn',
    );
  }
}
