import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

import 'mappers.dart';

class MapperEntry<T> with EquatableMixin {
  MapperEntry(this.mapper);

  String get baseType => T.toString().split('<')[0];
  final BaseMapper<T> mapper;

  @override
  List<Object?> get props => [baseType];
}

extension MapperEntryX<T> on Iterable<MapperEntry<T>> {
  MapperEntry<T>? whereBaseType(String type) =>
      firstWhereOrNull((entry) => entry.baseType == type);
}
