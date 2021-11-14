import '../../dart_mappable.dart';
import 'mapper.dart';

mixin Mappable {
  BaseMapper? get _mapper => Mapper.i.getWithTypeNullable(runtimeType);

  String toJson() => Mapper.i.toJson(this);

  Map<String, dynamic> toMap() => Mapper.i.toMap(this);

  @override
  String toString() => _mapper?.stringify(this) ?? super.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (runtimeType == other.runtimeType &&
          (_mapper?.equals(this, other) ?? super == other));

  @override
  int get hashCode => _mapper?.hash(this) ?? super.hashCode;
}

extension MapGet on Map<String, dynamic> {
  T get<T>(String key, {MappingHooks? hooks}) => hooked(hooks, key, (v) {
        if (v == null) {
          throw MapperException('Parameter $key is required.');
        }
        return Mapper.i.fromValue<T>(v);
      });

  T? getOpt<T>(String key, {MappingHooks? hooks}) => hooked(hooks, key, (v) {
        if (v == null) {
          return null;
        }
        return Mapper.i.fromValue<T>(v);
      });

  List<T> getList<T>(String key, {MappingHooks? hooks}) =>
      hooked(hooks, key, (v) {
        if (v == null) {
          throw MapperException('Parameter $key is required.');
        } else if (v is! List) {
          throw MapperException('Parameter $v with key $key is not a List');
        }
        return v.map((dynamic item) => Mapper.i.fromValue<T>(item)).toList();
      });

  List<T>? getListOpt<T>(String key, {MappingHooks? hooks}) =>
      hooked(hooks, key, (v) {
        if (v == null) {
          return null;
        } else if (v is! List) {
          throw MapperException('Parameter $v with key $key is not a List');
        }
        return v.map((dynamic item) => Mapper.i.fromValue<T>(item)).toList();
      });

  Map<K, V> getMap<K, V>(String key, {MappingHooks? hooks}) => hooked(
        hooks,
        key,
        (v) {
          if (v == null) {
            throw MapperException('Parameter $key is required.');
          } else if (v is! Map) {
            throw MapperException('Parameter $v with key $key is not a Map');
          }
          return v.map(
            (dynamic key, dynamic value) => MapEntry(
              Mapper.i.fromValue<K>(key),
              Mapper.i.fromValue<V>(value),
            ),
          );
        },
      );

  Map<K, V>? getMapOpt<K, V>(String key, {MappingHooks? hooks}) =>
      hooked(hooks, key, (v) {
        if (v == null) {
          return null;
        } else if (v is! Map) {
          throw MapperException('Parameter $v with key $key is not a Map');
        }

        return v.map(
          (dynamic key, dynamic value) => MapEntry(
            Mapper.i.fromValue<K>(key),
            Mapper.i.fromValue<V>(value),
          ),
        );
      });

  T hooked<T>(MappingHooks? hooks, String key, T Function(dynamic v) fn) {
    if (hooks == null) {
      return fn(this[key]);
    } else {
      return hooks.afterDecode(fn(hooks.beforeDecode(this[key]))) as T;
    }
  }
}

T $identity<T>(T value) => value;

typedef Then<$T, $R> = $R Function($T);

class _None {
  const _None();
}

const _none = _None();

class BaseCopyWith<$T, $R> {
  BaseCopyWith(this.value, this.then);

  final $T value;
  final Then<$T, $R> then;

  T or<T>(Object? _v, T v) => _v == _none ? v : _v as T;
}
