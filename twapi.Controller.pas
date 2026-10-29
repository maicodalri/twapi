{*******************************************************************************
  TTWApiController - Mapeamento Automático de Tabelas ZeosDB para API REST
  Autor: Antigravity AI

  Dependências:
    - ZConnection, ZDataset (Suíte ZeosDB)
    - Horse (HashLoad Web Framework)
    - DataSet.Serialize (viniciussanchez)
    - Generics.Collections (Dicionários nativos do FPC/Delphi)

  Descrição:
    Esta unit expõe automaticamente uma tabela do banco de dados configurada como
    uma API REST (JSON) no framework Horse. Ela cria de forma autônoma os seguintes
    endpoints CRUD:

      GET    /recurso       -> Listar todos os registros da tabela (JSON Array)
      GET    /recurso/:id   -> Buscar um registro específico pela chave primária (JSON Object)
      POST   /recurso       -> Criar novo registro (Envia JSON Object no body, retorna 201)
      PUT    /recurso/:id   -> Atualizar registro existente (Envia JSON Object no body, retorna 200)
      DELETE /recurso/:id   -> Excluir um registro (Retorna HTTP 204 No Content)

  Multi-Tenancy & Segurança do Banco (TAuthSession & Custom Auth):
    O banco de dados de cada operação é chaveado de forma estritamente dinâmica e segura:
      1. Se o evento 'OnAuthenticateRequest' estiver definido, ele será executado
         em primeiro plano para realizar validações customizadas (ex: chaves de API,
         basic auth, etc.) e extrair o nome do banco de dados (tenant) associado.
      2. Caso contrário (ou se a validação customizada não retornar banco), o
         controlador faz o fallback padrão extraindo o banco de dados da sessão
         criptografada de autenticação ('Req.Session<TAuthSession>.DatabaseName').
      Se ambas as validações falharem (ou não estiverem ativas), o controlador
      bloqueia a operação imediatamente e retorna HTTP 401 Unauthorized.

  Mapeamento de Apelidos de Campos (Field Aliases):
    Através do método 'AddFieldMapping', é possível definir quais colunas da tabela
    devem ser expostas na API e sob quais apelidos (ex: expor a coluna 'id' no JSON
    como 'codigo'). Qualquer campo da tabela não mapeado será automaticamente
    oculto da API de retorno. Caso nenhum mapeamento seja feito (padrão), todos
    os campos originais da tabela serão exibidos.

  TZeosConnectionPool (Pool de Conexões Thread-Safe):
    Gerencia conexões abertas no pool por banco (tenant), reaproveitando-as.
    Seguro para concorrência multi-thread e protegido contra vazamento de memória.

  Paginação Automática (Listagem - GET):
    O endpoint de listagem aceita os seguintes parâmetros de Query String na URL:
      ?page=1&limit=50   (Padrão: página 1, limite 50. Limite máximo: 1000)
    Os metadados da paginação são injetados nos Cabeçalhos de Resposta HTTP (Response Headers):
      X-Total-Count: Total absoluto de registros filtrados na tabela
      X-Total-Pages: Total de páginas gerado a partir do limite e filtros
      X-Page: Página atual retornada
      X-Limit: Limite de registros por página retornado

  Filtros Dinâmicos de Query (Buscas - GET):
    Qualquer outro parâmetro de Query String na URL (que não seja 'page' ou 'limit')
    será interpretado automaticamente como um filtro de pesquisa (cláusula WHERE).
    - Mapeamento: Chaves JSON da URL (aliases) são traduzidas automaticamente para
      as colunas físicas do banco de dados (ex: 'nome_completo' -> 'nome').
      Chaves não registradas no AddFieldMapping caem em fallback para o próprio nome.
    - Segurança: Nomes de colunas são sanitizados alfanumericamente e valores são
      vinculados via parâmetros nomeados (:filter_campo), blindados contra SQL Injection.
    - Tipos de Busca:
      * Exata: Busca correspondência idêntica (ex: ?codigo=5).
      * Parcial: Se o valor contiver '%', faz busca parcial (ex: ?nome_completo=Maico%
        ou ?nome_completo=%Maico%).

  Eventos de Ciclo de Vida (CRUD Lifecycle Hooks):
    Permite interceptar e validar operações de escrita antes e após a gravação física:
      - OnBeforeCreate: Executa antes de inserir. Permite ler/alterar o JSON de entrada
        ou rejeitar a criação definindo AAllow := False e retornando um erro customizado.
      - OnAfterCreate: Executa após salvar com sucesso. Recebe o JSON gravado (contendo ID gerado).
      - OnBeforeUpdate: Executa antes de atualizar. Permite validar e rejeitar o update.
      - OnAfterUpdate: Executa após a gravação do update com sucesso.
      - OnBeforeDelete: Executa antes de excluir (somente se o registro existir).
      - OnAfterDelete: Executa após a exclusão física com sucesso no banco de dados.
*******************************************************************************}
unit twapi.Controller;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, DB,
  ZConnection, ZDataset, twapi.SmartPointerBase,
  Horse, fpjson, SyncObjs,
  DataSet.Serialize, Generics.Collections,
  twapi.SQLBuilder,
  twapi.Controller.PoolConn, twapi.Types, twapi.TextFileLog; // [IA] Adicionado twapi.TextFileLog para log seguro sem depender de console

type
  TFieldMapping = record
    FieldName: string;
    JSONKey: string;
  end;

  TTWApiController = class;

  TBeforeCreateEvent = procedure(Sender: TTWApiController; AJSONObject: TJSONObject; var AAllow: Boolean; var AErrorMessage: string; var DBConn: TZConnection) of object;
  TAfterCreateEvent = procedure(Sender: TTWApiController; AJSONObject: TJSONObject; var DBConn: TZConnection) of object;

  TBeforeUpdateEvent = procedure(Sender: TTWApiController; const AId: string; AJSONObject: TJSONObject; var AAllow: Boolean; var AErrorMessage: string; var DBConn: TZConnection) of object;
  TAfterUpdateEvent = procedure(Sender: TTWApiController; const AId: string; AJSONObject: TJSONObject; var DBConn: TZConnection) of object;

  TBeforeDeleteEvent = procedure(Sender: TTWApiController; const AId: string; var AAllow: Boolean; var AErrorMessage: string; var DBConn: TZConnection) of object;
  TAfterDeleteEvent = procedure(Sender: TTWApiController; const AId: string; var DBConn: TZConnection) of object;

  { TTWApiController }

  TTWApiController = class
  private
    FDefaultSortField: string;
    FOptionalListCondition: string;
    FTableName: string;
    FPrimaryKey: string;
    FBasePath: string;
    FDebugMode: Boolean;
    FOnBeforeCreate: TBeforeCreateEvent;
    FOnAfterCreate: TAfterCreateEvent;
    FOnBeforeUpdate: TBeforeUpdateEvent;
    FOnAfterUpdate: TAfterUpdateEvent;
    FOnBeforeDelete: TBeforeDeleteEvent;
    FOnAfterDelete: TAfterDeleteEvent;
    FFieldMappings: TDictionary<string, string>;
    FReverseFieldMappings: TDictionary<string, string>;
    FSoftDeleteField: string;
    FSoftDeleteActiveValue: string;
    FSoftDeleteDeletedValue: string;
    class var FRoutePrefix: string;
    function IsValidFieldName(const AName: string): Boolean;
    procedure ConfigureFields(ADataSet: TDataSet);
    procedure HandleException(Res: THorseResponse; E: Exception);

    // Helpers para mapeamento de chaves JSON
    function MapJSONArray(AArray: TJSONArray): TJSONArray;
    function MapJSONObject(AObj: TJSONObject): TJSONObject;
    function UnmapJSONObject(AObj: TJSONObject): TJSONObject;

    // Métodos internos que executam o CRUD
    procedure DoList(Req: THorseRequest; Res: THorseResponse);
    procedure DoFind(Req: THorseRequest; Res: THorseResponse);
    procedure DoCreate(Req: THorseRequest; Res: THorseResponse);
    procedure DoUpdate(Req: THorseRequest; Res: THorseResponse);
    procedure DoDelete(Req: THorseRequest; Res: THorseResponse);
  public
    constructor Create(const ATableName, APrimaryKey: string; ADebug: Boolean = False);
    destructor Destroy; override;

    procedure RegisterRoutes(const APath: string);
    procedure AddFieldMapping(const AFieldName, AJSONKey: string);

    property DefaultSortField: string read FDefaultSortField write FDefaultSortField;
    property TableName: string read FTableName;
    property PrimaryKey: string read FPrimaryKey;
    property BasePath: string read FBasePath;
    property DebugMode: Boolean read FDebugMode write FDebugMode;
    property OnBeforeCreate: TBeforeCreateEvent read FOnBeforeCreate write FOnBeforeCreate;
    property OnAfterCreate: TAfterCreateEvent read FOnAfterCreate write FOnAfterCreate;
    property OnBeforeUpdate: TBeforeUpdateEvent read FOnBeforeUpdate write FOnBeforeUpdate;
    property OnAfterUpdate: TAfterUpdateEvent read FOnAfterUpdate write FOnAfterUpdate;
    property OnBeforeDelete: TBeforeDeleteEvent read FOnBeforeDelete write FOnBeforeDelete;
    property OnAfterDelete: TAfterDeleteEvent read FOnAfterDelete write FOnAfterDelete;
    property OptionalListCondition: string read FOptionalListCondition write FOptionalListCondition;

    property SoftDeleteField: string read FSoftDeleteField write FSoftDeleteField;
    property SoftDeleteActiveValue: string read FSoftDeleteActiveValue write FSoftDeleteActiveValue;
    property SoftDeleteDeletedValue: string read FSoftDeleteDeletedValue write FSoftDeleteDeletedValue;

    class property RoutePrefix: string read FRoutePrefix write FRoutePrefix;
  end;

implementation

uses twapi.Auth;

var
  GControllers: TStringList = nil;
  GControllersLock: TCriticalSection = nil; // [IA] Lock para proteger acesso concorrente ao registro de controllers

// Declaração das procedures globais compatíveis com o Horse no FPC
procedure GlobalDoList(Req: THorseRequest; Res: THorseResponse); forward;
procedure GlobalDoFind(Req: THorseRequest; Res: THorseResponse); forward;
procedure GlobalDoCreate(Req: THorseRequest; Res: THorseResponse); forward;
procedure GlobalDoUpdate(Req: THorseRequest; Res: THorseResponse); forward;
procedure GlobalDoDelete(Req: THorseRequest; Res: THorseResponse); forward;

procedure InitRegistry;
begin
  if not Assigned(GControllersLock) then
    GControllersLock := TCriticalSection.Create;
  if not Assigned(GControllers) then
  begin
    GControllers := TStringList.Create;
    GControllers.Sorted := False;
  end;
end;

procedure UnregisterController(AController: TTWApiController);
var
  i: Integer;
begin
  if Assigned(GControllers) and Assigned(GControllersLock) then
  begin
    GControllersLock.Enter; // [IA] Proteção thread-safe ao remover controller da lista global
    try
      for i := GControllers.Count - 1 downto 0 do
      begin
        if GControllers.Objects[i] = AController then
          GControllers.Delete(i);
      end;
    finally
      GControllersLock.Leave;
    end;
  end;
end;

function FindController(Req: THorseRequest): TTWApiController;
var
  LPath: string;
  i: Integer;
  LKey: string;
  LBestIndex: Integer;
  LMaxLength: Integer;
begin
  Result := nil;
  if (not Assigned(GControllers)) or (not Assigned(GControllersLock)) then Exit;

  LPath := LowerCase(Req.RawWebRequest.PathInfo);
  if (LPath <> '') and (LPath[Length(LPath)] = '/') then
    Delete(LPath, Length(LPath), 1);

  LBestIndex := -1;
  LMaxLength := -1;

  GControllersLock.Enter; // [IA] Proteção thread-safe na busca de rotas
  try
    for i := 0 to GControllers.Count - 1 do
    begin
      LKey := LowerCase(GControllers[i]);
      if (LPath = LKey) or (Pos(LKey + '/', LPath) = 1) then
      begin
        if Length(LKey) > LMaxLength then
        begin
          LMaxLength := Length(LKey);
          LBestIndex := i;
        end;
      end;
    end;

    if LBestIndex <> -1 then
      Result := TTWApiController(GControllers.Objects[LBestIndex]);
  finally
    GControllersLock.Leave;
  end;
end;

{ TTWApiController }

constructor TTWApiController.Create(const ATableName, APrimaryKey: string; ADebug: Boolean = False);
begin
  inherited Create;
  FTableName := ATableName;
  FPrimaryKey := APrimaryKey;
  FDebugMode := ADebug;
  FSoftDeleteField := '';
  FSoftDeleteActiveValue := '';
  FSoftDeleteDeletedValue := '';
  FOptionalListCondition:= '';
  FFieldMappings := TDictionary<string, string>.Create;
  FReverseFieldMappings := TDictionary<string, string>.Create;
  InitRegistry;
end;

destructor TTWApiController.Destroy;
begin
  UnregisterController(Self);
  FFieldMappings.Free;
  FReverseFieldMappings.Free;
  inherited Destroy;
end;

function TTWApiController.IsValidFieldName(const AName: string): Boolean;
var
  i: Integer;
begin
  Result := AName <> '';
  if not Result then Exit;
  for i := 1 to Length(AName) do
  begin
    if not (AName[i] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

procedure TTWApiController.ConfigureFields(ADataSet: TDataSet);
var
  i: Integer;
  LField: TField;
begin
  if FFieldMappings.Count = 0 then Exit;

  for i := 0 to ADataSet.FieldCount - 1 do
    ADataSet.Fields[i].Visible := False;

  for i := 0 to ADataSet.FieldCount - 1 do
  begin
    LField := ADataSet.Fields[i];
    if FFieldMappings.ContainsKey(LField.FieldName) then
    begin
      LField.Visible := True;
    end;
  end;
end;

procedure TTWApiController.HandleException(Res: THorseResponse; E: Exception);
var
  LErrObj: TJSONObject;
begin
  // [IA] Substituído WriteLn por WriteLog (twapi.TextFileLog) para evitar erro I/O 103 em modo GUI/Serviço
  WriteLog(Format('[ERRO] %s', [E.Message]), ltErro);

  // [IA] Uso de TJSONObject para escapar corretamente caracteres especiais e aspas na mensagem JSON
  LErrObj := TJSONObject.Create;
  try
    if FDebugMode then
      LErrObj.Add('error', E.Message)
    else
      LErrObj.Add('error', 'Ocorreu um erro interno no processamento do servidor.');

    Res.Status(500).Send(LErrObj.AsJSON).ContentType(CONTENT_TYPE_JSON);
  finally
    LErrObj.Free;
  end;
end;

procedure TTWApiController.AddFieldMapping(const AFieldName, AJSONKey: string);
begin
  FFieldMappings.AddOrSetValue(AFieldName, AJSONKey);
  FReverseFieldMappings.AddOrSetValue(AJSONKey, AFieldName);
end;

function TTWApiController.MapJSONArray(AArray: TJSONArray): TJSONArray;
var
  i: Integer;
  LNewArray: TJSONArray;
  LObj: TJSONObject;
begin
  if FFieldMappings.Count = 0 then
  begin
    Result := AArray;
    Exit;
  end;

  LNewArray := TJSONArray.Create;
  for i := 0 to AArray.Count - 1 do
  begin
    if AArray.Items[i].JSONType = jtObject then
    begin
      LObj := MapJSONObject(TJSONObject(AArray.Items[i].Clone));
      LNewArray.Add(LObj);
    end;
  end;
  AArray.Free;
  Result := LNewArray;
end;

function TTWApiController.MapJSONObject(AObj: TJSONObject): TJSONObject;
var
  i: Integer;
  LNewObj: TJSONObject;
  LName, LAlias: string;
begin
  if FFieldMappings.Count = 0 then
  begin
    Result := AObj;
    Exit;
  end;

  LNewObj := TJSONObject.Create;
  for i := 0 to AObj.Count - 1 do
  begin
    LName := AObj.Names[i];
    if FFieldMappings.TryGetValue(LName, LAlias) then
    begin
      LNewObj.Add(LAlias, AObj.Items[i].Clone);
    end;
  end;
  AObj.Free;
  Result := LNewObj;
end;

function TTWApiController.UnmapJSONObject(AObj: TJSONObject): TJSONObject;
var
  i: Integer;
  LNewObj: TJSONObject;
  LName, LFieldName: string;
begin
  if FFieldMappings.Count = 0 then
  begin
    Result := AObj;
    Exit;
  end;

  LNewObj := TJSONObject.Create;
  for i := 0 to AObj.Count - 1 do
  begin
    LName := AObj.Names[i];
    if FReverseFieldMappings.TryGetValue(LName, LFieldName) then
    begin
      LNewObj.Add(LFieldName, AObj.Items[i].Clone);
    end;
  end;
  AObj.Free;
  Result := LNewObj;
end;

procedure TTWApiController.RegisterRoutes(const APath: string);
var
  LCleanPath: string;
  LCleanPrefix: string;
begin
  LCleanPath := APath;
  if (LCleanPath <> '') and (LCleanPath[Length(LCleanPath)] = '/') then
    Delete(LCleanPath, Length(LCleanPath), 1);
  if (LCleanPath <> '') and (LCleanPath[1] <> '/') then
    LCleanPath := '/' + LCleanPath;

  LCleanPrefix := FRoutePrefix;
  if (LCleanPrefix <> '') and (LCleanPrefix[Length(LCleanPrefix)] = '/') then
    Delete(LCleanPrefix, Length(LCleanPrefix), 1);
  if (LCleanPrefix <> '') and (LCleanPrefix[1] <> '/') then
    LCleanPrefix := '/' + LCleanPrefix;

  FBasePath := LCleanPrefix + LCleanPath;
  FBasePath := StringReplace(FBasePath, '//', '/', [rfReplaceAll]);

  GControllersLock.Enter; // [IA] Proteção thread-safe ao registrar rota na lista global
  try
    GControllers.AddObject(FBasePath, Self);
  finally
    GControllersLock.Leave;
  end;

  THorse.Get(FBasePath, GlobalDoList);
  THorse.Get(FBasePath + '/:_id', GlobalDoFind);
  THorse.Post(FBasePath, GlobalDoCreate);
  THorse.Put(FBasePath + '/:_id', GlobalDoUpdate);
  THorse.Delete(FBasePath + '/:_id', GlobalDoDelete);
end;

procedure TTWApiController.DoList(Req: THorseRequest; Res: THorseResponse);
var
  LQuery: TSmartPointer<TZQuery>;
  LCountQuery: TSmartPointer<TZQuery>;
  LConnection: TZConnection;
  LJSONArray: TJSONArray;
  LJSONString: string;
  LSortField, LOrderDir: string;
  LPage, LLimit: Integer;
  LTotalCount: Integer;
  LTotalPages: Integer;
  LPageStr, LLimitStr: string;
  LWhereClause: string;
  LFieldName: string;
  LSQLParamOp: string;
  LKey, LValue: string;
  LCondition: string;
  LSQL: ISQLSelectBuilder;
  LTokenData: TTokenData;

  procedure BindParams(AQuery: TZQuery);
  begin

    for LKey in Req.Query.Dictionary.Keys do
    begin
      if SameText(LKey, 'page') or SameText(LKey, 'limit') then
        Continue;
      LValue := Req.Query.Dictionary[LKey];
      if not FReverseFieldMappings.TryGetValue(LKey, LFieldName) then
        LFieldName := LKey;
      AQuery.ParamByName('filter_' + LFieldName).AsString := LValue;
    end;

  end;

  procedure ContaRegistros;
  begin

    // Executa contagem filtrada para obter o total de registros (Total Count)
    LCountQuery := TZQuery.Create(nil);
    LCountQuery.Value.Connection := LConnection;
    LCountQuery.Value.SQL.Text := LSQL.BuildCount;
    // Realiza o binding parametrizado dos filtros no CountQuery
    BindParams(LCountQuery.Value);
    LCountQuery.Value.Open;
    LTotalCount := LCountQuery.Value.Fields[0].AsInteger;

  end;

  procedure CalculaTotalPaginas;
  begin

    // Calcula total de páginas sem Math unit (divisão por inteiros)
    if LTotalCount > 0 then
    begin
      LTotalPages := LTotalCount div LLimit;
      if (LTotalCount mod LLimit) > 0 then
        Inc(LTotalPages);
    end;

  end;

  procedure AplicaLimitesSeguranca;
  begin

    // Aplica limites de segurança para a paginação
    if LPage < 1 then
      LPage := 1;
    if LLimit < 1 then
      LLimit := 50;
    if LLimit > 1000 then
      LLimit := 1000; // Cap de segurança contra sobrecarga de memória

  end;

begin

  LSQL:= TSQLSelectBuilder.Create;
  LSQL.From(FTableName);

  LTokenData:= ValidateToken(GetTokenByReq(Req));

  // 1. Constrói a cláusula WHERE dinamicamente a partir dos filtros da URL (Query String)
  for LKey in Req.Query.Dictionary.Keys do
  begin
    if SameText(LKey, 'page') or SameText(LKey, 'limit') then Continue;
    LValue := Req.Query.Dictionary[LKey];

    // Traduz a chave JSON para o campo físico correspondente no banco
    if not FReverseFieldMappings.TryGetValue(LKey, LFieldName) then
      LFieldName := LKey;

    // Sanitiza o nome da coluna física para evitar SQL Injection
    if not IsValidFieldName(LFieldName) then
    begin
      Res.Status(400).Send('{"error": "Parâmetro de busca inválido ou inseguro"}').ContentType(CONTENT_TYPE_JSON);
      Exit;
    end;

    // Se o valor contiver %, faz busca parcial (LIKE), caso contrário faz busca exata (=)
    if Pos('%', LValue) > 0 then
      LSQLParamOp := ' LIKE '
    else
      LSQLParamOp := ' = ';

    // [IA] Corrigido bug onde LWhereClause acumulava as condições anteriores sem zerar na iteração, gerando erro de sintaxe SQL com 2+ filtros
    LWhereClause := LFieldName + LSQLParamOp + ':filter_' + LFieldName;

    LSQL.Where(LWhereClause);

  end;

  // [IA] Corrigido filtro de Soft Delete no DoList para também tratar FSoftDeleteActiveValue vazio (IS NULL), alinhando com DoFind/DoUpdate/DoDelete
  if FSoftDeleteField <> '' then
  begin
    if FSoftDeleteActiveValue = '' then
      LSQL.WhereIsNull(FSoftDeleteField)
    else
      LSQL.WhereEqual(FSoftDeleteField, FSoftDeleteActiveValue);
  end;

  if (LTokenData.UserType <> 'A') and (LTokenData.UserType <> '') then //Se não for Administrador ('A'), aplica os filtros de escopo
  begin

    if Self.OptionalListCondition <> '' then
    begin

      LCondition:= Self.OptionalListCondition;
      if Pos(':USERID', Self.OptionalListCondition) > 0 then
        LCondition:= StringReplace(Self.OptionalListCondition, ':USERID', IntToStr(LTokenData.UserId), [rfIgnoreCase, rfReplaceAll]);
      LSQL.WhereAnd(LCondition);

    end;

  end;

  // Processa ordenação (se fornecida via headers)
  LSortField := Req.Headers['X-Sort'];
  LOrderDir := Req.Headers['X-Order'];

  if LSortField = '' then
    LSortField := Self.DefaultSortField;

  if LSortField <> '' then
  begin
    // Traduz o apelido (alias) para o campo físico correspondente no banco
    if not FReverseFieldMappings.TryGetValue(LSortField, LFieldName) then
      LFieldName := LSortField;

    if not IsValidFieldName(LFieldName) then
    begin
      Res.Status(400).Send('{"error": "O nome do campo para ordenação é inválido"}').ContentType(CONTENT_TYPE_JSON);
      Exit;
    end;

    // [IA] Uso de SameText para aceitar tanto 'DESC' quanto 'desc' no cabeçalho X-Order
    if SameText(LOrderDir, 'DESC') then
      LSQL.OrderBy(LFieldName, TSQLOrderDirection.odDesc)
    else
      LSQL.OrderBy(LFieldName, TSQLOrderDirection.odAsc);

  end;

  try
    LConnection := TZeosConnectionPool.GetInstance.Acquire(LTokenData.Database);
  except
    on E: Exception do
    begin
      HandleException(Res, E);
      Exit;
    end;
  end;

  // Resgata os parâmetros da query string para paginação
  LPageStr := Req.Query['page'];
  LLimitStr := Req.Query['limit'];

  LPage := StrToIntDef(LPageStr, 1);
  LLimit := StrToIntDef(LLimitStr, 50);

  AplicaLimitesSeguranca;

  LTotalCount := 0;
  LTotalPages := 0;

  try
    try // [IA] Captura exceções de SQL durante a listagem e direciona para HandleException
      ContaRegistros;

      CalculaTotalPaginas;

      // Parâmetros de paginação na query principal
      LSQL.Limit(LLimit).Offset((LPage - 1) * LLimit);

      LQuery := TZQuery.Create(nil);

      LQuery.Value.Connection := LConnection;
      LQuery.Value.SQL.Text := LSQL.Build;

      // Realiza o binding parametrizado dos filtros na consulta principal (LQuery)
      BindParams(LQuery.Value);

      LQuery.Value.Open;

      ConfigureFields(LQuery.Value);

      LJSONArray := LQuery.Value.ToJSONArray;
      try
        LJSONArray := MapJSONArray(LJSONArray);
        LJSONString := LJSONArray.AsJSON;

        // Adiciona os metadados de paginação nos cabeçalhos da resposta HTTP
        Res.AddHeader('X-Total-Count', IntToStr(LTotalCount));
        Res.AddHeader('X-Total-Pages', IntToStr(LTotalPages));
        Res.AddHeader('X-Page', IntToStr(LPage));
        Res.AddHeader('X-Limit', IntToStr(LLimit));

        Res.Send(LJSONString).ContentType(CONTENT_TYPE_JSON);
      finally
        LJSONArray.Free;
      end;
    except
      on E: Exception do
        HandleException(Res, E);
    end;
  finally
    TZeosConnectionPool.GetInstance.Release(LConnection);
  end;
end;

procedure TTWApiController.DoFind(Req: THorseRequest; Res: THorseResponse);
var
  LQuery: TZQuery;
  LConnection: TZConnection;
  LTokenData: TTokenData;
  LJSONObject: TJSONObject;
  LJSONString: string;
  LId: string;
  LSQL: string;
begin
  LId := Req.Params['_id'];

  LTokenData:= ValidateToken(GetTokenByReq(Req));

  try
    LConnection := TZeosConnectionPool.GetInstance.Acquire(LTokenData.Database);
  except
    on E: Exception do
    begin
      HandleException(Res, E);
      Exit;
    end;
  end;

  try
    try // [IA] Captura exceções de SQL durante a busca por ID e direciona para HandleException
      LQuery := TZQuery.Create(nil);
      try
        LQuery.Connection := LConnection;
        LSQL := 'SELECT * FROM ' + FTableName + ' WHERE ' + FPrimaryKey + ' = :_id';
        if FSoftDeleteField <> '' then
        begin
          if FSoftDeleteActiveValue = '' then
            LSQL := LSQL + ' AND ' + FSoftDeleteField + ' IS NULL'
          else
            LSQL := LSQL + ' AND ' + FSoftDeleteField + ' = :sd_active';
        end;
        LQuery.SQL.Text := LSQL;
        LQuery.ParamByName('_id').AsString := LId;
        if (FSoftDeleteField <> '') and (FSoftDeleteActiveValue <> '') then
          LQuery.ParamByName('sd_active').AsString := FSoftDeleteActiveValue;
        LQuery.Open;

        if LQuery.IsEmpty then
        begin
          Res.Status(404).Send('{"error": "Registro não encontrado"}').ContentType(CONTENT_TYPE_JSON);
          Exit;
        end;

        ConfigureFields(LQuery);

        LJSONObject := LQuery.ToJSONObject;
        try
          LJSONObject := MapJSONObject(LJSONObject);
          LJSONString := LJSONObject.AsJSON;
          Res.Send(LJSONString).ContentType(CONTENT_TYPE_JSON);
        finally
          LJSONObject.Free;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
        HandleException(Res, E);
    end;
  finally
    TZeosConnectionPool.GetInstance.Release(LConnection);
  end;
end;

procedure TTWApiController.DoCreate(Req: THorseRequest; Res: THorseResponse);
var
  LQuery: TZQuery;
  LConnection: TZConnection;
  LTokenData: TTokenData;
  LJSONData: TJSONData;
  LJSONObject: TJSONObject;
  LResultObject: TJSONObject;
  LAllow: Boolean;
  LErrorMsg: string;
  LID: Int64;
begin

  LTokenData:= ValidateToken(GetTokenByReq(Req));

  // [IA] Proteção contra exceção EJSONParser caso o corpo da requisição contenha JSON malformado
  LJSONData := nil;
  try
    LJSONData := GetJSON(Req.Body);
  except
    LJSONData := nil;
  end;

  if (not Assigned(LJSONData)) or (LJSONData.JSONType <> jtObject) then
  begin
    if Assigned(LJSONData) then LJSONData.Free;
    Res.Status(400).Send('{"error": "Corpo da requisição inválido ou não é um objeto JSON válido"}').ContentType(CONTENT_TYPE_JSON);
    Exit;
  end;

  LJSONObject := TJSONObject(LJSONData);
  try

    try
      LConnection := TZeosConnectionPool.GetInstance.Acquire(LTokenData.Database);
    except
      on E: Exception do
      begin
        HandleException(Res, E);
        Exit;
      end;
    end;

    // [IA] Bloco try..finally movido para logo após o Acquire para garantir Release(LConnection) mesmo se OnBeforeCreate rejeitar (Exit)
    try
      try
        if Assigned(FOnBeforeCreate) then
        begin
          LAllow := True;
          LErrorMsg := '';
          FOnBeforeCreate(Self, LJSONObject, LAllow, LErrorMsg, LConnection);
          if not LAllow then
          begin
            if LErrorMsg = '' then LErrorMsg := 'A criação do registro foi rejeitada.';
            Res.Status(400).Send(Format('{"error": "%s"}', [LErrorMsg])).ContentType(CONTENT_TYPE_JSON);
            Exit;
          end;
        end;

        LJSONObject := UnmapJSONObject(LJSONObject);

        LQuery := TZQuery.Create(nil);
        try

          LQuery.Connection := LConnection;

          // [IA] Obtém nextval apenas se não for SQLite e aplica no campo FPrimaryKey após LoadFromJSON
          LID := 0;
          if not SameText(LConnection.Protocol, 'sqlite') then
          begin
            LQuery.SQL.Text:= 'SELECT nextval(''seq_global_id'')';
            LQuery.Open;
            LID:= LQuery.Fields[0].AsLargeInt;
            LQuery.Close;
          end;

          LQuery.SQL.Text := 'SELECT * FROM ' + FTableName + ' WHERE 1 = 0';
          LQuery.Open;
          ConfigureFields(LQuery);
          LQuery.Append;
          LQuery.LoadFromJSON(LJSONObject);
          LJSONObject := nil; // [IA] DataSet.Serialize libera LJSONObject internamente; atribuir nil evita Double Free no finally

          // [IA] Atribui LID na coluna configurada em FPrimaryKey (em vez de 'id' fixo) e após LoadFromJSON para não ser sobrescrito
          if (LID > 0) and (LQuery.FindField(FPrimaryKey) <> nil) then
            LQuery.FieldByName(FPrimaryKey).AsLargeInt := LID;

          if LQuery.State in dsEditModes then
            LQuery.Post;

          LResultObject := LQuery.ToJSONObject;
          try
            LResultObject := MapJSONObject(LResultObject);
            if Assigned(FOnAfterCreate) then
              FOnAfterCreate(Self, LResultObject, LConnection);
            Res.Status(201).Send(LResultObject.AsJSON).ContentType(CONTENT_TYPE_JSON);
          finally
            LResultObject.Free;
          end;
        finally
          LQuery.Free;
        end;
      except
        on E: Exception do
          HandleException(Res, E);
      end;
    finally
      TZeosConnectionPool.GetInstance.Release(LConnection);
    end;
  finally
    // [IA] Descomentado para evitar Memory Leak caso a rotina saia antes de LoadFromJSON (ex: falha no Acquire, OnBeforeCreate ou SQL)
    if Assigned(LJSONObject) then
      LJSONObject.Free;
  end;
end;

procedure TTWApiController.DoUpdate(Req: THorseRequest; Res: THorseResponse);
var
  LQuery: TZQuery;
  LConnection: TZConnection;
  LTokenData: TTokenData;
  LJSONData: TJSONData;
  LJSONObject: TJSONObject;
  LResultObject: TJSONObject;
  LId: string;
  LAllow: Boolean;
  LErrorMsg: string;
  LSQL: string;
begin
  LId := Req.Params['_id'];

  LTokenData:= ValidateToken(GetTokenByReq(Req));

  // [IA] Proteção contra exceção EJSONParser caso o corpo da requisição contenha JSON malformado
  LJSONData := nil;
  try
    LJSONData := GetJSON(Req.Body);
  except
    LJSONData := nil;
  end;

  if (not Assigned(LJSONData)) or (LJSONData.JSONType <> jtObject) then
  begin
    if Assigned(LJSONData) then LJSONData.Free;
    Res.Status(400).Send('{"error": "Corpo da requisição inválido ou não é um objeto JSON válido"}').ContentType(CONTENT_TYPE_JSON);
    Exit;
  end;

  LJSONObject := TJSONObject(LJSONData);
  try

    try
      LConnection := TZeosConnectionPool.GetInstance.Acquire(LTokenData.Database);
    except
      on E: Exception do
      begin
        HandleException(Res, E);
        Exit;
      end;
    end;

    // [IA] Bloco try..finally movido para logo após o Acquire para garantir Release(LConnection) mesmo se OnBeforeUpdate rejeitar (Exit)
    try
      try
        if Assigned(FOnBeforeUpdate) then
        begin
          LAllow := True;
          LErrorMsg := '';
          FOnBeforeUpdate(Self, LId, LJSONObject, LAllow, LErrorMsg, LConnection);
          if not LAllow then
          begin
            if LErrorMsg = '' then
              LErrorMsg := 'A atualização do registro foi rejeitada.';
            Res.Status(400).Send(Format('{"error": "%s"}', [LErrorMsg])).ContentType(CONTENT_TYPE_JSON);
            Exit;
          end;
        end;

        LJSONObject := UnmapJSONObject(LJSONObject);

        LQuery := TZQuery.Create(nil);
        try
          LQuery.Connection := LConnection;
          LSQL := 'SELECT * FROM ' + FTableName + ' WHERE ' + FPrimaryKey + ' = :_id';
          if FSoftDeleteField <> '' then
          begin
            if FSoftDeleteActiveValue = '' then
              LSQL := LSQL + ' AND ' + FSoftDeleteField + ' IS NULL'
            else
              LSQL := LSQL + ' AND ' + FSoftDeleteField + ' = :sd_active';
          end;
          LQuery.SQL.Text := LSQL;
          LQuery.ParamByName('_id').AsString := LId;
          if (FSoftDeleteField <> '') and (FSoftDeleteActiveValue <> '') then
            LQuery.ParamByName('sd_active').AsString := FSoftDeleteActiveValue;
          LQuery.Open;

          if LQuery.IsEmpty then
          begin
            Res.Status(404).Send('{"error": "Registro não encontrado"}').ContentType(CONTENT_TYPE_JSON);
            Exit;
          end;

          ConfigureFields(LQuery);

          LQuery.Edit;
          LQuery.MergeFromJSONObject(LJSONObject);
          LJSONObject := nil; // [IA] DataSet.Serialize libera LJSONObject internamente; atribuir nil evita Double Free no finally

          if LQuery.State in dsEditModes then
            LQuery.Post;

          LResultObject := LQuery.ToJSONObject;
          try
            LResultObject := MapJSONObject(LResultObject);
            if Assigned(FOnAfterUpdate) then
              FOnAfterUpdate(Self, LId, LResultObject, LConnection);
            Res.Send(LResultObject.AsJSON).ContentType(CONTENT_TYPE_JSON);
          finally
            LResultObject.Free;
          end;
        finally
          LQuery.Free;
        end;
      except
        on E: Exception do
          HandleException(Res, E);
      end;
    finally
      TZeosConnectionPool.GetInstance.Release(LConnection);
    end;
  finally
    // [IA] Descomentado para evitar Memory Leak quando o registro não for encontrado (404) ou rejeitado em OnBeforeUpdate
    if Assigned(LJSONObject) then
      LJSONObject.Free;
  end;
end;

procedure TTWApiController.DoDelete(Req: THorseRequest; Res: THorseResponse);
var
  LQuery: TZQuery;
  LConnection: TZConnection;
  LId: string;
  LAllow: Boolean;
  LErrorMsg: string;
  LSQL: string;
  LTokenData: TTokenData;
begin
  LId := Req.Params['_id'];

  LTokenData:= ValidateToken(GetTokenByReq(Req));

  try
    LConnection := TZeosConnectionPool.GetInstance.Acquire(LTokenData.Database);
  except
    on E: Exception do
    begin
      HandleException(Res, E);
      Exit;
    end;
  end;

  try
    try // [IA] Captura exceções de SQL durante a exclusão (ex: violação de FK) e direciona para HandleException
      LQuery := TZQuery.Create(nil);
      try
        LQuery.Connection := LConnection;
        LSQL := 'SELECT * FROM ' + FTableName + ' WHERE ' + FPrimaryKey + ' = :_id';
        if FSoftDeleteField <> '' then
        begin
          if FSoftDeleteActiveValue = '' then
            LSQL := LSQL + ' AND ' + FSoftDeleteField + ' IS NULL'
          else
            LSQL := LSQL + ' AND ' + FSoftDeleteField + ' = :sd_active';
        end;
        LQuery.SQL.Text := LSQL;
        LQuery.ParamByName('_id').AsString := LId;
        if (FSoftDeleteField <> '') and (FSoftDeleteActiveValue <> '') then
          LQuery.ParamByName('sd_active').AsString := FSoftDeleteActiveValue;
        LQuery.Open;

        if LQuery.IsEmpty then
        begin
          Res.Status(404).Send('{"error": "Registro não encontrado"}').ContentType(CONTENT_TYPE_JSON);
          Exit;
        end;

        if Assigned(FOnBeforeDelete) then
        begin
          LAllow := True;
          LErrorMsg := '';
          FOnBeforeDelete(Self, LId, LAllow, LErrorMsg, LConnection);
          if not LAllow then
          begin
            if LErrorMsg = '' then
              LErrorMsg := 'A exclusão do registro foi rejeitada.';
            Res.Status(400).Send(Format('{"error": "%s"}', [LErrorMsg])).ContentType(CONTENT_TYPE_JSON);
            Exit;
          end;
        end;

        if FSoftDeleteField <> '' then
        begin
          LQuery.Edit;
          if FSoftDeleteDeletedValue <> '' then
            LQuery.FieldByName(FSoftDeleteField).AsString := FSoftDeleteDeletedValue
          else
          begin
            case LQuery.FieldByName(FSoftDeleteField).DataType of
              ftBoolean: LQuery.FieldByName(FSoftDeleteField).AsBoolean := False;
              ftInteger, ftLargeint, ftSmallint: LQuery.FieldByName(FSoftDeleteField).AsInteger := 0;
              ftFloat, ftCurrency: LQuery.FieldByName(FSoftDeleteField).AsFloat := 0.0;
              ftDate, ftTime, ftDateTime, ftTimeStamp: LQuery.FieldByName(FSoftDeleteField).AsDateTime := Now;
              else
                LQuery.FieldByName(FSoftDeleteField).AsString := 'D';
            end;
          end;
          LQuery.Post;
        end
        else
        begin
          LQuery.Delete;
        end;
        if Assigned(FOnAfterDelete) then
          FOnAfterDelete(Self, LId, LConnection);
        Res.Status(204).Send('');
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
        HandleException(Res, E);
    end;
  finally
    TZeosConnectionPool.GetInstance.Release(LConnection);
  end;
end;

// Implementação das procedures globais que redirecionam a requisição
procedure GlobalDoList(Req: THorseRequest; Res: THorseResponse);
var
  LController: TTWApiController;
begin
  LController := FindController(Req);
  if Assigned(LController) then
    LController.DoList(Req, Res)
  else
    Res.Status(404).Send('{"error": "Rota base não mapeada"}').ContentType(CONTENT_TYPE_JSON);
end;

procedure GlobalDoFind(Req: THorseRequest; Res: THorseResponse);
var
  LController: TTWApiController;
begin
  LController := FindController(Req);
  if Assigned(LController) then
    LController.DoFind(Req, Res)
  else
    Res.Status(404).Send('{"error": "Rota base não mapeada"}').ContentType(CONTENT_TYPE_JSON);
end;

procedure GlobalDoCreate(Req: THorseRequest; Res: THorseResponse);
var
  LController: TTWApiController;
begin
  LController := FindController(Req);
  if Assigned(LController) then
    LController.DoCreate(Req, Res)
  else
    Res.Status(404).Send('{"error": "Rota base não mapeada"}').ContentType(CONTENT_TYPE_JSON);
end;

procedure GlobalDoUpdate(Req: THorseRequest; Res: THorseResponse);
var
  LController: TTWApiController;
begin
  LController := FindController(Req);
  if Assigned(LController) then
    LController.DoUpdate(Req, Res)
  else
    Res.Status(404).Send('{"error": "Rota base não mapeada"}').ContentType(CONTENT_TYPE_JSON);
end;

procedure GlobalDoDelete(Req: THorseRequest; Res: THorseResponse);
var
  LController: TTWApiController;
begin
  LController := FindController(Req);
  if Assigned(LController) then
    LController.DoDelete(Req, Res)
  else
    Res.Status(404).Send('{"error": "Rota base não mapeada"}').ContentType(CONTENT_TYPE_JSON);
end;

initialization
  TTWApiController.RoutePrefix := '/db';

finalization
  if Assigned(GControllers) then
    FreeAndNil(GControllers);
  if Assigned(GControllersLock) then // [IA] Libera o lock global de rotas no encerramento
    FreeAndNil(GControllersLock);

end.
