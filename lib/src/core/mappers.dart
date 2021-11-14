import 'package:collection/collection.dart';

import 'mapper.dart';

/// This class needs to be implemented by all mappers
abstract class BaseMapper<T> {
  const BaseMapper();

  Function? get decoder => null;

  Function? get encoder => null;

  Function? get typeFactory => (f) => f<T>();

  bool? equals(T self, T other) => null;

  int? hash(T self) => null;

  String? stringify(T self) => null;

  Type get type => T;

  bool isFor(dynamic v) => v is T;

  R checked<R, U>(dynamic v, R Function(U) fn) {
    if (v is U) {
      return fn(v);
    } else {
      throw MapperException(
        'Cannot decode value of type ${v.runtimeType} to type $R,'
        ' because a value of type $U is expected.',
      );
    }
  }
}

/// Simple wrapper around the [BaseMapper] class that provides direct abstract function declarations
abstract class SimpleMapper<T> extends BaseMapper<T> {
  const SimpleMapper();

  @override
  Function get encoder => encode;

  dynamic encode(T self);

  @override
  Function get decoder => decode;

  T decode(dynamic value);
}

class MapperEquality implements Equality {
  @override
  bool equals(dynamic e1, dynamic e2) => Mapper.i.isEqual(e1, e2);

  @override
  int hash(dynamic e) => Mapper.i.hash(e);

  @override
  bool isValidKey(Object? o) => true;
}

mixin MapperEqualityMixin<T> implements BaseMapper<T> {
  Equality get equality;

  @override
  bool? equals(T self, T other) => equality.equals(self, other);

  @override
  int? hash(T self) => equality.hash(self);
}

class MapperException implements Exception {
  final String message;

  const MapperException(this.message);

  @override
  String toString() => 'MapperException: $message';
}

class DateTimeMapper extends SimpleMapper<DateTime> {
  @override
  DateTime decode(dynamic d) {
    if (d is String) {
      return DateTime.parse(d);
    } else if (d is num) {
      return DateTime.fromMillisecondsSinceEpoch(d.round());
    } else {
      throw MapperException(
        'Cannot decode value of type ${d.runtimeType} to type DateTime, '
        'because a value of type String or num is expected.',
      );
    }
  }

  @override
  String encode(DateTime self) {
    return self.toUtc().toIso8601String();
  }
}

class IterableMapper<I extends Iterable> extends BaseMapper<I>
    with MapperEqualityMixin<I> {
  Iterable<U> Function<U>(Iterable<U> iterable) fromIterable;

  IterableMapper(this.fromIterable, this.typeFactory);

  @override
  Function get decoder => <T>(dynamic l) => checked(
        l,
        (Iterable l) => fromIterable(
          l.map(
            (v) => Mapper.i.fromValue<T>(v),
          ),
        ),
      );

  @override
  Function get encoder =>
      (I self) => self.map((v) => Mapper.i.toValue(v)).toList();
  @override
  Function typeFactory;

  @override
  Equality equality = IterableEquality(MapperEquality());
}

class MapMapper<M extends Map> extends BaseMapper<M>
    with MapperEqualityMixin<M> {
  Map<K, V> Function<K, V>(Map<K, V> map) fromMap;

  MapMapper(this.fromMap, this.typeFactory);

  @override
  Function get decoder => <K, V>(dynamic m) => checked(
        m,
        (Map m) => fromMap(
          m.map(
            (key, value) => MapEntry(
              Mapper.i.fromValue<K>(key),
              Mapper.i.fromValue<V>(value),
            ),
          ),
        ),
      );

  @override
  Function get encoder => (M self) => self.map(
        (key, value) => MapEntry(
          Mapper.i.toValue(key),
          Mapper.i.toValue(value),
        ),
      );

  @override
  Function typeFactory;

  @override
  Equality equality =
      MapEquality(keys: MapperEquality(), values: MapperEquality());
}

class PrimitiveMapper<T> extends BaseMapper<T> {
  const PrimitiveMapper(this.decoder);

  @override
  final T Function(dynamic value) decoder;

  @override
  Function get encoder => (T value) => value;

  @override
  Function get typeFactory => (f) => f<T>();

  @override
  bool isFor(dynamic v) => v.runtimeType == T;
}

class EnumMapper<T> extends SimpleMapper<T> {
  EnumMapper(this._decoder, this._encoder);

  final T Function(String value) _decoder;
  final String Function(T value) _encoder;

  @override
  T decode(dynamic v) => checked(v, _decoder);

  @override
  dynamic encode(T value) => _encoder(value);
}
