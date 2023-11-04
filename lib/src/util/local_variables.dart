import 'package:flutter/foundation.dart';
import 'package:org_flutter/org_flutter.dart';
import 'package:org_flutter/src/util/elisp.dart';
import 'package:petit_lisp/lisp.dart';
import 'package:petitparser/petitparser.dart';

final _lispParserDef = LispParserDefinition();

class LocalVariablesParser extends GrammarDefinition {
  @override
  Parser start() => ref0(entry).plus().end();

  Parser entry() =>
      (ref0(symbol) & ref0(delimiter).trim() & ref0(atom) & ref0(trailing))
          .map((items) => (key: items[0], value: items[2]));

  Parser symbol() => ref0(symbolToken).flatten('Symbol expected');

  // Patterns taken from LispParserDefinition.symbolToken, but adapted here to
  // stop at the delimiter
  Parser symbolToken() =>
      pattern('a-zA-Z!#\$%&*/:<=>?@\\^_|~+-') &
      pattern('a-zA-Z0-9!#\$%&*/:<=>?@\\^_|~+-')
          .starLazy(ref0(delimiter) | endOfInput());

  Parser delimiter() => char(':') & whitespace();

  // We use atomChoice instead of atom to avoid trimming whitespace
  Parser atom() => _lispParserDef.buildFrom(_lispParserDef.atomChoice());

  Parser trailing() => any().starLazy(ref0(endOfLine)) & ref0(endOfLine);

  Parser endOfLine() => newline() | endOfInput();
}

final localVariablesParser = LocalVariablesParser().build<List<dynamic>>();

Map<String, dynamic> extractLocalVariables(OrgDocument doc) {
  final lvars = doc.find<OrgLocalVariables>((_) => true);
  if (lvars == null) return {};

  final parsed = localVariablesParser.parse(lvars.node.contentString);
  if (parsed is Failure) {
    debugPrint('Failed to parse local variables: $parsed');
    return {};
  }

  final entries = parsed.value.cast<({String key, dynamic value})>();
  final env = ElispEnvironment(StandardEnvironment(NativeEnvironment()));

  final initialKeys = List.of(env.keys);

  for (final (key: symbol, value: value) in entries) {
    switch (symbol) {
      case 'eval':
        try {
          eval(env, value);
        } catch (e) {
          debugPrint('Failed to eval $value: $e');
        }
        break;
      default:
        env.define(Name(symbol), value);
        break;
    }
  }

  final addedKeys = List.of(env.keys)
    ..removeWhere((key) => initialKeys.contains(key));

  return addedKeys.fold<Map<String, dynamic>>(
    {},
    (acc, key) => acc..[key.toString()] = env[key],
  );
}

const _kOrgEntitiesUserKeys = [
  'org-entities-user',
  'org-entities-local',
];

Map<String, String> getOrgEntities(
  Map<String, String> defaults,
  Map<String, dynamic> localVariables,
) {
  if (!_kOrgEntitiesUserKeys.any(localVariables.containsKey)) return defaults;

  final result = Map.of(defaults);

  for (final key in _kOrgEntitiesUserKeys) {
    var userEntities = localVariables[key];
    while (userEntities is Cons) {
      final entry = userEntities.head;
      if (entry is Cons) {
        final name = entry.head;
        // Entries are of the form
        // 1. name
        // 2. LaTeX replacement
        // 3. LaTeX mathp
        // 4. HTML replacement
        // 5. ASCII replacement
        // 6. Latin1 replacement
        // 7. utf-8 replacement
        final value = entry.tail?.tail?.tail?.tail?.tail?.tail?.head;
        if (name is String && value is String) {
          result[name] = value;
        }
      }
      userEntities = userEntities.tail;
    }
  }

  return result;
}
