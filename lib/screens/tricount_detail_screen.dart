import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../widgets/expenses_view.dart';
import '../widgets/balance_view.dart';
import '../widgets/photos_view.dart';
import '../widgets/insights_view.dart';
import '../services/data_provider.dart';
import 'add_expense_screen.dart';

class TricountDetailScreen extends StatefulWidget {
  final String tricountId;

  const TricountDetailScreen({
    super.key,
    required this.tricountId,
  });

  @override
  State<TricountDetailScreen> createState() => _TricountDetailScreenState();
}

class _TricountDetailScreenState extends State<TricountDetailScreen> {
  int _selectedSegment = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _showAddExpenseDialog(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(tricountId: widget.tricountId),
      ),
    );

    if (result == true) {
      setState(() {
        _refreshKey++;
      });
    }
  }

  Future<void> _addGhostParticipant(BuildContext context) async {
    final nameController = TextEditingController();
    final enteredName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Participant Manually'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (val) => Navigator.pop(dialogContext, val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, nameController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final name = enteredName?.trim();
    if (name == null || name.isEmpty) return;

    try {
      await Supabase.instance.client.rpc('add_ghost_participant', params: {
        'p_tricount_id': widget.tricountId,
        'p_name': name,
      });
    } catch (e) {
      debugPrint('RPC add_ghost_participant failed, trying fallback: $e');

      // Fallback: direct update path for setups where RPC was not created yet.
      final tricountRes = await Supabase.instance.client
          .from('tricounts')
          .select('participants')
          .eq('id', widget.tricountId)
          .single();

      final List<dynamic> participants =
          List.from(tricountRes['participants'] ?? []);

      if (participants.any((p) => p['name'] == name)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Participant already exists')),
          );
        }
        return;
      }

      participants.add({
        'id': const Uuid().v4(),
        'name': name,
        'photo_url': null,
        'is_ghost': true,
      });

      await Supabase.instance.client
          .from('tricounts')
          .update({'participants': participants}).eq('id', widget.tricountId);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Participant added')),
      );
      DataProvider().refreshAll();
      setState(() {
        _refreshKey++;
      });
    }
  }

  Future<void> _showInviteParticipantDialog(BuildContext context) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;
    final parentContext = context;

    await showDialog(
      context: context,
      builder: (dialogContext) => FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('friends')
            .select('friend_id, users!friend_id(name, photo_url)')
            .eq('user_id', currentUser.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final friends = snapshot.data!;

          return AlertDialog(
            title: const Text('Invite Participants'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person_add, color: Colors.white),
                    ),
                    title: const Text('Add manually (no account needed)'),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _addGhostParticipant(parentContext);
                    },
                  ),
                  const Divider(),
                  if (friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('You have no friends yet'),
                    )
                  else
                    SizedBox(
                      height: MediaQuery.of(dialogContext).size.height * 0.35,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: friends.length,
                        itemBuilder: (context, index) {
                          final friendData =
                              friends[index]['users'] as Map<String, dynamic>;
                          final friendId = friends[index]['friend_id'];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey[800],
                              backgroundImage: friendData['photo_url'] != null
                                  ? NetworkImage(friendData['photo_url'])
                                  : null,
                              child: friendData['photo_url'] == null
                                  ? const Icon(Icons.person,
                                      color: Colors.white)
                                  : null,
                            ),
                            title: Text(friendData['name'] ?? ''),
                            onTap: () => _inviteParticipant(
                              dialogContext,
                              friendId,
                              friendData['name'],
                              friendData['photo_url'],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _inviteParticipant(
    BuildContext context,
    String userId,
    String name,
    String? photoUrl,
  ) async {
    try {
      final tricountRes = await Supabase.instance.client
          .from('tricounts')
          .select()
          .eq('id', widget.tricountId)
          .single();

      final List<dynamic> participantIds = tricountRes['participant_ids'] ?? [];

      if (participantIds.contains(userId)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('This person is already participating')),
          );
        }
        return;
      }

      // Check if invite already exists
      final existingInvite = await Supabase.instance.client
          .from('tricount_invites')
          .select()
          .eq('user_id', userId)
          .eq('tricount_id', widget.tricountId)
          .maybeSingle();

      if (existingInvite != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('An invitation is already pending')),
          );
        }
        return;
      }

      // Send invitation
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserName = currentUser?.userMetadata?['name'] ?? 'Unknown';

      await Supabase.instance.client.from('tricount_invites').insert({
        'tricount_id': widget.tricountId,
        'tricount_name': tricountRes['name'],
        'invited_by': currentUserName,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending invitation: $e')),
        );
      }
    }
  }

  Future<void> _deleteTricountDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tricount'),
        content: const Text(
            'Are you sure you want to delete this tricount? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        await _deleteTricount(context);
      }
    }
  }

  Future<void> _deleteTricount(BuildContext context) async {
    try {
      await Supabase.instance.client
          .from('tricounts')
          .delete()
          .eq('id', widget.tricountId);

      if (context.mounted) {
        DataProvider().refreshAll();
        Navigator.pop(context); // Go back to list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tricount deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting tricount: $e')),
        );
      }
    }
  }

  Future<void> _leaveTricountDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Tricount'),
        content: const Text('Are you sure you want to leave this tricount?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        await _leaveTricount(context);
      }
    }
  }

  Future<void> _leaveTricount(BuildContext context) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;

      await Supabase.instance.client.rpc('leave_tricount', params: {
        'p_tricount_id': widget.tricountId,
      });

      if (context.mounted) {
        DataProvider().refreshAll();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You left the tricount')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leaving tricount: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: DataProvider(),
          builder: (context, _) {
            final data = DataProvider().tricountById(widget.tricountId);
            if (data == null) {
              return const Text('Loading...');
            }
            return Text(data['name'] ?? 'Unnamed');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share Tricount ID',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.tricountId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Tricount ID copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showInviteParticipantDialog(context),
          ),
          ListenableBuilder(
            listenable: DataProvider(),
            builder: (context, _) {
              final data = DataProvider().tricountById(widget.tricountId);
              if (data == null) {
                return const SizedBox.shrink();
              }
              final createdBy = data['created_by'];
              final currentUser = Supabase.instance.client.auth.currentUser;
              final isCreator = currentUser?.id == createdBy;

              if (isCreator) {
                return IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteTricountDialog(context),
                );
              } else {
                return IconButton(
                  icon: const Icon(Icons.exit_to_app),
                  onPressed: () => _leaveTricountDialog(context),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Expenses'),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Balance'),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Photos'),
                ),
                ButtonSegment(
                  value: 3,
                  label: Text('Insights'),
                ),
              ],
              selected: {_selectedSegment},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _selectedSegment = newSelection.first;
                });
              },
            ),
          ),
          Expanded(
            child: _buildSelectedView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddExpenseDialog(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildSelectedView() {
    final key = ValueKey(_refreshKey);
    switch (_selectedSegment) {
      case 0:
        return ExpensesView(key: key, tricountId: widget.tricountId);
      case 1:
        return BalanceView(key: key, tricountId: widget.tricountId);
      case 2:
        return PhotosView(key: key, tricountId: widget.tricountId);
      case 3:
        return InsightsView(key: key, tricountId: widget.tricountId);
      default:
        return const SizedBox.shrink();
    }
  }
}
