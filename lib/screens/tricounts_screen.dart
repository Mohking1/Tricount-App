import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tricount_detail_screen.dart';
import '../services/data_provider.dart';
import '../services/photo_service.dart';

class TricountsScreen extends StatelessWidget {
  const TricountsScreen({super.key});

  Future<String?> _uploadTricountIcon() async {
    final picked = await PhotoService.pickImage();
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final path =
        'tricount_icons/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';

    await Supabase.instance.client.storage.from('photos').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(upsert: true));

    return Supabase.instance.client.storage.from('photos').getPublicUrl(path);
  }

  Widget _buildTricountAvatar(
      BuildContext context, Map<String, dynamic> tricount) {
    final iconValue = tricount['emoji']?.toString();
    final isImage = iconValue != null && iconValue.startsWith('http');

    if (isImage) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        backgroundImage: NetworkImage(iconValue),
      );
    }

    if (iconValue != null && iconValue.trim().isNotEmpty) {
      return CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Text(
          iconValue,
          style: const TextStyle(fontSize: 18),
        ),
      );
    }

    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(
        Icons.account_balance_wallet,
        color: Colors.white,
      ),
    );
  }

  Future<void> _showTricountFormDialog(BuildContext context,
      {Map<String, dynamic>? tricount}) async {
    final isEdit = tricount != null;
    final nameController =
        TextEditingController(text: tricount?['name']?.toString() ?? '');

    final rawIcon = tricount?['emoji']?.toString();
    String selectedIcon =
        (rawIcon != null && rawIcon.trim().isNotEmpty) ? rawIcon : '🏠';
    bool isSaving = false;
    bool isUploading = false;

    const presets = [
      '🏠',
      '💸',
      '🧾',
      '🛒',
      '🍔',
      '🎉',
      '🧹',
      '🛋️',
      '📦',
      '🧑‍🤝‍🧑'
    ];

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Tricount' : 'New Tricount'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: selectedIcon.startsWith('http')
                      ? CircleAvatar(
                          radius: 28,
                          backgroundImage: NetworkImage(selectedIcon),
                        )
                      : CircleAvatar(
                          radius: 28,
                          child: Text(
                            selectedIcon,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Tricount name'),
                ),
                const SizedBox(height: 12),
                const Text('Emoji Icon'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets
                      .map((emoji) => InkWell(
                            onTap: () =>
                                setDialogState(() => selectedIcon = emoji),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selectedIcon == emoji
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Custom emoji (optional)',
                  ),
                  onChanged: (v) {
                    final trimmed = v.trim();
                    if (trimmed.isNotEmpty) {
                      setDialogState(() => selectedIcon = trimmed);
                    }
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isUploading
                        ? null
                        : () async {
                            setDialogState(() => isUploading = true);
                            try {
                              final url = await _uploadTricountIcon();
                              if (url != null && context.mounted) {
                                setDialogState(() => selectedIcon = url);
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Failed to upload icon image')),
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setDialogState(() => isUploading = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.image_outlined),
                    label:
                        Text(isUploading ? 'Uploading...' : 'Use Image Icon'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final tricountName = nameController.text.trim();
                      if (tricountName.isEmpty) return;

                      setDialogState(() => isSaving = true);
                      try {
                        final currentUser =
                            Supabase.instance.client.auth.currentUser;
                        if (currentUser == null) return;

                        if (isEdit) {
                          await Supabase.instance.client
                              .from('tricounts')
                              .update({
                            'name': tricountName,
                            'emoji': selectedIcon
                          }).eq('id', tricount['id']);
                        } else {
                          final userName =
                              currentUser.userMetadata?['name'] ?? 'Me';
                          await Supabase.instance.client
                              .from('tricounts')
                              .insert({
                            'name': tricountName,
                            'emoji': selectedIcon,
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
                        }

                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                          DataProvider().refreshAll();
                        }
                      } finally {
                        if (context.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddTricountDialog(BuildContext context) async {
    await _showTricountFormDialog(context);
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
          .maybeSingle();

      if (tricountRes == null) {
        final rpcRes = await Supabase.instance.client.rpc(
          'join_tricount_by_uuid',
          params: {'p_tricount_id': tricountId},
        );

        final status =
            rpcRes is Map ? (rpcRes['status']?.toString() ?? '') : '';
        final message =
            rpcRes is Map ? (rpcRes['message']?.toString() ?? '') : '';

        if (status == 'ghosts_available') {
          final ghostsRaw = rpcRes is Map ? (rpcRes['ghosts'] as List?) : null;
          final ghosts = List<Map<String, dynamic>>.from(
            (ghostsRaw ?? const []).map((e) => Map<String, dynamic>.from(e)),
          );

          if (ghosts.isNotEmpty && context.mounted) {
            await _showGhostClaimDialogRpc(context, tricountId, ghosts);
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No claimable ghost profiles found')),
            );
          }
          return;
        }

        if (context.mounted) {
          if (status == 'joined' ||
              status == 'claimed' ||
              status == 'already_joined') {
            DataProvider().refreshAll();
            final text = message.isNotEmpty
                ? message
                : (status == 'claimed'
                    ? 'Joined and claimed matching ghost profile'
                    : 'Joined successfully!');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(text)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  message.isNotEmpty
                      ? message
                      : 'Tricount not found or you do not have access yet',
                ),
              ),
            );
          }
        }
        return;
      }

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

  Future<void> _showGhostClaimDialogRpc(
    BuildContext context,
    String tricountId,
    List<Map<String, dynamic>> ghosts,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Claim an existing profile?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...ghosts.map((g) => ListTile(
                    title: Text((g['name'] ?? 'Unknown').toString()),
                    subtitle: const Text('Take over this existing participant'),
                    leading: const Icon(Icons.person_outline),
                    onTap: () async {
                      Navigator.pop(context);
                      final res = await Supabase.instance.client.rpc(
                        'join_tricount_by_uuid',
                        params: {
                          'p_tricount_id': tricountId,
                          'p_ghost_id': (g['id'] ?? '').toString(),
                        },
                      );

                      final status =
                          res is Map ? (res['status']?.toString() ?? '') : '';
                      final message =
                          res is Map ? (res['message']?.toString() ?? '') : '';

                      if (!context.mounted) return;
                      if (status == 'claimed' || status == 'already_joined') {
                        DataProvider().refreshAll();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              message.isNotEmpty
                                  ? message
                                  : 'Profile claimed successfully!',
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              message.isNotEmpty
                                  ? message
                                  : 'Could not claim profile',
                            ),
                          ),
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
                  final res = await Supabase.instance.client.rpc(
                    'join_tricount_by_uuid',
                    params: {
                      'p_tricount_id': tricountId,
                      'p_join_as_new': true,
                    },
                  );

                  final status =
                      res is Map ? (res['status']?.toString() ?? '') : '';
                  final message =
                      res is Map ? (res['message']?.toString() ?? '') : '';

                  if (!context.mounted) return;
                  if (status == 'joined' || status == 'already_joined') {
                    DataProvider().refreshAll();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          message.isNotEmpty ? message : 'Joined successfully!',
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          message.isNotEmpty
                              ? message
                              : 'Could not join tricount',
                        ),
                      ),
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
                      await _claimGhost(tricountId, g);
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

  Future<void> _joinAsNew(
      String tricountId,
      User currentUser,
      List<Map<String, dynamic>> allParticipants,
      List<String> allParticipantIds) async {
    final newParticipant = {
      'id': currentUser.id,
      'name': currentUser.userMetadata?['name'] ?? 'Me',
      'photo_url': currentUser.userMetadata?['photo_url'],
      'is_ghost': false,
    };

    final updatedParticipants = [...allParticipants, newParticipant];
    final updatedIds = {...allParticipantIds, currentUser.id}.toList();

    await Supabase.instance.client.from('tricounts').update({
      'participants': updatedParticipants,
      'participant_ids': updatedIds,
      'created_by': currentUser.id,
    }).eq('id', tricountId);
  }

  Future<void> _claimGhost(
      String tricountId, Map<String, dynamic> selectedGhost) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final ghostId = selectedGhost['id'];

    // Fetch current tricount data
    final tricountRes = await Supabase.instance.client
        .from('tricounts')
        .select()
        .eq('id', tricountId)
        .single();

    final participants =
        List<Map<String, dynamic>>.from(tricountRes['participants'] ?? []);
    final participantIds =
        List<String>.from(tricountRes['participant_ids'] ?? []);

    // Update participants: replace ghost with real user
    final newParticipants = participants.map((p) {
      if (p['id'] == ghostId) {
        return {
          'id': currentUser.id,
          'name': currentUser.userMetadata?['name'] ?? 'Me',
          'photo_url': currentUser.userMetadata?['photo_url'],
          'is_ghost': false,
        };
      }
      return p;
    }).toList();

    final newParticipantIds = {
      ...participantIds.where((id) => id != ghostId),
      currentUser.id,
    }.toList();

    // Update tricount
    await Supabase.instance.client.from('tricounts').update({
      'participants': newParticipants,
      'participant_ids': newParticipantIds,
      'created_by': currentUser.id,
    }).eq('id', tricountId);

    // Update expenses: replace ghost references with real user
    final expenses = await Supabase.instance.client
        .from('expenses')
        .select()
        .eq('tricount_id', tricountId);
    for (final expense in expenses) {
      bool updated = false;

      // Update payer if it was the ghost
      if (expense['user_id'] == ghostId) {
        await Supabase.instance.client
            .from('expenses')
            .update({'user_id': currentUser.id}).eq('id', expense['id']);
        updated = true;
      }

      // Update involved_participants
      final involved = List<Map<String, dynamic>>.from(
          expense['involved_participants'] ?? []);
      bool involvedChanged = false;
      final newInvolved = involved.map((i) {
        if (i['user_id'] == ghostId || i['id'] == ghostId) {
          involvedChanged = true;
          return {
            'user_id': currentUser.id,
            'id': currentUser.id,
            'name': currentUser.userMetadata?['name'] ?? 'Me',
            'photo_url': currentUser.userMetadata?['photo_url'],
          };
        }
        return i;
      }).toList();

      if (involvedChanged) {
        await Supabase.instance.client.from('expenses').update(
            {'involved_participants': newInvolved}).eq('id', expense['id']);
        updated = true;
      }

      if (updated) {
        // Update the expense in DataProvider if needed, but refreshAll will handle it
      }
    }
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
                    leading: _buildTricountAvatar(context, tricount),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TricountDetailScreen(
                            tricountId: tricount['id'].toString()),
                      ),
                    ),
                    onLongPress: () =>
                        _showTricountFormDialog(context, tricount: tricount),
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
