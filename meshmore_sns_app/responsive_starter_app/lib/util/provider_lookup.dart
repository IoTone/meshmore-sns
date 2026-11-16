// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Looks a provider up by its *registered* type and answers null when the tree
/// does not have it.
///
/// The difference from `context.read<X?>()` is the *value*, not the lookup.
/// `Provider<X>` registers a scope for `X?` (provider 6.1.5 creates
/// `_InheritedProviderScope<T?>`), so a nullable lookup does find it. What
/// differs is what happens when the value itself is null: `Provider.of<X>`
/// throws `ProviderNullException`, while `Provider.of<X?>` returns null. These
/// helpers ask for `T` and catch only `ProviderNotFoundException`, so a
/// registered provider whose value is null still throws rather than being
/// silently read as absent.
///
/// An earlier version of this comment claimed the lookup types did not match.
/// They do, and the claim taught the codebase that twenty working nullable
/// lookups were broken.
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
