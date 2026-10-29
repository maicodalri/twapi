unit twapi.Controller.PoolConn;

{$mode Delphi}{$H+}

interface

uses
  Classes, SysUtils, ZConnection, SyncObjs, twapi.SmartPointerBase,
  twapi.Types, IniFiles;

type

  { TTempleteConn }

  TTempleteConn = record
    Protocol:         String;
    Port:             Integer;
    HostName:         String;
    DataBase:         String;
    User:             String;
    Password:         String;
    Lib:              String;
    procedure LoadFromFile;
    function BuildConn: TZConnection;
  end;

  TPooledConnection = class
  public
    Connection: TZConnection;
    DatabaseName: string;
    InUse: Boolean;
    LastUsed: TDateTime;
  end;

  { TZeosConnectionPool }

  TZeosConnectionPool = class
  strict private
    FTemplateConnection: TZConnection;
    FOwnsTemplate: Boolean; // [IA] Controla se o pool deve liberar FTemplateConnection no Destroy
    FConnections: TList;
    FLock: TCriticalSection;
    FMaxIdleMinutes: Integer;
    function CreateConnection(const ADatabaseName: string): TZConnection;
    procedure CleanupIdleConnections;
    class var FInstance: TZeosConnectionPool;
    class var FClassLock: TCriticalSection; // [IA] Lock para garantir Thread-Safety no Singleton GetInstance
  public
    class constructor ClassCreate; // [IA] Inicializa recursos estáticos da classe
    class destructor ClassDestroy; // [IA] Libera o Singleton FInstance e FClassLock evitando Memory Leak
    constructor Create(ATemplateConnection: TZConnection; AOwnsTemplate: Boolean = False);
    destructor Destroy; override;
    function Acquire(const ADatabaseName: string): TZConnection;
    procedure Release(AConnection: TZConnection);
    procedure Clear;
    property MaxIdleMinutes: Integer read FMaxIdleMinutes write FMaxIdleMinutes;
    class function GetInstance: TZeosConnectionPool;
    class function GetTampleteConnection: TZConnection;
  end;


implementation

{ TTempleteConn }

procedure TTempleteConn.LoadFromFile;
var
  lIniFile: TSmartPointer<TIniFile>;
  lFileName: string;
begin
  lFileName:= ChangeFileExt(ParamStr(0), '.conf');
  if not FileExists(lFileName) then
    raise Exception.CreateFmt('Arquivo [%s] não encotnrado.', [lFileName]);
  lIniFile:= TIniFile.Create(lFileName);
  Self.Protocol        := lIniFile.Value.ReadString  (SECT_DB_NAME, 'Protocol', 'sqlite');
  Self.Port            := lIniFile.Value.ReadInteger (SECT_DB_NAME, 'Port',     5432);
  Self.HostName        := lIniFile.Value.ReadString  (SECT_DB_NAME, 'Host',     'localhost');
  Self.Database        := lIniFile.Value.ReadString  (SECT_DB_NAME, 'Database', MASTER_DB);
  Self.User            := lIniFile.Value.ReadString  (SECT_DB_NAME, 'User',     '');
  Self.Password        := lIniFile.Value.ReadString  (SECT_DB_NAME, 'Paswd',    '');
  Self.Lib             := lIniFile.Value.ReadString  (SECT_DB_NAME, 'Lib',      '');

  if (SameText(Self.Protocol, DB_TYPE_SQLITE) and
     (not (Pos(Self.Database, '.db') <= 0))) then
    Self.Database:= Self.Database + '.db';

end;

function TTempleteConn.BuildConn: TZConnection;
begin
  Result:= TZConnection.Create(nil);
  Result.Protocol := Self.Protocol;
  Result.Database := Self.DataBase;
  Result.LibraryLocation := Self.Lib;
  Result.Password := Self.Password;
  Result.HostName := Self.HostName;
  Result.Port := Self.Port;
  Result.User := Self.User;
end;

{ TZeosConnectionPool }

// [IA] Criado class constructor para inicializar o lock estático do Singleton
class constructor TZeosConnectionPool.ClassCreate;
begin
  FClassLock := TCriticalSection.Create;
end;

// [IA] Criado class destructor para liberar a instância do Singleton e evitar vazamento de memória (Memory Leak)
class destructor TZeosConnectionPool.ClassDestroy;
begin
  FreeAndNil(FInstance);
  FreeAndNil(FClassLock);
end;

function TZeosConnectionPool.CreateConnection(const ADatabaseName: string): TZConnection;
begin

  Result := TZConnection.Create(nil);
  try
    Result.Protocol        := FTemplateConnection.Protocol;
    Result.HostName        := FTemplateConnection.HostName;
    Result.Port            := FTemplateConnection.Port;
    Result.User            := FTemplateConnection.User;
    Result.Password        := FTemplateConnection.Password;
    Result.Catalog         := FTemplateConnection.Catalog;
    Result.LibraryLocation := FTemplateConnection.LibraryLocation;
    Result.AutoCommit      := FTemplateConnection.AutoCommit; // [IA] Preserva configuração de AutoCommit do template
    Result.Properties.Assign(FTemplateConnection.Properties);

    // [IA] Caso ADatabaseName venha vazio, utiliza o Database padrão configurado no Template
    if Trim(ADatabaseName) <> '' then
      Result.Database := ADatabaseName
    else
      Result.Database := FTemplateConnection.Database;

    Result.Connect;
  except
    on E: Exception do
    begin
      Result.Free;
      raise Exception.Create('Falha de conexão com o banco "' + ADatabaseName + '": ' + E.Message);
    end;
  end;

end;

procedure TZeosConnectionPool.CleanupIdleConnections;
var
  i: Integer;
  LPooled: TPooledConnection;
begin
  // Nota: Este método deve ser executado apenas sob o lock do FLock
  for i := FConnections.Count - 1 downto 0 do
  begin
    LPooled := TPooledConnection(FConnections[i]);
    if (not LPooled.InUse) and ((Now - LPooled.LastUsed) * 1440 > FMaxIdleMinutes) then
    begin
      try
        if LPooled.Connection.Connected then
          LPooled.Connection.Disconnect;
      except
        // Ignora erros ao fechar a conexão física
      end;
      LPooled.Connection.Free;
      LPooled.Free;
      FConnections.Delete(i);
    end;
  end;
end;

constructor TZeosConnectionPool.Create(ATemplateConnection: TZConnection; AOwnsTemplate: Boolean = False);
begin
  inherited Create;
  FTemplateConnection := ATemplateConnection;
  FOwnsTemplate := AOwnsTemplate; // [IA] Define se FTemplateConnection será destruída junto com o pool
  FConnections := TList.Create;
  FLock := TCriticalSection.Create;
  FMaxIdleMinutes := 10; // 10 minutos de inatividade padrão antes de desconectar
end;

destructor TZeosConnectionPool.Destroy;
begin
  Clear;
  // [IA] Libera FTemplateConnection caso pertença ao Pool, corrigindo Memory Leak do BuildConn
  if FOwnsTemplate then
    FreeAndNil(FTemplateConnection);
  FConnections.Free;
  FLock.Free;
  inherited Destroy;
end;

function TZeosConnectionPool.Acquire(const ADatabaseName: string): TZConnection;
var
  i: Integer;
  LPooled: TPooledConnection;
  LTargetDb, LDbKey: string;
begin
  // [IA] Se ADatabaseName for vazio, usa o Database configurado no FTemplateConnection
  if Trim(ADatabaseName) <> '' then
    LTargetDb := ADatabaseName
  else
    LTargetDb := FTemplateConnection.Database;

  LDbKey := LowerCase(LTargetDb);

  FLock.Enter;
  try
    // Executa a limpeza preventiva de conexões inativas
    CleanupIdleConnections;
    // [IA] Percorre a lista permitindo remover conexões corrompidas caso a reconexão falhe
    i := 0;
    while i < FConnections.Count do
    begin
      LPooled := TPooledConnection(FConnections[i]);
      if (not LPooled.InUse) and (LPooled.DatabaseName = LDbKey) then
      begin
        // [IA] Verifica Connected e, apenas em bancos cliente/servidor (não-SQLite), executa PingServer protegido por try..except (pois SQLite no ZeosDB lança 'Unsupported operation' em PingServer)
        try
          if not LPooled.Connection.Connected then
            LPooled.Connection.Connect
          else if (Pos('sqlite', LowerCase(LPooled.Connection.Protocol)) = 0) and (not LPooled.Connection.PingServer) then
          begin
            LPooled.Connection.Disconnect;
            LPooled.Connection.Connect;
          end;
        except
          // [IA] Se falhar no PingServer ou reconexão, tenta reconectar e, se falhar novamente, descarta a conexão quebrada do pool
          try
            if LPooled.Connection.Connected then
              LPooled.Connection.Disconnect;
            LPooled.Connection.Connect;
          except
            try
              LPooled.Connection.Free;
            except
            end;
            LPooled.Free;
            FConnections.Delete(i);
            Continue;
          end;
        end;
        LPooled.InUse := True;
        LPooled.LastUsed := Now;
        Result := LPooled.Connection;
        Exit;
      end;
      Inc(i);
    end;

    // Se não encontrou nenhuma disponível, cria uma nova conexão física no pool
    LPooled := TPooledConnection.Create;
    try
      LPooled.Connection := CreateConnection(LTargetDb);
      LPooled.DatabaseName := LDbKey;
      LPooled.InUse := True;
      LPooled.LastUsed := Now;
      FConnections.Add(LPooled);
      Result := LPooled.Connection;
    except
      LPooled.Free;
      raise;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TZeosConnectionPool.Release(AConnection: TZConnection);
var
  i: Integer;
  LPooled: TPooledConnection;
begin
  if AConnection = nil then
    Exit;

  FLock.Enter;
  try
    for i := 0 to FConnections.Count - 1 do
    begin
      LPooled := TPooledConnection(FConnections[i]);
      if LPooled.Connection = AConnection then
      begin
        // [IA] Garante que nenhuma transação aberta acidentalmente fique pendurada ao devolver a conexão ao pool
        try
          if AConnection.Connected and AConnection.InTransaction then
            AConnection.Rollback;
          if Assigned(FTemplateConnection) then
            AConnection.AutoCommit := FTemplateConnection.AutoCommit
          else
            AConnection.AutoCommit := True;
        except
          // [IA] Se falhar ao dar Rollback (ex: conexão caiu durante o uso), força desconexão para ser recriada no próximo Acquire
          try
            AConnection.Disconnect;
          except
          end;
        end;

        LPooled.InUse := False;
        LPooled.LastUsed := Now;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TZeosConnectionPool.Clear;
var
  i: Integer;
  LPooled: TPooledConnection;
begin
  FLock.Enter;
  try
    for i := FConnections.Count - 1 downto 0 do
    begin
      LPooled := TPooledConnection(FConnections[i]);
      try
        if LPooled.Connection.Connected then
          LPooled.Connection.Disconnect;
      except
        // Ignora erros ao fechar
      end;
      LPooled.Connection.Free;
      LPooled.Free;
    end;
    FConnections.Clear;
  finally
    FLock.Leave;
  end;
end;

class function TZeosConnectionPool.GetInstance: TZeosConnectionPool;
var
  lConnRec: TTempleteConn;
begin
  // [IA] Double-checked locking com FClassLock para tornar o Singleton Thread-Safe e com FOwnsTemplate = True
  if not Assigned(Self.FInstance) then
  begin
    FClassLock.Enter;
    try
      if not Assigned(Self.FInstance) then
      begin
        lConnRec.LoadFromFile;
        Self.FInstance:= TZeosConnectionPool.Create(lConnRec.BuildConn, True);
      end;
    finally
      FClassLock.Leave;
    end;
  end;
  Result:= Self.FInstance;
end;

class function TZeosConnectionPool.GetTampleteConnection: TZConnection;
begin
  // [IA] Implementado retorno de FTemplateConnection para evitar retorno de ponteiro inválido (Access Violation)
  Result := GetInstance.FTemplateConnection;
end;

end.

