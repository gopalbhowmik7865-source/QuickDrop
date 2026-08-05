import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class BannerManagementPage extends StatefulWidget {
  const BannerManagementPage({super.key});

  @override
  State<BannerManagementPage> createState() => _BannerManagementPageState();
}

class _BannerManagementPageState extends State<BannerManagementPage> {
  Uint8List? _selectedImage;
  String _contentType = 'image/jpeg';
  bool _isUploading = false;

  Future<void> _selectImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to read the selected image.')),
      );
      return;
    }

    final extension = file.extension?.toLowerCase();
    setState(() {
      _selectedImage = bytes;
      _contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
    });
  }

  Future<void> _uploadBanner() async {
    final image = _selectedImage;
    if (image == null || _isUploading) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final reference = FirebaseStorage.instance.ref('banners/$timestamp.jpg');
      await reference.putData(
        image,
        SettableMetadata(contentType: _contentType),
      );
      final imageUrl = await reference.getDownloadURL();

      await FirebaseFirestore.instance.collection('banners').add({
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'displayOrder': 0,
      });

      if (!mounted) return;
      setState(() {
        _selectedImage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Banner uploaded successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload banner: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  String _formatUploadDate(dynamic value) {
    if (value is! Timestamp) {
      return 'Pending';
    }

    final date = value.toDate();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  Future<void> _deleteBanner(
    DocumentReference<Map<String, dynamic>> document,
    String imageUrl,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Banner'),
        content: const Text('Are you sure you want to delete this banner?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      if (imageUrl.isNotEmpty) {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      }
      await document.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Banner deleted successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete banner: $error')),
      );
    }
  }

  Widget _bannerList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load banners.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final documents = snapshot.data?.docs ?? const [];
        if (documents.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No banners uploaded yet.'),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: documents.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final document = documents[index];
            final data = document.data();
            final imageUrl = data['imageUrl']?.toString().trim() ?? '';
            final isActive = data['isActive'] as bool? ?? false;
            final displayOrder = data['displayOrder'] as num? ?? 0;

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 7,
                    child: imageUrl.isEmpty
                        ? const ColoredBox(
                            color: Color(0xFFF1F6FD),
                            child: Icon(Icons.image_not_supported_outlined),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.prefer,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) {
                                return child;
                              }
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0xFFF1F6FD),
                              child: Icon(Icons.image_not_supported_outlined),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Uploaded: ${_formatUploadDate(data['createdAt'])}',
                              ),
                              const SizedBox(height: 4),
                              Text('Display Order: $displayOrder'),
                              const SizedBox(height: 4),
                              Text(isActive ? 'Active' : 'Inactive'),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete banner',
                          onPressed: () => _deleteBanner(
                            document.reference,
                            imageUrl,
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banner Management')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 7,
                      child: Image.memory(_selectedImage!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _selectImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Select Banner Image'),
                  ),
                ),
                if (_selectedImage != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _isUploading ? null : _uploadBanner,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        _isUploading ? 'Uploading...' : 'Upload Banner',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _bannerList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
