unit gittan.syntaxthemes;

{** The syntax themes Gittan can color code with.

  CudaText names its theme styles (Id, IdKeyword, String, Comment, ...) and
  every lexer's .cuda-lexmap maps the lexer's own style names to them, so
  one palette colors all lexers alike. A theme here does not list those
  styles one by one: each style plays a role (keyword, string, comment,
  type, ...), and a theme gives a color per role for a light and a dark
  editor, plus the roles it shows in bold or italics. The text role is
  always NoColor, which leaves the editor's text color in place. The
  background styles (BracketBG, SectionBG1, ...) are not listed: Gittan
  paints no style backgrounds, so the themes only color text.

  The unit has no LCL dependency, so the tests can use it. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  {** A role color that leaves the editor's text color in place. }
  NoColor = $FFFFFFFF;

type
  TThemeFontStyle = (tfsBold, tfsItalic, tfsStrikeOut);
  TThemeFontStyles = set of TThemeFontStyle;

  TThemeRole = (trText, trVariable, trType, trFunction, trConstant, trKeyword,
    trControl, trError, trString, trRegex, trComment, trPreproc, trNumber,
    trValue, trTagBound, trTag, trAttribute);
  TThemeRoles = set of TThemeRole;
  {** $RRGGBB per role. }
  TThemeRoleColors = array[TThemeRole] of cardinal;

  TSyntaxTheme = record
    Name: string;
    Light, Dark: TThemeRoleColors;
    Bold, Italic: TThemeRoles;
  end;

const
  {** The theme a fresh install and an unknown name get: VS Code. }
  DefaultSyntaxTheme = 0;

  { Role order: Text, Variable, Type, Function, Constant, Keyword, Control,
    Error, String, Regex, Comment, Preproc, Number, Value, TagBound, Tag,
    Attribute. }
  SyntaxThemes: array[0..4] of TSyntaxTheme = (
    { VS Code's Light+ and Dark+ token colors. }
    (Name: 'VS Code';
     Light: (NoColor, $001080, $267F99, $795E26, $0070C1, $0000FF, $AF00DB,
       $CD3131, $A31515, $811F3F, $008000, $AF00DB, $098658, $0451A5,
       $800000, $800000, $E50000);
     Dark: (NoColor, $9CDCFE, $4EC9B0, $DCDCAA, $4FC1FF, $569CD6, $C586C0,
       $F44747, $CE9178, $D16969, $6A9955, $C586C0, $B5CEA8, $CE9178,
       $808080, $569CD6, $9CDCFE);
     Bold: []; Italic: []),
    { RAD Studio's default editor colors: reserved words bold navy,
      comments green italics, strings and numbers blue, directives teal,
      identifiers plain. The dark side carries the same scheme over to a
      dark background. }
    (Name: 'Delphi';
     Light: (NoColor, NoColor, NoColor, NoColor, NoColor, $000080, $000080,
       $FF0000, $0000FF, $0000FF, $008000, $008080, $0000FF, $0000FF,
       $000080, $000080, $800000);
     Dark: (NoColor, NoColor, NoColor, NoColor, NoColor, $9DB8F0, $9DB8F0,
       $FF6B6B, $5FA8FF, $5FA8FF, $6CBF6C, $4EC9C9, $5FA8FF, $5FA8FF,
       $9DB8F0, $9DB8F0, $E5A07A);
     Bold: [trKeyword, trControl]; Italic: [trComment]),
    { GitHub's Primer colors, as on github.com in light and dark mode. }
    (Name: 'GitHub';
     Light: (NoColor, $953800, $953800, $8250DF, $0550AE, $CF222E, $CF222E,
       $82071E, $0A3069, $116329, $6E7781, $CF222E, $0550AE, $0A3069,
       NoColor, $116329, $0550AE);
     Dark: (NoColor, $FFA657, $FFA657, $D2A8FF, $79C0FF, $FF7B72, $FF7B72,
       $FFA198, $A5D6FF, $7EE787, $8B949E, $FF7B72, $79C0FF, $A5D6FF,
       NoColor, $7EE787, $79C0FF);
     Bold: []; Italic: []),
    { Ethan Schoonover's Solarized: the same accent colors on either side,
      the comments in the base tone meant for the background. }
    (Name: 'Solarized';
     Light: (NoColor, $268BD2, $B58900, $268BD2, $2AA198, $859900, $859900,
       $DC322F, $2AA198, $DC322F, $93A1A1, $CB4B16, $D33682, $2AA198,
       NoColor, $268BD2, $B58900);
     Dark: (NoColor, $268BD2, $B58900, $268BD2, $2AA198, $859900, $859900,
       $DC322F, $2AA198, $DC322F, $586E75, $CB4B16, $D33682, $2AA198,
       NoColor, $268BD2, $B58900);
     Bold: []; Italic: [trComment]),
    { Xcode's Default (Light) and Default (Dark). }
    (Name: 'Xcode';
     Light: (NoColor, $326D74, $0B4F79, $326D74, $6C36A9, $9B2393, $9B2393,
       $C41A16, $C41A16, $C41A16, $5D6C79, $643820, $1C00CF, $1C00CF,
       NoColor, $9B2393, $815F03);
     Dark: (NoColor, $67B7A4, $5DD8FF, $67B7A4, $A167E6, $FC5FA3, $FC5FA3,
       $FF8170, $FC6A5D, $FC6A5D, $6C7986, $FD8F3F, $D0BF69, $D0BF69,
       NoColor, $FC5FA3, $BF8555);
     Bold: [trKeyword, trControl]; Italic: [])
  );

{** The index of the theme with this name (case ignored), or -1. }
function FindSyntaxTheme(const AName: string): integer;

{** The color ($RRGGBB, or NoColor) and font style ATheme gives the
  CudaText theme style AStyleName on a dark or a light editor. False when
  the style is not one the themes color; the lexer then keeps its own. }
function SyntaxThemeStyle(ATheme: integer; const AStyleName: string;
  ADark: boolean; out AColor: cardinal; out AStyle: TThemeFontStyles): boolean;

implementation

type
  TStyleRole = record
    Name: string;
    Role: TThemeRole;
    Style: TThemeFontStyles;
  end;

const
  { Every CudaText theme style that colors text, with its role. The Text*
    styles carry their own font style on top of the role's. }
  StyleRoles: array[0..34] of TStyleRole = (
    (Name: 'Id'; Role: trText; Style: []),
    (Name: 'Id1'; Role: trVariable; Style: []),
    (Name: 'Id2'; Role: trType; Style: []),
    (Name: 'Id3'; Role: trFunction; Style: []),
    (Name: 'Id4'; Role: trConstant; Style: []),
    (Name: 'IdKeyword'; Role: trKeyword; Style: []),
    (Name: 'IdVar'; Role: trVariable; Style: []),
    (Name: 'IdBad'; Role: trError; Style: []),
    (Name: 'String'; Role: trString; Style: []),
    (Name: 'String2'; Role: trRegex; Style: []),
    (Name: 'String3'; Role: trString; Style: []),
    (Name: 'Symbol'; Role: trText; Style: []),
    (Name: 'Symbol2'; Role: trControl; Style: []),
    (Name: 'SymbolBad'; Role: trError; Style: []),
    (Name: 'Comment'; Role: trComment; Style: []),
    (Name: 'Comment2'; Role: trPreproc; Style: []),
    (Name: 'CommentDoc'; Role: trComment; Style: []),
    (Name: 'Number'; Role: trNumber; Style: []),
    (Name: 'Label'; Role: trFunction; Style: []),
    (Name: 'Color'; Role: trValue; Style: []),
    (Name: 'TagBound'; Role: trTagBound; Style: []),
    (Name: 'TagId'; Role: trTag; Style: []),
    (Name: 'TagIdBad'; Role: trError; Style: []),
    (Name: 'TagProp'; Role: trAttribute; Style: []),
    (Name: 'TagPropBad'; Role: trError; Style: []),
    (Name: 'TagInclude'; Role: trPreproc; Style: []),
    (Name: 'SeparLine'; Role: trText; Style: []),
    (Name: 'TextBold'; Role: trText; Style: [tfsBold]),
    (Name: 'TextItalic'; Role: trText; Style: [tfsItalic]),
    (Name: 'TextBoldItalic'; Role: trText; Style: [tfsBold, tfsItalic]),
    (Name: 'TextCross'; Role: trText; Style: [tfsStrikeOut]),
    (Name: 'TextCrossBold'; Role: trText; Style: [tfsStrikeOut, tfsBold]),
    (Name: 'TextCrossItalic'; Role: trText; Style: [tfsStrikeOut, tfsItalic]),
    (Name: 'TextCrossBoldItalic'; Role: trText;
      Style: [tfsStrikeOut, tfsBold, tfsItalic]),
    (Name: 'Keyword'; Role: trKeyword; Style: [])
  );

function FindSyntaxTheme(const AName: string): integer;
begin
  for Result := 0 to High(SyntaxThemes) do
    if SameText(SyntaxThemes[Result].Name, AName) then
      Exit;
  Result := -1;
end;

function SyntaxThemeStyle(ATheme: integer; const AStyleName: string;
  ADark: boolean; out AColor: cardinal; out AStyle: TThemeFontStyles): boolean;
var
  i: integer;
  R: TThemeRole;
begin
  AColor := NoColor;
  AStyle := [];
  if (ATheme < 0) or (ATheme > High(SyntaxThemes)) then
    ATheme := DefaultSyntaxTheme;
  for i := 0 to High(StyleRoles) do
    if StyleRoles[i].Name = AStyleName then
    begin
      R := StyleRoles[i].Role;
      with SyntaxThemes[ATheme] do
      begin
        if ADark then
          AColor := Dark[R]
        else
          AColor := Light[R];
        AStyle := StyleRoles[i].Style;
        if R in Bold then
          Include(AStyle, tfsBold);
        if R in Italic then
          Include(AStyle, tfsItalic);
      end;
      Exit(True);
    end;
  Result := False;
end;

end.
