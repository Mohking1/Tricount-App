import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/photo_service.dart';

class PhotosView extends StatefulWidget {
  final String tricountId;

  const PhotosView({
    super.key,
    required this.tricountId,
  });

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await PhotoService.pickImage();
      if (image == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading...')),
      );

      // Use a temporary ID for non-expense photos
      final String tempId = DateTime.now().millisecondsSinceEpoch.toString();
      final String? photoUrl = await PhotoService.uploadExpenseImage(
        widget.tricountId,
        tempId,
        image,
      );

      if (photoUrl != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo added successfully')),
        );
        setState(() {}); // Refresh the list
      } else {
        throw Exception('Error uploading photo');
      }
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error uploading photo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _pickAndUploadImage,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Add proof of purchase'),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: PhotoService.getPhotos(widget.tricountId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint('FutureBuilder Error: ${snapshot.error}');
                  return const Center(child: Text('An error occurred'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final photos = snapshot.data!;

                if (photos.isEmpty) {
                  return const Center(
                    child: Text('No photos'),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _showFullScreenImage(context, photos[index]),
                      child: Hero(
                        tag: photos[index],
                        child: Image.network(
                          photos[index],
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Hero(
              tag: imageUrl,
              child: Image.network(imageUrl),
            ),
          ),
        ),
      ),
    );
  }
}
