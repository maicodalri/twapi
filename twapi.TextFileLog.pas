unit twapi.TextFileLog;

{$mode Delphi}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, twapi.Types;

type

  TProcLog = procedure (const ALog: string);

  TLogLevel = (llLv0{0},
               llLv1{1},
               llLv2{2});

  TLogType = (ltDebug{0},
              ltInfo{1},
              ltErro{2},
              ltCritical{3});


  { TFileTextLog }

  TFileTextLog = class
  private
    class var FLogLevel: TLogLevel;
    class var FOnLog: TProcLog;
    class var FCriticalSection: TCriticalSection;
  public
    class property LogLevel: TLogLevel read FLogLevel write FLogLevel;
    class property OnLog: TProcLog read FOnLog write FOnLog;
    class procedure WriteLog(const AText: string; ALogType: TLogType = ltInfo; ALogLevel: TLogLevel = llLv1);
    class constructor ClassCreate;
    class destructor ClassDestroy;
  end;

  procedure WriteLog(const AText: string; ALogType: TLogType = ltInfo; ALogLevel: TLogLevel = llLv1);
  procedure WriteLogDbg(const AText: string; ALogType: TLogType = ltDebug; ALogLevel: TLogLevel = llLv1);
  procedure WriteLogFmt(const AText: string; const Args: Array of const; ALogType: TLogType = ltInfo; ALogLevel: TLogLevel = llLv1);

implementation

procedure WriteLog(const AText: string; ALogType: TLogType = ltInfo; ALogLevel: TLogLevel = llLv1);
begin
  TFileTextLog.WriteLog(AText, ALogType, ALogLevel);
end;

procedure WriteLogDbg(const AText: string; ALogType: TLogType = ltDebug; ALogLevel: TLogLevel = llLv1);
begin
  if GConfigEnv.Debug then
    TFileTextLog.WriteLog(AText, ALogType, ALogLevel);
end;

procedure WriteLogFmt(const AText: string; const Args: Array of const; ALogType: TLogType = ltInfo; ALogLevel: TLogLevel = llLv1);
begin
  WriteLog(Format(AText, Args), ALogType, ALogLevel);
end;

{ TFileTextLog }

class procedure TFileTextLog.WriteLog(const AText: string; ALogType: TLogType = ltInfo; ALogLevel: TLogLevel = llLv1);
var
  lPreFix, lFileLogName, lLogLine: string;
  lFile: TextFile;
  lOnLog: TProcLog;
begin
  if ALogLevel > TFileTextLog.LogLevel then
    Exit;

  case ALogType of
    ltDebug:    lPreFix:= '[Debg] ';
    ltInfo:     lPreFix:= '[Info] ';
    ltErro:     lPreFix:= '[Erro] ';
    ltCritical: lPreFix:= '[Crit] ';
  end;

  lLogLine:= lPreFix + FormatDateTime('dd/mm/yyyy hh:nn:ss:zzz', Now) + ' => ' + AText;

  TFileTextLog.FCriticalSection.Enter;
  try
    lFileLogName:= ChangeFileExt(ParamStr(0), '.log');

    AssignFile(lFile, lFileLogName);
    {$I-}
    if not FileExists(lFileLogName) then
      Rewrite(lFile)
    else
      Append(lFile);
    {$I+}

    if IOResult = 0 then
    try
      if ALogType <> ltCritical then
        WriteLn(lFile, lLogLine)
      else
      begin
        WriteLn(lFile, '==================================================================');
        WriteLn(lFile, lLogLine);
        WriteLn(lFile, '==================================================================');
      end;
    finally
      CloseFile(lFile);
    end;

    lOnLog:= TFileTextLog.OnLog;
  finally
    TFileTextLog.FCriticalSection.Leave;
  end;

  if Assigned(lOnLog) then
    lOnLog(AText);

end;

class constructor TFileTextLog.ClassCreate;
begin
  TFileTextLog.FCriticalSection:= TCriticalSection.Create;
  TFileTextLog.FLogLevel:= llLv2;
end;

class destructor TFileTextLog.ClassDestroy;
begin
  TFileTextLog.FCriticalSection.Free;
end;

end.
