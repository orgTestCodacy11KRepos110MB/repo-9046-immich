import 'package:isar/isar.dart';

abstract class BaseAsset {
  BaseAsset(this.localId);

  @Index(
    unique: false,
    replace: false,
    type: IndexType.hash,
  )
  String? localId;
}

typedef BaseLocalId = String;

BaseLocalId localIdFromString(String id) => id;
