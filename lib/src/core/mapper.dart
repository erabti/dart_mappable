import 'dart:convert';
import 'dart:developer';

import 'package:collection/collection.dart';

import '../../dart_mappable.dart';
import 'mapper_entry.dart';
import 'type_info.dart';

class Mapper {
  Mapper._();

  final _mappers = <MapperEntry>{
    MapperEntry<dynamic>(PrimitiveMapper((dynamic v) => v)),
    MapperEntry<String>(PrimitiveMapper<String>((dynamic v) => v.toString())),
    MapperEntry<int>(
      PrimitiveMapper<int>(
        (dynamic v) => num.parse(v.toString()).round(),
      ),
    ),
    MapperEntry<double>(
      PrimitiveMapper<double>((dynamic v) => double.parse(v.toString())),
    ),
    MapperEntry<num>(
      PrimitiveMapper<num>((dynamic v) => num.parse(v.toString())),
    ),
    MapperEntry<bool>(
      PrimitiveMapper<bool>(
        (dynamic v) => v is num ? v != 0 : v.toString() == 'true',
      ),
    ),
    MapperEntry<DateTime>(
      DateTimeMapper(),
    ),
    MapperEntry<List>(
      IterableMapper<List>(
        <T>(Iterable<T> i) => i.toList(),
        <T>(f) => f<List<T>>(),
      ),
    ),
    MapperEntry<Set>(
      IterableMapper<Set>(
        <T>(Iterable<T> i) => i.toSet(),
        <T>(f) => f<Set<T>>(),
      ),
    ),
    MapperEntry<Map>(
      MapMapper<Map>(
        <K, V>(Map<K, V> map) => map,
        <K, V>(f) => f<Map<K, V>>(),
      ),
    ),
  };

  static late final _instance = Mapper._();

  static Mapper get i {
    if (!_didInit) {
      throw const MapperException(
        'Used mapper without initialization.',
      );
    }
    return _instance;
  }

  static var _didInit = false;

  static void init(Set<MapperEntry> entries) {
    _didInit = true;
    i._mappers.addAll(entries);
  }

  MapperEntry<T> _resolveEntry<T>([String? t]) {
    final entry = _mappers.whereBaseType(typeOf<T>(t));
    if (entry == null) {
      throw MapperException(
        'Cannot find a mapper of type $T. Unknown type. Did you forgot '
        'to include the class or register a custom mapper?',
      );
    }

    if (entry is! MapperEntry<T>) {
      throw const MapperException(
        'Mismatched type of mapper entry registered',
      );
    }

    return entry;
  }

  MapperEntry<T>? _resolveEntryNullable<T>([String? t]) {
    final entry = _mappers.whereBaseType(typeOf<T>(t));

    if (entry is! MapperEntry<T>) {
      throw const MapperException(
        'Mismatched type of mapper entry registered',
      );
    }

    return entry;
  }

  BaseMapper<T> _resolveMapper<T>([String? t]) => _resolveEntry<T>(t).mapper;

  BaseMapper<T>? _resolveMapperNullable<T>([String? t]) =>
      _resolveEntryNullable<T>(t)?.mapper;

  BaseMapper<T> get<T>() => _resolveMapper<T>();

  BaseMapper<T> getWithType<T>(Type type) => _resolveMapper<T>(type.toString());

  BaseMapper<T>? getWithTypeNullable<T>(Type type) =>
      _resolveMapperNullable<T>(type.toString());

  T fromValue<T>(dynamic value) {
    if (value.runtimeType == T || value == null) {
      return value as T;
    } else {
      final TypeInfo typeInfo;
      if (value is Map<String, dynamic> && value['__type'] != null) {
        typeInfo = TypeInfo.fromType(value['__type'] as String);
      } else {
        typeInfo = TypeInfo.fromType<T>();
      }

      final mapper = _resolveMapper(typeInfo.type);
      try {
        return _genericCall(typeInfo, mapper.decoder!, value) as T;
      } catch (e) {
        throw MapperException(
          'Error on decoding type $T: ${e is MapperException ? e.message : e}',
        );
      }
    }
  }

  dynamic toValue(dynamic value) {
    if (value == null) return null;
    final typeInfo = TypeInfo.fromValue(value);
    final entry = _mappers.whereBaseType(typeInfo.type) ??
        _mappers.firstWhereOrNull((e) => e.mapper.isFor(value));

    final mapper = entry?.mapper;

    if (mapper != null && mapper.encoder != null) {
      final encoded = mapper.encoder!.call(value);
      if (encoded is Map<String, dynamic>) {
        _clearType(encoded);
        if (typeInfo.params.isNotEmpty) {
          typeInfo.type = typeOf(mapper.type.toString());
          encoded['__type'] = typeInfo.toString();
        }
      }
      return encoded;
    } else {
      throw MapperException(
        'Cannot encode value $value of type ${value.runtimeType}. Unknown type. '
        'Did you forgot to include the class or register a custom mapper?',
      );
    }
  }

  T fromMap<T>(Map<String, dynamic> map) => fromValue<T>(map);

  Map<String, dynamic> toMap(dynamic object) {
    final value = toValue(object);
    if (value is Map<String, dynamic>) {
      return value;
    } else {
      throw MapperException(
        'Cannot encode value of type ${object.runtimeType} to Map. '
        'Instead encoded to type ${value.runtimeType}.',
      );
    }
  }

  T fromIterable<T>(Iterable<dynamic> iterable) => fromValue<T>(iterable);

  Iterable<dynamic> toIterable(dynamic object) {
    final value = toValue(object);
    if (value is Iterable<dynamic>) {
      return value;
    } else {
      throw MapperException(
        'Cannot encode value of type ${object.runtimeType} to Iterable. '
        'Instead encoded to type ${value.runtimeType}.',
      );
    }
  }

  T fromJson<T>(String json) => fromValue<T>(jsonDecode(json));

  String toJson(dynamic object) => jsonEncode(toValue(object));

  bool isEqual(dynamic value, Object? other) {
    if (value == null || other == null) {
      return value == other;
    }
    final info = TypeInfo.fromValue(value);
    final mapper = _resolveMapperNullable(info.type);
    return mapper?.equals(value, other) ?? value == other;
  }

  int hash(dynamic value) {
    final info = TypeInfo.fromValue(value);
    final mapper = _resolveMapperNullable(info.type);
    return mapper?.hash(value) ?? value.hashCode;
  }

  String asString(dynamic value) {
    final info = TypeInfo.fromValue(value);
    final mapper = _resolveMapperNullable(info.type);
    return mapper?.stringify(value) ?? value.toString();
  }

  void use<T>(BaseMapper<T> mapper) => _mappers.add(MapperEntry<T>(mapper));

  BaseMapper<T>? unuse<T>() => _mappers.remove(typeOf<T>()) as BaseMapper<T>?;

  void _clearType(Map<String, dynamic> map) {
    map.removeWhere((key, _) => key == '__type');
    map.values.whereType<Map<String, dynamic>>().forEach(_clearType);
    map.values.whereType<Iterable>().forEach(
          (l) => l.whereType<Map<String, dynamic>>().forEach(_clearType),
        );
  }

  dynamic _genericCall(TypeInfo info, Function fn, dynamic value) {
    final params = [...info.params];

    dynamic call(dynamic Function<T>() next) {
      final t = params.removeAt(0);

      try {
        final mapper = _resolveMapper(t.type);
        return _genericCall(t, mapper.typeFactory ?? (f) => f(), next);
      } catch (e) {
        log(e.toString());
        throw MapperException('Cannot find generic wrapper for type $t.');
      }
    }

    if (params.isEmpty) {
      return fn(value);
    } else if (params.length == 1) {
      return call(<A>() => fn<A>(value));
    } else if (params.length == 2) {
      return call(<A>() => call(<B>() => fn<A, B>(value)));
    } else if (params.length == 3) {
      return call(<A>() => call(<B>() => call(<C>() => fn<A, B, C>(value))));
    } else {
      throw MapperException(
        'Cannot construct generic wrapper for type $info. '
        'Mapper only supports generic classes with up to 3 type arguments.',
      );
    }
  }
}

String typeOf<T>([String? t]) => (t ?? T.toString()).split('<')[0];
