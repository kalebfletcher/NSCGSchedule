// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FriendAdapter extends TypeAdapter<Friend> {
  @override
  final typeId = 1;

  @override
  Friend read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Friend(
      id: fields[0] as String,
      name: fields[1] as String,
      privacyLevel: fields[2] as PrivacyLevel,
      timetable: fields[3] as FriendTimetable,
      addedAt: fields[4] as DateTime,
      profilePicPath: fields[5] as String?,
      userId: fields[6] as String?,
      isOnlineSync: fields[7] == null ? false : fields[7] as bool,
      syncFileId: fields[8] as String?,
      syncAccessCode: fields[9] as String?,
      syncDecryptionKey: fields[10] as String?,
      syncServerUrl: fields[11] as String?,
      lastSyncedAt: fields[12] as DateTime?,
      isHidden: fields[13] == null ? false : fields[13] as bool,
      grantedAccessCode: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Friend obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.privacyLevel)
      ..writeByte(3)
      ..write(obj.timetable)
      ..writeByte(4)
      ..write(obj.addedAt)
      ..writeByte(5)
      ..write(obj.profilePicPath)
      ..writeByte(6)
      ..write(obj.userId)
      ..writeByte(7)
      ..write(obj.isOnlineSync)
      ..writeByte(8)
      ..write(obj.syncFileId)
      ..writeByte(9)
      ..write(obj.syncAccessCode)
      ..writeByte(10)
      ..write(obj.syncDecryptionKey)
      ..writeByte(11)
      ..write(obj.syncServerUrl)
      ..writeByte(12)
      ..write(obj.lastSyncedAt)
      ..writeByte(13)
      ..write(obj.isHidden)
      ..writeByte(14)
      ..write(obj.grantedAccessCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FriendTimetableAdapter extends TypeAdapter<FriendTimetable> {
  @override
  final typeId = 2;

  @override
  FriendTimetable read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FriendTimetable(days: (fields[0] as List).cast<FriendDaySchedule>());
  }

  @override
  void write(BinaryWriter writer, FriendTimetable obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.days);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendTimetableAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FriendDayScheduleAdapter extends TypeAdapter<FriendDaySchedule> {
  @override
  final typeId = 3;

  @override
  FriendDaySchedule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FriendDaySchedule(
      weekday: fields[0] as String,
      lessons: (fields[1] as List).cast<FriendLesson>(),
    );
  }

  @override
  void write(BinaryWriter writer, FriendDaySchedule obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.weekday)
      ..writeByte(1)
      ..write(obj.lessons);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendDayScheduleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FriendLessonAdapter extends TypeAdapter<FriendLesson> {
  @override
  final typeId = 4;

  @override
  FriendLesson read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FriendLesson(
      startTime: fields[0] as String,
      endTime: fields[1] as String,
      name: fields[2] as String?,
      room: fields[3] as String?,
      courseCode: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FriendLesson obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.startTime)
      ..writeByte(1)
      ..write(obj.endTime)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.room)
      ..writeByte(4)
      ..write(obj.courseCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendLessonAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PrivacyLevelAdapter extends TypeAdapter<PrivacyLevel> {
  @override
  final typeId = 0;

  @override
  PrivacyLevel read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PrivacyLevel.freeTimeOnly;
      case 1:
        return PrivacyLevel.busyBlocks;
      case 2:
        return PrivacyLevel.fullDetails;
      default:
        return PrivacyLevel.freeTimeOnly;
    }
  }

  @override
  void write(BinaryWriter writer, PrivacyLevel obj) {
    switch (obj) {
      case PrivacyLevel.freeTimeOnly:
        writer.writeByte(0);
      case PrivacyLevel.busyBlocks:
        writer.writeByte(1);
      case PrivacyLevel.fullDetails:
        writer.writeByte(2);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacyLevelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
