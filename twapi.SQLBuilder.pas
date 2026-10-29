{*******************************************************************************

  twapi.SQLBuilder - Gerador fluente de comandos SQL SELECT (PostgreSQL e SQLite)

  Descrição:
    Unit para construção programática de comandos SQL SELECT com suporte a múltiplos
    dialetos (PostgreSQL e SQLite). Utiliza o padrão Fluent Interface (method
    chaining) para uma API intuitiva, segura e legível. A implementação é baseada
    em interfaces COM com contagem de referência automática, eliminando a
    necessidade de gerenciamento manual de memória (try/finally/Free).

  Funcionalidades e Diferenças de Dialeto:
    - Dialetos suportados: PostgreSQL (sdPostgreSQL) e SQLite (sdSQLite).
    - Seleção de dialeto flexível:
        * Globalmente via TSQLSelectBuilder.DefaultDialect (padrão inicial: sdPostgreSQL).
        * Na factory: SQLSelect(sdSQLite) ou SQLSelect('sqlite').
        * No encadeamento fluente: .Dialect(sdSQLite) ou .Dialect('sqlite').
        * No construtor da classe: TSQLSelectBuilder.Create(sdSQLite).
    - Case-insensitive LIKE (WhereILike e WhereILikeParam):
        * PostgreSQL: gera "campo ILIKE 'padrao'" ou "campo ILIKE :param".
        * SQLite: traduz para "campo LIKE 'padrao' COLLATE NOCASE" ou
          "campo LIKE :param COLLATE NOCASE" (o SQLite não possui o operador ILIKE).
    - Paginação segura (LIMIT e OFFSET):
        * PostgreSQL: suporta OFFSET isolado ("OFFSET n").
        * SQLite: exige LIMIT quando há OFFSET; gera "LIMIT -1 OFFSET n".
    - Suporte inteligente a schemas (FromSchema):
        * PostgreSQL: gera "schema"."tabela" (ex: "public"."clientes").
        * SQLite: omite automaticamente o schema "public", gerando "clientes"
          para evitar erro "no such table: public.clientes", mas mantém o schema
          caso seja um banco de dados anexado (ATTACH DATABASE).
    - Helpers booleanos tipados (WhereEqual / WhereNotEqual com Boolean):
        * PostgreSQL: gera "TRUE" / "FALSE".
        * SQLite: gera "1" / "0".
    - Helpers numéricos e datas:
        * Formatação decimal invariante (usa ponto "." mesmo em locale pt-BR).
        * WhereBetweenDate com formatação ISO "yyyy-mm-dd" ou "yyyy-mm-dd hh:nn:ss".
    - Parâmetros nomeados (:param) e integração direta com TParams (SQLdb, Zeos).
    - Geração de SELECT COUNT(*) simplificado via BuildCount.

  Exemplo 1 - Via interface (PostgreSQL padrão, contagem de referência automática):

    var
      Query: string;
    begin
      Query := SQLSelect
        .Fields(['id', 'nome', 'email'])
        .From('clientes')
        .WhereEqual('cidade', 'Curitiba')
        .OrderBy('nome')
        .Limit(10)
        .Build;
    end;

  Exemplo 2 - Via interface com SQLite:

    var
      Query: string;
    begin
      // Dialeto especificado na chamada:
      Query := SQLSelect(sdSQLite)
        .Fields(['id', 'nome'])
        .From('clientes')
        .WhereILike('nome', '%silva%')  // Gera: (nome LIKE '%silva%' COLLATE NOCASE)
        .WhereEqual('ativo', True)     // Gera: (ativo = 1)
        .Offset(20)                    // Gera: LIMIT -1 OFFSET 20
        .Build;

      // Ou utilizando o método fluente .Dialect():
      Query := SQLSelect
        .Dialect(sdSQLite)
        .Fields(['*'])
        .From('clientes')
        .Build;
    end;

  Exemplo 3 - Configuração global do dialeto (ideal na inicialização do app):

    // Configure uma única vez no início da aplicação (ex: lendo do arquivo .conf):
    TSQLSelectBuilder.DefaultDialect := StringToSQLDialect(LConfig.Protocol);

    // A partir de então, todas as chamadas SQLSelect usarão o dialeto configurado:
    Query := SQLSelect.From('clientes').WhereILike('nome', '%teste%').Build;

  Exemplo 4 - Parâmetros nomeados e integração com TParams (Zeos / SQLdb):

    var
      LSQL: ISQLSelectBuilder;
    begin
      LSQL := SQLSelect(sdSQLite)
        .From('clientes')
        .WhereEqualParam('cidade', 'pCidade')
        .WhereEqualParam('ativo', 'pAtivo')
        .SetParamStr('pCidade', 'Curitiba')
        .SetParamBool('pAtivo', True);

      QryClientes.SQL.Text := LSQL.Build;
      LSQL.ApplyParams(QryClientes.Params);
      QryClientes.Open;

      // Para obter a contagem total de registros (ignora LIMIT, OFFSET e ORDER BY):
      QryCount.SQL.Text := LSQL.BuildCount;
      LSQL.ApplyParams(QryCount.Params);
      QryCount.Open;
    end;

  Exemplo 5 - Uso via classe (gerenciamento manual com try/finally):

    var
      LSQL: TSQLSelectBuilder;
    begin
      LSQL := TSQLSelectBuilder.Create(sdSQLite);
      try
        LSQL.From('clientes');
        LSQL.Fields(['id', 'nome']);
        LSQL.WhereEqualParam('id', 'pId');
        LSQL.SetParamInt('pId', 123);

        Qry.SQL.Text := LSQL.Build;
        LSQL.ApplyParams(Qry.Params);
        Qry.Open;
      finally
        LSQL.Free;
      end;
    end;

  Compatibilidade:
    - Lazarus / Free Pascal (modo ObjFPC)
    - Interfaces COM (diretiva $interfaces com) para contagem de referência
    - Componentes de acesso a dados que utilizem TParams (SQLdb, Zeos, etc.)

  Dependências:
    Classes, SysUtils, DB

*******************************************************************************}

unit twapi.SQLBuilder;

{$mode objfpc}{$H+}
{$interfaces com}

interface

uses
  Classes, SysUtils, DB;

type
  { Dialetos SQL suportados }
  TSQLDialect = (
    sdPostgreSQL,
    sdSQLite
  );

  { Operador lógico entre cláusulas WHERE }
  TSQLLogicOperator = (loAnd, loOr);

  { Registro para armazenar cada cláusula WHERE }
  TSQLWhereClause = record
    Condition: string;
    LogicOp: TSQLLogicOperator;
    IsFirst: Boolean;
  end;

  { Direção da ordenação }
  TSQLOrderDirection = (odAsc, odDesc);

  { Registro para armazenar cada cláusula ORDER BY }
  TSQLOrderByClause = record
    FieldName: string;
    Direction: TSQLOrderDirection;
  end;

  { Tipo do parâmetro SQL }
  TSQLParamDataType = (
    spdtString,
    spdtInteger,
    spdtInt64,
    spdtFloat,
    spdtCurrency,
    spdtDate,
    spdtTime,
    spdtDateTime,
    spdtBoolean,
    spdtNull
  );

  { Registro para armazenar cada parâmetro nomeado }
  TSQLParamItem = record
    Name: string;
    DataType: TSQLParamDataType;
    AsString: string;
    AsInteger: Integer;
    AsInt64: Int64;
    AsFloat: Double;
    AsCurrency: Currency;
    AsDateTime: TDateTime;
    AsBoolean: Boolean;
  end;

  { ISQLSelectBuilder - Interface para geração de comandos SELECT (PostgreSQL e SQLite).
    Utiliza contagem de referência para gerenciamento automático de memória.

    Suporta dois modos de uso:

    1) Valores literais (rápido, para queries internas confiáveis):
       SQLSelect(sdSQLite).Fields(['id','nome']).From('clientes')
         .WhereILike('nome', '%silva%')
         .WhereEqual('ativo', True)
         .Build;

    2) Parâmetros nomeados (seguro, para dados de entrada do usuário):
       SQL := SQLSelect(sdSQLite).Fields(['id','nome']).From('clientes')
         .WhereEqualParam('cidade', 'pCidade')
         .SetParamStr('pCidade', 'Curitiba');
       Query.SQL.Text := SQL.Build;
       SQL.ApplyParams(Query.Params);
  }
  ISQLSelectBuilder = interface
    ['{A3F7B2E1-6D4C-4A8E-9F12-3B5C7D8E0FA1}']

    { ====== Configuração de dialeto ====== }
    function Dialect(ADialect: TSQLDialect): ISQLSelectBuilder; overload;
    function Dialect(const ADialectName: string): ISQLSelectBuilder; overload;

    { ====== Seleção de campos ====== }
    function Fields(const AFields: array of string): ISQLSelectBuilder; overload;
    function Fields(const AFieldsCSV: string): ISQLSelectBuilder; overload;
    function AllFields: ISQLSelectBuilder;
    function Distinct: ISQLSelectBuilder;

    { ====== Tabela de origem ====== }
    function From(const ATableName: string): ISQLSelectBuilder;
    function FromSchema(const ASchemaName, ATableName: string): ISQLSelectBuilder;

    { ====== WHERE - condição livre ====== }
    function Where(const ACondition: string): ISQLSelectBuilder;
    function WhereAnd(const ACondition: string): ISQLSelectBuilder;
    function WhereOr(const ACondition: string): ISQLSelectBuilder;

    { ====== WHERE - helpers com valores literais ====== }
    function WhereEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereEqual(const AField: string; AValue: Boolean): ISQLSelectBuilder; overload;
    function WhereEqual(const AField: string; AValue: TDateTime; const AFormat: string = ''): ISQLSelectBuilder; overload;
    function WhereNotEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereNotEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereNotEqual(const AField: string; AValue: Boolean): ISQLSelectBuilder; overload;
    function WhereGreaterThan(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereGreaterThan(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereGreaterThan(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereLessThan(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereLessThan(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereLessThan(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereGreaterOrEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereGreaterOrEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereGreaterOrEqual(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereLessOrEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereLessOrEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereLessOrEqual(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereLike(const AField: string; const APattern: string): ISQLSelectBuilder;
    function WhereILike(const AField: string; const APattern: string): ISQLSelectBuilder;
    function WhereIn(const AField: string; const AValues: array of string): ISQLSelectBuilder;
    function WhereInInt(const AField: string; const AValues: array of Integer): ISQLSelectBuilder;
    function WhereNotIn(const AField: string; const AValues: array of string): ISQLSelectBuilder;
    function WhereNotInInt(const AField: string; const AValues: array of Integer): ISQLSelectBuilder;
    function WhereIsNull(const AField: string): ISQLSelectBuilder;
    function WhereIsNotNull(const AField: string): ISQLSelectBuilder;
    function WhereBetween(const AField: string; const AMinValue, AMaxValue: string): ISQLSelectBuilder;
    function WhereBetweenInt(const AField: string; AMinValue, AMaxValue: Integer): ISQLSelectBuilder;
    function WhereBetweenDate(const AField: string; AMinValue, AMaxValue: TDateTime): ISQLSelectBuilder;

    { ====== WHERE - com parâmetros nomeados (:param) ====== }
    function WhereParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
    function WhereAndParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
    function WhereOrParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
    function WhereEqualParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereNotEqualParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereLikeParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereILikeParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereBetweenParam(const AField, AParamMin, AParamMax: string): ISQLSelectBuilder;

    { ====== Definição de valores dos parâmetros ====== }
    function SetParamStr(const AName: string; const AValue: string): ISQLSelectBuilder;
    function SetParamInt(const AName: string; AValue: Integer): ISQLSelectBuilder;
    function SetParamInt64(const AName: string; AValue: Int64): ISQLSelectBuilder;
    function SetParamFloat(const AName: string; AValue: Double): ISQLSelectBuilder;
    function SetParamCurrency(const AName: string; AValue: Currency): ISQLSelectBuilder;
    function SetParamDate(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
    function SetParamTime(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
    function SetParamDateTime(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
    function SetParamBool(const AName: string; AValue: Boolean): ISQLSelectBuilder;
    function SetParamNull(const AName: string): ISQLSelectBuilder;

    { Aplica os parâmetros armazenados a um TParams (TSQLQuery.Params, TZQuery.Params, etc.) }
    procedure ApplyParams(AParams: TParams);

    { ====== Ordenação ====== }
    function OrderBy(const AField: string; ADirection: TSQLOrderDirection = odAsc): ISQLSelectBuilder;
    function OrderByDesc(const AField: string): ISQLSelectBuilder;

    { ====== Paginação ====== }
    function Limit(AValue: Integer): ISQLSelectBuilder;
    function Offset(AValue: Integer): ISQLSelectBuilder;

    { ====== Construção e reset ====== }
    function Build: string;
    function BuildCount: string;
    function Clear: ISQLSelectBuilder;

    { ====== Propriedades de inspeção ====== }
    function GetDialect: TSQLDialect;
    procedure SetDialect(AValue: TSQLDialect);
    function GetTableName: string;
    function GetSchemaName: string;
    function GetHasLimit: Boolean;
    function GetHasOffset: Boolean;
    function GetLimitValue: Integer;
    function GetOffsetValue: Integer;
    function GetWhereCount: Integer;
    function GetParamCount: Integer;

    property SQLDialect: TSQLDialect read GetDialect write SetDialect;
    property TableName: string read GetTableName;
    property SchemaName: string read GetSchemaName;
    property HasLimit: Boolean read GetHasLimit;
    property HasOffset: Boolean read GetHasOffset;
    property LimitValue: Integer read GetLimitValue;
    property OffsetValue: Integer read GetOffsetValue;
    property WhereCount: Integer read GetWhereCount;
    property ParamCount: Integer read GetParamCount;
  end;

  { TSQLSelectBuilder - Implementação da interface ISQLSelectBuilder.
    Herda de TInterfacedObject para contagem de referência automática
    quando utilizado via interface.

    Suporta configuração de dialeto global (TSQLSelectBuilder.DefaultDialect)
    ou por instância (Create(sdSQLite), Create('sqlite'), etc.). }
  TSQLSelectBuilder = class(TInterfacedObject, ISQLSelectBuilder)
  private
    class var FDefaultDialect: TSQLDialect;
  private
    FDialect: TSQLDialect;
    FTableName: string;
    FSchemaName: string;
    FFieldsList: TStringList;
    FWhereClauses: array of TSQLWhereClause;
    FWhereCount: Integer;
    FOrderByClauses: array of TSQLOrderByClause;
    FOrderByCount: Integer;
    FParams: array of TSQLParamItem;
    FParamCount: Integer;
    FLimitValue: Integer;
    FOffsetValue: Integer;
    FHasLimit: Boolean;
    FHasOffset: Boolean;
    FIsSelectAll: Boolean;
    FIsDistinct: Boolean;

    procedure AddWhereClause(const ACondition: string; ALogicOp: TSQLLogicOperator);
    procedure InternalSetParam(const AItem: TSQLParamItem);
    function FindParamIndex(const AName: string): Integer;
    function QuoteIdentifier(const AIdentifier: string): string;
    function BuildFieldList: string;
    function BuildFromClause: string;
    function BuildWhereClause: string;
    function BuildOrderByClause: string;
    function BuildLimitOffset: string;
  public
    constructor Create; overload;
    constructor Create(ADialect: TSQLDialect); overload;
    constructor Create(const ADialectName: string); overload;
    destructor Destroy; override;

    class property DefaultDialect: TSQLDialect read FDefaultDialect write FDefaultDialect;

    { Configuração de dialeto }
    function Dialect(ADialect: TSQLDialect): ISQLSelectBuilder; overload;
    function Dialect(const ADialectName: string): ISQLSelectBuilder; overload;

    { Seleção de campos }
    function Fields(const AFields: array of string): ISQLSelectBuilder; overload;
    function Fields(const AFieldsCSV: string): ISQLSelectBuilder; overload;
    function AllFields: ISQLSelectBuilder;
    function Distinct: ISQLSelectBuilder;

    { Tabela de origem }
    function From(const ATableName: string): ISQLSelectBuilder;
    function FromSchema(const ASchemaName, ATableName: string): ISQLSelectBuilder;

    { WHERE - condição livre }
    function Where(const ACondition: string): ISQLSelectBuilder;
    function WhereAnd(const ACondition: string): ISQLSelectBuilder;
    function WhereOr(const ACondition: string): ISQLSelectBuilder;

    { WHERE - helpers com valores literais }
    function WhereEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereEqual(const AField: string; AValue: Boolean): ISQLSelectBuilder; overload;
    function WhereEqual(const AField: string; AValue: TDateTime; const AFormat: string = ''): ISQLSelectBuilder; overload;
    function WhereNotEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereNotEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereNotEqual(const AField: string; AValue: Boolean): ISQLSelectBuilder; overload;
    function WhereGreaterThan(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereGreaterThan(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereGreaterThan(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereLessThan(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereLessThan(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereLessThan(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereGreaterOrEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereGreaterOrEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereGreaterOrEqual(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereLessOrEqual(const AField: string; const AValue: string): ISQLSelectBuilder; overload;
    function WhereLessOrEqual(const AField: string; AValue: Integer): ISQLSelectBuilder; overload;
    function WhereLessOrEqual(const AField: string; AValue: Double): ISQLSelectBuilder; overload;
    function WhereLike(const AField: string; const APattern: string): ISQLSelectBuilder;
    function WhereILike(const AField: string; const APattern: string): ISQLSelectBuilder;
    function WhereIn(const AField: string; const AValues: array of string): ISQLSelectBuilder;
    function WhereInInt(const AField: string; const AValues: array of Integer): ISQLSelectBuilder;
    function WhereNotIn(const AField: string; const AValues: array of string): ISQLSelectBuilder;
    function WhereNotInInt(const AField: string; const AValues: array of Integer): ISQLSelectBuilder;
    function WhereIsNull(const AField: string): ISQLSelectBuilder;
    function WhereIsNotNull(const AField: string): ISQLSelectBuilder;
    function WhereBetween(const AField: string; const AMinValue, AMaxValue: string): ISQLSelectBuilder;
    function WhereBetweenInt(const AField: string; AMinValue, AMaxValue: Integer): ISQLSelectBuilder;
    function WhereBetweenDate(const AField: string; AMinValue, AMaxValue: TDateTime): ISQLSelectBuilder;

    { WHERE - com parâmetros nomeados }
    function WhereParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
    function WhereAndParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
    function WhereOrParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
    function WhereEqualParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereNotEqualParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereLikeParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereILikeParam(const AField, AParamName: string): ISQLSelectBuilder;
    function WhereBetweenParam(const AField, AParamMin, AParamMax: string): ISQLSelectBuilder;

    { Valores dos parâmetros }
    function SetParamStr(const AName: string; const AValue: string): ISQLSelectBuilder;
    function SetParamInt(const AName: string; AValue: Integer): ISQLSelectBuilder;
    function SetParamInt64(const AName: string; AValue: Int64): ISQLSelectBuilder;
    function SetParamFloat(const AName: string; AValue: Double): ISQLSelectBuilder;
    function SetParamCurrency(const AName: string; AValue: Currency): ISQLSelectBuilder;
    function SetParamDate(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
    function SetParamTime(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
    function SetParamDateTime(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
    function SetParamBool(const AName: string; AValue: Boolean): ISQLSelectBuilder;
    function SetParamNull(const AName: string): ISQLSelectBuilder;
    procedure ApplyParams(AParams: TParams);

    { Ordenação }
    function OrderBy(const AField: string; ADirection: TSQLOrderDirection = odAsc): ISQLSelectBuilder;
    function OrderByDesc(const AField: string): ISQLSelectBuilder;

    { Paginação }
    function Limit(AValue: Integer): ISQLSelectBuilder;
    function Offset(AValue: Integer): ISQLSelectBuilder;

    { Construção e reset }
    function Build: string;
    function BuildCount: string;
    function Clear: ISQLSelectBuilder;

    { Getters e Setters para propriedades da interface }
    function GetDialect: TSQLDialect;
    procedure SetDialect(AValue: TSQLDialect);
    function GetTableName: string;
    function GetSchemaName: string;
    function GetHasLimit: Boolean;
    function GetHasOffset: Boolean;
    function GetLimitValue: Integer;
    function GetOffsetValue: Integer;
    function GetWhereCount: Integer;
    function GetParamCount: Integer;

    property SQLDialect: TSQLDialect read GetDialect write SetDialect;
  end;

  { [IA] Ações de integridade referencial para Foreign Keys }
  TSQLForeignKeyAction = (
    fkNoAction,
    fkRestrict,
    fkCascade,
    fkSetNull,
    fkSetDefault
  );

  { [IA] Tipos lógicos de coluna abstraídos entre PostgreSQL e SQLite }
  TSQLColumnKind = (
    ckPrimaryKey,
    ckVarchar,
    ckText,
    ckInteger,
    ckBigInt,
    ckSmallInt,
    ckFloat,
    ckNumeric,
    ckBoolean,
    ckDate,
    ckTime,
    ckDateTime,
    ckBlob,
    ckCustom
  );

  { [IA] Definição interna de coluna para CREATE TABLE }
  TSQLColumnDef = record
    Name: string;
    Kind: TSQLColumnKind;
    CustomType: string;
    Size: Integer;
    Precision: Integer;
    Scale: Integer;
    NotNull: Boolean;
    Unique: Boolean;
    AutoIncrement: Boolean;
    UseBigInt: Boolean;
    HasDefault: Boolean;
    DefaultExpr: string;
    DefaultBool: Boolean;
  end;

  { [IA] Definição interna de Foreign Key }
  TSQLForeignKeyDef = record
    FieldName: string;
    RefTable: string;
    RefField: string;
    OnDelete: TSQLForeignKeyAction;
    OnUpdate: TSQLForeignKeyAction;
  end;

  { [IA] ISQLCreateTableBuilder - Interface fluente para criação de tabelas (PostgreSQL e SQLite)
    com suporte a verificação de existência (IF NOT EXISTS e consulta ao catálogo). }
  ISQLCreateTableBuilder = interface
    ['{D4E8C1A2-9B3F-4E7A-8C61-5A2F9E4B1D03}']

    { Configuração de dialeto e tabela }
    function Dialect(ADialect: TSQLDialect): ISQLCreateTableBuilder; overload;
    function Dialect(const ADialectName: string): ISQLCreateTableBuilder; overload;
    function Table(const ATableName: string): ISQLCreateTableBuilder;
    function TableSchema(const ASchemaName, ATableName: string): ISQLCreateTableBuilder;
    function IfNotExists(AValue: Boolean = True): ISQLCreateTableBuilder;

    { Adição de colunas tipadas (abstraídas por dialeto) }
    function AddPrimaryKey(const AFieldName: string; AAutoIncrement: Boolean = True; AUseBigInt: Boolean = False): ISQLCreateTableBuilder;
    function AddVarchar(const AFieldName: string; ASize: Integer = 100; ANotNull: Boolean = False; const ADefault: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;
    function AddText(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddInteger(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;
    function AddBigInt(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;
    function AddSmallInt(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddFloat(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddNumeric(const AFieldName: string; APrecision: Integer = 15; AScale: Integer = 2; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddCurrency(const AFieldName: string; ANotNull: Boolean = False; ADefaultZero: Boolean = False): ISQLCreateTableBuilder;
    function AddBoolean(const AFieldName: string; ANotNull: Boolean = False; AHasDefault: Boolean = False; ADefaultValue: Boolean = False): ISQLCreateTableBuilder;
    function AddDate(const AFieldName: string; ANotNull: Boolean = False; ADefaultNow: Boolean = False): ISQLCreateTableBuilder;
    function AddTime(const AFieldName: string; ANotNull: Boolean = False; ADefaultNow: Boolean = False): ISQLCreateTableBuilder;
    function AddDateTime(const AFieldName: string; ANotNull: Boolean = False; ADefaultNow: Boolean = False): ISQLCreateTableBuilder;
    function AddBlob(const AFieldName: string; ANotNull: Boolean = False): ISQLCreateTableBuilder;
    function AddCustomColumn(const AFieldName, ATypeDefinition: string; ANotNull: Boolean = False; const ADefaultExpr: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;

    { Constraints e Chaves Estrangeiras }
    function AddForeignKey(const AFieldName, ARefTable, ARefField: string; AOnDelete: TSQLForeignKeyAction = fkNoAction; AOnUpdate: TSQLForeignKeyAction = fkNoAction): ISQLCreateTableBuilder;
    function AddUniqueConstraint(const AConstraintName: string; const AFields: array of string): ISQLCreateTableBuilder;
    function AddCheckConstraint(const AConstraintName, ACondition: string): ISQLCreateTableBuilder;

    { Geração de SQL e Verificação de Existência }
    function Build: string;
    function BuildCheckTableExists: string;
    function BuildCreateIndex(const AIndexName: string; const AFields: array of string; AUnique: Boolean = False; AIfNotExists: Boolean = True): string;
    function Clear: ISQLCreateTableBuilder;

    { Inspeção }
    function GetDialect: TSQLDialect;
    procedure SetDialect(AValue: TSQLDialect);
    function GetTableName: string;
    function GetSchemaName: string;
    function GetIfNotExists: Boolean;
    function GetColumnCount: Integer;

    property SQLDialect: TSQLDialect read GetDialect write SetDialect;
    property TableName: string read GetTableName;
    property SchemaName: string read GetSchemaName;
    property CheckIfNotExists: Boolean read GetIfNotExists;
    property ColumnCount: Integer read GetColumnCount;
  end;

  { [IA] TSQLCreateTableBuilder - Implementação fluente de CREATE TABLE para PostgreSQL e SQLite }
  TSQLCreateTableBuilder = class(TInterfacedObject, ISQLCreateTableBuilder)
  private
    FDialect: TSQLDialect;
    FTableName: string;
    FSchemaName: string;
    FIfNotExists: Boolean;
    FColumns: array of TSQLColumnDef;
    FColumnCount: Integer;
    FForeignKeys: array of TSQLForeignKeyDef;
    FForeignKeyCount: Integer;
    FTableConstraints: TStringList;

    procedure InternalAddColumn(const ACol: TSQLColumnDef);
    function QuoteIdentifier(const AIdentifier: string): string;
    function BuildFullTableName: string;
    function FormatColumnDef(const ACol: TSQLColumnDef): string;
    function FormatForeignKeyAction(AAction: TSQLForeignKeyAction): string;
    function FormatForeignKeyDef(const AFK: TSQLForeignKeyDef): string;
  public
    constructor Create; overload;
    constructor Create(ADialect: TSQLDialect); overload;
    constructor Create(const ADialectName: string); overload;
    destructor Destroy; override;

    function Dialect(ADialect: TSQLDialect): ISQLCreateTableBuilder; overload;
    function Dialect(const ADialectName: string): ISQLCreateTableBuilder; overload;
    function Table(const ATableName: string): ISQLCreateTableBuilder;
    function TableSchema(const ASchemaName, ATableName: string): ISQLCreateTableBuilder;
    function IfNotExists(AValue: Boolean = True): ISQLCreateTableBuilder;

    function AddPrimaryKey(const AFieldName: string; AAutoIncrement: Boolean = True; AUseBigInt: Boolean = False): ISQLCreateTableBuilder;
    function AddVarchar(const AFieldName: string; ASize: Integer = 100; ANotNull: Boolean = False; const ADefault: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;
    function AddText(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddInteger(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;
    function AddBigInt(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;
    function AddSmallInt(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddFloat(const AFieldName: string; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddNumeric(const AFieldName: string; APrecision: Integer = 15; AScale: Integer = 2; ANotNull: Boolean = False; const ADefault: string = ''): ISQLCreateTableBuilder;
    function AddCurrency(const AFieldName: string; ANotNull: Boolean = False; ADefaultZero: Boolean = False): ISQLCreateTableBuilder;
    function AddBoolean(const AFieldName: string; ANotNull: Boolean = False; AHasDefault: Boolean = False; ADefaultValue: Boolean = False): ISQLCreateTableBuilder;
    function AddDate(const AFieldName: string; ANotNull: Boolean = False; ADefaultNow: Boolean = False): ISQLCreateTableBuilder;
    function AddTime(const AFieldName: string; ANotNull: Boolean = False; ADefaultNow: Boolean = False): ISQLCreateTableBuilder;
    function AddDateTime(const AFieldName: string; ANotNull: Boolean = False; ADefaultNow: Boolean = False): ISQLCreateTableBuilder;
    function AddBlob(const AFieldName: string; ANotNull: Boolean = False): ISQLCreateTableBuilder;
    function AddCustomColumn(const AFieldName, ATypeDefinition: string; ANotNull: Boolean = False; const ADefaultExpr: string = ''; AUnique: Boolean = False): ISQLCreateTableBuilder;

    function AddForeignKey(const AFieldName, ARefTable, ARefField: string; AOnDelete: TSQLForeignKeyAction = fkNoAction; AOnUpdate: TSQLForeignKeyAction = fkNoAction): ISQLCreateTableBuilder;
    function AddUniqueConstraint(const AConstraintName: string; const AFields: array of string): ISQLCreateTableBuilder;
    function AddCheckConstraint(const AConstraintName, ACondition: string): ISQLCreateTableBuilder;

    function Build: string;
    function BuildCheckTableExists: string;
    function BuildCreateIndex(const AIndexName: string; const AFields: array of string; AUnique: Boolean = False; AIfNotExists: Boolean = True): string;
    function Clear: ISQLCreateTableBuilder;

    function GetDialect: TSQLDialect;
    procedure SetDialect(AValue: TSQLDialect);
    function GetTableName: string;
    function GetSchemaName: string;
    function GetIfNotExists: Boolean;
    function GetColumnCount: Integer;

    property SQLDialect: TSQLDialect read GetDialect write SetDialect;
  end;

  { Funções utilitárias de dialeto }
  function StringToSQLDialect(const AName: string): TSQLDialect;
  function SQLDialectToString(ADialect: TSQLDialect): string;
  function GetDefaultSQLDialect: TSQLDialect;
  procedure SetDefaultSQLDialect(ADialect: TSQLDialect);

  { Funções factory - atalhos para criar instâncias via interface }
  function SQLSelect: ISQLSelectBuilder; overload;
  function SQLSelect(ADialect: TSQLDialect): ISQLSelectBuilder; overload;
  function SQLSelect(const ADialectName: string): ISQLSelectBuilder; overload;

  function SQLSelectFrom(const ATableName: string): ISQLSelectBuilder; overload;
  function SQLSelectFrom(const ATableName: string; ADialect: TSQLDialect): ISQLSelectBuilder; overload;
  function SQLSelectFrom(const ATableName: string; const ADialectName: string): ISQLSelectBuilder; overload;

  { [IA] Funções factory para criação de tabelas (CREATE TABLE) }
  function SQLCreateTable: ISQLCreateTableBuilder; overload;
  function SQLCreateTable(const ATableName: string): ISQLCreateTableBuilder; overload;
  function SQLCreateTable(const ATableName: string; ADialect: TSQLDialect): ISQLCreateTableBuilder; overload;
  function SQLCreateTable(const ATableName, ADialectName: string): ISQLCreateTableBuilder; overload;

implementation

{ ============================================================================ }
{ Funções utilitárias }
{ ============================================================================ }

function FloatToSQLStr(AValue: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FloatToStr(AValue, FS);
end;

function StringToSQLDialect(const AName: string): TSQLDialect;
var
  S: string;
begin
  S := LowerCase(Trim(AName));
  if (S = 'sqlite') or (S = 'sqlite-3') or (S = 'sqlite3') or (S = 'sqlite_3') then
    Result := sdSQLite
  else if (S = 'postgresql') or (S = 'postgres') or (S = 'pgsql') or (S = 'pg') or (S = 'postgre') then
    Result := sdPostgreSQL
  else
    Result := TSQLSelectBuilder.DefaultDialect;
end;

function SQLDialectToString(ADialect: TSQLDialect): string;
begin
  case ADialect of
    sdPostgreSQL: Result := 'PostgreSQL';
    sdSQLite:     Result := 'SQLite';
  else
    Result := 'PostgreSQL';
  end;
end;

function GetDefaultSQLDialect: TSQLDialect;
begin
  Result := TSQLSelectBuilder.DefaultDialect;
end;

procedure SetDefaultSQLDialect(ADialect: TSQLDialect);
begin
  TSQLSelectBuilder.DefaultDialect := ADialect;
end;

{ ============================================================================ }
{ Funções factory }
{ ============================================================================ }

function SQLSelect: ISQLSelectBuilder;
begin
  Result := TSQLSelectBuilder.Create;
end;

function SQLSelect(ADialect: TSQLDialect): ISQLSelectBuilder;
begin
  Result := TSQLSelectBuilder.Create(ADialect);
end;

function SQLSelect(const ADialectName: string): ISQLSelectBuilder;
begin
  Result := TSQLSelectBuilder.Create(ADialectName);
end;

function SQLSelectFrom(const ATableName: string): ISQLSelectBuilder;
begin
  Result := TSQLSelectBuilder.Create;
  Result.From(ATableName);
end;

function SQLSelectFrom(const ATableName: string; ADialect: TSQLDialect): ISQLSelectBuilder;
begin
  Result := TSQLSelectBuilder.Create(ADialect);
  Result.From(ATableName);
end;

function SQLSelectFrom(const ATableName: string; const ADialectName: string): ISQLSelectBuilder;
begin
  Result := TSQLSelectBuilder.Create(ADialectName);
  Result.From(ATableName);
end;

// [IA] Funções factory para ISQLCreateTableBuilder
function SQLCreateTable: ISQLCreateTableBuilder;
begin
  Result := TSQLCreateTableBuilder.Create;
end;

function SQLCreateTable(const ATableName: string): ISQLCreateTableBuilder;
begin
  Result := TSQLCreateTableBuilder.Create;
  Result.Table(ATableName);
end;

function SQLCreateTable(const ATableName: string; ADialect: TSQLDialect): ISQLCreateTableBuilder;
begin
  Result := TSQLCreateTableBuilder.Create(ADialect);
  Result.Table(ATableName);
end;

function SQLCreateTable(const ATableName, ADialectName: string): ISQLCreateTableBuilder;
begin
  Result := TSQLCreateTableBuilder.Create(ADialectName);
  Result.Table(ATableName);
end;

{ ============================================================================ }
{ TSQLSelectBuilder }
{ ============================================================================ }

constructor TSQLSelectBuilder.Create;
begin
  Create(FDefaultDialect);
end;

constructor TSQLSelectBuilder.Create(ADialect: TSQLDialect);
begin
  inherited Create;
  FDialect := ADialect;
  FFieldsList := TStringList.Create;
  FFieldsList.Delimiter := ',';
  FFieldsList.StrictDelimiter := True;
  FWhereCount := 0;
  FOrderByCount := 0;
  FParamCount := 0;
  FLimitValue := 0;
  FOffsetValue := 0;
  FHasLimit := False;
  FHasOffset := False;
  FIsSelectAll := True;
  FIsDistinct := False;
end;

constructor TSQLSelectBuilder.Create(const ADialectName: string);
begin
  Create(StringToSQLDialect(ADialectName));
end;

destructor TSQLSelectBuilder.Destroy;
begin
  FFieldsList.Free;
  SetLength(FWhereClauses, 0);
  SetLength(FOrderByClauses, 0);
  SetLength(FParams, 0);
  inherited Destroy;
end;

{ ---------------------------------------------------------------------------- }
{ Configuração de dialeto }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.Dialect(ADialect: TSQLDialect): ISQLSelectBuilder;
begin
  FDialect := ADialect;
  Result := Self;
end;

function TSQLSelectBuilder.Dialect(const ADialectName: string): ISQLSelectBuilder;
begin
  FDialect := StringToSQLDialect(ADialectName);
  Result := Self;
end;

function TSQLSelectBuilder.GetDialect: TSQLDialect;
begin
  Result := FDialect;
end;

procedure TSQLSelectBuilder.SetDialect(AValue: TSQLDialect);
begin
  FDialect := AValue;
end;

{ ---------------------------------------------------------------------------- }
{ Getters }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.GetTableName: string;
begin
  Result := FTableName;
end;

function TSQLSelectBuilder.GetSchemaName: string;
begin
  Result := FSchemaName;
end;

function TSQLSelectBuilder.GetHasLimit: Boolean;
begin
  Result := FHasLimit;
end;

function TSQLSelectBuilder.GetHasOffset: Boolean;
begin
  Result := FHasOffset;
end;

function TSQLSelectBuilder.GetLimitValue: Integer;
begin
  Result := FLimitValue;
end;

function TSQLSelectBuilder.GetOffsetValue: Integer;
begin
  Result := FOffsetValue;
end;

function TSQLSelectBuilder.GetWhereCount: Integer;
begin
  Result := FWhereCount;
end;

function TSQLSelectBuilder.GetParamCount: Integer;
begin
  Result := FParamCount;
end;

{ ---------------------------------------------------------------------------- }
{ Métodos privados }
{ ---------------------------------------------------------------------------- }

procedure TSQLSelectBuilder.AddWhereClause(const ACondition: string;
  ALogicOp: TSQLLogicOperator);
var
  Clause: TSQLWhereClause;
begin
  Clause.Condition := ACondition;
  Clause.LogicOp := ALogicOp;
  Clause.IsFirst := (FWhereCount = 0);

  Inc(FWhereCount);
  if FWhereCount > Length(FWhereClauses) then
    SetLength(FWhereClauses, FWhereCount + 4);

  FWhereClauses[FWhereCount - 1] := Clause;
end;

function TSQLSelectBuilder.FindParamIndex(const AName: string): Integer;
var
  I: Integer;
  UpperName: string;
begin
  Result := -1;
  UpperName := UpperCase(AName);
  for I := 0 to FParamCount - 1 do
    if UpperCase(FParams[I].Name) = UpperName then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TSQLSelectBuilder.InternalSetParam(const AItem: TSQLParamItem);
var
  Idx: Integer;
begin
  Idx := FindParamIndex(AItem.Name);
  if Idx >= 0 then
  begin
    // Atualiza parâmetro existente
    FParams[Idx] := AItem;
  end
  else
  begin
    // Adiciona novo parâmetro
    Inc(FParamCount);
    if FParamCount > Length(FParams) then
      SetLength(FParams, FParamCount + 4);
    FParams[FParamCount - 1] := AItem;
  end;
end;

function TSQLSelectBuilder.QuoteIdentifier(const AIdentifier: string): string;
begin
  if (Length(AIdentifier) >= 2) and (AIdentifier[1] = '"') and (AIdentifier[Length(AIdentifier)] = '"') then
    Exit(AIdentifier);

  if (Pos(' ', AIdentifier) > 0) or (Pos('-', AIdentifier) > 0) then
    Result := '"' + StringReplace(AIdentifier, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AIdentifier;
end;

function TSQLSelectBuilder.BuildFieldList: string;
var
  I: Integer;
begin
  if FIsSelectAll or (FFieldsList.Count = 0) then
    Result := '*'
  else
  begin
    Result := '';
    for I := 0 to FFieldsList.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ', ';
      Result := Result + Trim(FFieldsList[I]);
    end;
  end;

  if FIsDistinct then
    Result := 'DISTINCT ' + Result;
end;

function TSQLSelectBuilder.BuildFromClause: string;
begin
  // Em SQLite, o schema 'public' não existe por padrão, portanto é ignorado
  // mantendo apenas o nome da tabela. Se for outro schema (ex: banco anexado), mantém.
  if (FSchemaName <> '') and not ((FDialect = sdSQLite) and SameText(FSchemaName, 'public')) then
    Result := QuoteIdentifier(FSchemaName) + '.' + QuoteIdentifier(FTableName)
  else
    Result := QuoteIdentifier(FTableName);
end;

function TSQLSelectBuilder.BuildWhereClause: string;
var
  I: Integer;
begin
  Result := '';
  if FWhereCount = 0 then
    Exit;

  Result := ' WHERE ';
  for I := 0 to FWhereCount - 1 do
  begin
    if not FWhereClauses[I].IsFirst then
    begin
      case FWhereClauses[I].LogicOp of
        loAnd: Result := Result + ' AND ';
        loOr:  Result := Result + ' OR ';
      end;
    end;
    Result := Result + '(' + FWhereClauses[I].Condition + ')';
  end;
end;

function TSQLSelectBuilder.BuildOrderByClause: string;
var
  I: Integer;
begin
  Result := '';
  if FOrderByCount = 0 then
    Exit;

  Result := ' ORDER BY ';
  for I := 0 to FOrderByCount - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + FOrderByClauses[I].FieldName;
    case FOrderByClauses[I].Direction of
      odAsc:  Result := Result + ' ASC';
      odDesc: Result := Result + ' DESC';
    end;
  end;
end;

function TSQLSelectBuilder.BuildLimitOffset: string;
begin
  Result := '';
  if FDialect = sdSQLite then
  begin
    // SQLite exige que OFFSET seja acompanhado de LIMIT.
    // Se houver apenas OFFSET, usa LIMIT -1 OFFSET n
    if FHasLimit then
      Result := Result + ' LIMIT ' + IntToStr(FLimitValue)
    else if FHasOffset then
      Result := Result + ' LIMIT -1';

    if FHasOffset then
      Result := Result + ' OFFSET ' + IntToStr(FOffsetValue);
  end
  else
  begin
    // PostgreSQL aceita OFFSET isolado
    if FHasLimit then
      Result := Result + ' LIMIT ' + IntToStr(FLimitValue);
    if FHasOffset then
      Result := Result + ' OFFSET ' + IntToStr(FOffsetValue);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Seleção de campos }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.Fields(const AFields: array of string): ISQLSelectBuilder;
var
  I: Integer;
begin
  FIsSelectAll := False;
  FFieldsList.Clear;
  for I := Low(AFields) to High(AFields) do
    FFieldsList.Add(Trim(AFields[I]));
  Result := Self;
end;

function TSQLSelectBuilder.Fields(const AFieldsCSV: string): ISQLSelectBuilder;
var
  TempList: TStringList;
  I: Integer;
begin
  FIsSelectAll := False;
  FFieldsList.Clear;
  TempList := TStringList.Create;
  try
    TempList.Delimiter := ',';
    TempList.StrictDelimiter := True;
    TempList.DelimitedText := AFieldsCSV;
    for I := 0 to TempList.Count - 1 do
      FFieldsList.Add(Trim(TempList[I]));
  finally
    TempList.Free;
  end;
  Result := Self;
end;

function TSQLSelectBuilder.AllFields: ISQLSelectBuilder;
begin
  FIsSelectAll := True;
  FFieldsList.Clear;
  Result := Self;
end;

function TSQLSelectBuilder.Distinct: ISQLSelectBuilder;
begin
  FIsDistinct := True;
  Result := Self;
end;

{ ---------------------------------------------------------------------------- }
{ Tabela de origem }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.From(const ATableName: string): ISQLSelectBuilder;
begin
  FTableName := ATableName;
  FSchemaName := '';
  Result := Self;
end;

function TSQLSelectBuilder.FromSchema(const ASchemaName, ATableName: string): ISQLSelectBuilder;
begin
  FSchemaName := ASchemaName;
  FTableName := ATableName;
  Result := Self;
end;

{ ---------------------------------------------------------------------------- }
{ WHERE - condição livre }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.Where(const ACondition: string): ISQLSelectBuilder;
begin
  AddWhereClause(ACondition, loAnd);
  Result := Self;
end;

function TSQLSelectBuilder.WhereAnd(const ACondition: string): ISQLSelectBuilder;
begin
  AddWhereClause(ACondition, loAnd);
  Result := Self;
end;

function TSQLSelectBuilder.WhereOr(const ACondition: string): ISQLSelectBuilder;
begin
  AddWhereClause(ACondition, loOr);
  Result := Self;
end;

{ ---------------------------------------------------------------------------- }
{ WHERE - helpers com valores literais }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.WhereEqual(const AField: string; const AValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' = ' + QuotedStr(AValue));
end;

function TSQLSelectBuilder.WhereEqual(const AField: string; AValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' = ' + IntToStr(AValue));
end;

function TSQLSelectBuilder.WhereEqual(const AField: string; AValue: Boolean): ISQLSelectBuilder;
begin
  if FDialect = sdSQLite then
  begin
    if AValue then
      Result := Where(AField + ' = 1')
    else
      Result := Where(AField + ' = 0');
  end
  else
  begin
    if AValue then
      Result := Where(AField + ' = TRUE')
    else
      Result := Where(AField + ' = FALSE');
  end;
end;

function TSQLSelectBuilder.WhereEqual(const AField: string; AValue: TDateTime; const AFormat: string): ISQLSelectBuilder;
var
  Fmt: string;
begin
  if AFormat <> '' then
    Fmt := AFormat
  else if Frac(AValue) = 0 then
    Fmt := 'yyyy-mm-dd'
  else
    Fmt := 'yyyy-mm-dd hh:nn:ss';

  Result := Where(AField + ' = ' + QuotedStr(FormatDateTime(Fmt, AValue)));
end;

function TSQLSelectBuilder.WhereNotEqual(const AField: string; const AValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' <> ' + QuotedStr(AValue));
end;

function TSQLSelectBuilder.WhereNotEqual(const AField: string; AValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' <> ' + IntToStr(AValue));
end;

function TSQLSelectBuilder.WhereNotEqual(const AField: string; AValue: Boolean): ISQLSelectBuilder;
begin
  if FDialect = sdSQLite then
  begin
    if AValue then
      Result := Where(AField + ' <> 1')
    else
      Result := Where(AField + ' <> 0');
  end
  else
  begin
    if AValue then
      Result := Where(AField + ' <> TRUE')
    else
      Result := Where(AField + ' <> FALSE');
  end;
end;

function TSQLSelectBuilder.WhereGreaterThan(const AField: string; const AValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' > ' + AValue);
end;

function TSQLSelectBuilder.WhereGreaterThan(const AField: string; AValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' > ' + IntToStr(AValue));
end;

function TSQLSelectBuilder.WhereGreaterThan(const AField: string; AValue: Double): ISQLSelectBuilder;
begin
  Result := Where(AField + ' > ' + FloatToSQLStr(AValue));
end;

function TSQLSelectBuilder.WhereLessThan(const AField: string; const AValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' < ' + AValue);
end;

function TSQLSelectBuilder.WhereLessThan(const AField: string; AValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' < ' + IntToStr(AValue));
end;

function TSQLSelectBuilder.WhereLessThan(const AField: string; AValue: Double): ISQLSelectBuilder;
begin
  Result := Where(AField + ' < ' + FloatToSQLStr(AValue));
end;

function TSQLSelectBuilder.WhereGreaterOrEqual(const AField: string; const AValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' >= ' + AValue);
end;

function TSQLSelectBuilder.WhereGreaterOrEqual(const AField: string; AValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' >= ' + IntToStr(AValue));
end;

function TSQLSelectBuilder.WhereGreaterOrEqual(const AField: string; AValue: Double): ISQLSelectBuilder;
begin
  Result := Where(AField + ' >= ' + FloatToSQLStr(AValue));
end;

function TSQLSelectBuilder.WhereLessOrEqual(const AField: string; const AValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' <= ' + AValue);
end;

function TSQLSelectBuilder.WhereLessOrEqual(const AField: string; AValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' <= ' + IntToStr(AValue));
end;

function TSQLSelectBuilder.WhereLessOrEqual(const AField: string; AValue: Double): ISQLSelectBuilder;
begin
  Result := Where(AField + ' <= ' + FloatToSQLStr(AValue));
end;

function TSQLSelectBuilder.WhereLike(const AField: string; const APattern: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' LIKE ' + QuotedStr(APattern));
end;

function TSQLSelectBuilder.WhereILike(const AField: string; const APattern: string): ISQLSelectBuilder;
begin
  if FDialect = sdSQLite then
    Result := Where(AField + ' LIKE ' + QuotedStr(APattern) + ' COLLATE NOCASE')
  else
    Result := Where(AField + ' ILIKE ' + QuotedStr(APattern));
end;

function TSQLSelectBuilder.WhereIn(const AField: string; const AValues: array of string): ISQLSelectBuilder;
var
  I: Integer;
  ValueList: string;
begin
  if Length(AValues) = 0 then
  begin
    Result := Where('1 = 0');
    Exit;
  end;
  ValueList := '';
  for I := Low(AValues) to High(AValues) do
  begin
    if I > Low(AValues) then
      ValueList := ValueList + ', ';
    ValueList := ValueList + QuotedStr(AValues[I]);
  end;
  Result := Where(AField + ' IN (' + ValueList + ')');
end;

function TSQLSelectBuilder.WhereInInt(const AField: string; const AValues: array of Integer): ISQLSelectBuilder;
var
  I: Integer;
  ValueList: string;
begin
  if Length(AValues) = 0 then
  begin
    Result := Where('1 = 0');
    Exit;
  end;
  ValueList := '';
  for I := Low(AValues) to High(AValues) do
  begin
    if I > Low(AValues) then
      ValueList := ValueList + ', ';
    ValueList := ValueList + IntToStr(AValues[I]);
  end;
  Result := Where(AField + ' IN (' + ValueList + ')');
end;

function TSQLSelectBuilder.WhereNotIn(const AField: string; const AValues: array of string): ISQLSelectBuilder;
var
  I: Integer;
  ValueList: string;
begin
  if Length(AValues) = 0 then
  begin
    Result := Self;
    Exit;
  end;
  ValueList := '';
  for I := Low(AValues) to High(AValues) do
  begin
    if I > Low(AValues) then
      ValueList := ValueList + ', ';
    ValueList := ValueList + QuotedStr(AValues[I]);
  end;
  Result := Where(AField + ' NOT IN (' + ValueList + ')');
end;

function TSQLSelectBuilder.WhereNotInInt(const AField: string; const AValues: array of Integer): ISQLSelectBuilder;
var
  I: Integer;
  ValueList: string;
begin
  if Length(AValues) = 0 then
  begin
    Result := Self;
    Exit;
  end;
  ValueList := '';
  for I := Low(AValues) to High(AValues) do
  begin
    if I > Low(AValues) then
      ValueList := ValueList + ', ';
    ValueList := ValueList + IntToStr(AValues[I]);
  end;
  Result := Where(AField + ' NOT IN (' + ValueList + ')');
end;

function TSQLSelectBuilder.WhereIsNull(const AField: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' IS NULL');
end;

function TSQLSelectBuilder.WhereIsNotNull(const AField: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' IS NOT NULL');
end;

function TSQLSelectBuilder.WhereBetween(const AField: string; const AMinValue, AMaxValue: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' BETWEEN ' + QuotedStr(AMinValue) + ' AND ' + QuotedStr(AMaxValue));
end;

function TSQLSelectBuilder.WhereBetweenInt(const AField: string; AMinValue, AMaxValue: Integer): ISQLSelectBuilder;
begin
  Result := Where(AField + ' BETWEEN ' + IntToStr(AMinValue) + ' AND ' + IntToStr(AMaxValue));
end;

function TSQLSelectBuilder.WhereBetweenDate(const AField: string; AMinValue, AMaxValue: TDateTime): ISQLSelectBuilder;
var
  Fmt: string;
begin
  if (Frac(AMinValue) <> 0) or (Frac(AMaxValue) <> 0) then
    Fmt := 'yyyy-mm-dd hh:nn:ss'
  else
    Fmt := 'yyyy-mm-dd';

  Result := Where(AField + ' BETWEEN ' +
    QuotedStr(FormatDateTime(Fmt, AMinValue)) +
    ' AND ' +
    QuotedStr(FormatDateTime(Fmt, AMaxValue)));
end;

{ ---------------------------------------------------------------------------- }
{ WHERE - com parâmetros nomeados (:param) }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.WhereParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' ' + AOperator + ' :' + AParamName);
end;

function TSQLSelectBuilder.WhereAndParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
begin
  Result := WhereAnd(AField + ' ' + AOperator + ' :' + AParamName);
end;

function TSQLSelectBuilder.WhereOrParam(const AField, AOperator, AParamName: string): ISQLSelectBuilder;
begin
  Result := WhereOr(AField + ' ' + AOperator + ' :' + AParamName);
end;

function TSQLSelectBuilder.WhereEqualParam(const AField, AParamName: string): ISQLSelectBuilder;
begin
  Result := WhereParam(AField, '=', AParamName);
end;

function TSQLSelectBuilder.WhereNotEqualParam(const AField, AParamName: string): ISQLSelectBuilder;
begin
  Result := WhereParam(AField, '<>', AParamName);
end;

function TSQLSelectBuilder.WhereLikeParam(const AField, AParamName: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' LIKE :' + AParamName);
end;

function TSQLSelectBuilder.WhereILikeParam(const AField, AParamName: string): ISQLSelectBuilder;
begin
  if FDialect = sdSQLite then
    Result := Where(AField + ' LIKE :' + AParamName + ' COLLATE NOCASE')
  else
    Result := Where(AField + ' ILIKE :' + AParamName);
end;

function TSQLSelectBuilder.WhereBetweenParam(const AField, AParamMin, AParamMax: string): ISQLSelectBuilder;
begin
  Result := Where(AField + ' BETWEEN :' + AParamMin + ' AND :' + AParamMax);
end;

{ ---------------------------------------------------------------------------- }
{ Definição de valores dos parâmetros }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.SetParamStr(const AName: string; const AValue: string): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtString;
  Item.AsString := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamInt(const AName: string; AValue: Integer): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtInteger;
  Item.AsInteger := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamInt64(const AName: string; AValue: Int64): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtInt64;
  Item.AsInt64 := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamFloat(const AName: string; AValue: Double): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtFloat;
  Item.AsFloat := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamCurrency(const AName: string; AValue: Currency): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtCurrency;
  Item.AsCurrency := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamDate(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtDate;
  Item.AsDateTime := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamTime(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtTime;
  Item.AsDateTime := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamDateTime(const AName: string; AValue: TDateTime): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtDateTime;
  Item.AsDateTime := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamBool(const AName: string; AValue: Boolean): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtBoolean;
  Item.AsBoolean := AValue;
  InternalSetParam(Item);
  Result := Self;
end;

function TSQLSelectBuilder.SetParamNull(const AName: string): ISQLSelectBuilder;
var
  Item: TSQLParamItem;
begin
  Item := Default(TSQLParamItem);
  Item.Name := AName;
  Item.DataType := spdtNull;
  InternalSetParam(Item);
  Result := Self;
end;

{ ---------------------------------------------------------------------------- }
{ Aplicação de parâmetros a TParams }
{ ---------------------------------------------------------------------------- }

procedure TSQLSelectBuilder.ApplyParams(AParams: TParams);
var
  I: Integer;
  P: TParam;
  Item: TSQLParamItem;
begin
  for I := 0 to FParamCount - 1 do
  begin
    Item := FParams[I];

    // Busca parâmetro existente ou cria novo
    P := AParams.FindParam(Item.Name);
    if P = nil then
      P := AParams.CreateParam(ftUnknown, Item.Name, ptInput);

    case Item.DataType of
      spdtString:
      begin
        P.DataType := ftString;
        P.AsString := Item.AsString;
      end;
      spdtInteger:
      begin
        P.DataType := ftInteger;
        P.AsInteger := Item.AsInteger;
      end;
      spdtInt64:
      begin
        P.DataType := ftLargeint;
        P.AsLargeInt := Item.AsInt64;
      end;
      spdtFloat:
      begin
        P.DataType := ftFloat;
        P.AsFloat := Item.AsFloat;
      end;
      spdtCurrency:
      begin
        P.DataType := ftCurrency;
        P.AsCurrency := Item.AsCurrency;
      end;
      spdtDate:
      begin
        P.DataType := ftDate;
        P.AsDate := Item.AsDateTime;
      end;
      spdtTime:
      begin
        P.DataType := ftTime;
        P.AsTime := Item.AsDateTime;
      end;
      spdtDateTime:
      begin
        P.DataType := ftDateTime;
        P.AsDateTime := Item.AsDateTime;
      end;
      spdtBoolean:
      begin
        P.DataType := ftBoolean;
        P.AsBoolean := Item.AsBoolean;
      end;
      spdtNull:
      begin
        P.Clear;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Ordenação }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.OrderBy(const AField: string; ADirection: TSQLOrderDirection): ISQLSelectBuilder;
var
  OrderClause: TSQLOrderByClause;
begin
  OrderClause.FieldName := AField;
  OrderClause.Direction := ADirection;

  Inc(FOrderByCount);
  if FOrderByCount > Length(FOrderByClauses) then
    SetLength(FOrderByClauses, FOrderByCount + 2);

  FOrderByClauses[FOrderByCount - 1] := OrderClause;
  Result := Self;
end;

function TSQLSelectBuilder.OrderByDesc(const AField: string): ISQLSelectBuilder;
begin
  Result := OrderBy(AField, odDesc);
end;

{ ---------------------------------------------------------------------------- }
{ Paginação }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.Limit(AValue: Integer): ISQLSelectBuilder;
begin
  FLimitValue := AValue;
  FHasLimit := True;
  Result := Self;
end;

function TSQLSelectBuilder.Offset(AValue: Integer): ISQLSelectBuilder;
begin
  FOffsetValue := AValue;
  FHasOffset := True;
  Result := Self;
end;

{ ---------------------------------------------------------------------------- }
{ Construção e reset }
{ ---------------------------------------------------------------------------- }

function TSQLSelectBuilder.Build: string;
begin
  if FTableName = '' then
    raise Exception.Create('TSQLSelectBuilder: nome da tabela não definido. Utilize o método From().');

  Result := 'SELECT ' + BuildFieldList +
            ' FROM ' + BuildFromClause +
            BuildWhereClause +
            BuildOrderByClause +
            BuildLimitOffset;
end;

function TSQLSelectBuilder.BuildCount: string;
begin
  if FTableName = '' then
    raise Exception.Create('TSQLSelectBuilder: nome da tabela não definido. Utilize o método From().');

  // Gera SELECT COUNT(*) preservando apenas FROM e WHERE.
  // ORDER BY, LIMIT e OFFSET são ignorados pois o objetivo
  // é retornar o total absoluto de registros que atendem aos filtros.
  Result := 'SELECT COUNT(*) FROM ' + BuildFromClause +
            BuildWhereClause;
end;

function TSQLSelectBuilder.Clear: ISQLSelectBuilder;
begin
  FTableName := '';
  FSchemaName := '';
  FFieldsList.Clear;
  SetLength(FWhereClauses, 0);
  FWhereCount := 0;
  SetLength(FOrderByClauses, 0);
  FOrderByCount := 0;
  SetLength(FParams, 0);
  FParamCount := 0;
  FLimitValue := 0;
  FOffsetValue := 0;
  FHasLimit := False;
  FHasOffset := False;
  FIsSelectAll := True;
  FIsDistinct := False;
  Result := Self;
end;

{ ============================================================================ }
{ [IA] TSQLCreateTableBuilder - Criação de tabelas e verificação de existência }
{ ============================================================================ }

constructor TSQLCreateTableBuilder.Create;
begin
  Create(TSQLSelectBuilder.DefaultDialect);
end;

constructor TSQLCreateTableBuilder.Create(ADialect: TSQLDialect);
begin
  inherited Create;
  FDialect := ADialect;
  FTableName := '';
  FSchemaName := '';
  FIfNotExists := True; // [IA] Por padrão sempre verifica se a tabela já existe (IF NOT EXISTS)
  FColumnCount := 0;
  FForeignKeyCount := 0;
  FTableConstraints := TStringList.Create;
end;

constructor TSQLCreateTableBuilder.Create(const ADialectName: string);
begin
  Create(StringToSQLDialect(ADialectName));
end;

destructor TSQLCreateTableBuilder.Destroy;
begin
  FTableConstraints.Free;
  SetLength(FColumns, 0);
  SetLength(FForeignKeys, 0);
  inherited Destroy;
end;

procedure TSQLCreateTableBuilder.InternalAddColumn(const ACol: TSQLColumnDef);
begin
  if Trim(ACol.Name) = '' then
    raise Exception.Create('TSQLCreateTableBuilder: nome da coluna não pode ser vazio.');

  Inc(FColumnCount);
  if FColumnCount > Length(FColumns) then
    SetLength(FColumns, FColumnCount + 8);
  FColumns[FColumnCount - 1] := ACol;
end;

function TSQLCreateTableBuilder.QuoteIdentifier(const AIdentifier: string): string;
begin
  if (Length(AIdentifier) >= 2) and (AIdentifier[1] = '"') and (AIdentifier[Length(AIdentifier)] = '"') then
    Exit(AIdentifier);

  if (Pos(' ', AIdentifier) > 0) or (Pos('-', AIdentifier) > 0) then
    Result := '"' + StringReplace(AIdentifier, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AIdentifier;
end;

function TSQLCreateTableBuilder.BuildFullTableName: string;
begin
  if (FSchemaName <> '') and not ((FDialect = sdSQLite) and SameText(FSchemaName, 'public')) then
    Result := QuoteIdentifier(FSchemaName) + '.' + QuoteIdentifier(FTableName)
  else
    Result := QuoteIdentifier(FTableName);
end;

function TSQLCreateTableBuilder.FormatColumnDef(const ACol: TSQLColumnDef): string;
var
  LTypeStr: string;
begin
  Result := QuoteIdentifier(ACol.Name) + ' ';

  // [IA] Tratamento específico de Primary Key por dialeto (PostgreSQL vs SQLite)
  if ACol.Kind = ckPrimaryKey then
  begin
    if FDialect = sdSQLite then
    begin
      if ACol.AutoIncrement then
        Result := Result + 'INTEGER PRIMARY KEY AUTOINCREMENT'
      else if ACol.UseBigInt then
        Result := Result + 'BIGINT PRIMARY KEY NOT NULL'
      else
        Result := Result + 'INTEGER PRIMARY KEY NOT NULL';
    end
    else
    begin
      if ACol.AutoIncrement then
      begin
        if ACol.UseBigInt then
          Result := Result + 'BIGSERIAL PRIMARY KEY'
        else
          Result := Result + 'SERIAL PRIMARY KEY';
      end
      else
      begin
        if ACol.UseBigInt then
          Result := Result + 'BIGINT PRIMARY KEY NOT NULL'
        else
          Result := Result + 'INTEGER PRIMARY KEY NOT NULL';
      end;
    end;
    Exit;
  end;

  // [IA] Mapeamento do tipo físico de acordo com o dialeto
  case ACol.Kind of
    ckVarchar:
      if ACol.Size > 0 then
        LTypeStr := 'VARCHAR(' + IntToStr(ACol.Size) + ')'
      else
        LTypeStr := 'TEXT';
    ckText:
      LTypeStr := 'TEXT';
    ckInteger:
      LTypeStr := 'INTEGER';
    ckBigInt:
      LTypeStr := 'BIGINT';
    ckSmallInt:
      LTypeStr := 'SMALLINT';
    ckFloat:
      if FDialect = sdSQLite then
        LTypeStr := 'REAL'
      else
        LTypeStr := 'DOUBLE PRECISION';
    ckNumeric:
      LTypeStr := 'NUMERIC(' + IntToStr(ACol.Precision) + ', ' + IntToStr(ACol.Scale) + ')';
    ckBoolean:
      if FDialect = sdSQLite then
        LTypeStr := 'INTEGER'
      else
        LTypeStr := 'BOOLEAN';
    ckDate:
      LTypeStr := 'DATE';
    ckTime:
      LTypeStr := 'TIME';
    ckDateTime:
      if FDialect = sdSQLite then
        LTypeStr := 'DATETIME'
      else
        LTypeStr := 'TIMESTAMP';
    ckBlob:
      if FDialect = sdSQLite then
        LTypeStr := 'BLOB'
      else
        LTypeStr := 'BYTEA';
    ckCustom:
      LTypeStr := ACol.CustomType;
  else
    LTypeStr := 'TEXT';
  end;

  Result := Result + LTypeStr;

  if ACol.NotNull then
    Result := Result + ' NOT NULL';

  if ACol.Unique then
    Result := Result + ' UNIQUE';

  if ACol.HasDefault then
  begin
    if ACol.Kind = ckBoolean then
    begin
      if FDialect = sdSQLite then
      begin
        if ACol.DefaultBool then
          Result := Result + ' DEFAULT 1'
        else
          Result := Result + ' DEFAULT 0';
      end
      else
      begin
        if ACol.DefaultBool then
          Result := Result + ' DEFAULT TRUE'
        else
          Result := Result + ' DEFAULT FALSE';
      end;
    end
    else if ACol.DefaultExpr <> '' then
      Result := Result + ' DEFAULT ' + ACol.DefaultExpr;
  end;
end;

function TSQLCreateTableBuilder.FormatForeignKeyAction(AAction: TSQLForeignKeyAction): string;
begin
  case AAction of
    fkRestrict:   Result := 'RESTRICT';
    fkCascade:    Result := 'CASCADE';
    fkSetNull:    Result := 'SET NULL';
    fkSetDefault: Result := 'SET DEFAULT';
  else
    Result := 'NO ACTION';
  end;
end;

function TSQLCreateTableBuilder.FormatForeignKeyDef(const AFK: TSQLForeignKeyDef): string;
begin
  Result := 'FOREIGN KEY (' + QuoteIdentifier(AFK.FieldName) + ') REFERENCES ' +
            QuoteIdentifier(AFK.RefTable) + ' (' + QuoteIdentifier(AFK.RefField) + ')';

  if AFK.OnDelete <> fkNoAction then
    Result := Result + ' ON DELETE ' + FormatForeignKeyAction(AFK.OnDelete);

  if AFK.OnUpdate <> fkNoAction then
    Result := Result + ' ON UPDATE ' + FormatForeignKeyAction(AFK.OnUpdate);
end;

function TSQLCreateTableBuilder.Dialect(ADialect: TSQLDialect): ISQLCreateTableBuilder;
begin
  FDialect := ADialect;
  Result := Self;
end;

function TSQLCreateTableBuilder.Dialect(const ADialectName: string): ISQLCreateTableBuilder;
begin
  FDialect := StringToSQLDialect(ADialectName);
  Result := Self;
end;

function TSQLCreateTableBuilder.Table(const ATableName: string): ISQLCreateTableBuilder;
begin
  FTableName := Trim(ATableName);
  FSchemaName := '';
  Result := Self;
end;

function TSQLCreateTableBuilder.TableSchema(const ASchemaName, ATableName: string): ISQLCreateTableBuilder;
begin
  FSchemaName := Trim(ASchemaName);
  FTableName := Trim(ATableName);
  Result := Self;
end;

function TSQLCreateTableBuilder.IfNotExists(AValue: Boolean): ISQLCreateTableBuilder;
begin
  FIfNotExists := AValue;
  Result := Self;
end;

function TSQLCreateTableBuilder.AddPrimaryKey(const AFieldName: string; AAutoIncrement: Boolean; AUseBigInt: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckPrimaryKey;
  Col.AutoIncrement := AAutoIncrement;
  Col.UseBigInt := AUseBigInt;
  Col.NotNull := True;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddVarchar(const AFieldName: string; ASize: Integer; ANotNull: Boolean; const ADefault: string; AUnique: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckVarchar;
  Col.Size := ASize;
  Col.NotNull := ANotNull;
  Col.Unique := AUnique;
  if ADefault <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := QuotedStr(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddText(const AFieldName: string; ANotNull: Boolean; const ADefault: string): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckText;
  Col.NotNull := ANotNull;
  if ADefault <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := QuotedStr(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddInteger(const AFieldName: string; ANotNull: Boolean; const ADefault: string; AUnique: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckInteger;
  Col.NotNull := ANotNull;
  Col.Unique := AUnique;
  if Trim(ADefault) <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := Trim(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddBigInt(const AFieldName: string; ANotNull: Boolean; const ADefault: string; AUnique: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckBigInt;
  Col.NotNull := ANotNull;
  Col.Unique := AUnique;
  if Trim(ADefault) <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := Trim(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddSmallInt(const AFieldName: string; ANotNull: Boolean; const ADefault: string): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckSmallInt;
  Col.NotNull := ANotNull;
  if Trim(ADefault) <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := Trim(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddFloat(const AFieldName: string; ANotNull: Boolean; const ADefault: string): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckFloat;
  Col.NotNull := ANotNull;
  if Trim(ADefault) <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := Trim(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddNumeric(const AFieldName: string; APrecision: Integer; AScale: Integer; ANotNull: Boolean; const ADefault: string): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckNumeric;
  Col.Precision := APrecision;
  Col.Scale := AScale;
  Col.NotNull := ANotNull;
  if Trim(ADefault) <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := Trim(ADefault);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddCurrency(const AFieldName: string; ANotNull: Boolean; ADefaultZero: Boolean): ISQLCreateTableBuilder;
begin
  if ADefaultZero then
    Result := AddNumeric(AFieldName, 15, 2, ANotNull, '0.00')
  else
    Result := AddNumeric(AFieldName, 15, 2, ANotNull, '');
end;

function TSQLCreateTableBuilder.AddBoolean(const AFieldName: string; ANotNull: Boolean; AHasDefault: Boolean; ADefaultValue: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckBoolean;
  Col.NotNull := ANotNull;
  Col.HasDefault := AHasDefault;
  Col.DefaultBool := ADefaultValue;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddDate(const AFieldName: string; ANotNull: Boolean; ADefaultNow: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckDate;
  Col.NotNull := ANotNull;
  if ADefaultNow then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := 'CURRENT_DATE';
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddTime(const AFieldName: string; ANotNull: Boolean; ADefaultNow: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckTime;
  Col.NotNull := ANotNull;
  if ADefaultNow then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := 'CURRENT_TIME';
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddDateTime(const AFieldName: string; ANotNull: Boolean; ADefaultNow: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckDateTime;
  Col.NotNull := ANotNull;
  if ADefaultNow then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := 'CURRENT_TIMESTAMP';
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddBlob(const AFieldName: string; ANotNull: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckBlob;
  Col.NotNull := ANotNull;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddCustomColumn(const AFieldName, ATypeDefinition: string; ANotNull: Boolean; const ADefaultExpr: string; AUnique: Boolean): ISQLCreateTableBuilder;
var
  Col: TSQLColumnDef;
begin
  Col := Default(TSQLColumnDef);
  Col.Name := Trim(AFieldName);
  Col.Kind := ckCustom;
  Col.CustomType := Trim(ATypeDefinition);
  Col.NotNull := ANotNull;
  Col.Unique := AUnique;
  if Trim(ADefaultExpr) <> '' then
  begin
    Col.HasDefault := True;
    Col.DefaultExpr := Trim(ADefaultExpr);
  end;
  InternalAddColumn(Col);
  Result := Self;
end;

function TSQLCreateTableBuilder.AddForeignKey(const AFieldName, ARefTable, ARefField: string; AOnDelete: TSQLForeignKeyAction; AOnUpdate: TSQLForeignKeyAction): ISQLCreateTableBuilder;
var
  FK: TSQLForeignKeyDef;
begin
  FK := Default(TSQLForeignKeyDef);
  FK.FieldName := Trim(AFieldName);
  FK.RefTable := Trim(ARefTable);
  FK.RefField := Trim(ARefField);
  FK.OnDelete := AOnDelete;
  FK.OnUpdate := AOnUpdate;

  Inc(FForeignKeyCount);
  if FForeignKeyCount > Length(FForeignKeys) then
    SetLength(FForeignKeys, FForeignKeyCount + 4);
  FForeignKeys[FForeignKeyCount - 1] := FK;

  Result := Self;
end;

function TSQLCreateTableBuilder.AddUniqueConstraint(const AConstraintName: string; const AFields: array of string): ISQLCreateTableBuilder;
var
  I: Integer;
  LFieldList, LPrefix: string;
begin
  if Length(AFields) = 0 then
    Exit(Self);

  LFieldList := '';
  for I := Low(AFields) to High(AFields) do
  begin
    if I > Low(AFields) then
      LFieldList := LFieldList + ', ';
    LFieldList := LFieldList + QuoteIdentifier(Trim(AFields[I]));
  end;

  if Trim(AConstraintName) <> '' then
    LPrefix := 'CONSTRAINT ' + QuoteIdentifier(Trim(AConstraintName)) + ' '
  else
    LPrefix := '';

  FTableConstraints.Add(LPrefix + 'UNIQUE (' + LFieldList + ')');
  Result := Self;
end;

function TSQLCreateTableBuilder.AddCheckConstraint(const AConstraintName, ACondition: string): ISQLCreateTableBuilder;
var
  LPrefix: string;
begin
  if Trim(ACondition) = '' then
    Exit(Self);

  if Trim(AConstraintName) <> '' then
    LPrefix := 'CONSTRAINT ' + QuoteIdentifier(Trim(AConstraintName)) + ' '
  else
    LPrefix := '';

  FTableConstraints.Add(LPrefix + 'CHECK (' + ACondition + ')');
  Result := Self;
end;

function TSQLCreateTableBuilder.Build: string;
var
  I: Integer;
  LParts: TStringList;
  LHeader: string;
begin
  if FTableName = '' then
    raise Exception.Create('TSQLCreateTableBuilder: nome da tabela não definido. Utilize o método Table().');

  if FColumnCount = 0 then
    raise Exception.CreateFmt('TSQLCreateTableBuilder: nenhuma coluna foi adicionada para a tabela "%s".', [FTableName]);

  LHeader := 'CREATE TABLE ';
  if FIfNotExists then
    LHeader := LHeader + 'IF NOT EXISTS ';
  LHeader := LHeader + BuildFullTableName + ' (';

  LParts := TStringList.Create;
  try
    for I := 0 to FColumnCount - 1 do
      LParts.Add(FormatColumnDef(FColumns[I]));

    for I := 0 to FForeignKeyCount - 1 do
      LParts.Add(FormatForeignKeyDef(FForeignKeys[I]));

    for I := 0 to FTableConstraints.Count - 1 do
      LParts.Add(FTableConstraints[I]);

    Result := LHeader;
    for I := 0 to LParts.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ', ';
      Result := Result + LParts[I];
    end;
    Result := Result + ')';
  finally
    LParts.Free;
  end;
end;

function TSQLCreateTableBuilder.BuildCheckTableExists: string;
var
  LSchema: string;
begin
  if FTableName = '' then
    raise Exception.Create('TSQLCreateTableBuilder: nome da tabela não definido. Utilize o método Table().');

  // [IA] Gera SELECT de verificação no catálogo nativo de cada banco (sqlite_master vs information_schema.tables)
  if FDialect = sdSQLite then
  begin
    Result := 'SELECT COUNT(*) FROM sqlite_master WHERE type = ' + QuotedStr('table') +
              ' AND lower(name) = ' + QuotedStr(LowerCase(FTableName));
  end
  else
  begin
    if FSchemaName <> '' then
      LSchema := LowerCase(FSchemaName)
    else
      LSchema := 'public';

    Result := 'SELECT COUNT(*) FROM information_schema.tables WHERE lower(table_schema) = ' +
              QuotedStr(LSchema) + ' AND lower(table_name) = ' + QuotedStr(LowerCase(FTableName));
  end;
end;

function TSQLCreateTableBuilder.BuildCreateIndex(const AIndexName: string; const AFields: array of string; AUnique: Boolean; AIfNotExists: Boolean): string;
var
  I: Integer;
  LFieldList: string;
begin
  if FTableName = '' then
    raise Exception.Create('TSQLCreateTableBuilder: nome da tabela não definido. Utilize o método Table().');
  if Trim(AIndexName) = '' then
    raise Exception.Create('TSQLCreateTableBuilder: nome do índice não pode ser vazio.');
  if Length(AFields) = 0 then
    raise Exception.Create('TSQLCreateTableBuilder: informe ao menos um campo para o índice.');

  LFieldList := '';
  for I := Low(AFields) to High(AFields) do
  begin
    if I > Low(AFields) then
      LFieldList := LFieldList + ', ';
    LFieldList := LFieldList + QuoteIdentifier(Trim(AFields[I]));
  end;

  Result := 'CREATE ';
  if AUnique then
    Result := Result + 'UNIQUE ';
  Result := Result + 'INDEX ';
  if AIfNotExists then
    Result := Result + 'IF NOT EXISTS ';
  Result := Result + QuoteIdentifier(Trim(AIndexName)) + ' ON ' + BuildFullTableName + ' (' + LFieldList + ')';
end;

function TSQLCreateTableBuilder.Clear: ISQLCreateTableBuilder;
begin
  FTableName := '';
  FSchemaName := '';
  FIfNotExists := True;
  SetLength(FColumns, 0);
  FColumnCount := 0;
  SetLength(FForeignKeys, 0);
  FForeignKeyCount := 0;
  FTableConstraints.Clear;
  Result := Self;
end;

function TSQLCreateTableBuilder.GetDialect: TSQLDialect;
begin
  Result := FDialect;
end;

procedure TSQLCreateTableBuilder.SetDialect(AValue: TSQLDialect);
begin
  FDialect := AValue;
end;

function TSQLCreateTableBuilder.GetTableName: string;
begin
  Result := FTableName;
end;

function TSQLCreateTableBuilder.GetSchemaName: string;
begin
  Result := FSchemaName;
end;

function TSQLCreateTableBuilder.GetIfNotExists: Boolean;
begin
  Result := FIfNotExists;
end;

function TSQLCreateTableBuilder.GetColumnCount: Integer;
begin
  Result := FColumnCount;
end;

initialization
  TSQLSelectBuilder.DefaultDialect := sdPostgreSQL;

end.
