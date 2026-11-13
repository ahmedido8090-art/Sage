// utils/friendly_error.dart
//
// Turns whatever went wrong into something a person can act on. Raw
// exception text never reaches the screen: it goes to the debug log, and the
// user sees a calm sentence plus what to try.
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ErrorKind { generic, timeout, storage, band, permission, data }

class FriendlyError {
  final ErrorKind kind;
  final String title;
  final String message;
  const FriendlyError(this.kind, this.title, this.message);
}

FriendlyError humanizeError(Object? error, {StackTrace? stackTrace}) {
  if (error != null) debugPrint('Handled error: $error\n${stackTrace ?? ''}');
  final text = error?.toString().toLowerCase() ?? '';

  if (error is TimeoutException || text.contains('timed out')) {
    return const FriendlyError(
      ErrorKind.timeout,
      'That took a little too long',
      'Nothing was lost. Give it another go in a moment.',
    );
  }
  if (error is PlatformException && text.contains('permission') ||
      text.contains('permission') ||
      text.contains('not authorized')) {
    return const FriendlyError(
      ErrorKind.permission,
      'Sage needs a little permission',
      'Allow access when your phone asks, or switch it on in Settings.',
    );
  }
  if (text.contains('bluetooth') ||
      text.contains('gatt') ||
      text.contains('rfcomm') ||
      text.contains('characteristic') ||
      text.contains('connect')) {
    return const FriendlyError(
      ErrorKind.band,
      'Your band didn\'t connect',
      'Make sure it is on and nearby, then try again. Bluetooth sometimes '
          'needs a second go.',
    );
  }
  if (error is FormatException ||
      text.contains('type \'') && text.contains('subtype')) {
    return const FriendlyError(
      ErrorKind.data,
      'Some of your data looks a bit tangled',
      'Sage skipped what it couldn\'t read. Pull to refresh to try again.',
    );
  }
  if (error is FileSystemException ||
      text.contains('hive') ||
      text.contains('disk')) {
    return const FriendlyError(
      ErrorKind.storage,
      'Couldn\'t reach your saved data',
      'Your phone may be low on storage. Free a little space and try again.',
    );
  }
  return const FriendlyError(
    ErrorKind.generic,
    'Something didn\'t go to plan',
    'It\'s not you. Try again, and if it keeps happening, restart Sage.',
  );
}
