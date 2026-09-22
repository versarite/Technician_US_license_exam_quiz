unit uMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  fpjson, jsonparser, uFigure;

type
  TQuestion = record
    ID: string;
    QuestionText: string;
    Choices: array[0..3] of string;
    CorrectIndex: Integer; // 0=A, 1=B, 2=C, 3=D, into Choices
    Sub: string;           // subelement code, e.g. 'T5'
    Figure: string;        // optional diagram filename (e.g. 't-1.png'), '' if none
  end;

  { TForm1 }

  TForm1 = class(TForm)
    btnNext: TButton;
    btnRestart: TButton;
    cmbCategory: TComboBox;
    lblPct: TLabel;
    lblpct_unit: TLabel;
    lblCategory: TLabel;
    lblFooter: TLabel;
    lblProgress: TLabel;
    lblQID: TLabel;
    lblQuestion: TLabel;
    lblResult: TLabel;
    lblScore: TLabel;
    rgChoices: TRadioGroup;
    procedure btnNextClick(Sender: TObject);
    procedure btnRestartClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure rgChoicesClick(Sender: TObject);
    procedure cmbCategoryChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FQuestions: array of TQuestion;
    FFiltered: array of Integer;   // indices into FQuestions, filtered by category, shuffled
    FPos: Integer;                 // position within FFiltered
    FAsked, FCorrect: Integer;
    Percval: double;

    FDisplayMap: array[0..3] of Integer; // display slot -> original choice index
    FAnswered: Boolean;
    FCatPrefixes: array of string;
    FImagesDir: string;
    FFigureForm: TFormFigure; // lazily-created non-modal popup for T6 diagrams
    procedure LoadQuestions(const FileName: string);
    function ReadFileUTF8(const FileName: string): string;
    function SubelementTitle(const Prefix: string): string;
    function ExamClassName: string;
    procedure BuildCategoryList;
    procedure ApplyFilterAndReset;
    procedure ShowCurrentQuestion;
    procedure ShowFinishedState;
    procedure UpdateScoreLabel;
    procedure ShowFigurePopup(const FigureFile, FigureCaption: string);
    procedure CloseFigurePopup;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

function TForm1.ReadFileUTF8(const FileName: string): string;
var
  fs: TFileStream;
  Bytes: TBytes;
begin
  fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Bytes, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Bytes[0], fs.Size);
  finally
    fs.Free;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

procedure TForm1.LoadQuestions(const FileName: string);
var
  JSONData: TJSONData;
  JSONArr: TJSONArray;
  JSONObj: TJSONObject;
  ChoicesArr: TJSONArray;
  i, j: Integer;
  JsonText: string;
begin
  JsonText := ReadFileUTF8(FileName);
  JSONData := GetJSON(JsonText);
  try
    if not (JSONData is TJSONArray) then
      raise Exception.Create('questions.json does not contain a JSON array at the top level.');
    JSONArr := TJSONArray(JSONData);
    SetLength(FQuestions, JSONArr.Count);
    for i := 0 to JSONArr.Count - 1 do
    begin
      JSONObj := TJSONObject(JSONArr[i]);
      FQuestions[i].ID := JSONObj.Get('id', '');
      FQuestions[i].QuestionText := JSONObj.Get('question', '');
      FQuestions[i].CorrectIndex := JSONObj.Get('correct', 0);
      FQuestions[i].Figure := JSONObj.Get('figure', '');
      FQuestions[i].Sub := Copy(FQuestions[i].ID, 1, 2);
      ChoicesArr := JSONObj.Arrays['choices'];
      for j := 0 to 3 do
      begin
        if j < ChoicesArr.Count then
          FQuestions[i].Choices[j] := ChoicesArr.Strings[j]
        else
          FQuestions[i].Choices[j] := '';
      end;
    end;
  finally
    JSONData.Free;
  end;
end;

function TForm1.SubelementTitle(const Prefix: string): string;
const
  // Human-readable subelement names, covering the Technician (T),
  // General (G) and Amateur Extra (E) syllabi. If a future or unknown
  // pool uses a prefix not listed here, we just fall back to a generic
  // label rather than failing - the filter still works either way.
  Known: array[0..29, 0..1] of string = (
    ('T0', 'Safety'),
    ('T1', 'Commission''s Rules'),
    ('T2', 'Operating Procedures'),
    ('T3', 'Radio Wave Propagation'),
    ('T4', 'Amateur Radio Practices and Station Setup'),
    ('T5', 'Electrical Principles'),
    ('T6', 'Electrical Components'),
    ('T7', 'Station Equipment'),
    ('T8', 'Modulation Modes'),
    ('T9', 'Antennas and Feed Lines'),
    ('G0', 'Electrical and RF Safety'),
    ('G1', 'Commission''s Rules'),
    ('G2', 'Operating Procedures'),
    ('G3', 'Radio Wave Propagation'),
    ('G4', 'Amateur Radio Practices'),
    ('G5', 'Electrical Principles'),
    ('G6', 'Circuit Components'),
    ('G7', 'Practical Circuits'),
    ('G8', 'Signals and Emissions'),
    ('G9', 'Antennas and Feed Lines'),
    ('E0', 'Electrical and RF Safety'),
    ('E1', 'Commission''s Rules'),
    ('E2', 'Operating Procedures'),
    ('E3', 'Radio Wave Propagation'),
    ('E4', 'Amateur Radio Practices'),
    ('E5', 'Electrical Principles'),
    ('E6', 'Circuit Components'),
    ('E7', 'Practical Circuits'),
    ('E8', 'Signals and Emissions'),
    ('E9', 'Antennas and Feed Lines')
  );
var
  i: Integer;
begin
  for i := 0 to High(Known) do
    if Known[i, 0] = Prefix then
      Exit(Known[i, 1]);
  Result := 'Miscellaneous';
end;

function TForm1.ExamClassName: string;
begin
  if Length(FQuestions) = 0 then
    Exit('Amateur Radio License');
  case UpCase(FQuestions[0].ID[1]) of
    'T': Result := 'Technician Class';
    'G': Result := 'General Class';
    'E': Result := 'Amateur Extra Class';
  else
    Result := 'Amateur Radio License';
  end;
end;

procedure TForm1.BuildCategoryList;
var
  i: Integer;
  prefixes: TStringList;
begin
  // Derive the list of subelements straight from whatever questions.json
  // was loaded, rather than assuming it's the Technician pool. This is
  // what lets a different pool (General, Extra, ...) be dropped in as
  // just a new questions.json, with no code changes needed.
  prefixes := TStringList.Create;
  try
    prefixes.Sorted := True;
    prefixes.Duplicates := dupIgnore;
    for i := 0 to High(FQuestions) do
      prefixes.Add(FQuestions[i].Sub);

    SetLength(FCatPrefixes, prefixes.Count + 1);
    FCatPrefixes[0] := '';

    cmbCategory.Items.BeginUpdate;
    try
      cmbCategory.Items.Clear;
      cmbCategory.Items.Add('All subelements');
      for i := 0 to prefixes.Count - 1 do
      begin
        FCatPrefixes[i + 1] := prefixes[i];
        cmbCategory.Items.Add(prefixes[i] + ' - ' + SubelementTitle(prefixes[i]));
      end;
    finally
      cmbCategory.Items.EndUpdate;
    end;
  finally
    prefixes.Free;
  end;
  cmbCategory.ItemIndex := 0;
end;

procedure TForm1.ApplyFilterAndReset;
var
  i, n, k, r: Integer;
  prefix: string;
  tmp: Integer;
begin
  if (cmbCategory.ItemIndex < 0) or (cmbCategory.ItemIndex > High(FCatPrefixes)) then
    prefix := ''
  else
    prefix := FCatPrefixes[cmbCategory.ItemIndex];

  SetLength(FFiltered, 0);
  n := 0;
  SetLength(FFiltered, Length(FQuestions));
  for i := 0 to High(FQuestions) do
  begin
    if (prefix = '') or (FQuestions[i].Sub = prefix) then
    begin
      FFiltered[n] := i;
      Inc(n);
    end;
  end;
  SetLength(FFiltered, n);

  // Fisher-Yates shuffle
  for k := High(FFiltered) downto 1 do
  begin
    r := Random(k + 1);
    tmp := FFiltered[k];
    FFiltered[k] := FFiltered[r];
    FFiltered[r] := tmp;
  end;

  FPos := 0;
  FAsked := 0;
  FCorrect := 0;
  rgChoices.Enabled := True;
  btnNext.Enabled := False;
  UpdateScoreLabel;

  if Length(FFiltered) = 0 then
  begin
    lblQID.Caption := '';
    lblQuestion.Caption := 'No questions found for this category.';
    rgChoices.Items.Clear;
    rgChoices.Enabled := False;
    lblResult.Caption := '';
    lblProgress.Caption := '';
    CloseFigurePopup;
  end
  else
    ShowCurrentQuestion;
end;

procedure TForm1.ShowCurrentQuestion;
var
  q: TQuestion;
  order: array[0..3] of Integer;
  i, k, r, tmp: Integer;
  Letters: array[0..3] of Char;
begin
  Letters[0] := 'A'; Letters[1] := 'B'; Letters[2] := 'C'; Letters[3] := 'D';

  if (FPos < 0) or (FPos >= Length(FFiltered)) then
  begin
    ShowFinishedState;
    Exit;
  end;

  q := FQuestions[FFiltered[FPos]];

  lblProgress.Caption := Format('Question %d of %d', [FPos + 1, Length(FFiltered)]);
  lblQID.Caption := q.ID;
  lblQuestion.Caption := q.QuestionText;
  lblResult.Caption := '';
  lblResult.Font.Color := clWindowText;

  // Shuffle the display order of the four choices so the correct
  // answer is not always in the same position.
  for i := 0 to 3 do
    order[i] := i;
  for k := 3 downto 1 do
  begin
    r := Random(k + 1);
    tmp := order[k];
    order[k] := order[r];
    order[r] := tmp;
  end;

  rgChoices.Items.BeginUpdate;
  try
    rgChoices.Items.Clear;
    for i := 0 to 3 do
    begin
      FDisplayMap[i] := order[i];
      rgChoices.Items.Add(Letters[i] + '.  ' + q.Choices[order[i]]);
    end;
  finally
    rgChoices.Items.EndUpdate;
  end;
  rgChoices.ItemIndex := -1;
  rgChoices.Enabled := True;

  // A handful of questions (all in T6, Electrical Components) refer to a
  // labeled schematic diagram. Pop it up in its own window, big enough to
  // actually read, only when this question has one.
  if (q.Figure <> '') and FileExists(FImagesDir + q.Figure) then
    ShowFigurePopup(FImagesDir + q.Figure,
      'Figure ' + UpperCase(ChangeFileExt(q.Figure, '')))
  else
    CloseFigurePopup;

  btnNext.Enabled := False;
  FAnswered := False;
end;

procedure TForm1.ShowFinishedState;
var
  pct: Double;
begin
  lblProgress.Caption := 'Quiz complete!';
  lblQID.Caption := '';
  lblQuestion.Caption := '';
  rgChoices.Items.Clear;
  rgChoices.Enabled := False;
  btnNext.Enabled := False;
  CloseFigurePopup;

  if FAsked > 0 then
    pct := (FCorrect / FAsked) * 100.0
  else
    pct := 0.0;

  lblResult.Font.Color := clNavy;
  lblResult.Caption := Format(
    'You answered %d out of %d correctly (%.1f%%).'#13#10 +
    'Click "Restart / Reshuffle" to try again.',
    [FCorrect, FAsked, pct]);

end;

procedure TForm1.UpdateScoreLabel;

begin
  lblScore.Caption := Format('Score: %d / %d', [FCorrect, FAsked]);
  if FAsked >0 then PercVal:= (FCorrect / FAsked)*100 else percval:=0;
  lblPct.Caption:= Format('%.1f', [PercVal]);
  if fasked-fcorrect > 9 then lblpct.font.Color:= clRed else lblpct.font.Color:= clDefault ;
end;

procedure TForm1.ShowFigurePopup(const FigureFile, FigureCaption: string);
begin
  // Created once, then reused (shown/hidden) for the life of the app -
  // a plain, non-modal 600x400 window so the diagram is actually
  // readable, positioned beside the main window rather than on top of it.
  if not Assigned(FFigureForm) then
  begin
    FFigureForm := TFormFigure.Create(Self);
    FFigureForm.Width := 600;
    FFigureForm.Height := 400;
    FFigureForm.Left := Self.Left + Self.Width + 16;
    FFigureForm.Top := Self.Top;
  end;
  FFigureForm.LoadImage(FigureFile, FigureCaption);
  FFigureForm.Show;
end;

procedure TForm1.CloseFigurePopup;
begin
  if Assigned(FFigureForm) then
    FFigureForm.Hide;
end;

procedure TForm1.rgChoicesClick(Sender: TObject);
var
  q: TQuestion;
  chosenOrigIndex: Integer;
  isCorrect: Boolean;
  correctLetter: Char;
  Letters: array[0..3] of Char;
  i: Integer;
begin
  // Fires whenever the user clicks any radio button in the group. Guard
  // against re-entry (once a question is answered the group gets
  // disabled, but a stray click could still land here) and against a
  // click that landed on the group box itself with nothing selected.
  if FAnswered then
    Exit;

  if rgChoices.ItemIndex < 0 then
    Exit;

  Letters[0] := 'A'; Letters[1] := 'B'; Letters[2] := 'C'; Letters[3] := 'D';

  q := FQuestions[FFiltered[FPos]];
  chosenOrigIndex := FDisplayMap[rgChoices.ItemIndex];
  isCorrect := (chosenOrigIndex = q.CorrectIndex);

  // Find which displayed letter corresponds to the correct original choice
  correctLetter := 'A';
  for i := 0 to 3 do
    if FDisplayMap[i] = q.CorrectIndex then
      correctLetter := Letters[i];

  Inc(FAsked);
  if isCorrect then
    Inc(FCorrect);

  if isCorrect then
  begin
    lblResult.Font.Color := clGreen;
    lblResult.Caption := 'Correct!  ' + correctLetter + '.  ' + q.Choices[q.CorrectIndex];
  end
  else
  begin
    lblResult.Font.Color := clRed;
    lblResult.Caption := 'Incorrect.  The correct answer is ' + correctLetter +
      '.  ' + q.Choices[q.CorrectIndex];
  end;

  UpdateScoreLabel;
  rgChoices.Enabled := False;
  btnNext.Enabled := True;
  FAnswered := True;
end;

procedure TForm1.btnNextClick(Sender: TObject);
begin
  Inc(FPos);
  ShowCurrentQuestion;
end;

procedure TForm1.btnRestartClick(Sender: TObject);
begin
  ApplyFilterAndReset;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Take the figure popup down with the main window instead of leaving
  // an orphaned window open after the app quits.
  if Assigned(FFigureForm) then
    FFigureForm.Close;
end;

procedure TForm1.cmbCategoryChange(Sender: TObject);
begin
  ApplyFilterAndReset;
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  QFile: string;
begin
  Randomize;
  FAnswered := False;

  QFile := ExtractFilePath(ParamStr(0)) + 'questions.json';
  if not FileExists(QFile) then
    QFile := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'questions.json';
  if not FileExists(QFile) then
    QFile := 'questions.json';

  // Diagrams (Figure T-1/T-2/T-3) live in an "images" folder next to
  // questions.json - resolve it the same tolerant way.
  FImagesDir := ExtractFilePath(ParamStr(0)) + 'images' + PathDelim;
  if not DirectoryExists(FImagesDir) then
    FImagesDir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'images' + PathDelim;
  if not DirectoryExists(FImagesDir) then
    FImagesDir := 'images' + PathDelim;

  if not FileExists(QFile) then
  begin
    ShowMessage('Could not find questions.json. Please make sure it is in the ' +
      'same folder as the program executable.');
    Exit;
  end;

  try
    LoadQuestions(QFile);
  except
    on E: Exception do
    begin
      ShowMessage('Failed to load questions.json:' + LineEnding + E.Message);
      Exit;
    end;
  end;

  Caption := ExamClassName + ' Quiz';
  lblFooter.Caption := Format('Loaded %d questions from questions.json (%s)',
    [Length(FQuestions), ExamClassName]);

  BuildCategoryList;
  ApplyFilterAndReset;
end;

end.
