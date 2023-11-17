import 'dart:developer';

import 'package:petit_lisp/lisp.dart';

// TODO(aaron): more accurate standard env
class ElispEnvironment extends Environment {
  ElispEnvironment(super.owner) {
    define(Name('eq'), _eq);
    // petit_lisp's `set!` does not evaluate the symbol
    define(Name('set'), _set);
    define(Name('setq'), _setq);
    define(Name('debugger'), _debugger);
    evalString(lispParser, this, _standardLibrary);
  }

  static dynamic _eq(Environment env, dynamic args) {
    final a = eval(env, args.head);
    final b = eval(env, args.tail.head);
    return identical(a, b);
  }

  static dynamic _set(Environment env, dynamic args) {
    final sym = eval(env, args.head);
    if (sym is! Name) {
      throw ArgumentError('set: first argument must be a symbol');
    }
    return env[sym] = eval(env, args.tail.head);
  }

  static dynamic _setq(Environment env, dynamic args) {
    dynamic result;
    while (args is Cons) {
      final sym = args.head;
      if (sym is! Name) {
        throw ArgumentError('Invalid setq: $sym is not a symbol');
      }
      args = args.tail;
      result = env.setOrDefine(sym, eval(env, args.head));
      args = args.tail;
    }
    return result;
  }

  static dynamic _debugger(Environment env, dynamic args) {
    debugger();
  }

  static const _standardLibrary = '''
(define t true)
(define nil null)

(define equal =)

(define-macro (defun name args &rest body)
  `(define ,(cons name args) ,@body))

(define-macro (defvar name value)
  `(define ,name ,value))

(define-macro (defmacro name args &rest body)
  `(define-macro ,(cons name args) ,@body))

(defun member (element list &optional compare-fn)
  (if list
    (or ((eval (or compare-fn 'equal)) element (car list))
        (member element (cdr list) compare-fn))))

(defun memq (elt list)
  (member elt list eq))

(defun add-to-list (list-var element &optional appendp compare-fn)
  (if (not (member element (eval list-var) compare-fn))
      (set list-var (if appendp
                        (append (eval list-var) (cons element nil))
                        (cons element (eval list-var)))))
  (eval list-var))

(defmacro dolist (spec &rest body)
  (let ((var (car spec))
        (templist (make-symbol "list"))
        (resultvar (caddr spec)))
    `(let ((,templist ,(cadr spec))
           ,var
           ,@(when resultvar `(,resultvar)))
       (while ,templist
         (setq ,var (car ,templist))
         ,@body
         (setq ,templist (cdr ,templist)))
       ,resultvar)))
''';
}

extension ElispExt on Environment {
  Environment get _root {
    var env = this;
    while (env.owner != null) {
      env = env.owner!;
    }
    return env;
  }

  dynamic setOrDefine(Name key, dynamic value) {
    try {
      return this[key] = value;
    } on ArgumentError {
      return _root.define(key, value);
    }
  }
}
