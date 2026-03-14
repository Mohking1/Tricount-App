import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class PhotoService {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> pickImage() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
  }

  static Future<File?> compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');

    var result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    return result != null ? File(result.path) : null;
  }

  static Future<String?> uploadExpenseImage(
      String tricountId, String expenseId, XFile image) async {
    try {
      final File originalFile = File(image.path);
      final File? compressedFile = await compressImage(originalFile);

      if (compressedFile == null) {
        throw Exception('Error compressing image');
      }

      final fileName = '$tricountId/$expenseId.jpg';

      await Supabase.instance.client.storage.from('expenses').upload(
          fileName, compressedFile,
          fileOptions: const FileOptions(upsert: true));

      await compressedFile.delete();

      final imageUrl = Supabase.instance.client.storage
          .from('expenses')
          .getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  static Future<List<String>> getPhotos(String tricountId) async {
    try {
      final List<FileObject> objects = await Supabase.instance.client.storage
          .from('expenses')
          .list(path: tricountId);

      return objects.map((obj) {
        return Supabase.instance.client.storage
            .from('expenses')
            .getPublicUrl('$tricountId/${obj.name}');
      }).toList();
    } catch (e) {
      debugPrint('Error fetching photos: $e');
      return [];
    }
  }
}
