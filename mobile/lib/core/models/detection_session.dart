import 'package:hive/hive.dart';
import 'ghana_cedi_denomination.dart';

/// Represents a completed or ongoing scanning session.
class DetectionSession {
  final String id;
  final DateTime timestamp;
  final double totalValue;
  final int totalNotes;
  final Map<GhanaCedi, int> denominationCounts;

  DetectionSession({
    required this.id,
    required this.timestamp,
    required this.totalValue,
    required this.totalNotes,
    required this.denominationCounts,
  });

  DetectionSession copyWith({
    String? id,
    DateTime? timestamp,
    double? totalValue,
    int? totalNotes,
    Map<GhanaCedi, int>? denominationCounts,
  }) {
    return DetectionSession(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      totalValue: totalValue ?? this.totalValue,
      totalNotes: totalNotes ?? this.totalNotes,
      denominationCounts: denominationCounts ?? this.denominationCounts,
    );
  }
}

/// Manual Hive Adapter for [DetectionSession].
/// We use a manual adapter to avoid depending on build_runner and hive_generator.
class DetectionSessionAdapter extends TypeAdapter<DetectionSession> {
  @override
  final int typeId = 1; // Unique ID for Hive

  @override
  DetectionSession read(BinaryReader reader) {
    final id = reader.readString();
    final timestamp = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final totalValue = reader.readDouble();
    final totalNotes = reader.readInt();
    
    // Read the map: length, then pairs of (GhanaCedi string name, count)
    final mapLength = reader.readInt();
    final denominationCounts = <GhanaCedi, int>{};
    for (var i = 0; i < mapLength; i++) {
      final denominationStr = reader.readString();
      final count = reader.readInt();
      
      // Parse string back to enum
      final denomination = GhanaCedi.values.firstWhere(
        (e) => e.name == denominationStr,
        // Fallback for safety if enum names change, though they shouldn't.
        orElse: () => GhanaCedi.ghs1, 
      );
      
      denominationCounts[denomination] = count;
    }

    return DetectionSession(
      id: id,
      timestamp: timestamp,
      totalValue: totalValue,
      totalNotes: totalNotes,
      denominationCounts: denominationCounts,
    );
  }

  @override
  void write(BinaryWriter writer, DetectionSession obj) {
    writer.writeString(obj.id);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
    writer.writeDouble(obj.totalValue);
    writer.writeInt(obj.totalNotes);
    
    // Write map
    writer.writeInt(obj.denominationCounts.length);
    obj.denominationCounts.forEach((denomination, count) {
      writer.writeString(denomination.name); // Store enum as string
      writer.writeInt(count);
    });
  }
}
