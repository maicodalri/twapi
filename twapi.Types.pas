unit twapi.Types;

{$mode Delphi}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, SyncObjs; // [IA] Adicionados IniFiles e SyncObjs para leitura/geração thread-safe do JWTSecret no .conf

type

  { TConfigEnv }

  TConfigEnv = class
  private
    FIndexFilePage: string;
    FServerPort: Integer;
    FDebug: Boolean;
    FJWTSecret: string; // [IA] Armazena o segredo JWT em memória após carregar/gerar
    FLock: TCriticalSection; // [IA] Garante thread-safety ao carregar/criar o JWTSecret no .conf
    function GetJWTSecret: string; // [IA] Lê o JWTSecret do .conf ou gera automaticamente se não existir
    procedure SetJWTSecret(const AValue: string);
  public
    constructor Create;
    destructor Destroy; override;
    property Debug: Boolean read FDebug write FDebug;
    property IndexFilePage: string read FIndexFilePage write FIndexFilePage;
    property ServerPort: Integer read FServerPort write FServerPort;
    property JWTSecret: string read GetJWTSecret write SetJWTSecret; // [IA] Propriedade global para obter/definir o JWT_SECRET do projeto
  end;

const

  DB_TYPE_SQLITE     = 'sqlite';
  DB_TYPE_POSTGRESQL = 'postgresql';
  CONTENT_TYPE_JSON  = 'application/json; charset=utf-8';
  MASTER_DB          = 'masterdb';
  SECT_DB_NAME       = 'DB';
  SECT_BASE_NAME     = 'BASE';
  KEY_JWT_SECRET     = 'JWTSecret'; // [IA] Nome da chave no arquivo .conf dentro da seção [BASE]

var
  GConfigEnv: TConfigEnv;

implementation

{ TConfigEnv }

constructor TConfigEnv.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FJWTSecret := '';
end;

destructor TConfigEnv.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

// [IA] Obtém o JWTSecret da memória; se vazio, busca no .conf e, se não existir no .conf, gera um novo automaticamente e persiste
function TConfigEnv.GetJWTSecret: string;
var
  LIni: TIniFile;
  LFileName: string;
  LGUID1, LGUID2: TGUID;
  LGenerated: string;
begin
  if FJWTSecret <> '' then
    Exit(FJWTSecret);

  FLock.Enter;
  try
    if FJWTSecret = '' then
    begin
      LFileName := ChangeFileExt(ParamStr(0), '.conf');
      LIni := TIniFile.Create(LFileName);
      try
        FJWTSecret := Trim(LIni.ReadString(SECT_BASE_NAME, KEY_JWT_SECRET, ''));
        if FJWTSecret = '' then
        begin
          // [IA] Gera chave aleatória de 64 caracteres hexadecimais (256 bits) usando 2 GUIDs
          CreateGUID(LGUID1);
          CreateGUID(LGUID2);
          LGenerated := GUIDToString(LGUID1) + GUIDToString(LGUID2);
          LGenerated := StringReplace(LGenerated, '{', '', [rfReplaceAll]);
          LGenerated := StringReplace(LGenerated, '}', '', [rfReplaceAll]);
          LGenerated := StringReplace(LGenerated, '-', '', [rfReplaceAll]);

          FJWTSecret := LGenerated;
          LIni.WriteString(SECT_BASE_NAME, KEY_JWT_SECRET, FJWTSecret);
          LIni.UpdateFile;
        end;
      finally
        LIni.Free;
      end;
    end;
    Result := FJWTSecret;
  finally
    FLock.Leave;
  end;
end;

procedure TConfigEnv.SetJWTSecret(const AValue: string);
begin
  FLock.Enter;
  try
    FJWTSecret := Trim(AValue);
  finally
    FLock.Leave;
  end;
end;

initialization
  GConfigEnv:= TConfigEnv.Create;

finalization
  GConfigEnv.Free;

end.
