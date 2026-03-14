import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Offline-first data provider. All UI reads from this service.
/// Data is synced from Supabase on:
///   1. App launch
///   2. Push notification / change signal
///   3. Manual pull-to-refresh
class DataProvider extends ChangeNotifier {
  static final DataProvider _instance = DataProvider._internal();
  factory DataProvider() => _instance;
  DataProvider._internal();

  // ── Cached data ──────────────────────────────────────────────
  List<Map<String, dynamic>> _tricounts = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _tricountInvites = [];
  List<Map<String, dynamic>> _personalTransactions = [];
  List<Map<String, dynamic>> _personalBalances = [];
  List<Map<String, dynamic>> _users = [];

  // ── Public getters ───────────────────────────────────────────
  List<Map<String, dynamic>> get tricounts => _tricounts;
  List<Map<String, dynamic>> get expenses => _expenses;
  List<Map<String, dynamic>> get friends => _friends;
  List<Map<String, dynamic>> get friendRequests => _friendRequests;
  List<Map<String, dynamic>> get tricountInvites => _tricountInvites;
  List<Map<String, dynamic>> get personalTransactions => _personalTransactions;
  List<Map<String, dynamic>> get personalBalances => _personalBalances;
  List<Map<String, dynamic>> get users => _users;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _initialized = false;
  bool get initialized => _initialized;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  // ── Convenience getters ──────────────────────────────────────

  /// Tricounts the current user participates in (sorted newest first).
  List<Map<String, dynamic>> get myTricounts {
    final uid = _currentUserId;
    if (uid == null) return [];
    return _tricounts.where((t) {
      final pIds = List<dynamic>.from(t['participant_ids'] ?? []);
      return pIds.contains(uid);
    }).toList();
  }

  /// Expenses for a specific tricount (sorted newest first).
  List<Map<String, dynamic>> expensesForTricount(String tricountId) {
    return _expenses.where((e) => e['tricount_id'] == tricountId).toList()
      ..sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
  }

  /// Get a single tricount by ID.
  Map<String, dynamic>? tricountById(String id) {
    try {
      return _tricounts.firstWhere((t) => t['id'] == id);
    } catch (_) {
      return null;
    }
  }

  /// Friend requests for the current user.
  List<Map<String, dynamic>> get myFriendRequests {
    final uid = _currentUserId;
    if (uid == null) return [];
    return _friendRequests.where((r) => r['receiver_id'] == uid).toList();
  }

  /// Tricount invites for the current user.
  List<Map<String, dynamic>> get myTricountInvites {
    final uid = _currentUserId;
    if (uid == null) return [];
    return _tricountInvites.where((i) => i['user_id'] == uid).toList();
  }

  /// Current user's friends.
  List<Map<String, dynamic>> get myFriends {
    final uid = _currentUserId;
    if (uid == null) return [];
    return _friends.where((f) => f['user_id'] == uid).toList();
  }

  /// Current user's personal transactions.
  List<Map<String, dynamic>> get myPersonalTransactions {
    final uid = _currentUserId;
    if (uid == null) return [];
    return _personalTransactions.where((t) => t['user_id'] == uid).toList()
      ..sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
  }

  /// Current user's personal balance record.
  Map<String, dynamic>? get myPersonalBalance {
    final uid = _currentUserId;
    if (uid == null) return null;
    try {
      return _personalBalances.firstWhere((b) => b['user_id'] == uid);
    } catch (_) {
      return null;
    }
  }

  /// Current user's profile from users table.
  Map<String, dynamic>? get myProfile {
    final uid = _currentUserId;
    if (uid == null) return null;
    try {
      return _users.firstWhere((u) => u['id'] == uid);
    } catch (_) {
      return null;
    }
  }

  // ── Initialization ───────────────────────────────────────────

  /// Load from cache first, then fetch fresh from server.
  Future<void> initialize() async {
    if (_initialized) return;
    await _loadFromCache();
    _initialized = true;
    notifyListeners();

    // Fetch fresh data in background
    await refreshAll();
  }

  // ── Cache I/O ────────────────────────────────────────────────

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _tricounts = _decodeList(prefs.getString('dp_tricounts'));
      _expenses = _decodeList(prefs.getString('dp_expenses'));
      _friends = _decodeList(prefs.getString('dp_friends'));
      _friendRequests = _decodeList(prefs.getString('dp_friend_requests'));
      _tricountInvites = _decodeList(prefs.getString('dp_tricount_invites'));
      _personalTransactions =
          _decodeList(prefs.getString('dp_personal_transactions'));
      _personalBalances = _decodeList(prefs.getString('dp_personal_balances'));
      _users = _decodeList(prefs.getString('dp_users'));

      final ts = prefs.getString('dp_last_sync');
      if (ts != null) _lastSyncTime = DateTime.tryParse(ts);

      debugPrint('[DataProvider] Loaded from cache');
    } catch (e) {
      debugPrint('[DataProvider] Cache load error: $e');
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await Future.wait([
        prefs.setString('dp_tricounts', jsonEncode(_tricounts)),
        prefs.setString('dp_expenses', jsonEncode(_expenses)),
        prefs.setString('dp_friends', jsonEncode(_friends)),
        prefs.setString('dp_friend_requests', jsonEncode(_friendRequests)),
        prefs.setString('dp_tricount_invites', jsonEncode(_tricountInvites)),
        prefs.setString(
            'dp_personal_transactions', jsonEncode(_personalTransactions)),
        prefs.setString('dp_personal_balances', jsonEncode(_personalBalances)),
        prefs.setString('dp_users', jsonEncode(_users)),
        prefs.setString('dp_last_sync', DateTime.now().toIso8601String()),
      ]);

      _lastSyncTime = DateTime.now();
      debugPrint('[DataProvider] Saved to cache');
    } catch (e) {
      debugPrint('[DataProvider] Cache save error: $e');
    }
  }

  static List<Map<String, dynamic>> _decodeList(String? json) {
    if (json == null) return [];
    try {
      return List<Map<String, dynamic>>.from(
          jsonDecode(json).map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {
      return [];
    }
  }

  // ── Data refresh (from Supabase) ─────────────────────────────

  /// Force full data refresh from Supabase.
  /// Called on: app launch, push notification, manual pull-to-refresh.
  Future<void> refreshAll() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      final uid = _currentUserId;
      if (uid == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Fetch all data in parallel
      final results = await Future.wait([
        client.from('tricounts').select().order('created_at', ascending: false),
        client.from('expenses').select(),
        client.from('friends').select(),
        client.from('friend_requests').select(),
        client.from('tricount_invites').select(),
        client
            .from('personal_transactions')
            .select()
            .eq('user_id', uid)
            .order('date', ascending: false),
        client.from('personal_balances').select().eq('user_id', uid),
        client.from('users').select().eq('id', uid),
      ]);

      // Store the OLD expenses before update (for auto-personal-expense detection)
      final oldExpenseIds = _expenses.map((e) => e['id']).toSet();

      _tricounts = List<Map<String, dynamic>>.from(results[0]);
      _expenses = List<Map<String, dynamic>>.from(results[1]);
      _friends = List<Map<String, dynamic>>.from(results[2]);
      _friendRequests = List<Map<String, dynamic>>.from(results[3]);
      _tricountInvites = List<Map<String, dynamic>>.from(results[4]);
      _personalTransactions = List<Map<String, dynamic>>.from(results[5]);
      _personalBalances = List<Map<String, dynamic>>.from(results[6]);
      _users = List<Map<String, dynamic>>.from(results[7]);

      await _saveToCache();

      // Auto-register group expenses in personal tracker
      await _autoRegisterPersonalExpenses(oldExpenseIds);

      debugPrint('[DataProvider] Full refresh complete');
    } catch (e) {
      debugPrint('[DataProvider] Refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh expenses for a specific tricount only.
  Future<void> refreshTricountExpenses(String tricountId) async {
    try {
      final client = Supabase.instance.client;
      final freshExpenses =
          await client.from('expenses').select().eq('tricount_id', tricountId);

      // Replace expenses for this tricount, keep others
      _expenses.removeWhere((e) => e['tricount_id'] == tricountId);
      _expenses.addAll(List<Map<String, dynamic>>.from(freshExpenses));

      await _saveToCache();
      notifyListeners();
    } catch (e) {
      debugPrint('[DataProvider] Tricount expense refresh error: $e');
    }
  }

  /// Refresh just the tricount invites and friend requests.
  Future<void> refreshRequests() async {
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client.from('friend_requests').select(),
        client.from('tricount_invites').select(),
      ]);

      _friendRequests = List<Map<String, dynamic>>.from(results[0]);
      _tricountInvites = List<Map<String, dynamic>>.from(results[1]);

      await _saveToCache();
      notifyListeners();
    } catch (e) {
      debugPrint('[DataProvider] Requests refresh error: $e');
    }
  }

  /// Refresh personal tracker data.
  Future<void> refreshPersonal() async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client
            .from('personal_transactions')
            .select()
            .eq('user_id', uid)
            .order('date', ascending: false),
        client.from('personal_balances').select().eq('user_id', uid),
      ]);

      _personalTransactions = List<Map<String, dynamic>>.from(results[0]);
      _personalBalances = List<Map<String, dynamic>>.from(results[1]);

      await _saveToCache();
      notifyListeners();
    } catch (e) {
      debugPrint('[DataProvider] Personal refresh error: $e');
    }
  }

  /// Refresh profile and friends data.
  Future<void> refreshProfile() async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client.from('users').select().eq('id', uid),
        client.from('friends').select().eq('user_id', uid),
      ]);

      _users = List<Map<String, dynamic>>.from(results[0]);
      _friends = List<Map<String, dynamic>>.from(results[1]);

      await _saveToCache();
      notifyListeners();
    } catch (e) {
      debugPrint('[DataProvider] Profile refresh error: $e');
    }
  }

  // ── Auto personal expense registration ───────────────────────

  /// Detect new group expenses involving the current user (created by others)
  /// and auto-create personal tracker entries for their share.
  Future<void> _autoRegisterPersonalExpenses(Set<dynamic> oldExpenseIds) async {
    final uid = _currentUserId;
    if (uid == null) return;

    try {
      // Find new expenses that weren't in the old set
      final newExpenses =
          _expenses.where((e) => !oldExpenseIds.contains(e['id'])).toList();

      if (newExpenses.isEmpty) return;

      final client = Supabase.instance.client;

      for (final expense in newExpenses) {
        // Skip expenses created by the current user (they already synced
        // their own personal tracker when creating the expense)
        if (expense['user_id'] == uid) continue;

        // Only process group expenses (must have a tricount_id)
        if (expense['tricount_id'] == null) continue;

        // Find the current user's share
        double myShare = 0;
        final involved = expense['involved_participants'];
        if (involved is List) {
          for (var item in involved) {
            if (item is Map) {
              final itemUid = item['user_id'] ?? item['id'];
              if (itemUid == uid) {
                myShare =
                    double.tryParse(item['amount']?.toString() ?? '0') ?? 0;
                break;
              }
            }
          }
        }

        // Skip if user has no share in this expense
        if (myShare <= 0) continue;

        // Check if we already logged this expense (by checking notes for expense name + tricount_id)
        final alreadyExists = _personalTransactions.any((pt) =>
            pt['notes'] != null &&
            pt['notes'].toString().contains('Group expense') &&
            pt['name'] == expense['name'] &&
            pt['amount']?.toString() == myShare.toStringAsFixed(2));

        if (alreadyExists) continue;

        // Create personal tracker entry
        try {
          await client.from('personal_transactions').insert({
            'user_id': uid,
            'name': expense['name'],
            'amount': myShare,
            'type': 'expense',
            'payment_mode':
                (expense['payment_method'] as String?)?.toLowerCase() ??
                    'online',
            'category': expense['category'] ?? 'Other',
            'date': expense['created_at'],
            'notes':
                'Group expense (your share, paid by ${expense['paid_by'] ?? 'someone'})',
          });
          debugPrint(
              '[DataProvider] Auto-registered personal expense: ${expense['name']} = ₹$myShare');
        } catch (e) {
          debugPrint('[DataProvider] Auto personal expense insert error: $e');
        }
      }

      // Refresh personal data to include newly inserted entries
      if (newExpenses
          .any((e) => e['user_id'] != uid && e['tricount_id'] != null)) {
        await refreshPersonal();
      }
    } catch (e) {
      debugPrint('[DataProvider] Auto register error: $e');
    }
  }

  // ── Clear on logout ──────────────────────────────────────────

  Future<void> clear() async {
    _tricounts = [];
    _expenses = [];
    _friends = [];
    _friendRequests = [];
    _tricountInvites = [];
    _personalTransactions = [];
    _personalBalances = [];
    _users = [];
    _initialized = false;
    _lastSyncTime = null;

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('dp_'));
    for (final key in keys) {
      await prefs.remove(key);
    }

    notifyListeners();
  }
}
