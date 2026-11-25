unit testhelpers;

{** What the tests share: the deletion of the temporary folder a test
  made its repository in. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{** Deletes ADir with everything in it; a link in it goes, not what it
  points at. }
procedure RemoveTree(const ADir: string);

implementation

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile or faSymLink, Info) = 0 then
  try
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      {$IFDEF WINDOWS}
      { A junction or a link to a folder is taken away as a folder. }
      if (Info.Attr and (faDirectory or faSymLink)) = (faDirectory or faSymLink) then
        RemoveDir(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
      {$ENDIF}
      if (Info.Attr and (faDirectory or faSymLink)) = faDirectory then
        RemoveTree(IncludeTrailingPathDelimiter(ADir) + Info.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  RemoveDir(ADir);
end;

end.
