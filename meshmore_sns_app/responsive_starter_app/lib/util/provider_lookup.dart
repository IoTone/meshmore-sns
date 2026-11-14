// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Looks a provider up by its *registered* type and answers null when the tree
/// does not have it.
///
/// `context.read<X?>()` looks like the tolerant spelling and is not: a provider
/// registered as `X` does not match a lookup for `X?`, so the nullable form
/// returns null in the app and only works in a test that happened to register
/// the nullable type. That silent mismatch has cost this app two bugs — a strip
/// that never drew and an offer store that was recreated per sheet.
///
/// These helpers ask for `T`, which is what `Provider<T>` registers, and treat
/// "not there" as absence rather than as a null value.
T? readOrNull<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// [readOrNull] for a widget that should rebuild when the value is replaced.
T? watchOrNull<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}
