unit twapi.Auth;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, syncobjs,
  fpjson, jsonparser, sha1, base64,
  Horse, Horse.Commons,
  ZConnection, ZDataset, twapi.TextFileLog,
  twapi.Types, twapi.SQLBuilder; // [IA] Adicionado twapi.SQLBuilder para abstrair DDL e SELECT da tabela de sessões

const

  SQLITE3DLL = 'sqlite3.dll';

  // [IA] Removida constante fixa JWT_SECRET; agora a chave é obtida dinamicamente via GConfigEnv.JWTSecret (.conf)
  // [IA] Substituídas constantes de SQL fixo (CREATE TABLE, CREATE INDEX e SELECT) pelas classes de twapi.SQLBuilder
  TB_SESSIONS_NAME  = 'tb_sessions';
  IND_SESSIONS_NAME = 'idx_tb_sessions_token';

  // [IA] Comando para limpeza automática de sessões já expiradas no banco SQLite
  DELETE_EXPIRED_SESSIONS = 'DELETE FROM tb_sessions WHERE validade <= :agora';

var
  GLoginRoute: string;

type

  { TPersistToken }

  TPersistToken = class
  strict private
    class var FInstance: TPersistToken;
    class var FLock: TCriticalSection;
    FConnection: TZConnection;
  public
    function GetQuery(const ASql: string = ''): TZQuery;
    constructor Create;
    destructor Destroy; override;
    procedure SaveToken(const AToken: string);
    function ValidaTokenSalvo(const AToken: string): Boolean;
    class function GetInstance: TPersistToken;
    class constructor ClassConstructor;
    class destructor ClassDestroy;
  end;

  TTokenData = record
    UserId: Integer;
    Username: string;
    Database: string;
    UserType: string;
    Expiration: TDateTime;
    IsValid: Boolean;
  end;

  TAuthenticationEvent = function(const AUser: string;
                                  const APass: string;
                                  const ATenantAlias: string;
                                  const AIdSistem: Integer;
                                    out ADataBase: string;
                                    out AUserId: Integer;
                                    out AErrorMsg: string;
                                    out ATipoUser: string;
                                    out ALogoBase64: string): Boolean  of object;

// Retorna o nome do banco de dados pelo token
function GetDataBaseNameByToken(const AToken: string): string;

// Retornar a DataBase pela requisição
function GetDataBaseByReq(const AReq: THorseRequest): string;

// Retornar o ID do usuário pelo token
function GetUserIDByToken(const AToken: string): Int64;

//Retorna o ID do usuário pela requisição
function GetUserIDByReq(const AReq: THorseRequest): integer;

//Retornar o Token da requisição
function GetTokenByReq(const AReq: THorseRequest): string;

// Gera um token assinado criptograficamente contendo os dados de login e banco do tenant
function GenerateToken(const AUserId: Integer; const AUsername, AUserType, ADatabase: string): string;

// Valida o token recebido e extrai seus dados
function ValidateToken(const AToken: string): TTokenData;

// Valida o nome do banco de dados
function IsValidDatabaseName(const AName: string): Boolean;

// Middleware oficial do Horse para interceptar e autenticar requisições
procedure HorseAuthMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);

// Registra a rota de Login no Horse vinculando o evento callback de autenticação
procedure RegisterLoginRoute(const APath: string; AAuthEvent: TAuthenticationEvent);

// Função de Login principal
procedure HandleLogin(Req: THorseRequest; Res: THorseResponse);

implementation

var
  GOnAuthenticate: TAuthenticationEvent = nil;

// [IA] Helper para criar FormatSettings ISO fixo, independente da configuração regional do SO
function GetISOFormatSettings: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DateSeparator := '-';
  Result.TimeSeparator := ':';
  Result.ShortDateFormat := 'yyyy-mm-dd';
  Result.LongTimeFormat := 'hh:nn:ss';
end;

function GetDataBaseNameByToken(const AToken: string): string;
var
  lTokenData: TTokenData;
begin

  if Trim(AToken) = '' then
    Result:= ''
  else
  begin

    lTokenData:= ValidateToken(AToken);
    if lTokenData.IsValid then
      Result:= lTokenData.Database
    else
      Result:= '';

  end;

end;

function GetDataBaseByReq(const AReq: THorseRequest): string;
var
  lToken: string;
begin
  lToken:= GetTokenByReq(AReq);
  Result:= GetDataBaseNameByToken(lToken);
end;

function GetUserIDByToken(const AToken: string): Int64;
var
  lTokenData: TTokenData;
begin

  if Trim(AToken) = '' then
    Result:= 0
  else
  begin

    lTokenData:= ValidateToken(AToken);
    if lTokenData.IsValid then
      Result:= lTokenData.UserId
    else
      Result:= 0;

  end;

end;

function GetUserIDByReq(const AReq: THorseRequest): integer;
var
  lToken: string;
begin
  lToken:= GetTokenByReq(AReq);
  Result:= GetUserIDByToken(lToken);
end;

function GetTokenByReq(const AReq: THorseRequest): string;
var
  lAuthHeader: string;
begin

  lAuthHeader := AReq.Headers['Authorization'];
  if (lAuthHeader = '') or (not SameText(Copy(lAuthHeader, 1, 7), 'Bearer ')) then
  begin
    Result:= '';
  end
  else
    Result := Trim(Copy(LAuthHeader, 8, Length(LAuthHeader) - 7)); // [IA] Trim para remover eventuais espaços extras no header

end;

function GenerateToken(const AUserId: Integer; const AUsername, AUserType, ADatabase: string): string;
var
  LPayload: TJSONObject;
  LPayloadStr: string;
  LBase64: string;
  LSignature: string;
  LExp: TDateTime;
begin
  LPayload := TJSONObject.Create;
  try
    LExp := Now + 1.0; // Expira em 1 dia
    LPayload.Add('id', AUserId);
    LPayload.Add('usuario', AUsername);
    LPayload.Add('usuario_tipo', AUserType);
    LPayload.Add('database', ADatabase);
    // [IA] Grava a data de expiração em formato ISO invariante (independente de locale)
    LPayload.Add('exp', DateTimeToStr(LExp, GetISOFormatSettings));
    LPayloadStr := LPayload.AsJSON;
  finally
    LPayload.Free;
  end;

  LBase64 := EncodeStringBase64(LPayloadStr);
  // Limpa quebras de linha inseridas pelo codificador Base64
  LBase64 := StringReplace(LBase64, #13, '', [rfReplaceAll]);
  LBase64 := StringReplace(LBase64, #10, '', [rfReplaceAll]);

  // [IA] Cria a assinatura usando SHA1 do payload base64 + GConfigEnv.JWTSecret (lido/gerado no .conf)
  LSignature := SHA1Print(SHA1String(LBase64 + GConfigEnv.JWTSecret));
  Result := LBase64 + '.' + LSignature;
end;

function ValidateToken(const AToken: string): TTokenData;
var
  LParts: TStringList;
  LBase64, LSignature, LExpectedSig: string;
  LPayloadStr: string;
  LParser: TJSONParser;
  LJSONData: TJSONData;
  LPayload: TJSONObject;
  LExpStr: string;
  LExp: TDateTime;
begin
  Result := Default(TTokenData); // [IA] Inicializa todos os campos do record com valores seguros
  Result.IsValid := False;
  if Trim(AToken) = '' then Exit;

  LParts := TStringList.Create;
  try
    LParts.Delimiter := '.';
    LParts.StrictDelimiter := True;
    LParts.DelimitedText := AToken;

    if LParts.Count <> 2 then Exit;

    LBase64 := LParts[0];
    LSignature := LParts[1];

    // [IA] Valida assinatura criptográfica usando GConfigEnv.JWTSecret (lido/gerado no .conf)
    LExpectedSig := SHA1Print(SHA1String(LBase64 + GConfigEnv.JWTSecret));
    if LSignature <> LExpectedSig then Exit;

    try
      LPayloadStr := DecodeStringBase64(LBase64);
      LParser := TJSONParser.Create(LPayloadStr);
      try
        // [IA] Verifica se o retorno do Parse é realmente um TJSONObject antes do typecast para evitar Access Violation e Memory Leak
        LJSONData := LParser.Parse;
        if not Assigned(LJSONData) then Exit;
        try
          if LJSONData.JSONType <> jtObject then Exit;
          LPayload := TJSONObject(LJSONData);

          Result.UserId := LPayload.Get('id', 0);
          Result.Username := LPayload.Get('usuario', '');
          Result.Database := LPayload.Get('database', '');
          Result.UserType := LPayload.Get('usuario_tipo', '');
          LExpStr := LPayload.Get('exp', '');

          if LExpStr <> '' then
          begin
            // [IA] Tenta converter com formato ISO fixo e faz fallback para o formato local
            if not TryStrToDateTime(LExpStr, LExp, GetISOFormatSettings) then
              LExp := StrToDateTime(LExpStr);
            Result.Expiration := LExp;
            if LExp < Now then Exit; // Token expirado
          end
          else
            Exit; // [IA] Rejeita tokens sem data de expiração

          Result.IsValid := True;
        finally
          LJSONData.Free;
        end;
      finally
        LParser.Free;
      end;
    except
      Result.IsValid := False;
    end;
  finally
    LParts.Free;
  end;
end;

function IsValidDatabaseName(const AName: string): Boolean;
var
  i: Integer;
  LCleanName: string;
begin
  Result := AName <> '';
  if not Result then Exit;

  // Bloqueia barras de caminho e pontos de subida de pasta (Path Traversal)
  if (Pos('..', AName) > 0) or (Pos('/', AName) > 0) or (Pos('\', AName) > 0) then
  begin
    Result := False;
    Exit;
  end;

  // Se o banco contiver extensões locais de SQLite, remove para validar o nome limpo
  LCleanName := AName;
  // [IA] Verifica tamanho mínimo antes de usar Copy para evitar índice <= 0
  if (Length(LCleanName) > 3) and SameText(Copy(LCleanName, Length(LCleanName) - 2, 3), '.db') then
    LCleanName := Copy(LCleanName, 1, Length(LCleanName) - 3)
  else if (Length(LCleanName) > 7) and SameText(Copy(LCleanName, Length(LCleanName) - 6, 7), '.sqlite') then
    LCleanName := Copy(LCleanName, 1, Length(LCleanName) - 7);

  // [IA] Garante que o nome limpo não ficou vazio (ex: caso AName fosse apenas '.db')
  if LCleanName = '' then
  begin
    Result := False;
    Exit;
  end;

  // O nome do arquivo/banco deve ser estritamente alfanumérico ou underscore
  for i := 1 to Length(LCleanName) do
  begin
    if not (LCleanName[i] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

procedure HorseAuthMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  LToken: string;
  LTokenData: TTokenData;
  LDatabaseName: string;
begin

  // [IA] Permite passar livremente requisições OPTIONS, rota de login ou recursos estáticos (tudo que não inicia com /api/)
  if SameText(Req.RawWebRequest.Method, 'OPTIONS') or
     SameText(Req.RawWebRequest.PathInfo, GLoginRoute) or
     (not SameText(Copy(Trim(Req.RawWebRequest.PathInfo), 1, 5), '/api/')) then
  begin
    Next();
    Exit;
  end;

  // [IA] Extrai o token e valida uma única vez no middleware, reaproveitando LTokenData.Database
  LToken := GetTokenByReq(Req);
  LTokenData := ValidateToken(LToken);

  if (not LTokenData.IsValid) then
  begin
    Res.Status(401).Send('{"error": "Token de autorização inválido ou expirado"}').ContentType(CONTENT_TYPE_JSON);
    raise EHorseCallbackInterrupted.Create;
  end;

  if not TPersistToken.GetInstance.ValidaTokenSalvo(LToken) then
  begin
    Res.Status(401).Send('{"error": "Token de autorização não salvo"}').ContentType(CONTENT_TYPE_JSON);
    raise EHorseCallbackInterrupted.Create;
  end;

  LDatabaseName := LTokenData.Database;
  if LDatabaseName = '' then
  begin
    Res.Status(401).Send('{"error": "Sessão de autenticação inválida ou ausente"}').ContentType(CONTENT_TYPE_JSON);
    raise EHorseCallbackInterrupted.Create;
  end;

  if not IsValidDatabaseName(LDatabaseName) then
  begin
    Res.Status(400).Send('{"error": "Nome do banco de dados inválido ou não autorizado"}').ContentType(CONTENT_TYPE_JSON);
    raise EHorseCallbackInterrupted.Create;
  end;

  Next();

end;

procedure HandleLogin(Req: THorseRequest; Res: THorseResponse);
var
  LJSONData: TJSONData;
  LJSONObject: TJSONObject;
  LRespObj: TJSONObject;
  LSysIdNode: TJSONData;
  LTpUser, LTenantAlias, LUser, LToken, LPass, LDataBaseName: string;
  LUserId, LSystemID: Integer;
  LErrorMsg, LLogoB64: string;
  LAuthenticated: Boolean;
begin

  if not Assigned(GOnAuthenticate) then
  begin
    Res.Status(500).Send('{"error": "Evento de autenticação não configurado"}').ContentType(CONTENT_TYPE_JSON);
    Exit;
  end;

  // [IA] Proteção try..except ao redor de GetJSON para evitar erro 500 se o cliente enviar JSON malformado
  LJSONData := nil;
  try
    LJSONData := GetJSON(Req.Body);
  except
    LJSONData := nil;
  end;

  if (not Assigned(LJSONData)) or (LJSONData.JSONType <> jtObject) then
  begin
    if Assigned(LJSONData) then LJSONData.Free;
    Res.Status(400).Send('{"error": "Corpo da requisição inválido ou vazio"}').ContentType(CONTENT_TYPE_JSON);
    Exit;
  end;

  LJSONObject := TJSONObject(LJSONData);
  try

    LUser        := LJSONObject.Get('usuario', '');
    LPass        := LJSONObject.Get('senha', '');
    LTenantAlias := LJSONObject.Get('tenantalias', '');

    // [IA] Suporta 'systemid' enviado tanto como número (Integer) quanto como texto (String) no JSON
    LSystemID := 0;
    LSysIdNode := LJSONObject.Find('systemid');
    if Assigned(LSysIdNode) then
    begin
      if LSysIdNode.JSONType = jtNumber then
        LSystemID := LSysIdNode.AsInteger
      else if LSysIdNode.JSONType = jtString then
        LSystemID := StrToIntDef(LSysIdNode.AsString, 0);
    end;

    if (LUser = '') or (LPass = '') or
       (LTenantAlias = '') or (LSystemID <= 0) then
    begin
      Res.Status(400).Send('{"error": "Campos \"usuario\", \"senha\", \"tenantalias\" e \"systemid\" são obrigatórios no corpo da requisição"}').ContentType(CONTENT_TYPE_JSON);
      Exit;
    end;

    LErrorMsg := '';
    LDataBaseName:= '';
    LTpUser := '';
    LLogoB64 := '';
    LUserId := 0;
    try
      LAuthenticated := GOnAuthenticate(LUser,
                                        LPass,
                                        LTenantAlias,
                                        LSystemID,
                                        LDataBaseName,
                                        LUserId,
                                        LErrorMsg,
                                        LTpUser,
                                        LLogoB64);
    except
      on E: Exception do
      begin
        // [IA] Monta JSON de erro com TJSONObject para escapar aspas e caracteres especiais de E.Message
        LRespObj := TJSONObject.Create;
        try
          LRespObj.Add('error', 'Erro durante a autenticação: ' + E.Message);
          Res.Status(500).Send(LRespObj.AsJSON).ContentType(CONTENT_TYPE_JSON);
        finally
          LRespObj.Free;
        end;
        Exit;
      end;
    end;

    if not LAuthenticated then
    begin
      if LErrorMsg = '' then
        LErrorMsg := 'Usuário ou senha inválidos';
      // [IA] Monta JSON de erro 401 com TJSONObject para evitar quebra de JSON
      LRespObj := TJSONObject.Create;
      try
        LRespObj.Add('error', LErrorMsg);
        Res.Status(401).Send(LRespObj.AsJSON).ContentType(CONTENT_TYPE_JSON);
      finally
        LRespObj.Free;
      end;
      Exit;
    end;

    // Sucesso: Gera o token criptográfico assinado contendo o banco do tenant e salva-o no db da sessão
    LToken:= GenerateToken(LUserId, LUser, LTpUser, LDataBaseName);
    TPersistToken.GetInstance.SaveToken(lToken);

    // [IA] Serializa resposta de login via TJSONObject para escapar quebras de linha em LLogoB64
    LRespObj := TJSONObject.Create;
    try
      LRespObj.Add('token', LToken);
      LRespObj.Add('user_type', LTpUser);
      LRespObj.Add('logo', LLogoB64);
      Res.Send(LRespObj.AsJSON).ContentType(CONTENT_TYPE_JSON);
    finally
      LRespObj.Free;
    end;
  finally
    LJSONObject.Free;
  end;
end;

procedure RegisterLoginRoute(const APath: string; AAuthEvent: TAuthenticationEvent);
begin
  GLoginRoute:= APath;
  GOnAuthenticate := AAuthEvent;
  THorse.Post(APath, HandleLogin);
end;

{ TPersistToken }

class function TPersistToken.GetInstance: TPersistToken;
begin
  // [IA] Double-checked locking usando FLock para garantir criação Thread-Safe da instância SQLite
  if not Assigned(Self.FInstance) then
  begin
    Self.FLock.Enter;
    try
      if not Assigned(Self.FInstance) then
        Self.FInstance:= TPersistToken.Create;
    finally
      Self.FLock.Leave;
    end;
  end;
  Result:= Self.FInstance;
end;

class constructor TPersistToken.ClassConstructor;
begin
  TPersistToken.FLock:= TCriticalSection.Create;
end;

class destructor TPersistToken.ClassDestroy;
begin
  // [IA] Destrói FInstance antes do FLock para manter ordem segura de destruição
  if Assigned(FInstance) then
    FreeAndNil(FInstance);
  FreeAndNil(TPersistToken.FLock);
end;

function TPersistToken.GetQuery(const ASql: string): TZQuery;
begin
  Result:= TZQuery.Create(nil);
  Result.Connection:= Self.FConnection;
  Result.SQL.Text := ASql;
end;

constructor TPersistToken.Create;
var
  lLibrary: string;
  lTableBuilder: ISQLCreateTableBuilder;
  lQry: TZQuery;
begin

  lLibrary:= ExtractFilePath(ParamStr(0)) + SQLITE3DLL;

  Self.FConnection:= TZConnection.Create(nil);
  Self.FConnection.Protocol        := 'sqlite';
  Self.FConnection.Database        := ChangeFileExt(ParamStr(0), '.db');
  Self.FConnection.LibraryLocation := lLibrary;
  Self.FConnection.Connected := True;

  // [IA] Utiliza ISQLCreateTableBuilder para verificar a existência e criar a tabela e o índice de sessões de forma abstraída
  lTableBuilder := SQLCreateTable(TB_SESSIONS_NAME, Self.FConnection.Protocol)
    .IfNotExists
    .AddPrimaryKey('id', True)
    .AddVarchar('token', 3000)
    .AddVarchar('dbtenant', 300)
    .AddDateTime('validade')
    .AddDateTime('data_cadastro', False, True);

  lQry := Self.GetQuery(lTableBuilder.BuildCheckTableExists);
  try
    lQry.Open;
    if lQry.Fields[0].AsInteger = 0 then
    begin
      Self.FConnection.ExecuteDirect(lTableBuilder.Build);
      Self.FConnection.ExecuteDirect(lTableBuilder.BuildCreateIndex(IND_SESSIONS_NAME, ['token'], True));
    end;
  finally
    lQry.Free;
  end;

end;

destructor TPersistToken.Destroy;
begin
  // [IA] Libera FConnection antes de chamar inherited Destroy
  FreeAndNil(Self.FConnection);
  inherited Destroy;
end;

procedure TPersistToken.SaveToken(const AToken: string);
var
  lQry: TZQuery;
  lTokenData: TTokenData;
  lSQL: ISQLSelectBuilder;
begin

  Self.FLock.Enter;

  try

    lTokenData:= ValidateToken(AToken);

    if not lTokenData.IsValid then
      exit;

    // [IA] Remove sessões vencidas para evitar crescimento infinito do banco SQLite
    lQry := Self.GetQuery(DELETE_EXPIRED_SESSIONS);
    try
      lQry.ParamByName('agora').AsDateTime := Now;
      lQry.ExecSQL;
    finally
      lQry.Free;
    end;

    // [IA] Uso de SQLSelectFrom (ISQLSelectBuilder) com parâmetro nomeado para consultar a sessão (compatível com TZParams do ZeosDB)
    lSQL := SQLSelectFrom(TB_SESSIONS_NAME, Self.FConnection.Protocol)
      .WhereEqualParam('token', 'token');

    lQry:= Self.GetQuery(lSQL.Build);
    try
      lQry.ParamByName('token').AsString := AToken;
      lQry.Open;

      if lQry.IsEmpty then
        lQry.Append
      else
        lQry.Edit;

      lQry.FieldByName('token').AsString := AToken;
      lQry.FieldByName('validade').AsDateTime := lTokenData.Expiration;
      lQry.FieldByName('dbtenant').AsString := lTokenData.Database;

      lQry.Post;

    finally
      lQry.Free;
    end;

  finally
    Self.FLock.Leave;
  end;

end;

function TPersistToken.ValidaTokenSalvo(const AToken: string): Boolean;
var
  lQry: TZQuery;
  lTokenData: TTokenData;
  lSQL: ISQLSelectBuilder;
begin
  Result := False; // [IA] Inicializa Result com False para evitar retorno de lixo de memória caso saia no Exit

  Self.FLock.Enter;

  try

    lTokenData:= ValidateToken(AToken);

    if not lTokenData.IsValid then
      Exit(False);

    // [IA] Uso de SQLSelectFrom (ISQLSelectBuilder) com parâmetro nomeado para validar o token salvo (compatível com TZParams do ZeosDB)
    lSQL := SQLSelectFrom(TB_SESSIONS_NAME, Self.FConnection.Protocol)
      .WhereEqualParam('token', 'token');

    lQry:= Self.GetQuery(lSQL.Build);
    try
      lQry.ParamByName('token').AsString := AToken;
      lQry.Open;

      if lQry.IsEmpty then
        Exit(False);

      if lQry.FieldByName('validade').AsDateTime <= Now then
        Exit(False);

      if lQry.FieldByName('dbtenant').AsString <> lTokenData.Database then
        Exit(False);

      Result:= True;

    finally
      lQry.Free;
    end;

  finally
    Self.FLock.Leave;
  end;

end;

initialization
  // Registra o Middleware de Autenticação global do Horse
  THorse.Use(HorseAuthMiddleware);


end.
