import 'package:characters/characters.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

enum DrawMode { allowRepeat, avoidPrevious, cycle }

enum PresentationStyle { gacha, instant }

enum RecordStatus { pending, completed, skipped }

class AppFailure implements Exception {
  final String code;
  final String message;
  const AppFailure(this.code, this.message);
  @override
  String toString() => message;
}

String normalized(String value) => unorm.nfc(value.trim());
String checkedText(
  String value,
  int max, {
  bool required = false,
  bool multiline = false,
}) {
  final text = normalized(value);
  if ((required && text.isEmpty) ||
      text.characters.length > max ||
      RegExp(
        multiline ? r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' : r'[\x00-\x1F\x7F]',
      ).hasMatch(text)) {
    throw AppFailure('validation', '请输入${required ? '1–' : '不超过'}$max 个可见字符');
  }
  return text;
}

DateTime dt(Object? value) => DateTime.parse(value as String).toUtc();
DateTime? nullableDt(Object? value) => value == null ? null : dt(value);

class Collection {
  final String id, name, description, iconKey, colorKey, executionCriterion;
  final DrawMode drawMode;
  final PresentationStyle presentationStyle;
  final int sortOrder;
  final DateTime? archivedAt;
  final DateTime createdAt, updatedAt;
  const Collection({
    required this.id,
    required this.name,
    this.description = '',
    this.iconKey = 'dice',
    this.colorKey = 'sage',
    this.executionCriterion = '',
    this.drawMode = DrawMode.allowRepeat,
    this.presentationStyle = PresentationStyle.gacha,
    this.sortOrder = 0,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  bool get archived => archivedAt != null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'iconKey': iconKey,
    'colorKey': colorKey,
    'executionCriterion': executionCriterion,
    'drawMode': drawMode.name,
    'presentationStyle': presentationStyle.name,
    'sortOrder': sortOrder,
    'archivedAt': archivedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory Collection.fromJson(Map<String, dynamic> m) => Collection(
    id: m['id'],
    name: m['name'],
    description: m['description'],
    iconKey: m['iconKey'],
    colorKey: m['colorKey'],
    executionCriterion: m['executionCriterion'],
    drawMode: DrawMode.values.byName(m['drawMode']),
    presentationStyle: PresentationStyle.values.byName(m['presentationStyle']),
    sortOrder: m['sortOrder'],
    archivedAt: nullableDt(m['archivedAt']),
    createdAt: dt(m['createdAt']),
    updatedAt: dt(m['updatedAt']),
  );
}

class Item {
  final String id, collectionId, title, note;
  final bool enabled;
  final DateTime? archivedAt;
  final int sortOrder;
  final DateTime createdAt, updatedAt;
  const Item({
    required this.id,
    required this.collectionId,
    required this.title,
    this.note = '',
    this.enabled = true,
    this.archivedAt,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });
  bool get available => enabled && archivedAt == null;
  bool get archived => archivedAt != null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'title': title,
    'note': note,
    'enabled': enabled,
    'archivedAt': archivedAt?.toIso8601String(),
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory Item.fromJson(Map<String, dynamic> m) => Item(
    id: m['id'],
    collectionId: m['collectionId'],
    title: m['title'],
    note: m['note'],
    enabled: m['enabled'],
    archivedAt: nullableDt(m['archivedAt']),
    sortOrder: m['sortOrder'],
    createdAt: dt(m['createdAt']),
    updatedAt: dt(m['updatedAt']),
  );
}

class DrawRecord {
  final String id,
      collectionId,
      itemId,
      collectionNameSnapshot,
      itemTitleSnapshot,
      itemNoteSnapshot,
      criterionSnapshot;
  final DrawMode modeSnapshot;
  final PresentationStyle styleSnapshot;
  final String? cycleId;
  final RecordStatus status;
  final DateTime drawnAt, updatedAt;
  final DateTime? completedAt;
  final int drawOrdinal, revision, appGeneration;
  const DrawRecord({
    required this.id,
    required this.collectionId,
    required this.itemId,
    required this.collectionNameSnapshot,
    required this.itemTitleSnapshot,
    this.itemNoteSnapshot = '',
    this.criterionSnapshot = '',
    this.modeSnapshot = DrawMode.allowRepeat,
    this.styleSnapshot = PresentationStyle.gacha,
    this.cycleId,
    this.status = RecordStatus.pending,
    required this.drawnAt,
    required this.updatedAt,
    this.completedAt,
    this.drawOrdinal = 0,
    this.revision = 0,
    this.appGeneration = 0,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'itemId': itemId,
    'collectionNameSnapshot': collectionNameSnapshot,
    'itemTitleSnapshot': itemTitleSnapshot,
    'itemNoteSnapshot': itemNoteSnapshot,
    'criterionSnapshot': criterionSnapshot,
    'modeSnapshot': modeSnapshot.name,
    'styleSnapshot': styleSnapshot.name,
    'cycleId': cycleId,
    'status': status.name,
    'drawnAt': drawnAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
  factory DrawRecord.fromJson(
    Map<String, dynamic> m, {
    int ordinal = 0,
    int revision = 0,
    int appGeneration = 0,
  }) => DrawRecord(
    id: m['id'],
    collectionId: m['collectionId'],
    itemId: m['itemId'],
    collectionNameSnapshot: m['collectionNameSnapshot'],
    itemTitleSnapshot: m['itemTitleSnapshot'],
    itemNoteSnapshot: m['itemNoteSnapshot'],
    criterionSnapshot: m['criterionSnapshot'],
    modeSnapshot: DrawMode.values.byName(m['modeSnapshot']),
    styleSnapshot: PresentationStyle.values.byName(m['styleSnapshot']),
    cycleId: m['cycleId'],
    status: RecordStatus.values.byName(m['status']),
    drawnAt: dt(m['drawnAt']),
    updatedAt: dt(m['updatedAt']),
    completedAt: nullableDt(m['completedAt']),
    drawOrdinal: ordinal,
    revision: revision,
    appGeneration: appGeneration,
  );
}

class CollectionCycle {
  final String id, collectionId;
  final int sequence;
  final Set<String> consumedItemIds;
  final DateTime createdAt;
  CollectionCycle({
    required this.id,
    required this.collectionId,
    required this.sequence,
    Set<String> consumedItemIds = const {},
    required this.createdAt,
  }) : consumedItemIds = Set.unmodifiable(consumedItemIds);
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'sequence': sequence,
    'consumedItemIds': consumedItemIds.toList(),
    'createdAt': createdAt.toIso8601String(),
  };
  factory CollectionCycle.fromJson(Map<String, dynamic> m) => CollectionCycle(
    id: m['id'],
    collectionId: m['collectionId'],
    sequence: m['sequence'],
    consumedItemIds: Set<String>.from(m['consumedItemIds']),
    createdAt: dt(m['createdAt']),
  );
}

class PickerSettings {
  final String themeMode;
  final bool soundEnabled, hapticsEnabled, reduceMotion, redrawHintSeen;
  const PickerSettings({
    this.themeMode = 'system',
    this.soundEnabled = false,
    this.hapticsEnabled = true,
    this.reduceMotion = false,
    this.redrawHintSeen = false,
  });
  PickerSettings copyWith({
    String? themeMode,
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? reduceMotion,
    bool? redrawHintSeen,
  }) => PickerSettings(
    themeMode: themeMode ?? this.themeMode,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    redrawHintSeen: redrawHintSeen ?? this.redrawHintSeen,
  );
  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
    'reduceMotion': reduceMotion,
    'redrawHintSeen': redrawHintSeen,
  };
  factory PickerSettings.fromJson(Map<String, dynamic> m) => PickerSettings(
    themeMode: m['themeMode'],
    soundEnabled: m['soundEnabled'],
    hapticsEnabled: m['hapticsEnabled'],
    reduceMotion: m['reduceMotion'],
    redrawHintSeen: m['redrawHintSeen'] ?? false,
  );
}

class Summary {
  final int total, completed, pending, skipped;
  const Summary({
    required this.total,
    required this.completed,
    required this.pending,
    required this.skipped,
  });
  double? get rate => total == 0 ? null : completed / total;
  String get rateLabel =>
      rate == null ? '—' : '${(rate! * 100).toStringAsFixed(1)}%';
}

enum ImportKind { added, blank, duplicateExisting, duplicateBatch, invalid }

class ImportLine {
  final int lineNumber;
  final String title;
  final ImportKind kind;
  const ImportLine(this.lineNumber, this.title, this.kind);
}

class BatchPreview {
  final List<ImportLine> lines;
  BatchPreview(List<ImportLine> lines) : lines = List.unmodifiable(lines);
  List<String> get titles => lines
      .where((e) => e.kind == ImportKind.added)
      .map((e) => e.title)
      .toList();
  int get added => titles.length;
  int get blank => lines.where((e) => e.kind == ImportKind.blank).length;
  int get duplicates => lines
      .where(
        (e) =>
            e.kind == ImportKind.duplicateExisting ||
            e.kind == ImportKind.duplicateBatch,
      )
      .length;
  int get invalid => lines.where((e) => e.kind == ImportKind.invalid).length;
  bool get canSave => added > 0 && invalid == 0;
}

class BackupPreview {
  final String json;
  final DateTime exportedAt;
  final int collectionCount, itemCount, recordCount;
  const BackupPreview._(
    this.json,
    this.exportedAt,
    this.collectionCount,
    this.itemCount,
    this.recordCount,
  );
  static BackupPreview validated(
    String json,
    DateTime time,
    int collections,
    int items,
    int records,
  ) => BackupPreview._(json, time, collections, items, records);
}
