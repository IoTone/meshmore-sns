// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The CI file has to be at the repository root, because that is the only place
/// GitHub reads a workflow from, and every `working-directory` in it has to name
/// a real project.
///
/// It used to live at `meshmore_sns_app/.github/workflows/ci.yml`, where no run
/// could ever start, and its paths (`packages/meshcore`, `responsive_starter_app`)
/// were relative to that same wrong place. Both halves of that defect were
/// invisible to every other test in this tree, so this is the test that makes
/// them visible: move the file or break a path and the suite goes red.
void main() {
  late Directory repo;

  setUpAll(() {
    repo = _repoRoot();
  });

  test('the workflow sits where GitHub looks for it', () {
    expect(
      File('${repo.path}/.github/workflows/ci.yml').existsSync(),
      isTrue,
      reason: 'repository root is ${repo.path}',
    );
  });

  test('no workflow is left under meshmore_sns_app/', () {
    // An empty directory cannot be tracked by git, so the invariant is about
    // files: any workflow file here is one GitHub will never read.
    final Directory stray = Directory('${repo.path}/meshmore_sns_app/.github');
    if (!stray.existsSync()) return;
    final List<String> workflows = <String>[
      for (final FileSystemEntity entity in stray.listSync(recursive: true))
        if (entity is File &&
            (entity.path.endsWith('.yml') || entity.path.endsWith('.yaml')))
          entity.path,
    ];
    expect(workflows, isEmpty,
        reason: 'a workflow there is never read, so it guards nothing');
  });

  test('every job runs at least one command, and the app gate is fatal', () {
    // A job with no `run:` step is a job that passes by doing nothing, and a
    // workflow can lose its steps in an edit that still looks right. The app
    // job's analyzer also has to be fatal: the tree is at zero issues, so an
    // info-level lint that does not fail the gate is a lint nobody fixes.
    final List<String> lines =
        File('${repo.path}/.github/workflows/ci.yml').readAsLinesSync();
    final List<(String, List<String>)> jobs = <(String, List<String>)>[];
    bool inJobs = false;
    for (final String line in lines) {
      if (line.trimRight() == 'jobs:') {
        inJobs = true;
        continue;
      }
      if (!inJobs) continue;
      final RegExpMatch? job = RegExp(r'^  ([a-z][a-z0-9-]*):$').firstMatch(line);
      if (job != null) {
        jobs.add((job.group(1)!, <String>[]));
        continue;
      }
      if (jobs.isNotEmpty) jobs.last.$2.add(line);
    }
    expect(jobs, isNotEmpty, reason: 'the workflow declares no jobs');
    for (final (String name, List<String> body) in jobs) {
      expect(body.where((String l) => l.trimLeft().startsWith('run:')),
          isNotEmpty,
          reason: 'job $name would pass without running anything');
    }
    final String appJob =
        jobs.firstWhere(((String, List<String>) j) => j.$1 == 'app-analyze').$2.join('\n');
    expect(appJob, contains('--fatal-infos'),
        reason: 'the app analyzer has to fail on an info-level lint');
  });

  test('every working-directory names a directory with a project in it', () {
    final File workflow = File('${repo.path}/.github/workflows/ci.yml');
    final List<String> dirs = <String>[
      for (final String line in workflow.readAsLinesSync())
        if (line.trimLeft().startsWith('working-directory:'))
          line
              .substring(line.indexOf('working-directory:') +
                  'working-directory:'.length)
              .trim()
              .replaceAll('"', '')
              .replaceAll("'", ''),
    ];
    expect(dirs, isNotEmpty,
        reason: 'each job has to say which project it runs in');

    for (final String rel in dirs) {
      final Directory dir = Directory('${repo.path}/$rel');
      expect(dir.existsSync(), isTrue,
          reason: 'working-directory $rel is gone');
      final bool isProject = File('${dir.path}/pubspec.yaml').existsSync() ||
          File('${dir.path}/gradlew').existsSync();
      expect(isProject, isTrue,
          reason: '$rel has neither a pubspec.yaml nor a gradlew, so no job '
              'can run in it');
    }
  });
}

/// Walks up from the package directory to the repository root.
///
/// The markers are the two project trees, not the workflow itself: if the
/// workflow were the marker, the root would be unfindable exactly when the file
/// is missing, which is the case this test exists to catch.
Directory _repoRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    final bool hasBoth = Directory('${dir.path}/libmeshcore').existsSync() &&
        Directory('${dir.path}/meshmore_sns_app').existsSync();
    if (hasBoth) return dir;
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('no repository root above ${Directory.current.path}: expected a '
      'directory holding both libmeshcore/ and meshmore_sns_app/');
}
