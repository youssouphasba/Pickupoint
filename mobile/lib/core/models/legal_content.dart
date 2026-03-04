class LegalContent {
  final String documentType;
  final String title;
  final String content;
  final DateTime updatedAt;
  final String? updatedBy;

  LegalContent({
    required this.documentType,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.updatedBy,
  });

  factory LegalContent.fromJson(Map<String, dynamic> json) {
    return LegalContent(
      documentType: json['document_type'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      updatedBy: json['updated_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'document_type': documentType,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'updated_by': updatedBy,
    };
  }
}
