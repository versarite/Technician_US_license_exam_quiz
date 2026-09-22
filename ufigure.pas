unit uFigure;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls;

type

  { TFormFigure }

  TFormFigure = class(TForm)
    imgPopup: TImage;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  private
  public
    procedure LoadImage(const FileName, ACaption: string);
  end;

implementation

{$R *.lfm}

{ TFormFigure }

procedure TFormFigure.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Clicking the window's own close button should just hide the popup,
  // not destroy it - the main form reuses this one instance.
  CloseAction := caHide;
end;

procedure TFormFigure.LoadImage(const FileName, ACaption: string);
begin
  imgPopup.Picture.LoadFromFile(FileName);
  Caption := ACaption;
end;

end.
