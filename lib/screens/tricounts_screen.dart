import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tricount_detail_screen.dart';
import '../services/data_provider.dart';

class TricountsScreen extends StatelessWidget {
  const TricountsScreen({super.key});

  Future<void> _showAddTricountDialog(BuildContext context) async {
    String? tricountName;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Tricount'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tricount name'),
          onChanged: (value) => tricountName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (tricountName?.isNotEmpty ?? false) {
                final currentUser = Supabase.instance.client.auth.currentUser;
                if (currentUser != null) {
                  final userName = currentUser.userMetadata?['name'] ?? 'Me';

                  await Supabase.instance.client.from('tricounts').insert({
                    'name': tricountName,
                    'created_by': currentUser.id,
                    'created_at': DateTime.now().toIso8601String(),
                    'participants': [
                      {
                        'id': currentUser.id,
                        'name': userName,
                      },
                    ],
                    'participant_ids': [currentUser.id],
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    DataProvider().refreshAll();
                  }
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinTricountDialog(BuildContext context) async {
    String? tricountId;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Tricount'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Tricount ID (UUID)'),
          onChanged: (value) => tricountId = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (tricountId?.isNotEmpty ?? false) {
                Navigator.pop(context);
                await _handleJoinTricount(context, tricountId!.trim());
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleJoinTricount(
      BuildContext context, String tricountId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      // Fetch Tricount
      final tricountRes = await Supabase.instance.client
          .from('tricounts')
          .select()
          .eq('id', tricountId)
          .single();

      final participants =
          List<Map<String, dynamic>>.from(tricountRes['participants'] ?? []);
      final participantIds =
          List<String>.from(tricountRes['participant_ids'] ?? []);

      // Check if already joined
      if (participantIds.contains(currentUser.id)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are already in this Tricount')),
          );
        }
        return;
      }

      // Find Ghosts
      final ghosts = participants.where((p) => p['is_ghost'] == true).toList();

      if (ghosts.isNotEmpty) {
        if (context.mounted) {
          await _showGhostClaimDialog(context, tricountId, ghosts, currentUser,
              participants, participantIds);
        }
      } else {
        await _joinAsNew(tricountId, currentUser, participants, participantIds);
        if (context.mounted) {
          DataProvider().refreshAll();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Joined successfully!')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error joining: $e')),
        );
      }
    }
  }

  Future<void> _showGhostClaimDialog(
      BuildContext context,
      String tricountId,
      List<Map<String, dynamic>> ghosts,
      User currentUser,
      List<Map<String, dynamic>> allParticipants,
      List<String> allParticipantIds) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you one of these people?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...ghosts.map((g) => ListTile(
                    title: Text(g['name']),
                    subtitle: const Text('Tap to claim this profile'),
                    leading: const Icon(Icons.person_outline),
                    onTap: () async {
                      Navigator.pop(context);
                      await _claimProfile(tricountId, g, currentUser,
                          allParticipants, allParticipantIds);
                      if (context.mounted) {
                        DataProvider().refreshAll();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Profile claimed successfully!')),
                        );
                      }
                    },
                  )),
              const Divider(),
              ListTile(
                title: const Text('None of these'),
                subtitle: const Text('Join as a new participant'),
                leading: const Icon(Icons.person_add),
                onTap: () async {
                  Navigator.pop(context);
                  await _joinAsNew(tricountId, currentUser, allParticipants,
                      allParticipantIds);
                  if (context.mounted) {
                    DataProvider().refreshAll();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Joined successfully!')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _claimProfile(
      String tricountId,
      Map<String, dynamic> ghost,
      User currentUser,
      List<Map<String, dynamic>> allParticipants,
      List<String> allParticipantIds) async {
    final ghostId = ghost['id'];
    final realId = currentUser.id;
    final realName = currentUser.userMetadata?['name'] ?? ghost['name'];

    // 1. Update Participants List
    final updatedParticipants = allParticipants.map((p) {
      if (p['id'] == ghostId) {
        return {
          'id': realId,
          'name': realName,
          'photo_url': currentUser.userMetadata?['photo_url'],
          'is_ghost': false,
        };
      }
      return p;
    }).toList();

    final updatedIds = [...allParticipantIds, realId];

    await Supabase.instance.client.from('tricounts').update({
      'participants': updatedParticipants,
      'participant_ids': updatedIds,
    }).eq('id', tricountId);

    // 2. Update Expenses (Paid By)
    await Supabase.instance.client
        .from('expenses')
        .update({'user_id': realId})
        .eq('tricount_id', tricountId)
        .eq('user_id', ghostId);

    // 3. Update Expenses (Involved Participants)
    final expensesRes = await Supabase.instance.client
        .from('expenses')
        .select()
        .eq('tricount_id', tricountId);

    final expenses = List<Map<String, dynamic>>.from(expensesRes);

    for (var expense in expenses) {
      final involved =
          List<dynamic>.from(expense['involved_participants'] ?? []);
      bool changed = false;

      final newInvolved = involved.map((item) {
        if (item is Map) {
          if (item['user_id'] == ghostId || item['id'] == ghostId) {
            changed = true;
            return {
              ...item,
              'user_id': realId,
              'id': realId,
            };
          }
        }
        return item;
      }).toList();

      if (changed) {
        await Supabase.instance.client.from('expenses').update(
            {'involved_participants': newInvolved}).eq('id', expense['id']);
      }
    }
  }

  Future<void> _joinAsNew(
      String tricountId,
      User currentUser,
      List<Map<String, dynamic>> allParticipants,
      List<String> allParticipantIds) async {
    final newParticipant = {
      'id': currentUser.id,
      'name': currentUser.userMetadata?['name'] ?? 'Me',
      'photo_url': currentUser.userMetadata?['photo_url'],
    };

    final updatedParticipants = [...allParticipants, newParticipant];
    final updatedIds = [...allParticipantIds, currentUser.id];

    await Supabase.instance.client.from('tricounts').update({
      'participants': updatedParticipants,
      'participant_ids': updatedIds,
    }).eq('id', tricountId);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Tricounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Join Tricount',
            onPressed: () => _showJoinTricountDialog(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DataProvider(),
        builder: (context, _) {
          final myTricounts = DataProvider().myTricounts;

          if (DataProvider().isLoading && myTricounts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (myTricounts.isEmpty) {
            return const Center(
              child: Text(
                'No tricounts found',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await DataProvider().refreshAll();
            },
            child: ListView.builder(
              itemCount: myTricounts.length,
              itemBuilder: (context, index) {
                final tricount = myTricounts[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(
                      tricount['name'] ?? 'Unnamed',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TricountDetailScreen(
                            tricountId: tricount['id'].toString()),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTricountDialog(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
