import 'package:hive/hive.dart';
import 'package:immich_mobile/constants/hive_box.dart';
import 'package:immich_mobile/shared/models/album.dart';
import 'package:immich_mobile/shared/models/asset.android.dart';
import 'package:immich_mobile/shared/models/user.dart';
import 'package:isar/isar.dart';
import 'package:openapi/api.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:immich_mobile/utils/builtin_extensions.dart';
import 'package:path/path.dart' as p;
import 'package:immich_mobile/shared/models/asset.base.dart'
    if (Platform.isAndroid) 'package:immich_mobile/shared/models/asset.android.dart'
    if (Platform.isIOS) 'package:immich_mobile/shared/models/asset.ios.dart';

// export 'package:immich_mobile/shared/models/asset.android.dart';

part 'asset.g.dart';

typedef LocalId = BaseLocalId;

/// Asset (online or local)
@Collection()
class Asset extends BaseAsset {
  Asset.remote(AssetResponseDto? remote, [User? owner])
      : remoteId = remote!.id,
        createdAt = DateTime.parse(remote.createdAt),
        modifiedAt = DateTime.parse(remote.modifiedAt),
        durationInSeconds = remote.duration.toDuration().inSeconds,
        height = remote.exifInfo?.exifImageHeight?.toInt(),
        width = remote.exifInfo?.exifImageWidth?.toInt(),
        name = remote.exifInfo?.imageName,
        originalExtension = p.extension(remote.originalPath),
        livePhotoVideoId = remote.livePhotoVideoId,
        deviceAssetId = remote.deviceAssetId,
        deviceId = remote.deviceId,
        latitude = remote.exifInfo?.latitude?.toDouble(),
        longitude = remote.exifInfo?.longitude?.toDouble(),
        exifInfo =
            remote.exifInfo != null ? ExifInfo.fromDto(remote.exifInfo!) : null,
        super(null) {
    this.owner.value = owner;
  }

  Asset.local(AssetEntity? local, User? owner)
      : latitude = local!.latitude,
        longitude = local.longitude,
        durationInSeconds = local.duration,
        height = local.height,
        width = local.width,
        name = local.title != null ? p.withoutExtension(local.title!) : null,
        originalExtension =
            local.title != null ? p.extension(local.title!) : null,
        deviceAssetId = local.id,
        deviceId = Hive.box(userInfoBox).get(deviceIdKey),
        modifiedAt = local.modifiedDateTime,
        createdAt = local.createDateTime,
        super(int.tryParse(local.id)) {
    this.owner.value = owner;
  }

  Asset(
    this.id,
    this.createdAt,
    this.durationInSeconds,
    this.modifiedAt,
    this.deviceAssetId,
    this.deviceId,
  ) : super(null);

  // TODO delete if no longer needed
  /*
  @ignore
  AssetResponseDto? get _remote {
    if (isRemote && __remote == null) {
      final ownerId = owner.value?.id ?? _tempOwnerId;
      __remote = AssetResponseDto(
        type: isImage ? AssetTypeEnum.IMAGE : AssetTypeEnum.VIDEO,
        id: remoteId!,
        deviceAssetId: deviceAssetId,
        ownerId: ownerId!,
        deviceId: deviceId,
        livePhotoVideoId: livePhotoVideoId,
        originalPath:
            'upload/$ownerId}/original/$deviceId/$remoteId$originalExtension',
        resizePath: 'upload/$ownerId/thumb/$deviceId/$remoteId.jpeg',
        createdAt: createdAt.toIso8601String(),
        modifiedAt: modifiedAt.toIso8601String(),
        isFavorite: false,
        mimeType: '',
        duration: duration.toString(),
        webpPath: 'upload/$ownerId/original/$deviceId/$remoteId.webp',
        exifInfo: ExifResponseDto(
          exifImageWidth: width,
          exifImageHeight: height,
          imageName: name,
          latitude: latitude,
          longitude: longitude,
          modifyDate: modifiedAt,
          dateTimeOriginal: createdAt,
        ),
      );
    }
    return __remote;
  }
  */

  @ignore
  AssetEntity? get local {
    if (isLocal && _local == null) {
      _local = AssetEntity(
        id: localId!.toString(),
        typeInt: isImage ? 1 : 2,
        width: width!,
        height: height!,
        duration: durationInSeconds,
        createDateSecond: createdAt.millisecondsSinceEpoch ~/ 1000,
        latitude: latitude,
        longitude: longitude,
        modifiedDateSecond: modifiedAt.millisecondsSinceEpoch ~/ 1000,
        title: name,
      );
    }
    return _local;
  }

  @ignore
  AssetEntity? _local;

  Id id = Isar.autoIncrement;

  @Index(unique: false, replace: false, type: IndexType.hash)
  String? remoteId;

  @Index(
    unique: true,
    replace: false,
    type: IndexType.hash,
    composite: [CompositeIndex('deviceId', type: IndexType.hash)],
  )
  String deviceAssetId;

  String deviceId;

  DateTime createdAt;

  DateTime modifiedAt;

  double? latitude;

  double? longitude;

  int durationInSeconds;

  int? width;

  int? height;

  String? name;

  String? originalExtension;

  String? livePhotoVideoId;

  ExifInfo? exifInfo;

  final IsarLink<User> owner = IsarLink<User>();
  @Backlink(to: 'assets')
  final IsarLinks<Album> albums = IsarLinks<Album>();

  // convenince getters:

  @ignore
  bool get isRemote => remoteId != null;

  @ignore
  bool get isLocal => localId != null;

  @ignore
  bool get isImage => durationInSeconds == 0;

  @ignore
  Duration get duration => Duration(seconds: durationInSeconds);

  @override
  bool operator ==(other) {
    if (other is! Asset) return false;
    return id == other.id;
  }

  @override
  @ignore
  int get hashCode => id.hashCode;
}

@embedded
class ExifInfo {
  int? fileSize;
  String? make;
  String? model;
  String? orientation;
  String? lensModel;
  double? fNumber;
  double? focalLength;
  int? iso;
  double? exposureTime;
  DateTime? dateTimeOriginal;
  DateTime? modifyDate;
  String? city;
  String? state;
  String? country;

  ExifInfo();

  ExifInfo.fromDto(ExifResponseDto dto)
      : fileSize = dto.fileSizeInByte,
        make = dto.make,
        model = dto.model,
        orientation = dto.orientation,
        lensModel = dto.lensModel,
        fNumber = dto.fNumber?.toDouble(),
        focalLength = dto.focalLength?.toDouble(),
        iso = dto.iso?.toInt(),
        exposureTime = dto.exposureTime?.toDouble(),
        dateTimeOriginal = dto.dateTimeOriginal,
        modifyDate = dto.modifyDate,
        city = dto.city,
        state = dto.state,
        country = dto.country;
}

extension AssetsHelper on IsarCollection<Asset> {
  Future<int> deleteAllByRemoteId(Iterable<String> ids) =>
      ids.isEmpty ? Future.value(0) : _remote(ids).deleteAll();
  Future<int> deleteAllByLocalId(Iterable<LocalId> ids) =>
      ids.isEmpty ? Future.value(0) : _local(ids).deleteAll();
  Future<List<Asset>> getAllByRemoteId(Iterable<String> ids) =>
      ids.isEmpty ? Future.value([]) : _remote(ids).findAll();
  Future<List<Asset>> getAllByLocalId(Iterable<LocalId> ids) =>
      ids.isEmpty ? Future.value([]) : _local(ids).findAll();

  QueryBuilder<Asset, Asset, QAfterWhereClause> _remote(Iterable<String> ids) =>
      where().anyOf(ids, (q, String e) => q.remoteIdEqualTo(e));
  QueryBuilder<Asset, Asset, QAfterWhereClause> _local(Iterable<LocalId> ids) {
    return where().anyOf(ids, (q, LocalId e) => q.localIdEqualTo(e));
  }
}

extension AssetResponseDtoHelper on AssetResponseDto {
  LocalId get localId => localIdFromString(deviceAssetId);
}

extension AssetEntityHelper on AssetEntity {
  LocalId get localId => localIdFromString(id);
}

extension AssetIdHelper on String {
  LocalId get asLocalId => localIdFromString(this);
}
