import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:merging_builder/merging_builder.dart';
import 'package:path/path.dart';
import 'package:source_gen/source_gen.dart';

import 'dart_mappable.dart';
import 'src/builder_options.dart';
import 'src/builders/class_mapper_builder.dart';
import 'src/builders/enum_mapper_builder.dart';
import 'src/utils.dart';

/// Entry point for the builder
Builder buildMappable(BuilderOptions options) {
  const defaultOptions = BuilderOptions({
    'input_files': 'lib/**.dart',
    'output_file': 'lib/main.mapper.dart',
    'header': '',
    'footer': '',
    'sort_assets': false,
  });

  // Apply user set options.
  final _options = defaultOptions.overrideWith(options);

  return MergingBuilder<ResolveStepResult, LibDir>(
    generator: MergedMappableGenerator(_options),
    inputFiles: _options.config['input_files'] as String? ?? '',
    outputFile: _options.config['output_file'] as String? ?? '',
    header: _options.config['header'] as String? ?? '',
    footer: _options.config['footer'] as String? ?? '',
    sortAssets: _options.config['sort_assets'] as bool? ?? false,
  );
}

class MergedMappableGenerator
    extends MergingGenerator<ResolveStepResult, MappableClass> {
  MergedMappableGenerator(this.options);

  final BuilderOptions options;

  @override
  FutureOr<String> generateMergedContent(
    Stream<ResolveStepResult> stream,
  ) async {
    final steps = await stream.toList();
    return generate(options, steps);
  }

  @override
  Stream<ResolveStepResult> generateStream(
    LibraryReader library,
    BuildStep buildStep,
  ) =>
      Stream.value(
        ResolveStepResult(
          library,
          buildStep,
        ),
      );

  @override
  ResolveStepResult generateStreamItemForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) =>
      throw UnimplementedError();
}

class ResolveStepResult {
  ResolveStepResult(this.library, this.step);

  final BuildStep step;
  final LibraryReader library;
}

Future<String> generate(
  BuilderOptions buildOptions,
  List<ResolveStepResult> buildSteps,
) async {
  final options = GlobalOptions.parse(buildOptions.config);
  //List<LibraryElement> libraries, BuildStep buildStep
  Set<String> imports = {
    'dart:convert',
    'package:dart_mappable/dart_mappable.dart',
  };

  Map<String, ClassMapperBuilder> classMappers = {};
  Map<String, EnumMapperBuilder> enumMappers = {};

  Map<String, ClassElement> customMappers = {};

  void addImport(LibraryElement library, BuildStep buildStep) {
    var lib = library.source.uri;
    if (lib.isScheme('asset')) {
      var relativePath =
          posix.relative(lib.path, from: dirname(buildStep.inputId.uri.path));
      imports.add(relativePath.replaceAll('\\', '/'));
    } else if (lib.isScheme('package') &&
        lib.pathSegments.first == buildStep.inputId.package) {
      var libPath = lib.replace(pathSegments: lib.pathSegments.skip(1)).path;
      var input = buildStep.inputId.uri;
      var inputPath =
          input.replace(pathSegments: input.pathSegments.skip(1)).path;
      var relativePath = relative(libPath, from: dirname(inputPath));
      imports.add(relativePath.replaceAll('\\', '/'));
    } else {
      imports.add(lib.toString().replaceAll('\\', '/'));
    }
  }

  for (final step in buildSteps) {
    final libraries = await step.step.resolver.libraries.toList();
    for (var library in libraries) {
      if (library.isInSdk) {
        continue;
      }

      var libraryOptions = options.forLibrary(library);

      var elements = elementsOf(library);

      ClassMapperBuilder? addRecursive(
        ClassElement element, {
        ClassMapperBuilder? subMapper,
        ConstructorElement? annotatedFactory,
      }) {
        if (element.isEnum) {
          if (enumMappers.containsKey(element.name)) {
            return null;
          }

          enumMappers[element.name] =
              EnumMapperBuilder(element, libraryOptions);
        } else {
          if (classMappers.containsKey(element.name)) {
            if (subMapper != null) {
              classMappers[element.name]!.subMappers.add(subMapper);
            }
            return classMappers[element.name];
          }

          var classMapper =
              ClassMapperBuilder(element, libraryOptions, annotatedFactory);

          if (subMapper != null) {
            classMapper.subMappers.add(subMapper);
          }

          if (element.isPrivate) {
            return classMapper;
          }

          classMappers[element.name] = classMapper;

          var supertype = element.supertype;
          if (supertype == null || supertype.isDartCoreObject) {
            supertype =
                element.interfaces.isNotEmpty ? element.interfaces.first : null;
          }

          if (supertype != null && !supertype.isDartCoreObject) {
            var superMapper =
                addRecursive(supertype.element, subMapper: classMapper);
            if (superMapper != null) {
              classMapper.setSuperMapper(superMapper);
            }
          }

          for (var c in element.constructors) {
            if (c.isFactory &&
                c.redirectedConstructor != null &&
                classChecker.hasAnnotationOf(c)) {
              var e = c.redirectedConstructor!.returnType.element;
              addRecursive(e, annotatedFactory: c);
            }
          }

          return classMapper;
        }
      }

      for (var element in elements) {
        if (customMapperChecker.hasAnnotationOf(element)) {
          var mapperIndex = element.allSupertypes
              .indexWhere((t) => mapperChecker.isExactlyType(t));
          if (mapperIndex == -1) {
            throw UnsupportedError(
              'Classes marked with @CustomMapper must extend the BaseMapper class',
            );
          }
          var type = element.allSupertypes[mapperIndex].typeArguments[0];
          customMappers[type.element!.name!] = element;
          addImport(library, step.step);
          addImport(type.element!.library!, step.step);
        } else if (libraryOptions.shouldGenerateFor(element) ||
            (!element.isEnum && classChecker.hasAnnotationOf(element)) ||
            (element.isEnum && enumChecker.hasAnnotationOf(element))) {
          addRecursive(element);
          addImport(library, step.step);
        }
      }
    }
  }

  final classMappersSnippet = classMappers.values
      .map(
        (om) => '  MapperEntry<${om.className}>(${om.mapperName}._()),\n',
      )
      .join();

  final enumMappersSnippet = enumMappers.values
      .map(
        (em) => 'MapperEntry<${em.className}>('
            'EnumMapper<${em.className}>(${em.mapperName}.fromString, '
            '(${em.className} ${em.paramName}) => ${em.paramName}.toStringValue() '
            '),\n',
      )
      .join();
  final customMappersSnippet = customMappers.entries
      .map((e) => 'MapperEntry<${e.key}>(${e.value.name}),\n')
      .join();

  return '''
  ${organizeImports(imports)}
      final _mappers = <MapperEntry>{
      // class mappers
      $classMappersSnippet
      // enum mappers
      $enumMappersSnippet
      // custom mappers
      $customMappersSnippet
      };
      
      void initMapper(){
        Mapper.init(_mappers);
      }
        '''
      '// === GENERATED CLASS MAPPERS AND EXTENSIONS ===\n\n'
      '${classMappers.values.map((om) => om.generateExtensionCode(classMappers)).join('\n\n')}\n'
      '\n\n'
      '// === GENERATED ENUM MAPPERS AND EXTENSIONS ===\n\n'
      '${enumMappers.values.map((em) => em.generateExtensionCode()).join('\n\n')}\n'
      '\n\n';
}

String organizeImports(Set<String> imports) {
  final List<String> sdk = [];
  final List<String> package = [];
  final List<String> relative = [];

  for (var import in imports) {
    if (import.startsWith('dart:')) {
      sdk.add(import);
    } else if (import.startsWith('package:')) {
      package.add(import);
    } else {
      relative.add(import);
    }
  }

  sdk.sort();
  package.sort();
  relative.sort();

  String joined(List<String> s) =>
      s.isNotEmpty ? '${s.map((s) => "import '$s';").join('\n')}\n\n' : '';
  return joined(sdk) + joined(package) + joined(relative);
}
