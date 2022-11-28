import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/hive_box.dart';
import 'package:immich_mobile/modules/backup/models/hive_backup_albums.model.dart';
import 'package:immich_mobile/shared/models/album.dart';
import 'package:immich_mobile/shared/models/asset.dart';
import 'package:immich_mobile/shared/models/user.dart';
import 'package:immich_mobile/shared/providers/api.provider.dart';
import 'package:immich_mobile/shared/providers/db.provider.dart';
import 'package:immich_mobile/shared/services/api.service.dart';
import 'package:immich_mobile/shared/services/asset.service.dart';
import 'package:immich_mobile/shared/services/user.service.dart';
import 'package:immich_mobile/utils/diff.dart';
import 'package:isar/isar.dart';
import 'package:openapi/api.dart';
import 'package:photo_manager/photo_manager.dart';

final albumServiceProvider = Provider(
  (ref) => AlbumService(
    ref.watch(apiServiceProvider),
    ref.watch(assetServiceProvider),
    ref.watch(userServiceProvider),
    ref.watch(dbProvider),
  ),
);

class AlbumService {
  final ApiService _apiService;
  final AssetService _assetService;
  final UserService _userService;
  final Isar _db;
  Completer<bool> _completer = Completer()..complete(false);

  AlbumService(
    this._apiService,
    this._assetService,
    this._userService,
    this._db,
  );

  Future<bool> refreshDeviceAlbums() async {
    if (!_completer.isCompleted) {
      return _completer.future;
    }
    final Stopwatch sw = Stopwatch()..start();
    _completer = Completer();
    bool changes = false;
    try {
      changes = await _refreshDeviceAlbums();
    } finally {
      _completer.complete(changes);
    }
    debugPrint("refreshDeviceAlbums took ${sw.elapsedMilliseconds}ms");
    return changes;
  }

  Future<bool> _refreshDeviceAlbums() async {
    final List<AssetPathEntity> onDevice = await PhotoManager.getAssetPathList(
      hasAll: false,
      filterOption: FilterOptionGroup(containsPathModified: true),
    );
    HiveBackupAlbums? infos =
        Hive.box<HiveBackupAlbums>(hiveBackupInfoBox).get(backupInfoKey);
    if (infos == null) {
      return false;
    }
    if (infos.excludedAlbumsIds.isNotEmpty) {
      onDevice.removeWhere((e) => infos.excludedAlbumsIds.contains(e.id));
    }
    if (infos.selectedAlbumIds.isNotEmpty) {
      onDevice.removeWhere((e) => !infos.selectedAlbumIds.contains(e.id));
    }
    onDevice.sort((a, b) => a.id.compareTo(b.id));

    final List<Album> inDb =
        await _db.albums.where().localIdIsNotNull().sortByLocalId().findAll();
    final List<Asset> deleteCandidates = [];
    final List<Asset> existing = [];

    final bool anyChanges = await diffSortedLists(
      onDevice,
      inDb,
      compare: (AssetPathEntity a, Album b) => a.id.compareTo(b.localId!),
      both: (AssetPathEntity ape, Album album) =>
          _syncAlbumInDbAndOnDevice(ape, album, deleteCandidates, existing),
      onlyFirst: (AssetPathEntity ape) => _addAlbumFromDevice(ape, existing),
      onlySecond: (Album a) => _removeAlbumFromDb(a, deleteCandidates),
    );

    await _assetService.handleLocalAssetRemoval(deleteCandidates, existing);

    return anyChanges;
  }

  Future<bool> _syncAlbumInDbAndOnDevice(
    AssetPathEntity ape,
    Album album,
    List<Asset> deleteCandidates,
    List<Asset> existing, [
    bool forceRefresh = false,
  ]) async {
    if (!forceRefresh && !await _hasAssetPathEntityChanged(ape, album)) {
      return false;
    }
    if (!forceRefresh && await _tryDeviceAlbumFastSync(ape, album)) {
      return true;
    }

    // general case, e.g. some assets have been deleted
    await album.assets.load();
    final List<Asset> inDb = album.assets.toList(growable: false);
    inDb.sort((a, b) => a.localId!.compareTo(b.localId!));
    List<AssetEntity> onDevice =
        await ape.getAssetListRange(start: 0, end: 0x7fffffffffffffff);
    onDevice.sort((a, b) => a.id.compareTo(b.id));
    final List<Asset> toAdd = [];
    final List<Asset> toDelete = [];
    await diffSortedLists(
      onDevice,
      inDb,
      compare: (AssetEntity a, Asset b) => a.localId.compareTo(b.localId!),
      both: (AssetEntity a, Asset b) => Future.value(false),
      onlyFirst: (AssetEntity a) =>
          toAdd.add(Asset.local(a, album.owner.value)),
      onlySecond: (Asset b) => toDelete.add(b),
    );

    final toLink = await _assetService.linkExistingToLocal(toAdd);

    deleteCandidates.addAll(toDelete);
    existing.addAll(toLink);
    album.name = ape.name;
    album.modifiedAt = ape.lastModified!;
    await _db.writeTxn(() async {
      await _db.assets.putAll(toAdd);
      await album.assets.update(link: toLink + toAdd, unlink: toDelete);
      await _db.albums.put(album);
    });

    return true;
  }

  /// fast path for common case: add new assets to album
  Future<bool> _tryDeviceAlbumFastSync(AssetPathEntity ape, Album album) async {
    final int totalOnDevice = await ape.assetCountAsync;
    final AssetPathEntity? modified = totalOnDevice > album.assetCount
        ? await ape.fetchPathProperties(
            filterOptionGroup: FilterOptionGroup(
              updateTimeCond: DateTimeCond(
                min: album.modifiedAt.add(const Duration(seconds: 1)),
                max: ape.lastModified!,
              ),
            ),
          )
        : null;
    if (modified == null) {
      return false;
    }
    final List<AssetEntity> newAssets = (await modified.getAssetListRange(
      start: 0,
      end: 0x7fffffffffffffff,
    ));
    if (totalOnDevice != album.assets.length + newAssets.length) {
      return false;
    }
    final List<Asset> assetsToAdd =
        newAssets.map((e) => Asset.local(e, album.owner.value)).toList();
    album.modifiedAt = ape.lastModified!;
    final toLink = await _assetService.linkExistingToLocal(assetsToAdd);
    toLink.addAll(assetsToAdd);
    await _db.writeTxn(() async {
      await _db.assets.putAll(assetsToAdd);
      await album.assets.update(link: toLink);
      await _db.albums.put(album);
    });
    return true;
  }

  void _addAlbumFromDevice(AssetPathEntity ape, List<Asset> existing) async {
    final Album newAlbum =
        Album.fromApe(ape, await _userService.getLoggedInUser());
    final List<AssetEntity> deviceAssets =
        await ape.getAssetListRange(start: 0, end: 0x7fffffffffffffff);
    final toAdd =
        deviceAssets.map((e) => Asset.local(e, newAlbum.owner.value)).toList();
    final toLink = await _assetService.linkExistingToLocal(toAdd);
    existing.addAll(toLink);
    newAlbum.assets.addAll(toLink);
    newAlbum.assets.addAll(toAdd);
    await _db.writeTxn(() async {
      await _db.assets.putAll(toAdd);
      await Future.wait(toAdd.map((e) => e.owner.save()));
      await _db.albums.store(newAlbum);
      if (newAlbum.assets.isNotEmpty) {
        newAlbum.albumThumbnailAsset.value = newAlbum.assets.first;
        await newAlbum.albumThumbnailAsset.save();
      }
    });
  }

  void _removeAlbumFromDb(Album album, List<Asset> deleteCandidates) async {
    await _db.writeTxn(() => _db.albums.delete(album.id));
    if (album.isLocal) {
      // delete assets in DB unless they are remote or part of some other album
      deleteCandidates.addAll(album.assets.where((a) => !a.isRemote));
    }
  }

  Future<bool> refreshRemoteAlbums({required bool isShared}) async {
    List<AlbumResponseDto>? serverAlbums =
        await _getRemoteAlbums(isShared: isShared, details: true);
    if (serverAlbums == null) {
      return false;
    }
    serverAlbums.sort((a, b) => a.id.compareTo(b.id));
    final List<Album> dbAlbums = await _db.albums
        .where()
        .remoteIdIsNotNull()
        .filter()
        .sharedEqualTo(isShared)
        .sortByRemoteId()
        .findAll();
    return diffSortedLists(
      serverAlbums,
      dbAlbums,
      compare: (AlbumResponseDto a, Album b) => a.id.compareTo(b.remoteId!),
      both: _syncAlbumInDbAndOnServer,
      onlyFirst: _addAlbumFromServer,
      onlySecond: (Album a) => _removeAlbumFromDb(a, []),
    );
  }

  /// syncs data from server to local DB (does not support syncing changes from local to server)
  Future<bool> _syncAlbumInDbAndOnServer(
    AlbumResponseDto dto,
    Album album,
  ) async {
    final modifiedOnServer = DateTime.parse(dto.modifiedAt).toUtc();
    if (!_hasAlbumResponseDtoChanged(dto, album)) {
      return false;
    }
    dto.assets.sort((a, b) => a.id.compareTo(b.id));
    await album.assets.load();
    final assetsInDb =
        album.assets.where((e) => e.isRemote).toList(growable: false);
    assetsInDb.sort((a, b) => a.remoteId!.compareTo(b.remoteId!));
    final List<String> idsToAdd = [];
    final List<Asset> toUnlink = [];
    await diffSortedLists(
      dto.assets,
      assetsInDb,
      compare: (AssetResponseDto a, Asset b) => a.id.compareTo(b.remoteId!),
      both: (a, b) => Future.value(false),
      onlyFirst: (AssetResponseDto a) => idsToAdd.add(a.id),
      onlySecond: (Asset a) => toUnlink.add(a),
    );

    // update shared users
    final List<User> sharedUsers = album.sharedUsers.toList(growable: false);
    sharedUsers.sort((a, b) => a.id.compareTo(b.id));
    dto.sharedUsers.sort((a, b) => a.id.compareTo(b.id));
    final List<String> userIdsToAdd = [];
    final List<User> usersToUnlink = [];
    await diffSortedLists(
      dto.sharedUsers,
      sharedUsers,
      compare: (UserResponseDto a, User b) => a.id.compareTo(b.id),
      both: (a, b) => Future.value(false),
      onlyFirst: (UserResponseDto a) => userIdsToAdd.add(a.id),
      onlySecond: (User a) => usersToUnlink.add(a),
    );

    album.name = dto.albumName;
    album.shared = dto.shared;
    album.modifiedAt = modifiedOnServer;
    if (album.albumThumbnailAsset.value?.remoteId !=
        dto.albumThumbnailAssetId) {
      album.albumThumbnailAsset.value = await _db.assets
          .where()
          .remoteIdEqualTo(dto.albumThumbnailAssetId)
          .findFirst();
    }
    final assetsToLink = await _db.assets.getAllByRemoteId(idsToAdd);
    final usersToLink = (await _db.users.getAllById(userIdsToAdd)).cast<User>();

    // write & commit all changes to DB
    await _db.writeTxn(() async {
      await album.albumThumbnailAsset.save();
      await album.sharedUsers.update(link: usersToLink, unlink: usersToUnlink);
      await album.assets.update(link: assetsToLink, unlink: toUnlink.cast());
      await _db.albums.put(album);
    });

    return true;
  }

  void _addAlbumFromServer(AlbumResponseDto dto) async {
    final Album a = await Album.fromDto(dto, _db);
    await _db.writeTxn(() => _db.albums.store(a));
  }

  Future<List<AlbumResponseDto>?> _getRemoteAlbums({
    required bool isShared,
    bool details = false,
  }) async {
    try {
      return await _apiService.albumApi.getAllAlbums(
        shared: isShared ? isShared : null,
        details: details ? details : null,
      );
    } catch (e) {
      debugPrint("Error getAllSharedAlbum  ${e.toString()}");
      return null;
    }
  }

  Future<Album?> createAlbum(
    String albumName,
    Iterable<Asset> assets, [
    Iterable<User> sharedUsers = const [],
  ]) async {
    try {
      AlbumResponseDto? remote = await _apiService.albumApi.createAlbum(
        CreateAlbumDto(
          albumName: albumName,
          assetIds: assets.map((asset) => asset.remoteId!).toList(),
          sharedWithUserIds: sharedUsers.map((e) => e.id).toList(),
        ),
      );
      if (remote != null) {
        Album album = await Album.fromDto(remote, _db);
        await _db.writeTxn(() => _db.albums.store(album));
        return album;
      }
    } catch (e) {
      debugPrint("Error createSharedAlbum  ${e.toString()}");
    }
    return null;
  }

  /*
   * Creates names like Untitled, Untitled (1), Untitled (2), ...
   */
  Future<String> _getNextAlbumName() async {
    const baseName = "Untitled";
    for (int round = 0;; round++) {
      final proposedName = "$baseName${round == 0 ? "" : " ($round)"}";

      if (null ==
          await _db.albums.filter().nameEqualTo(proposedName).findFirst()) {
        return proposedName;
      }
    }
  }

  Future<Album?> createAlbumWithGeneratedName(
    Iterable<Asset> assets,
  ) async {
    return createAlbum(
      await _getNextAlbumName(),
      assets,
      [],
    );
  }

  Future<Album?> getAlbumDetail(int albumId) {
    // try {
    //   return await _apiService.albumApi.getAlbumInfo(albumId);
    // } catch (e) {
    //   debugPrint('Error [getAlbumDetail] ${e.toString()}');
    //   return null;
    // }
    return _db.albums.get(albumId);
  }

  Future<AddAssetsResponseDto?> addAdditionalAssetToAlbum(
    Iterable<Asset> assets,
    Album albumId,
  ) async {
    try {
      var result = await _apiService.albumApi.addAssetsToAlbum(
        albumId.remoteId!,
        AddAssetsDto(assetIds: assets.map((asset) => asset.remoteId!).toList()),
      );
      return result;
    } catch (e) {
      debugPrint("Error addAdditionalAssetToAlbum  ${e.toString()}");
      return null;
    }
  }

  Future<bool> addAdditionalUserToAlbum(
    List<String> sharedUserIds,
    Album albumId,
  ) async {
    try {
      final result = await _apiService.albumApi.addUsersToAlbum(
        albumId.remoteId!,
        AddUsersDto(sharedUserIds: sharedUserIds),
      );
      if (result != null) {
        albumId.sharedUsers
            .addAll((await _db.users.getAllById(sharedUserIds)).cast());
        await _db.writeTxn(() => albumId.sharedUsers.save());
        return true;
      }
    } catch (e) {
      debugPrint("Error addAdditionalUserToAlbum  ${e.toString()}");
    }
    return false;
  }

  Future<bool> deleteAlbum(Album album) async {
    try {
      await _apiService.albumApi.deleteAlbum(album.remoteId!);
      return true;
    } catch (e) {
      debugPrint("Error deleteAlbum  ${e.toString()}");
    }
    return false;
  }

  Future<bool> leaveAlbum(String albumId) async {
    try {
      await _apiService.albumApi.removeUserFromAlbum(albumId, "me");

      return true;
    } catch (e) {
      debugPrint("Error deleteAlbum  ${e.toString()}");
      return false;
    }
  }

  Future<bool> removeAssetFromAlbum(
    Album album,
    Iterable<Asset> assets,
  ) async {
    try {
      await _apiService.albumApi.removeAssetFromAlbum(
        album.remoteId!,
        RemoveAssetsDto(
          assetIds: assets.map((e) => e.remoteId!).toList(growable: false),
        ),
      );
      final int countBefore = album.assets.length;
      await _db.writeTxn(() async {
        await album.assets.update(unlink: assets);
        await _db.albums.put(album);
      });
      assert(album.assets.length != countBefore);

      return true;
    } catch (e) {
      debugPrint("Error deleteAlbum  ${e.toString()}");
      return false;
    }
  }

  Future<bool> changeTitleAlbum(
    String albumId,
    String ownerId,
    String newAlbumTitle,
  ) async {
    try {
      await _apiService.albumApi.updateAlbumInfo(
        albumId,
        UpdateAlbumDto(
          albumName: newAlbumTitle,
        ),
      );

      return true;
    } catch (e) {
      debugPrint("Error deleteAlbum  ${e.toString()}");
      return false;
    }
  }
}

Future<bool> _hasAssetPathEntityChanged(AssetPathEntity a, Album b) async {
  return a.name != b.name ||
      a.lastModified != b.modifiedAt ||
      await a.assetCountAsync != b.assets.length;
}

bool _hasAlbumResponseDtoChanged(AlbumResponseDto dto, Album a) {
  return dto.assetCount != a.assetCount ||
      dto.albumName != a.name ||
      dto.albumThumbnailAssetId != a.albumThumbnailAsset.value?.remoteId ||
      dto.shared != a.shared ||
      DateTime.parse(dto.modifiedAt).toUtc() != a.modifiedAt.toUtc();
}
