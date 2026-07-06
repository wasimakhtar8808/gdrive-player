class DriveItem {
  final String id;
  final String name;
  final String mimeType;
  final int? size;
  final DateTime? modifiedTime;
  final String? thumbnailLink;

  const DriveItem({
    required this.id,
    required this.name,
    required this.mimeType,
    this.size,
    this.modifiedTime,
    this.thumbnailLink,
  });

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
  bool get isVideo => mimeType.startsWith('video/');

  String get sizeString {
    if (size == null) return '';
    final bytes = size!;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedDate {
    if (modifiedTime == null) return '';
    final local = modifiedTime!.toLocal().toString();
    if (local.length >= 16) {
      return local.substring(0, 16);
    }
    return local;
  }

  factory DriveItem.fromJson(Map<String, dynamic> json) {
    return DriveItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed',
      mimeType: json['mimeType'] as String? ?? '',
      size: json['size'] != null ? int.tryParse(json['size'].toString()) : null,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.tryParse(json['modifiedTime'] as String)
          : null,
      thumbnailLink: json['thumbnailLink'] as String?,
    );
  }
}
