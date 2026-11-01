{ Ported from Trndi (https://github.com/slicke/trndi), GPL-3.0. }

unit testextperm;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, gittan.ext.perm;

type
  TExtPermTest = class(TTestCase)
  published
    procedure TestExplicitManifest;
    procedure TestLegacyManifest;
    procedure TestUnknownPermissionIsRejected;
    procedure TestUnknownDirectiveIsRejected;
    procedure TestBaselinePermissionIsAccepted;
    procedure TestAsteriskDecorationIsStripped;
    procedure TestManifestMustStartTheFile;
    procedure TestUtf8BomIsAccepted;
    procedure TestUseStrictPrologueIsSkipped;
    procedure TestBlankLineAfterPrologueIsRejected;
  end;

implementation

procedure TExtPermTest.TestExplicitManifest;
var
  manifest: TExtManifest;
begin
  manifest := ParseExtManifest('/*' + LineEnding +
    '@name Example extension' + LineEnding +
    '@copyright (c) Example author' + LineEnding +
    '@version 1.2.3' + LineEnding +
    '@description Demonstrates manifests' + LineEnding +
    '@homepage https://example.com/extension' + LineEnding +
    '@license MIT' + LineEnding +
    '@perms net, settings' + LineEnding +
    '*/');

  AssertTrue('manifest should be valid', manifest.IsValid);
  AssertEquals('name', 'Example extension', manifest.DisplayName);
  AssertEquals('copyright', '(c) Example author', manifest.Author);
  AssertEquals('version', '1.2.3', manifest.Version);
  AssertEquals('description', 'Demonstrates manifests', manifest.Description);
  AssertEquals('homepage', 'https://example.com/extension', manifest.Homepage);
  AssertEquals('license', 'MIT', manifest.License);
  AssertTrue('net requested', epNet in manifest.Requested);
  AssertTrue('settings requested', epSettings in manifest.Requested);
end;

procedure TExtPermTest.TestLegacyManifest;
var
  manifest: TExtManifest;
begin
  manifest := ParseExtManifest('/* Legacy extension' + LineEnding +
    '(c) Existing author' + LineEnding + '@perms exec */');

  AssertTrue('legacy manifest should remain valid', manifest.IsValid);
  AssertEquals('legacy name', 'Legacy extension', manifest.DisplayName);
  AssertEquals('legacy author', '(c) Existing author', manifest.Author);
  AssertTrue('exec requested', epExec in manifest.Requested);
end;

procedure TExtPermTest.TestUnknownPermissionIsRejected;
var
  manifest: TExtManifest;
begin
  manifest := ParseExtManifest('/*' + LineEnding + '@name Invalid' + LineEnding +
    '@perms net, netwerk' + LineEnding + '*/');

  AssertFalse('unknown permissions must reject the manifest', manifest.IsValid);
  AssertTrue('error identifies the unknown permission',
    Pos('netwerk', manifest.ErrorMessage) > 0);
end;

procedure TExtPermTest.TestUnknownDirectiveIsRejected;
var
  manifest: TExtManifest;
begin
  manifest := ParseExtManifest('/*' + LineEnding + '@name Invalid' + LineEnding +
    '@auther Nobody' + LineEnding + '*/');

  AssertFalse('unknown directives must reject the manifest', manifest.IsValid);
  AssertTrue('error identifies the unknown directive',
    Pos('@auther', manifest.ErrorMessage) > 0);
end;

procedure TExtPermTest.TestBaselinePermissionIsAccepted;
var
  manifest: TExtManifest;
begin
  // Baseline groups are always granted; naming them is pointless but legal.
  manifest := ParseExtManifest('/*' + LineEnding + '@name Baseline' + LineEnding +
    '@perms timers, net' + LineEnding + '*/');

  AssertTrue('baseline permission names must not reject the manifest',
    manifest.IsValid);
  AssertTrue('timers requested', epTimers in manifest.Requested);
  AssertTrue('net requested', epNet in manifest.Requested);
end;

procedure TExtPermTest.TestAsteriskDecorationIsStripped;
var
  manifest: TExtManifest;
begin
  manifest := ParseExtManifest('/*' + LineEnding + ' * @name Decorated' + LineEnding +
    ' * @perms net' + LineEnding + ' */');

  AssertTrue('decorated manifest should be valid', manifest.IsValid);
  AssertEquals('decorated name', 'Decorated', manifest.DisplayName);
  AssertTrue('net requested', epNet in manifest.Requested);
end;

procedure TExtPermTest.TestManifestMustStartTheFile;
var
  manifest: TExtManifest;
begin
  // A block that does not open the file yields no manifest at all - and no
  // error, so the extension loads nameless and without permissions.
  manifest := ParseExtManifest('#!/usr/bin/env node' + LineEnding +
    '/*' + LineEnding + '@name Too late' + LineEnding + '@perms net' + LineEnding + '*/');

  AssertTrue('a missing manifest is not an error', manifest.IsValid);
  AssertEquals('no name is picked up', '', manifest.DisplayName);
  AssertTrue('no permissions are requested', manifest.Requested = []);
end;

procedure TExtPermTest.TestUtf8BomIsAccepted;
var
  manifest: TExtManifest;
begin
  manifest := ParseExtManifest(#$EF#$BB#$BF + '/* @name BOM extension */');

  AssertTrue('manifest after BOM should be valid', manifest.IsValid);
  AssertEquals('name after BOM', 'BOM extension', manifest.DisplayName);
end;

procedure TExtPermTest.TestUseStrictPrologueIsSkipped;
var
  manifest: TExtManifest;
begin
  // TypeScript (6.0+ unconditionally) and Babel prepend a strict-mode
  // prologue when compiling an extension to a plain script; the manifest
  // right after it must still be found.
  manifest := ParseExtManifest('"use strict";' + LineEnding +
    '/*' + LineEnding + '@name Compiled' + LineEnding + '@perms net' + LineEnding + '*/');
  AssertTrue('manifest after "use strict"; should be valid', manifest.IsValid);
  AssertEquals('name after prologue', 'Compiled', manifest.DisplayName);
  AssertTrue('net requested after prologue', epNet in manifest.Requested);

  // Single quotes and CRLF line endings are tolerated too.
  manifest := ParseExtManifest('''use strict'';'#13#10'/* @name Compiled2 */');
  AssertTrue('single-quoted prologue accepted', manifest.IsValid);
  AssertEquals('name after single-quoted prologue', 'Compiled2', manifest.DisplayName);

  // The prologue only excuses itself, nothing else before the manifest.
  manifest := ParseExtManifest('"use strict"; var x = 1;' + LineEnding +
    '/* @name Too late */');
  AssertEquals('code between prologue and manifest still disqualifies it',
    '', manifest.DisplayName);
end;

procedure TExtPermTest.TestBlankLineAfterPrologueIsRejected;
var
  manifest: TExtManifest;
begin
  // The prologue excuses exactly one line ending. Two in a row is a blank
  // line before the manifest, which disqualifies it just as it would in a
  // file without a prologue - for LF, CRLF and CR alike.
  manifest := ParseExtManifest('"use strict";'#10#10'/* @name Too late */');
  AssertEquals('blank LF line after prologue disqualifies the manifest',
    '', manifest.DisplayName);

  manifest := ParseExtManifest('"use strict";'#13#10#13#10'/* @name Too late */');
  AssertEquals('blank CRLF line after prologue disqualifies the manifest',
    '', manifest.DisplayName);

  manifest := ParseExtManifest('"use strict";'#13#13'/* @name Too late */');
  AssertEquals('blank CR line after prologue disqualifies the manifest',
    '', manifest.DisplayName);

  // A single line ending of any flavour remains fine.
  manifest := ParseExtManifest('"use strict";'#13'/* @name CR only */');
  AssertEquals('single CR after prologue accepted', 'CR only', manifest.DisplayName);
  manifest := ParseExtManifest('"use strict";'#10'/* @name LF only */');
  AssertEquals('single LF after prologue accepted', 'LF only', manifest.DisplayName);
end;

initialization
  RegisterTest(TExtPermTest);

end.
