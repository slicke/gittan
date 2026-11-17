{ A vertical scroll bar on a Windows memo only while its text overflows.

  The LCL gives a memo WS_VSCROLL for ssAutoVertical as for ssVertical,
  and a multiline EDIT control with that style keeps the bar shown,
  disabled, however short its text: the empty commit message box had
  one. FitMemoScrollBar hides it while every line fits in the control's
  formatting rectangle and shows it again once one does not. The lines
  are counted at the width the control has now, so it settles: lines
  that overflowed without the bar overflow beside it too, and lines that
  fit beside it fit without it.

  The unit uses Windows; umain keeps it behind LCLWin32, so the other
  widgetsets never see it. }
unit gittan.memoscroll;

{$mode objfpc}{$H+}

interface

uses
  StdCtrls;

{** Shows AMemo's vertical scroll bar while its lines do not all fit,
  hides it while they do. }
procedure FitMemoScrollBar(AMemo: TCustomMemo);

implementation

uses
  Windows, Messages;

procedure FitMemoScrollBar(AMemo: TCustomMemo);
var
  Wnd: HWND;
  DC: HDC;
  OldFont: HGDIOBJ;
  Metrics: TTextMetric;
  Rect: TRect;
  Lines, Fits: integer;
begin
  if not AMemo.HandleAllocated then
    Exit;
  Wnd := AMemo.Handle;
  Lines := SendMessage(Wnd, EM_GETLINECOUNT, 0, 0);
  DC := GetDC(Wnd);
  try
    OldFont := SelectObject(DC, HGDIOBJ(SendMessage(Wnd, WM_GETFONT, 0, 0)));
    GetTextMetrics(DC, Metrics);
    SelectObject(DC, OldFont);
  finally
    ReleaseDC(Wnd, DC);
  end;
  SendMessage(Wnd, EM_GETRECT, 0, LPARAM(@Rect));
  if Metrics.tmHeight <= 0 then
    Exit;
  Fits := (Rect.Bottom - Rect.Top) div Metrics.tmHeight;
  ShowScrollBar(Wnd, SB_VERT, Lines > Fits);
end;

end.
