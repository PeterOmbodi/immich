class TrashSyncDecision {
  final String assetId;
  final String checksum;
  final bool? isSyncApproved;

  const TrashSyncDecision({required this.assetId, required this.checksum, this.isSyncApproved});

  @override
  String toString() {
    return '''TrashSyncDecision {
   assetId: $assetId,
   checksum: $checksum,
   isSyncApproved: $isSyncApproved,
 }''';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TrashSyncDecision) return false;
    return assetId == other.assetId && checksum == other.checksum && isSyncApproved == other.isSyncApproved;
  }

  @override
  int get hashCode => checksum.hashCode ^ (assetId.hashCode) ^ (isSyncApproved?.hashCode ?? 0);

  TrashSyncDecision copyWith({String? id, String? checksum, bool? isSyncApproved}) {
    return TrashSyncDecision(
      assetId: id ?? assetId,
      checksum: checksum ?? this.checksum,
      isSyncApproved: isSyncApproved ?? this.isSyncApproved,
    );
  }
}
