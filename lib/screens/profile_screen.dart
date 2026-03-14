import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/data_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await DataProvider().clear();
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DataProvider(),
        builder: (context, _) {
          final userData = DataProvider().myProfile;

          if (DataProvider().isLoading && userData == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await DataProvider().refreshProfile();
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Profile Photo
                Center(
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: userData?['photo_url'] != null
                        ? NetworkImage(userData!['photo_url'])
                        : null,
                    child: userData?['photo_url'] == null
                        ? const Icon(Icons.person,
                            size: 50, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),

                // Personal Information
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Personal Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(userData?['name'] ?? 'Not specified'),
                          trailing: const Icon(Icons.edit),
                          onTap: () =>
                              _showEditNameDialog(context, userData?['name']),
                        ),
                        ListTile(
                          leading: const Icon(Icons.email),
                          title: Text(user?.email ?? 'Not specified'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Friends List
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'My Friends',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.person_add),
                              onPressed: () => _showAddFriendDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final friends = DataProvider().myFriends;

                            if (friends.isEmpty) {
                              return const Center(
                                child: Text('No friends yet'),
                              );
                            }

                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: friends.length,
                              itemBuilder: (context, index) {
                                final friendId = friends[index]['friend_id'];
                                return FutureBuilder<Map<String, dynamic>>(
                                  future: Supabase.instance.client
                                      .from('users')
                                      .select()
                                      .eq('id', friendId)
                                      .single(),
                                  builder: (context, friendUserSnapshot) {
                                    if (!friendUserSnapshot.hasData) {
                                      return const SizedBox.shrink();
                                    }
                                    final friend = friendUserSnapshot.data!;
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.grey[800],
                                        backgroundImage: friend['photo_url'] !=
                                                null
                                            ? NetworkImage(friend['photo_url'])
                                            : null,
                                        child: friend['photo_url'] == null
                                            ? const Icon(Icons.person,
                                                color: Colors.white)
                                            : null,
                                      ),
                                      title: Text(
                                        friend['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () => _deleteFriend(
                                          context,
                                          friends[index]['id'],
                                          friends[index]['friend_id'],
                                          friend['name'] ?? 'this friend',
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteFriend(
    BuildContext context,
    dynamic friendshipId,
    String friendId,
    String friendName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Remove $friendName from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;

      // Delete both directions of the friendship
      await Supabase.instance.client
          .from('friends')
          .delete()
          .eq('user_id', currentUser.id)
          .eq('friend_id', friendId);

      await Supabase.instance.client
          .from('friends')
          .delete()
          .eq('user_id', friendId)
          .eq('friend_id', currentUser.id);

      if (context.mounted) {
        DataProvider().refreshProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$friendName removed from friends')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing friend: $e')),
        );
      }
    }
  }

  Future<void> _showAddFriendDialog(BuildContext context) async {
    final TextEditingController emailController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            hintText: 'Friend\'s Email',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _sendFriendRequest(context, emailController.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFriendRequest(
      BuildContext context, String friendEmail) async {
    if (friendEmail.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an email')),
        );
      }
      return;
    }

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;

      // Don't allow adding yourself
      if (friendEmail.toLowerCase() == currentUser.email?.toLowerCase()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You cannot add yourself')),
          );
        }
        return;
      }

      // Search user by email in public.users table
      final userQuery = await Supabase.instance.client
          .from('users')
          .select()
          .ilike('email', friendEmail.trim())
          .limit(1);

      if (userQuery.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No user found with that email')),
          );
        }
        return;
      }

      final friendDoc = userQuery.first;

      // Check if already friends
      final existingFriend = await Supabase.instance.client
          .from('friends')
          .select()
          .eq('user_id', currentUser.id)
          .eq('friend_id', friendDoc['id'])
          .maybeSingle();

      if (existingFriend != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Already friends with this user')),
          );
        }
        return;
      }

      // Check if request already exists
      final existingRequest = await Supabase.instance.client
          .from('friend_requests')
          .select()
          .eq('sender_id', currentUser.id)
          .eq('receiver_id', friendDoc['id'])
          .maybeSingle();

      if (existingRequest != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Friend request already sent')),
          );
        }
        return;
      }

      // Check if they already sent us a request (auto-accept)
      final reverseRequest = await Supabase.instance.client
          .from('friend_requests')
          .select()
          .eq('sender_id', friendDoc['id'])
          .eq('receiver_id', currentUser.id)
          .maybeSingle();

      if (reverseRequest != null) {
        // They already sent us a request — auto-accept
        await Supabase.instance.client.from('friends').insert([
          {'user_id': currentUser.id, 'friend_id': friendDoc['id']},
          {'user_id': friendDoc['id'], 'friend_id': currentUser.id},
        ]);
        await Supabase.instance.client
            .from('friend_requests')
            .delete()
            .eq('id', reverseRequest['id']);

        if (context.mounted) {
          DataProvider().refreshProfile();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('They already sent you a request — now friends!')),
          );
        }
        return;
      }

      // Send friend request
      await Supabase.instance.client.from('friend_requests').insert({
        'sender_id': currentUser.id,
        'receiver_id': friendDoc['id'],
        'status': 'pending',
      });

      if (context.mounted) {
        DataProvider().refreshProfile();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showEditNameDialog(
      BuildContext context, String? currentName) async {
    final TextEditingController nameController =
        TextEditingController(text: currentName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Your Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                await _updateUserName(context, newName);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserName(BuildContext context, String newName) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client
          .from('users')
          .update({'name': newName}).eq('id', user.id);

      // Also update auth metadata if possible, or just rely on public table
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'name': newName}),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error updating name')),
        );
      }
    }
  }
}
