import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:nscgschedule/models/friend_models.dart';
import 'package:nscgschedule/friends_service.dart';

class EditFriendBottomSheet extends StatefulWidget {
  final Friend friend;
  final VoidCallback onSaved;

  const EditFriendBottomSheet({super.key, required this.friend, required this.onSaved});

  @override
  State<EditFriendBottomSheet> createState() => _EditFriendBottomSheetState();
}

class _EditFriendBottomSheetState extends State<EditFriendBottomSheet> {
  late TextEditingController _nameController;
  String? _profilePicPath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.friend.name);
    _profilePicPath = widget.friend.profilePicPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _profilePicPath = picked.path;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final updated = widget.friend.copyWith(
      name: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : widget.friend.name,
      profilePicPath: _profilePicPath,
    );
    await GetIt.I<FriendsService>().saveFriend(updated);
    if (mounted) {
      setState(() => _isSaving = false);
      widget.onSaved();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage;
    if (_profilePicPath != null && _profilePicPath!.isNotEmpty) {
      try {
        final f = File(_profilePicPath!);
        if (f.existsSync()) avatarImage = FileImage(f);
      } catch (_) {}
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24.0,
        right: 24.0,
        top: 24.0,
        bottom: 24.0 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Edit Profile',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(
                          _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : '?',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.camera_alt,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
