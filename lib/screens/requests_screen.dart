import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/data_provider.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    // Refresh requests every time screen is created
    DataProvider().refreshRequests();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DataProvider().refreshRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Requests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Tricounts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FriendRequestsTab(),
          _TricountInvitesTab(),
        ],
      ),
    );
  }
}

class _FriendRequestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Note: Friend requests logic needs to be implemented in Supabase.
    // For now, we'll assume a 'friend_requests' table or similar logic.
    // Based on the SQL setup, we don't have a friend_requests table yet.
    // We should probably add one or use a status in the friends table.
    // Assuming we will add a friend_requests table.

    // Since the SQL didn't explicitly create a friend_requests table,
    // I will assume for now we might need to create it or it was missed.
    // However, looking at the previous code, it was using a subcollection.
    // Let's assume we need to create a 'friend_requests' table.
    // For this refactor, I will implement the UI to fetch from 'friend_requests'
    // and we will need to ensure the table exists.

    return ListenableBuilder(
      listenable: DataProvider(),
      builder: (context, _) {
        final requests = DataProvider().myFriendRequests;

        if (DataProvider().isLoading && requests.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (requests.isEmpty) {
          return const Center(child: Text('No pending friend requests'));
        }

        return RefreshIndicator(
          onRefresh: () async {
            await DataProvider().refreshRequests();
          },
          child: ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              final senderId = request['sender_id'];

              return FutureBuilder<Map<String, dynamic>>(
                future: Supabase.instance.client
                    .from('users')
                    .select()
                    .eq('id', senderId)
                    .single(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) return const SizedBox.shrink();
                  final sender = userSnapshot.data!;

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[800],
                        backgroundImage: sender['photo_url'] != null
                            ? NetworkImage(sender['photo_url'])
                            : null,
                        child: sender['photo_url'] == null
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      title: Text(
                        sender['name'] ?? 'Unknown User',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      subtitle: const Text('Wants to add you as a friend',
                          overflow: TextOverflow.ellipsis, maxLines: 1),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _acceptFriendRequest(
                              context,
                              request['id'],
                              senderId,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => _rejectFriendRequest(
                              context,
                              request['id'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _acceptFriendRequest(
    BuildContext context,
    String requestId,
    String senderId,
  ) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      // Add friend relationship (bidirectional)
      await Supabase.instance.client.from('friends').insert([
        {'user_id': currentUser.id, 'friend_id': senderId},
        {'user_id': senderId, 'friend_id': currentUser.id},
      ]);

      // Delete request
      await Supabase.instance.client
          .from('friend_requests')
          .delete()
          .eq('id', requestId);

      if (context.mounted) {
        DataProvider().refreshAll();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request accepted')),
        );
      }
    } catch (e) {
      debugPrint('Error accepting friend request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting request: $e')),
        );
      }
    }
  }

  Future<void> _rejectFriendRequest(
      BuildContext context, String requestId) async {
    try {
      await Supabase.instance.client
          .from('friend_requests')
          .delete()
          .eq('id', requestId);

      if (context.mounted) {
        DataProvider().refreshRequests();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request rejected')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error rejecting request')),
        );
      }
    }
  }
}

class _TricountInvitesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: DataProvider(),
      builder: (context, _) {
        final invites = DataProvider().myTricountInvites;

        if (DataProvider().isLoading && invites.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (invites.isEmpty) {
          return const Center(
            child: Text('No pending invitations'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await DataProvider().refreshRequests();
          },
          child: ListView.builder(
            itemCount: invites.length,
            itemBuilder: (context, index) {
              final invite = invites[index];

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ListTile(
                  title: Text(
                    invite['tricount_name'] ?? 'Unnamed',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  subtitle: Text(
                    'Invited by ${invite['invited_by']}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _acceptTricountInvite(
                          context,
                          invite['id'],
                          invite['tricount_id'],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _rejectTricountInvite(
                          context,
                          invite['id'],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _acceptTricountInvite(
    BuildContext context,
    String inviteId,
    String tricountId,
  ) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      // Get current tricount data
      final tricountRes = await Supabase.instance.client
          .from('tricounts')
          .select()
          .eq('id', tricountId)
          .single();

      final participantIds =
          List<dynamic>.from(tricountRes['participant_ids'] ?? []);
      final participants = List<Map<String, dynamic>>.from(
          (tricountRes['participants'] as List? ?? [])
              .map((p) => Map<String, dynamic>.from(p)));

      // Check if already joined
      if (participantIds.contains(currentUser.id)) {
        // Just delete the invite and return
        await Supabase.instance.client
            .from('tricount_invites')
            .delete()
            .eq('id', inviteId);
        if (context.mounted) {
          DataProvider().refreshAll();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are already in this Tricount')),
          );
        }
        return;
      }

      // Find ghost participants
      final ghosts = participants.where((p) => p['is_ghost'] == true).toList();

      if (ghosts.isNotEmpty && context.mounted) {
        // Show ghost claim dialog
        await _showGhostClaimDialog(
          context,
          tricountId,
          inviteId,
          ghosts,
          currentUser,
          participants,
          participantIds,
        );
      } else {
        // No ghosts — join as new participant
        await _joinAsNew(tricountId, currentUser, participants, participantIds);
        // Delete invitation
        await Supabase.instance.client
            .from('tricount_invites')
            .delete()
            .eq('id', inviteId);
        if (context.mounted) {
          DataProvider().refreshAll();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation accepted')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error accepting tricount invite: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting invitation: $e')),
        );
      }
    }
  }

  Future<void> _showGhostClaimDialog(
    BuildContext context,
    String tricountId,
    String inviteId,
    List<Map<String, dynamic>> ghosts,
    User currentUser,
    List<Map<String, dynamic>> allParticipants,
    List<dynamic> allParticipantIds,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you one of these people?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...ghosts.map((g) => ListTile(
                    title: Text(g['name'] ?? 'Unknown'),
                    subtitle: const Text('Tap to claim this profile'),
                    leading: const Icon(Icons.person_outline),
                    onTap: () async {
                      Navigator.pop(dialogContext);
                      try {
                        await _claimGhostProfile(tricountId, g, currentUser,
                            allParticipants, allParticipantIds);
                        // Delete invitation
                        await Supabase.instance.client
                            .from('tricount_invites')
                            .delete()
                            .eq('id', inviteId);
                        if (context.mounted) {
                          DataProvider().refreshAll();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Profile claimed successfully!')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error claiming profile: $e')),
                          );
                        }
                      }
                    },
                  )),
              const Divider(),
              ListTile(
                title: const Text('None of these'),
                subtitle: const Text('Join as a new participant'),
                leading: const Icon(Icons.person_add),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  try {
                    await _joinAsNew(tricountId, currentUser, allParticipants,
                        allParticipantIds);
                    // Delete invitation
                    await Supabase.instance.client
                        .from('tricount_invites')
                        .delete()
                        .eq('id', inviteId);
                    if (context.mounted) {
                      DataProvider().refreshAll();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Joined successfully!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error joining: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _claimGhostProfile(
    String tricountId,
    Map<String, dynamic> ghost,
    User currentUser,
    List<Map<String, dynamic>> allParticipants,
    List<dynamic> allParticipantIds,
  ) async {
    final ghostId = ghost['id'];
    final realId = currentUser.id;
    final realName = currentUser.userMetadata?['name'] ?? ghost['name'];

    // 1. Update participants list — replace ghost with real user
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

    // 2. Update expenses — paid by ghost → paid by real user
    await Supabase.instance.client
        .from('expenses')
        .update({'user_id': realId})
        .eq('tricount_id', tricountId)
        .eq('user_id', ghostId);

    // 3. Update involved_participants in all expenses
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
            return {...item, 'user_id': realId, 'id': realId};
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
    List<Map<String, dynamic>> participants,
    List<dynamic> participantIds,
  ) async {
    if (!participantIds.contains(currentUser.id)) {
      participantIds.add(currentUser.id);
      participants.add({
        'id': currentUser.id,
        'name': currentUser.userMetadata?['name'] ?? 'Unknown',
        'photo_url': currentUser.userMetadata?['photo_url'],
      });

      await Supabase.instance.client.from('tricounts').update({
        'participant_ids': participantIds,
        'participants': participants,
      }).eq('id', tricountId);
    }
  }

  Future<void> _rejectTricountInvite(
      BuildContext context, String inviteId) async {
    try {
      await Supabase.instance.client
          .from('tricount_invites')
          .delete()
          .eq('id', inviteId);

      if (context.mounted) {
        DataProvider().refreshRequests();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation rejected')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error rejecting invitation')),
        );
      }
    }
  }
}
