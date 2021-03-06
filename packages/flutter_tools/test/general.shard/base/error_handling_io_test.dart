// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/error_handling_io.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/globals.dart' as globals show flutterUsage;
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as path; // ignore: package_path_import

import '../../src/common.dart';
import '../../src/context.dart';

class MockFile extends Mock implements File {}
class MockFileSystem extends Mock implements FileSystem {}
class MockPathContext extends Mock implements path.Context {}
class MockDirectory extends Mock implements Directory {}
class MockRandomAccessFile extends Mock implements RandomAccessFile {}
class MockProcessManager extends Mock implements ProcessManager {}
class MockUsage extends Mock implements Usage {}

final Platform windowsPlatform = FakePlatform(
  operatingSystem: 'windows',
  environment: <String, String>{}
);

final Platform linuxPlatform = FakePlatform(
  operatingSystem: 'linux',
  environment: <String, String>{}
);

final Platform macOSPlatform = FakePlatform(
  operatingSystem: 'macos',
  environment: <String, String>{}
);

void setupWriteMocks({
  FileSystem mockFileSystem,
  ErrorHandlingFileSystem fs,
  int errorCode,
}) {
  final MockFile mockFile = MockFile();
  when(mockFileSystem.file(any)).thenReturn(mockFile);
  when(mockFile.writeAsBytes(
    any,
    mode: anyNamed('mode'),
    flush: anyNamed('flush'),
  )).thenAnswer((_) async {
    throw FileSystemException('', '', OSError('', errorCode));
  });
  when(mockFile.writeAsString(
    any,
    mode: anyNamed('mode'),
    encoding: anyNamed('encoding'),
    flush: anyNamed('flush'),
  )).thenAnswer((_) async {
    throw FileSystemException('', '', OSError('', errorCode));
  });
  when(mockFile.writeAsBytesSync(
    any,
    mode: anyNamed('mode'),
    flush: anyNamed('flush'),
  )).thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockFile.writeAsStringSync(
    any,
    mode: anyNamed('mode'),
    encoding: anyNamed('encoding'),
    flush: anyNamed('flush'),
  )).thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockFile.openSync(
    mode: anyNamed('mode'),
  )).thenThrow(FileSystemException('', '', OSError('', errorCode)));
}

void setupReadMocks({
  FileSystem mockFileSystem,
  ErrorHandlingFileSystem fs,
  int errorCode,
}) {
  final MockFile mockFile = MockFile();
  when(mockFileSystem.file(any)).thenReturn(mockFile);
  when(mockFile.readAsStringSync(
    encoding: anyNamed('encoding'),
  )).thenThrow(FileSystemException('', '', OSError('', errorCode)));
}

void setupDirectoryMocks({
  FileSystem mockFileSystem,
  ErrorHandlingFileSystem fs,
  int errorCode,
}) {
  final MockDirectory mockDirectory = MockDirectory();
  when(mockFileSystem.directory(any)).thenReturn(mockDirectory);
  when(mockDirectory.createTemp(any)).thenAnswer((_) async {
    throw FileSystemException('', '', OSError('', errorCode));
  });
  when(mockDirectory.createTempSync(any))
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockDirectory.createSync(recursive: anyNamed('recursive')))
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockDirectory.create())
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockDirectory.createSync())
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockDirectory.delete())
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockDirectory.deleteSync())
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
  when(mockDirectory.existsSync())
    .thenThrow(FileSystemException('', '', OSError('', errorCode)));
}

void main() {
  testWithoutContext('deleteIfExists does not delete if file does not exist', () {
    final File file = MockFile();
    when(file.existsSync()).thenReturn(false);

    expect(ErrorHandlingFileSystem.deleteIfExists(file), false);
  });

  testWithoutContext('deleteIfExists deletes if file exists', () {
    final File file = MockFile();
    when(file.existsSync()).thenReturn(true);

     expect(ErrorHandlingFileSystem.deleteIfExists(file), true);
  });

  testWithoutContext('deleteIfExists handles separate program deleting file', () {
    final File file = MockFile();
    bool exists = true;
    // Return true for the first call, false for any subsequent calls.
    when(file.existsSync()).thenAnswer((Invocation _) {
      final bool result = exists;
      exists = false;
      return result;
    });
    when(file.deleteSync(recursive: false))
      .thenThrow(const FileSystemException('', '', OSError('', 2)));

    expect(ErrorHandlingFileSystem.deleteIfExists(file), true);
  });

  testWithoutContext('deleteIfExists throws tool exit if file exists on read-only volume', () {
    final File file = MockFile();
    when(file.existsSync()).thenReturn(true);
    when(file.deleteSync(recursive: false))
      .thenThrow(const FileSystemException('', '', OSError('', 2)));

    expect(() => ErrorHandlingFileSystem.deleteIfExists(file), throwsA(isA<ToolExit>()));
  });

  testWithoutContext('deleteIfExists does not tool exit if file exists on read-only '
    'volume and it is run under noExitOnFailure', () {
    final File file = MockFile();
    when(file.existsSync()).thenReturn(true);
    when(file.deleteSync(recursive: false))
      .thenThrow(const FileSystemException('', '', OSError('', 2)));

    expect(() {
      ErrorHandlingFileSystem.noExitOnFailure(() {
        ErrorHandlingFileSystem.deleteIfExists(file);
      });
    }, throwsA(isA<FileSystemException>()));
  });

  group('throws ToolExit on Windows', () {
    const int kDeviceFull = 112;
    const int kUserMappedSectionOpened = 1224;
    const int kUserPermissionDenied = 5;
    const int kFatalDeviceHardwareError =  483;
    MockFileSystem mockFileSystem;
    ErrorHandlingFileSystem fs;

    setUp(() {
      mockFileSystem = MockFileSystem();
      fs = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: windowsPlatform,
      );
      when(mockFileSystem.path).thenReturn(MockPathContext());
    });

    testWithoutContext('bypasses error handling when withAllowedFailure is used', () {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kUserPermissionDenied,
      );

      final File file = fs.file('file');

      expect(() => ErrorHandlingFileSystem.noExitOnFailure(
        () => file.writeAsStringSync('')), throwsA(isA<Exception>()));

      // nesting does not unconditionally re-enable errors.
      expect(() {
        ErrorHandlingFileSystem.noExitOnFailure(() {
          ErrorHandlingFileSystem.noExitOnFailure(() { });
          file.writeAsStringSync('');
        });
      }, throwsA(isA<Exception>()));

      // Check that state does not leak.
      expect(() => file.writeAsStringSync(''), throwsA(isA<ToolExit>()));
    });

    testWithoutContext('when access is denied', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kUserPermissionDenied,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The flutter tool cannot access the file';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.openSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when writing to a full device', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kDeviceFull,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The target device is full';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when the file is being used by another program', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kUserMappedSectionOpened,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The file is being used by another program';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when the device driver has a fatal error', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kFatalDeviceHardwareError,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'There is a problem with the device driver '
        'that this file or directory is stored on';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.openSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when creating a temporary dir on a full device', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kDeviceFull,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'The target device is full';
      expect(() async => await directory.createTemp('prefix'),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.createTempSync('prefix'),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when creating a directory with permission issues', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kUserPermissionDenied,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'Flutter failed to create a directory at';
      expect(() => directory.createSync(recursive: true),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when checking for directory existence with permission issues', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kUserPermissionDenied,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'Flutter failed to check for directory existence at';
      expect(() => directory.existsSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('When reading from a file without permission', () {
      setupReadMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: kUserPermissionDenied,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'Flutter failed to read a file at';
      expect(() => file.readAsStringSync(),
             throwsToolExit(message: expectedMessage));
    });
  });

  group('throws ToolExit on Linux', () {
    const int eperm = 1;
    const int enospc = 28;
    const int eacces = 13;
    MockFileSystem mockFileSystem;
    ErrorHandlingFileSystem fs;

    setUp(() {
      mockFileSystem = MockFileSystem();
      fs = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: linuxPlatform,
      );
      when(mockFileSystem.path).thenReturn(MockPathContext());
    });

    testWithoutContext('when access is denied', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eacces,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The flutter tool cannot access the file or directory';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.openSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when access is denied for directories', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eperm,
      );

      final Directory directory = fs.directory('file');

      const String expectedMessage = 'The flutter tool cannot access the file or directory';
      expect(() async => await directory.create(),
             throwsToolExit(message: expectedMessage));
      expect(() async => await directory.delete(),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.createSync(),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.deleteSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when writing to a full device', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: enospc,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The target device is full';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when creating a temporary dir on a full device', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: enospc,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'The target device is full';
      expect(() async => await directory.createTemp('prefix'),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.createTempSync('prefix'),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when checking for directory existence with permission issues', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eacces,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'Flutter failed to check for directory existence at';
      expect(() => directory.existsSync(),
             throwsToolExit(message: expectedMessage));
    });
  });

  group('throws ToolExit on macOS', () {
    const int eperm = 1;
    const int enospc = 28;
    const int eacces = 13;
    MockFileSystem mockFileSystem;
    ErrorHandlingFileSystem fs;

    setUp(() {
      mockFileSystem = MockFileSystem();
      fs = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: macOSPlatform,
      );
      when(mockFileSystem.path).thenReturn(MockPathContext());
    });

    testWithoutContext('when access is denied', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eacces,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The flutter tool cannot access the file';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.openSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when access is denied for directories', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eperm,
      );

      final Directory directory = fs.directory('file');

      const String expectedMessage = 'The flutter tool cannot access the file or directory';
      expect(() async => await directory.create(),
             throwsToolExit(message: expectedMessage));
      expect(() async => await directory.delete(),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.createSync(),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.deleteSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when writing to a full device', () async {
      setupWriteMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: enospc,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'The target device is full';
      expect(() async => await file.writeAsBytes(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() async => await file.writeAsString(''),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsBytesSync(<int>[0]),
             throwsToolExit(message: expectedMessage));
      expect(() => file.writeAsStringSync(''),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when creating a temporary dir on a full device', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: enospc,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'The target device is full';
      expect(() async => await directory.createTemp('prefix'),
             throwsToolExit(message: expectedMessage));
      expect(() => directory.createTempSync('prefix'),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('when checking for directory existence with permission issues', () async {
      setupDirectoryMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eacces,
      );

      final Directory directory = fs.directory('directory');

      const String expectedMessage = 'Flutter failed to check for directory existence at';
      expect(() => directory.existsSync(),
             throwsToolExit(message: expectedMessage));
    });

    testWithoutContext('When reading from a file without permission', () {
      setupReadMocks(
        mockFileSystem: mockFileSystem,
        fs: fs,
        errorCode: eacces,
      );

      final File file = fs.file('file');

      const String expectedMessage = 'Flutter failed to read a file at';
      expect(() => file.readAsStringSync(),
             throwsToolExit(message: expectedMessage));
    });
  });

  testWithoutContext('Caches path context correctly', () {
    final MockFileSystem mockFileSystem = MockFileSystem();
    final FileSystem fs = ErrorHandlingFileSystem(
      delegate: mockFileSystem,
      platform: const LocalPlatform(),
    );

    expect(identical(fs.path, fs.path), true);
  });

  testWithoutContext('Clears cache when CWD changes', () {
    final MockFileSystem mockFileSystem = MockFileSystem();
    final FileSystem fs = ErrorHandlingFileSystem(
      delegate: mockFileSystem,
      platform: const LocalPlatform(),
    );

    final Object firstPath = fs.path;

    fs.currentDirectory = null;
    when(mockFileSystem.path).thenReturn(MockPathContext());

    expect(identical(firstPath, fs.path), false);
  });

  group('toString() gives toString() of delegate', () {
    testWithoutContext('ErrorHandlingFileSystem', () {
      final MockFileSystem mockFileSystem = MockFileSystem();
      final FileSystem fs = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: const LocalPlatform(),
      );

      expect(mockFileSystem.toString(), isNotNull);
      expect(fs.toString(), equals(mockFileSystem.toString()));
    });

    testWithoutContext('ErrorHandlingFile', () {
      final MockFileSystem mockFileSystem = MockFileSystem();
      final FileSystem fs = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: const LocalPlatform(),
      );
      final MockFile mockFile = MockFile();
      when(mockFileSystem.file(any)).thenReturn(mockFile);

      expect(mockFile.toString(), isNotNull);
      expect(fs.file('file').toString(), equals(mockFile.toString()));
    });

    testWithoutContext('ErrorHandlingDirectory', () {
      final MockFileSystem mockFileSystem = MockFileSystem();
      final FileSystem fs = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: const LocalPlatform(),
      );
      final MockDirectory mockDirectory = MockDirectory();
      when(mockFileSystem.directory(any)).thenReturn(mockDirectory);

      expect(mockDirectory.toString(), isNotNull);
      expect(fs.directory('directory').toString(), equals(mockDirectory.toString()));

      when(mockFileSystem.currentDirectory).thenReturn(mockDirectory);

      expect(fs.currentDirectory.toString(), equals(mockDirectory.toString()));
      expect(fs.currentDirectory, isA<ErrorHandlingDirectory>());
    });
  });

  group('ProcessManager on windows throws tool exit', () {
    const int kDeviceFull = 112;
    const int kUserMappedSectionOpened = 1224;
    const int kUserPermissionDenied = 5;

    test('when the device is full', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: windowsPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, kDeviceFull);

      const String expectedMessage = 'The target device is full';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });

    test('when the file is being used by another program', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: windowsPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, kUserMappedSectionOpened);

      const String expectedMessage = 'The file is being used by another program';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });

    test('when permissions are denied', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: windowsPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, kUserPermissionDenied);

      const String expectedMessage = 'The flutter tool cannot access the file';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });
  });

  group('ProcessManager on linux throws tool exit', () {
    const int enospc = 28;
    const int eacces = 13;

    test('when writing to a full device', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: linuxPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, enospc);

      const String expectedMessage = 'The target device is full';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });

    test('when permissions are denied', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: linuxPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, eacces);

      const String expectedMessage = 'The flutter tool cannot access the file';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });
  });

  group('ProcessManager on macOS throws tool exit', () {
    const int enospc = 28;
    const int eacces = 13;

    test('when writing to a full device', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: macOSPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, enospc);

      const String expectedMessage = 'The target device is full';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });

    test('when permissions are denied', () {
      final MockProcessManager mockProcessManager = MockProcessManager();
      final ProcessManager processManager = ErrorHandlingProcessManager(
        delegate: mockProcessManager,
        platform: linuxPlatform,
      );
      setupProcessManagerMocks(mockProcessManager, eacces);

      const String expectedMessage = 'The flutter tool cannot access the file';
      expect(() => processManager.canRun('foo'),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.killPid(1),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.start(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() async => await processManager.run(<String>['foo']),
             throwsToolExit(message: expectedMessage));
      expect(() => processManager.runSync(<String>['foo']),
             throwsToolExit(message: expectedMessage));
    });
  });

  group('CopySync' , () {
    const int eaccess = 13;
    MockFileSystem mockFileSystem;
    ErrorHandlingFileSystem fileSystem;

    setUp(() {
      mockFileSystem = MockFileSystem();
      fileSystem = ErrorHandlingFileSystem(
        delegate: mockFileSystem,
        platform: linuxPlatform,
      );
      when(mockFileSystem.path).thenReturn(MockPathContext());
    });

    testWithoutContext('copySync handles error if openSync on source file fails', () {
      final MockFile source = MockFile();
      when(source.openSync(mode: anyNamed('mode')))
        .thenThrow(const FileSystemException('', '', OSError('', eaccess)));
      when(mockFileSystem.file('source')).thenReturn(source);

      expect(() => fileSystem.file('source').copySync('dest'), throwsToolExit());
    });

    testWithoutContext('copySync handles error if createSync on destination file fails', () {
      final MockFile source = MockFile();
      final MockFile dest = MockFile();
      when(source.openSync(mode: anyNamed('mode')))
        .thenReturn(MockRandomAccessFile());
      when(dest.createSync(recursive: anyNamed('recursive')))
        .thenThrow(const FileSystemException('', '', OSError('', eaccess)));
      when(mockFileSystem.file('source')).thenReturn(source);
      when(mockFileSystem.file('dest')).thenReturn(dest);

      expect(() => fileSystem.file('source').copySync('dest'), throwsToolExit());
    });

    // dart:io is able to clobber read-only files.
    testWithoutContext('copySync will copySync even if the destination is not writable', () {
      final MockFile source = MockFile();
      final MockFile dest = MockFile();

      when(source.copySync(any)).thenReturn(dest);
      when(mockFileSystem.file('source')).thenReturn(source);
      when(source.openSync(mode: anyNamed('mode')))
        .thenReturn(MockRandomAccessFile());
      when(mockFileSystem.file('dest')).thenReturn(dest);
      when(dest.openSync(mode: FileMode.writeOnly))
        .thenThrow(const FileSystemException('', '', OSError('', eaccess)));

      fileSystem.file('source').copySync('dest');

      verify(source.copySync('dest')).called(1);
    });

    testWithoutContext('copySync will copySync if there are no exceptions', () {
      final MockFile source = MockFile();
      final MockFile dest = MockFile();

      when(source.copySync(any)).thenReturn(dest);
      when(mockFileSystem.file('source')).thenReturn(source);
      when(source.openSync(mode: anyNamed('mode')))
        .thenReturn(MockRandomAccessFile());
      when(mockFileSystem.file('dest')).thenReturn(dest);
      when(dest.openSync(mode: anyNamed('mode')))
        .thenReturn(MockRandomAccessFile());

      fileSystem.file('source').copySync('dest');

      verify(source.copySync('dest')).called(1);
    });

    // Uses context for analytics.
    testUsingContext('copySync can directly copy bytes if both files can be opened but copySync fails', () {
      final MemoryFileSystem memoryFileSystem = MemoryFileSystem.test();
      final MockFile source = MockFile();
      final MockFile dest = MockFile();
      final List<int> expectedBytes = List<int>.generate(64 * 1024 + 3, (int i) => i.isEven ? 0 : 1);
      final File memorySource = memoryFileSystem.file('source')
        ..writeAsBytesSync(expectedBytes);
      final File memoryDest = memoryFileSystem.file('dest')
        ..createSync();

      when(source.copySync(any))
        .thenThrow(const FileSystemException('', '', OSError('', eaccess)));
      when(source.openSync(mode: anyNamed('mode')))
        .thenAnswer((Invocation invocation) => memorySource.openSync(mode: invocation.namedArguments[#mode] as FileMode));
      when(dest.openSync(mode: anyNamed('mode')))
        .thenAnswer((Invocation invocation) => memoryDest.openSync(mode: invocation.namedArguments[#mode] as FileMode));
      when(mockFileSystem.file('source')).thenReturn(source);
      when(mockFileSystem.file('dest')).thenReturn(dest);

      fileSystem.file('source').copySync('dest');

      expect(memoryDest.readAsBytesSync(), expectedBytes);
      verify(globals.flutterUsage.sendEvent('error-handling', 'copy-fallback')).called(1);
    }, overrides: <Type, Generator>{
      Usage: () => MockUsage(),
    });

    // Uses context for analytics.
    testUsingContext('copySync deletes the result file if the fallback fails', () {
      final MemoryFileSystem memoryFileSystem = MemoryFileSystem.test();
      final MockFile source = MockFile();
      final MockFile dest = MockFile();
      final File memorySource = memoryFileSystem.file('source')
        ..createSync();
      final File memoryDest = memoryFileSystem.file('dest')
        ..createSync();
      int calledCount = 0;

      when(dest.existsSync()).thenReturn(true);
      when(source.copySync(any))
        .thenThrow(const FileSystemException('', '', OSError('', eaccess)));
      when(source.openSync(mode: anyNamed('mode')))
        .thenAnswer((Invocation invocation) {
          if (calledCount == 1) {
            throw const FileSystemException('', '', OSError('', eaccess));
          }
          calledCount +=  1;
          return memorySource.openSync(mode: invocation.namedArguments[#mode] as FileMode);
        });
      when(dest.openSync(mode: anyNamed('mode')))
        .thenAnswer((Invocation invocation) => memoryDest.openSync(mode: invocation.namedArguments[#mode] as FileMode));
      when(mockFileSystem.file('source')).thenReturn(source);
      when(mockFileSystem.file('dest')).thenReturn(dest);

      expect(() => fileSystem.file('source').copySync('dest'), throwsToolExit());

      verify(dest.deleteSync(recursive: true)).called(1);
    }, overrides: <Type, Generator>{
      Usage: () => MockUsage(),
    });
  });
}

void setupProcessManagerMocks(
  MockProcessManager processManager,
  int errorCode,
) {
  when(processManager.canRun(any, workingDirectory: anyNamed('workingDirectory')))
    .thenThrow(ProcessException('', <String>[], '', errorCode));
  when(processManager.killPid(any, any))
    .thenThrow(ProcessException('', <String>[], '', errorCode));
  when(processManager.runSync(
    any,
    environment: anyNamed('environment'),
    includeParentEnvironment: anyNamed('includeParentEnvironment'),
    runInShell: anyNamed('runInShell'),
    workingDirectory: anyNamed('workingDirectory'),
    stdoutEncoding: anyNamed('stdoutEncoding'),
    stderrEncoding: anyNamed('stderrEncoding'),
  )).thenThrow(ProcessException('', <String>[], '', errorCode));
  when(processManager.run(
    any,
    environment: anyNamed('environment'),
    includeParentEnvironment: anyNamed('includeParentEnvironment'),
    runInShell: anyNamed('runInShell'),
    workingDirectory: anyNamed('workingDirectory'),
    stdoutEncoding: anyNamed('stdoutEncoding'),
    stderrEncoding: anyNamed('stderrEncoding'),
  )).thenThrow(ProcessException('', <String>[], '', errorCode));
  when(processManager.start(
    any,
    environment: anyNamed('environment'),
    includeParentEnvironment: anyNamed('includeParentEnvironment'),
    runInShell: anyNamed('runInShell'),
    workingDirectory: anyNamed('workingDirectory'),
  )).thenThrow(ProcessException('', <String>[], '', errorCode));
}
