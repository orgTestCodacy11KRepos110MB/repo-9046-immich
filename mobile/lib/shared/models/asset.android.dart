import 'package:isar/isar.dart';

abstract class BaseAsset {
  BaseAsset(this.localId);

  @Index(
    unique: false,
    replace: false,
    type: IndexType.value,
  )
  int? localId;
}

typedef BaseLocalId = int;

BaseLocalId localIdFromString(String id) => int.parse(id);
