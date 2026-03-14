import 'dart:convert';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles connectivity monitoring and offline operation queueing.
/// No realtime subscriptions — all data refresh is driven by
/// DataProvider on explicit triggers (launch, push, pull-to-refresh).
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Connectivity _connectivity = Connectivity();

  final _syncStatusController = StreamController<bool>.broadcast();
  Stream<bool> get syncStatusStream => _syncStatusController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);

    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);

    if (_isOnline) {
      await syncPendingOperations();
    }
  }

  void _updateConnectionStatus(dynamic results) {
    bool isConnected = false;

    if (results is ConnectivityResult) {
      isConnected = results != ConnectivityResult.none;
    } else if (results is List<ConnectivityResult>) {
      isConnected = results.any((r) => r != ConnectivityResult.none);
    }

    if (isConnected != _isOnline) {
      _isOnline = isConnected;
      _syncStatusController.add(_isOnline);
      if (_isOnline) {
        syncPendingOperations();
      }
    }
  }

  // ── Pending operations queue ─────────────────────────────────

  Future<void> syncPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingList = prefs.getStringList('pending_operations') ?? [];

    if (pendingList.isEmpty) return;

    debugPrint('Syncing ${pendingList.length} pending operations...');

    final List<String> remainingOps = [];

    for (final opJson in pendingList) {
      bool success = false;
      try {
        final op = jsonDecode(opJson);
        success = await _processOperation(op);
      } catch (e) {
        debugPrint('Error processing operation: $e');
      }

      if (!success) {
        remainingOps.add(opJson);
      }
    }

    await prefs.setStringList('pending_operations', remainingOps);
    debugPrint('Sync complete. Remaining: ${remainingOps.length}');
  }

  Future<bool> _processOperation(Map<String, dynamic> op) async {
    try {
      final type = op['type'];
      final table = op['table'];
      final data = op['data'] as Map<String, dynamic>;

      if (type == 'insert') {
        await Supabase.instance.client.from(table).insert(data);
      } else if (type == 'update') {
        final id = op['id'];
        await Supabase.instance.client.from(table).update(data).eq('id', id);
      } else if (type == 'delete') {
        final id = op['id'];
        await Supabase.instance.client.from(table).delete().eq('id', id);
      }
      return true;
    } catch (e) {
      debugPrint('Sync failed for op: $e');
      return false;
    }
  }

  Future<void> _queueOperation(Map<String, dynamic> op) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingList = prefs.getStringList('pending_operations') ?? [];
    pendingList.add(jsonEncode(op));
    await prefs.setStringList('pending_operations', pendingList);
  }

  // ── Public write API ─────────────────────────────────────────

  Future<void> insertExpense(Map<String, dynamic> data) async {
    if (_isOnline) {
      try {
        await Supabase.instance.client.from('expenses').insert(data);
      } catch (e) {
        if (_isNetworkError(e)) {
          await _queueOperation(
              {'type': 'insert', 'table': 'expenses', 'data': data});
        } else {
          rethrow;
        }
      }
    } else {
      await _queueOperation(
          {'type': 'insert', 'table': 'expenses', 'data': data});
    }
  }

  Future<void> updateExpense(String id, Map<String, dynamic> data) async {
    if (_isOnline) {
      try {
        await Supabase.instance.client
            .from('expenses')
            .update(data)
            .eq('id', id);
      } catch (e) {
        if (_isNetworkError(e)) {
          await _queueOperation(
              {'type': 'update', 'table': 'expenses', 'id': id, 'data': data});
        } else {
          rethrow;
        }
      }
    } else {
      await _queueOperation(
          {'type': 'update', 'table': 'expenses', 'id': id, 'data': data});
    }
  }

  Future<void> deleteExpense(String id) async {
    if (_isOnline) {
      try {
        await Supabase.instance.client.from('expenses').delete().eq('id', id);
      } catch (e) {
        if (_isNetworkError(e)) {
          await _queueOperation(
              {'type': 'delete', 'table': 'expenses', 'id': id, 'data': {}});
        } else {
          rethrow;
        }
      }
    } else {
      await _queueOperation(
          {'type': 'delete', 'table': 'expenses', 'id': id, 'data': {}});
    }
  }

  bool _isNetworkError(dynamic e) {
    final msg = e.toString();
    return msg.contains('SocketException') || msg.contains('Network');
  }
}
