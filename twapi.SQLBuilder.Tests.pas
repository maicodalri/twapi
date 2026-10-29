{*******************************************************************************

  twapi.SQLBuilder.Tests - Testes automatizados para twapi.SQLBuilder

  Descrição:
    Suite completa de testes unitários para o gerador de SQL SELECT (PostgreSQL
    e SQLite). Utiliza o framework FPCUnit (fpcunit / testregistry) nativo do
    Free Pascal / Lazarus.

  Cobertura de Testes:
    1. TTestSQLBuilderDialect:
       - Conversão de string para dialeto (PostgreSQL, SQLite, variações e fallback)
       - Conversão de dialeto para string
       - Configuração global do dialeto padrão (DefaultDialect)
       - Seleção de dialeto por instância (Construtor, Factory, Método fluente, Propriedade)
       - Factory SQLSelectFrom

    2. TTestSQLBuilderFieldsAndFrom:
       - Seleção padrão (*) e AllFields
       - Seleção de campos por array e por string CSV (com remoção de espaços)
       - DISTINCT com todos os campos e com campos específicos
       - Cláusula FROM simples
       - Schemas no PostgreSQL (public e customizados mantidos)
       - Schemas no SQLite (public omitido automaticamente, customizados mantidos)
       - Quote de identificadores (com espaços, com traços, já cotados e normais)
       - Validação de tabela obrigatória (exceção em Build e BuildCount)

    3. TTestSQLBuilderPostgreSQL:
       - Condições WHERE livres e operadores AND/OR
       - Helpers literais: Equal, NotEqual, GreaterThan, LessThan, GreaterOrEqual, LessOrEqual
       - Helpers booleanos (TRUE / FALSE)
       - Helpers de data e data/hora (ISO e formato personalizado)
       - Operador LIKE e ILIKE nativo do PostgreSQL
       - Operadores IN e NOT IN (com listas preenchidas e vazias)
       - Operadores IS NULL e IS NOT NULL
       - Operador BETWEEN (strings, inteiros e datas)
       - Parâmetros nomeados (:param), incluindo WhereILikeParam nativo
       - Cláusula ORDER BY (ASC, DESC e múltiplas colunas)
       - Paginação: LIMIT, LIMIT+OFFSET e OFFSET isolado (suportado no PG)
       - Geração de Build e BuildCount

    4. TTestSQLBuilderSQLite:
       - Condições WHERE livres e operadores AND/OR
       - Helpers literais com sintaxe SQLite
       - Helpers booleanos traduzidos para 1 e 0
       - Operador ILIKE traduzido para LIKE ... COLLATE NOCASE (evitando erro de sintaxe)
       - Parâmetros nomeados, incluindo WhereILikeParam traduzido para COLLATE NOCASE
       - Paginação no SQLite: OFFSET isolado gera automaticamente LIMIT -1 OFFSET n
       - Cláusula ORDER BY e BuildCount no SQLite
       - Tratamento de schemas no SQLite

    5. TTestSQLBuilderParamsAndLifecycle:
       - Armazenamento de parâmetros de todos os tipos tipados
       - Atualização de parâmetros existentes (case-insensitive)
       - Método ApplyParams integrado a TParams (criação, tipos de dados e valores)
       - Método Clear (limpeza completa de cláusulas e preservação do dialeto)
       - Inspeção de todas as propriedades públicas

*******************************************************************************}

unit twapi.SQLBuilder.Tests;

{$mode objfpc}{$H+}
{$interfaces com}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry, DB, twapi.SQLBuilder;

type
  { ========================================================================== }
  { TTestSQLBuilderDialect                                                     }
  { ========================================================================== }
  TTestSQLBuilderDialect = class(TTestCase)
  private
    FOriginalDefaultDialect: TSQLDialect;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStringToSQLDialect_PostgreSQL;
    procedure TestStringToSQLDialect_SQLite;
    procedure TestStringToSQLDialect_CaseInsensitive;
    procedure TestStringToSQLDialect_UnknownFallback;
    procedure TestSQLDialectToString;
    procedure TestGlobalDefaultDialect;
    procedure TestGetSetDefaultSQLDialect;
    procedure TestInstanceDialect_Constructor;
    procedure TestInstanceDialect_ConstructorString;
    procedure TestInstanceDialect_Factory;
    procedure TestInstanceDialect_FactoryString;
    procedure TestInstanceDialect_FluentMethod;
    procedure TestInstanceDialect_FluentMethodString;
    procedure TestInstanceDialect_Property;
    procedure TestSQLSelectFrom_WithDialect;
  end;

  { ========================================================================== }
  { TTestSQLBuilderFieldsAndFrom                                               }
  { ========================================================================== }
  TTestSQLBuilderFieldsAndFrom = class(TTestCase)
  published
    procedure TestDefaultAllFields;
    procedure TestAllFieldsExplicit;
    procedure TestFieldsArray;
    procedure TestFieldsCSV;
    procedure TestDistinctAll;
    procedure TestDistinctFields;
    procedure TestFromSimple;
    procedure TestFromSchema_PostgreSQL_Public;
    procedure TestFromSchema_PostgreSQL_Custom;
    procedure TestFromSchema_SQLite_PublicOmitted;
    procedure TestFromSchema_SQLite_PublicCaseInsensitive;
    procedure TestFromSchema_SQLite_CustomPreserved;
    procedure TestQuoteIdentifier_WithSpaces;
    procedure TestQuoteIdentifier_WithDashes;
    procedure TestQuoteIdentifier_AlreadyQuoted;
    procedure TestQuoteIdentifier_Standard;
    procedure TestBuildWithoutFrom_RaisesException;
    procedure TestBuildCountWithoutFrom_RaisesException;
  end;

  { ========================================================================== }
  { TTestSQLBuilderPostgreSQL                                                  }
  { ========================================================================== }
  TTestSQLBuilderPostgreSQL = class(TTestCase)
  private
    function CreateBuilder: ISQLSelectBuilder;
  published
    { Cláusulas WHERE livres }
    procedure TestWhereSingle;
    procedure TestWhereMultiple_ImplicitAnd;
    procedure TestWhereAnd_Explicit;
    procedure TestWhereOr_Explicit;
    procedure TestWhereMixedAndOr;

    { Helpers WHERE com literais }
    procedure TestWhereEqual_String;
    procedure TestWhereEqual_Integer;
    procedure TestWhereEqual_Boolean_True;
    procedure TestWhereEqual_Boolean_False;
    procedure TestWhereEqual_Date;
    procedure TestWhereEqual_DateTime;
    procedure TestWhereEqual_DateTimeCustomFormat;
    procedure TestWhereNotEqual_String;
    procedure TestWhereNotEqual_Integer;
    procedure TestWhereNotEqual_Boolean;
    procedure TestWhereGreaterThan_String;
    procedure TestWhereGreaterThan_Integer;
    procedure TestWhereGreaterThan_Double;
    procedure TestWhereLessThan_String;
    procedure TestWhereLessThan_Integer;
    procedure TestWhereLessThan_Double;
    procedure TestWhereGreaterOrEqual_String;
    procedure TestWhereGreaterOrEqual_Integer;
    procedure TestWhereGreaterOrEqual_Double;
    procedure TestWhereLessOrEqual_String;
    procedure TestWhereLessOrEqual_Integer;
    procedure TestWhereLessOrEqual_Double;
    procedure TestWhereLike;
    procedure TestWhereILike;
    procedure TestWhereIn_String_Populated;
    procedure TestWhereIn_String_Empty;
    procedure TestWhereInInt_Populated;
    procedure TestWhereInInt_Empty;
    procedure TestWhereNotIn_String_Populated;
    procedure TestWhereNotIn_String_Empty;
    procedure TestWhereNotInInt_Populated;
    procedure TestWhereNotInInt_Empty;
    procedure TestWhereIsNull;
    procedure TestWhereIsNotNull;
    procedure TestWhereBetween_String;
    procedure TestWhereBetweenInt;
    procedure TestWhereBetweenDate_DateOnly;
    procedure TestWhereBetweenDate_DateTime;

    { WHERE com parâmetros nomeados (:param) }
    procedure TestWhereParam;
    procedure TestWhereAndParam;
    procedure TestWhereOrParam;
    procedure TestWhereEqualParam;
    procedure TestWhereNotEqualParam;
    procedure TestWhereLikeParam;
    procedure TestWhereILikeParam;
    procedure TestWhereBetweenParam;

    { ORDER BY }
    procedure TestOrderBy_Asc;
    procedure TestOrderBy_Desc;
    procedure TestOrderByDesc;
    procedure TestOrderBy_Multiple;

    { Paginação }
    procedure TestPagination_LimitOnly;
    procedure TestPagination_LimitAndOffset;
    procedure TestPagination_OffsetOnly;

    { Build e BuildCount }
    procedure TestBuild_CompleteQuery;
    procedure TestBuildCount_PreservesFromAndWhere;
    procedure TestBuildCount_IgnoresOrderByAndLimitOffset;
  end;

  { ========================================================================== }
  { TTestSQLBuilderSQLite                                                      }
  { ========================================================================== }
  TTestSQLBuilderSQLite = class(TTestCase)
  private
    function CreateBuilder: ISQLSelectBuilder;
  published
    { Cláusulas WHERE livres }
    procedure TestWhereSingle;
    procedure TestWhereMultiple_ImplicitAnd;
    procedure TestWhereAnd_Explicit;
    procedure TestWhereOr_Explicit;

    { Helpers WHERE com literais e especificidades SQLite }
    procedure TestWhereEqual_String;
    procedure TestWhereEqual_Integer;
    procedure TestWhereEqual_Boolean_True;
    procedure TestWhereEqual_Boolean_False;
    procedure TestWhereEqual_Date;
    procedure TestWhereEqual_DateTime;
    procedure TestWhereNotEqual_String;
    procedure TestWhereNotEqual_Integer;
    procedure TestWhereNotEqual_Boolean;
    procedure TestWhereGreaterThan_Double;
    procedure TestWhereLessThan_Double;
    procedure TestWhereGreaterOrEqual_Double;
    procedure TestWhereLessOrEqual_Double;
    procedure TestWhereLike;
    procedure TestWhereILike_GeneratesCollateNoCase;
    procedure TestWhereIn_String_Populated;
    procedure TestWhereIn_String_Empty;
    procedure TestWhereInInt_Populated;
    procedure TestWhereInInt_Empty;
    procedure TestWhereNotIn_String_Populated;
    procedure TestWhereNotIn_String_Empty;
    procedure TestWhereNotInInt_Populated;
    procedure TestWhereNotInInt_Empty;
    procedure TestWhereIsNull;
    procedure TestWhereIsNotNull;
    procedure TestWhereBetween_String;
    procedure TestWhereBetweenInt;
    procedure TestWhereBetweenDate;

    { WHERE com parâmetros nomeados (:param) e especificidades SQLite }
    procedure TestWhereEqualParam;
    procedure TestWhereNotEqualParam;
    procedure TestWhereLikeParam;
    procedure TestWhereILikeParam_GeneratesCollateNoCase;
    procedure TestWhereBetweenParam;

    { Paginação no SQLite (especificidade LIMIT -1) }
    procedure TestPagination_LimitOnly;
    procedure TestPagination_LimitAndOffset;
    procedure TestPagination_OffsetOnly_GeneratesLimitMinusOne;

    { ORDER BY }
    procedure TestOrderBy_AscAndDesc;

    { Build e BuildCount }
    procedure TestBuild_CompleteQuery;
    procedure TestBuildCount;
  end;

  { ========================================================================== }
  { TTestSQLBuilderParamsAndLifecycle                                          }
  { ========================================================================== }
  TTestSQLBuilderParamsAndLifecycle = class(TTestCase)
  published
    procedure TestParamSetting_AllTypes;
    procedure TestParamUpdating_CaseInsensitive;
    procedure TestApplyParams_CreatesNewParams;
    procedure TestApplyParams_UpdatesExistingParams;
    procedure TestApplyParams_DataTypesVerification;
    procedure TestClear_ResetsAllClauses;
    procedure TestClear_RetainsDialect;
    procedure TestPropertyInspection;
  end;

implementation

{ ============================================================================ }
{ TTestSQLBuilderDialect                                                       }
{ ============================================================================ }

procedure TTestSQLBuilderDialect.SetUp;
begin
  inherited SetUp;
  FOriginalDefaultDialect := TSQLSelectBuilder.DefaultDialect;
end;

procedure TTestSQLBuilderDialect.TearDown;
begin
  TSQLSelectBuilder.DefaultDialect := FOriginalDefaultDialect;
  inherited TearDown;
end;

procedure TTestSQLBuilderDialect.TestStringToSQLDialect_PostgreSQL;
begin
  AssertEquals('postgresql', Ord(sdPostgreSQL), Ord(StringToSQLDialect('postgresql')));
  AssertEquals('postgres', Ord(sdPostgreSQL), Ord(StringToSQLDialect('postgres')));
  AssertEquals('pgsql', Ord(sdPostgreSQL), Ord(StringToSQLDialect('pgsql')));
  AssertEquals('pg', Ord(sdPostgreSQL), Ord(StringToSQLDialect('pg')));
  AssertEquals('postgre', Ord(sdPostgreSQL), Ord(StringToSQLDialect('postgre')));
end;

procedure TTestSQLBuilderDialect.TestStringToSQLDialect_SQLite;
begin
  AssertEquals('sqlite', Ord(sdSQLite), Ord(StringToSQLDialect('sqlite')));
  AssertEquals('sqlite-3', Ord(sdSQLite), Ord(StringToSQLDialect('sqlite-3')));
  AssertEquals('sqlite3', Ord(sdSQLite), Ord(StringToSQLDialect('sqlite3')));
  AssertEquals('sqlite_3', Ord(sdSQLite), Ord(StringToSQLDialect('sqlite_3')));
end;

procedure TTestSQLBuilderDialect.TestStringToSQLDialect_CaseInsensitive;
begin
  AssertEquals('SQLITE', Ord(sdSQLite), Ord(StringToSQLDialect('SQLITE')));
  AssertEquals('PostgreSQL', Ord(sdPostgreSQL), Ord(StringToSQLDialect('PostgreSQL')));
  AssertEquals('SQLite-3', Ord(sdSQLite), Ord(StringToSQLDialect('SQLite-3')));
end;

procedure TTestSQLBuilderDialect.TestStringToSQLDialect_UnknownFallback;
begin
  TSQLSelectBuilder.DefaultDialect := sdPostgreSQL;
  AssertEquals('desconhecido deve retornar default (PG)', Ord(sdPostgreSQL), Ord(StringToSQLDialect('oracle')));

  TSQLSelectBuilder.DefaultDialect := sdSQLite;
  AssertEquals('desconhecido deve retornar default (SQLite)', Ord(sdSQLite), Ord(StringToSQLDialect('mysql')));
end;

procedure TTestSQLBuilderDialect.TestSQLDialectToString;
begin
  AssertEquals('PostgreSQL string', 'PostgreSQL', SQLDialectToString(sdPostgreSQL));
  AssertEquals('SQLite string', 'SQLite', SQLDialectToString(sdSQLite));
end;

procedure TTestSQLBuilderDialect.TestGlobalDefaultDialect;
var
  SQL: string;
begin
  TSQLSelectBuilder.DefaultDialect := sdSQLite;
  SQL := SQLSelect.From('teste').Offset(5).Build;
  AssertEquals('Default global SQLite deve gerar LIMIT -1', 'SELECT * FROM teste LIMIT -1 OFFSET 5', SQL);

  TSQLSelectBuilder.DefaultDialect := sdPostgreSQL;
  SQL := SQLSelect.From('teste').Offset(5).Build;
  AssertEquals('Default global PG deve gerar OFFSET 5', 'SELECT * FROM teste OFFSET 5', SQL);
end;

procedure TTestSQLBuilderDialect.TestGetSetDefaultSQLDialect;
begin
  SetDefaultSQLDialect(sdSQLite);
  AssertEquals('GetDefaultSQLDialect SQLite', Ord(sdSQLite), Ord(GetDefaultSQLDialect));
  SetDefaultSQLDialect(sdPostgreSQL);
  AssertEquals('GetDefaultSQLDialect PG', Ord(sdPostgreSQL), Ord(GetDefaultSQLDialect));
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_Constructor;
var
  Builder: TSQLSelectBuilder;
begin
  Builder := TSQLSelectBuilder.Create(sdSQLite);
  try
    AssertEquals('Construtor com enum', Ord(sdSQLite), Ord(Builder.SQLDialect));
  finally
    Builder.Free;
  end;
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_ConstructorString;
var
  Builder: TSQLSelectBuilder;
begin
  Builder := TSQLSelectBuilder.Create('sqlite');
  try
    AssertEquals('Construtor com string', Ord(sdSQLite), Ord(Builder.SQLDialect));
  finally
    Builder.Free;
  end;
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_Factory;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect(sdSQLite);
  AssertEquals('Factory com enum', Ord(sdSQLite), Ord(Builder.SQLDialect));

  Builder := SQLSelect(sdPostgreSQL);
  AssertEquals('Factory com enum PG', Ord(sdPostgreSQL), Ord(Builder.SQLDialect));
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_FactoryString;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect('sqlite');
  AssertEquals('Factory com string', Ord(sdSQLite), Ord(Builder.SQLDialect));
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_FluentMethod;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect.Dialect(sdSQLite);
  AssertEquals('Metodo fluente com enum', Ord(sdSQLite), Ord(Builder.SQLDialect));
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_FluentMethodString;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect.Dialect('sqlite');
  AssertEquals('Metodo fluente com string', Ord(sdSQLite), Ord(Builder.SQLDialect));
end;

procedure TTestSQLBuilderDialect.TestInstanceDialect_Property;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect;
  Builder.SQLDialect := sdSQLite;
  AssertEquals('Propriedade escrita', Ord(sdSQLite), Ord(Builder.SQLDialect));
end;

procedure TTestSQLBuilderDialect.TestSQLSelectFrom_WithDialect;
var
  SQL: string;
begin
  SQL := SQLSelectFrom('clientes', sdSQLite).Offset(10).Build;
  AssertEquals('SQLSelectFrom com enum', 'SELECT * FROM clientes LIMIT -1 OFFSET 10', SQL);

  SQL := SQLSelectFrom('clientes', 'sqlite').Offset(10).Build;
  AssertEquals('SQLSelectFrom com string', 'SELECT * FROM clientes LIMIT -1 OFFSET 10', SQL);
end;

{ ============================================================================ }
{ TTestSQLBuilderFieldsAndFrom                                                 }
{ ============================================================================ }

procedure TTestSQLBuilderFieldsAndFrom.TestDefaultAllFields;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).From('usuarios').Build;
  AssertEquals('Default *', 'SELECT * FROM usuarios', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestAllFieldsExplicit;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Fields(['id', 'nome'])
    .AllFields
    .From('usuarios')
    .Build;
  AssertEquals('AllFields reseta campos', 'SELECT * FROM usuarios', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFieldsArray;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Fields(['id', 'nome', 'email'])
    .From('usuarios')
    .Build;
  AssertEquals('Fields array', 'SELECT id, nome, email FROM usuarios', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFieldsCSV;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Fields(' id , nome , email ')
    .From('usuarios')
    .Build;
  AssertEquals('Fields CSV com trim', 'SELECT id, nome, email FROM usuarios', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestDistinctAll;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Distinct
    .From('cidades')
    .Build;
  AssertEquals('Distinct all', 'SELECT DISTINCT * FROM cidades', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestDistinctFields;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Distinct
    .Fields(['uf', 'cidade'])
    .From('enderecos')
    .Build;
  AssertEquals('Distinct fields', 'SELECT DISTINCT uf, cidade FROM enderecos', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFromSimple;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).From('produtos').Build;
  AssertEquals('From simples', 'SELECT * FROM produtos', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFromSchema_PostgreSQL_Public;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).FromSchema('public', 'clientes').Build;
  AssertEquals('PG Schema public mantido', 'SELECT * FROM public.clientes', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFromSchema_PostgreSQL_Custom;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).FromSchema('vendas', 'pedidos').Build;
  AssertEquals('PG Schema custom mantido', 'SELECT * FROM vendas.pedidos', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFromSchema_SQLite_PublicOmitted;
var
  SQL: string;
begin
  SQL := SQLSelect(sdSQLite).FromSchema('public', 'clientes').Build;
  AssertEquals('SQLite Schema public omitido', 'SELECT * FROM clientes', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFromSchema_SQLite_PublicCaseInsensitive;
var
  SQL: string;
begin
  SQL := SQLSelect(sdSQLite).FromSchema('PUBLIC', 'clientes').Build;
  AssertEquals('SQLite Schema PUBLIC case-insensitive omitido', 'SELECT * FROM clientes', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestFromSchema_SQLite_CustomPreserved;
var
  SQL: string;
begin
  SQL := SQLSelect(sdSQLite).FromSchema('attached_db', 'clientes').Build;
  AssertEquals('SQLite Schema anexado mantido', 'SELECT * FROM attached_db.clientes', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestQuoteIdentifier_WithSpaces;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).From('tabela com espacos').Build;
  AssertEquals('Quote com espacos', 'SELECT * FROM "tabela com espacos"', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestQuoteIdentifier_WithDashes;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).From('minha-tabela').Build;
  AssertEquals('Quote com tracos', 'SELECT * FROM "minha-tabela"', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestQuoteIdentifier_AlreadyQuoted;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).From('"ja_cotado"').Build;
  AssertEquals('Quote nao duplica', 'SELECT * FROM "ja_cotado"', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestQuoteIdentifier_Standard;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL).From('tabela_normal').Build;
  AssertEquals('Nome padrao sem aspas desnecessarias', 'SELECT * FROM tabela_normal', SQL);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestBuildWithoutFrom_RaisesException;
var
  Passou: Boolean;
begin
  Passou := False;
  try
    SQLSelect(sdPostgreSQL).Fields(['id']).Build;
  except
    on E: Exception do
      Passou := True;
  end;
  AssertTrue('Build sem From deve lancar excecao', Passou);
end;

procedure TTestSQLBuilderFieldsAndFrom.TestBuildCountWithoutFrom_RaisesException;
var
  Passou: Boolean;
begin
  Passou := False;
  try
    SQLSelect(sdPostgreSQL).Fields(['id']).BuildCount;
  except
    on E: Exception do
      Passou := True;
  end;
  AssertTrue('BuildCount sem From deve lancar excecao', Passou);
end;

{ ============================================================================ }
{ TTestSQLBuilderPostgreSQL                                                    }
{ ============================================================================ }

function TTestSQLBuilderPostgreSQL.CreateBuilder: ISQLSelectBuilder;
begin
  Result := SQLSelect(sdPostgreSQL).From('itens');
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereSingle;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('status = 1').Build;
  AssertEquals('Where unico', 'SELECT * FROM itens WHERE (status = 1)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereMultiple_ImplicitAnd;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').Where('b = 2').Build;
  AssertEquals('Where multiplo AND implicito', 'SELECT * FROM itens WHERE (a = 1) AND (b = 2)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereAnd_Explicit;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').WhereAnd('b = 2').Build;
  AssertEquals('WhereAnd explicito', 'SELECT * FROM itens WHERE (a = 1) AND (b = 2)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereOr_Explicit;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').WhereOr('b = 2').Build;
  AssertEquals('WhereOr explicito', 'SELECT * FROM itens WHERE (a = 1) OR (b = 2)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereMixedAndOr;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').WhereAnd('b = 2').WhereOr('c = 3').Build;
  AssertEquals('Where misto AND e OR', 'SELECT * FROM itens WHERE (a = 1) AND (b = 2) OR (c = 3)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('cidade', 'Curitiba').Build;
  AssertEquals('WhereEqual string', 'SELECT * FROM itens WHERE (cidade = ''Curitiba'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('idade', 25).Build;
  AssertEquals('WhereEqual integer', 'SELECT * FROM itens WHERE (idade = 25)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_Boolean_True;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('ativo', True).Build;
  AssertEquals('PG WhereEqual boolean True', 'SELECT * FROM itens WHERE (ativo = TRUE)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_Boolean_False;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('ativo', False).Build;
  AssertEquals('PG WhereEqual boolean False', 'SELECT * FROM itens WHERE (ativo = FALSE)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_Date;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('dt_cadastro', EncodeDate(2026, 10, 15)).Build;
  AssertEquals('PG WhereEqual date', 'SELECT * FROM itens WHERE (dt_cadastro = ''2026-10-15'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_DateTime;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('dt_hora', EncodeDateTime(2026, 10, 15, 14, 30, 0, 0)).Build;
  AssertEquals('PG WhereEqual datetime', 'SELECT * FROM itens WHERE (dt_hora = ''2026-10-15 14:30:00'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqual_DateTimeCustomFormat;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('dt', EncodeDate(2026, 10, 15), 'yyyy/mm/dd').Build;
  AssertEquals('PG WhereEqual formato custom', 'SELECT * FROM itens WHERE (dt = ''2026/10/15'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotEqual_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqual('status', 'cancelado').Build;
  AssertEquals('WhereNotEqual string', 'SELECT * FROM itens WHERE (status <> ''cancelado'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotEqual_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqual('tipo', 9).Build;
  AssertEquals('WhereNotEqual integer', 'SELECT * FROM itens WHERE (tipo <> 9)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotEqual_Boolean;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqual('ativo', True).Build;
  AssertEquals('PG WhereNotEqual boolean', 'SELECT * FROM itens WHERE (ativo <> TRUE)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereGreaterThan_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterThan('cod', '100').Build;
  AssertEquals('WhereGreaterThan string', 'SELECT * FROM itens WHERE (cod > 100)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereGreaterThan_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterThan('idade', 18).Build;
  AssertEquals('WhereGreaterThan integer', 'SELECT * FROM itens WHERE (idade > 18)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereGreaterThan_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterThan('preco', 10.5).Build;
  AssertEquals('WhereGreaterThan double', 'SELECT * FROM itens WHERE (preco > 10.5)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLessThan_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessThan('cod', '500').Build;
  AssertEquals('WhereLessThan string', 'SELECT * FROM itens WHERE (cod < 500)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLessThan_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessThan('estoque', 10).Build;
  AssertEquals('WhereLessThan integer', 'SELECT * FROM itens WHERE (estoque < 10)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLessThan_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessThan('preco', 99.99).Build;
  AssertEquals('WhereLessThan double', 'SELECT * FROM itens WHERE (preco < 99.99)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereGreaterOrEqual_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterOrEqual('nota', '7').Build;
  AssertEquals('WhereGreaterOrEqual string', 'SELECT * FROM itens WHERE (nota >= 7)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereGreaterOrEqual_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterOrEqual('nota', 7).Build;
  AssertEquals('WhereGreaterOrEqual integer', 'SELECT * FROM itens WHERE (nota >= 7)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereGreaterOrEqual_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterOrEqual('nota', 7.5).Build;
  AssertEquals('WhereGreaterOrEqual double', 'SELECT * FROM itens WHERE (nota >= 7.5)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLessOrEqual_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessOrEqual('nota', '10').Build;
  AssertEquals('WhereLessOrEqual string', 'SELECT * FROM itens WHERE (nota <= 10)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLessOrEqual_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessOrEqual('nota', 10).Build;
  AssertEquals('WhereLessOrEqual integer', 'SELECT * FROM itens WHERE (nota <= 10)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLessOrEqual_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessOrEqual('nota', 9.9).Build;
  AssertEquals('WhereLessOrEqual double', 'SELECT * FROM itens WHERE (nota <= 9.9)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLike;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLike('codigo', 'PRD%').Build;
  AssertEquals('WhereLike', 'SELECT * FROM itens WHERE (codigo LIKE ''PRD%'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereILike;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereILike('nome', '%teste%').Build;
  AssertEquals('PG WhereILike nativo', 'SELECT * FROM itens WHERE (nome ILIKE ''%teste%'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereIn_String_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIn('uf', ['PR', 'SC', 'RS']).Build;
  AssertEquals('WhereIn com valores', 'SELECT * FROM itens WHERE (uf IN (''PR'', ''SC'', ''RS''))', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereIn_String_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIn('uf', []).Build;
  AssertEquals('WhereIn vazio gera 1 = 0', 'SELECT * FROM itens WHERE (1 = 0)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereInInt_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereInInt('cod', [1, 2, 3]).Build;
  AssertEquals('WhereInInt com valores', 'SELECT * FROM itens WHERE (cod IN (1, 2, 3))', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereInInt_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereInInt('cod', []).Build;
  AssertEquals('WhereInInt vazio gera 1 = 0', 'SELECT * FROM itens WHERE (1 = 0)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotIn_String_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotIn('uf', ['SP', 'RJ']).Build;
  AssertEquals('WhereNotIn com valores', 'SELECT * FROM itens WHERE (uf NOT IN (''SP'', ''RJ''))', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotIn_String_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotIn('uf', []).Build;
  AssertEquals('WhereNotIn vazio eh ignorado', 'SELECT * FROM itens', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotInInt_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotInInt('cod', [10, 20]).Build;
  AssertEquals('WhereNotInInt com valores', 'SELECT * FROM itens WHERE (cod NOT IN (10, 20))', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotInInt_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotInInt('cod', []).Build;
  AssertEquals('WhereNotInInt vazio eh ignorado', 'SELECT * FROM itens', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereIsNull;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIsNull('observacao').Build;
  AssertEquals('WhereIsNull', 'SELECT * FROM itens WHERE (observacao IS NULL)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereIsNotNull;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIsNotNull('observacao').Build;
  AssertEquals('WhereIsNotNull', 'SELECT * FROM itens WHERE (observacao IS NOT NULL)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereBetween_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetween('letra', 'A', 'Z').Build;
  AssertEquals('WhereBetween string', 'SELECT * FROM itens WHERE (letra BETWEEN ''A'' AND ''Z'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereBetweenInt;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenInt('idade', 18, 65).Build;
  AssertEquals('WhereBetweenInt', 'SELECT * FROM itens WHERE (idade BETWEEN 18 AND 65)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereBetweenDate_DateOnly;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenDate('dt', EncodeDate(2026, 1, 1), EncodeDate(2026, 12, 31)).Build;
  AssertEquals('WhereBetweenDate date only', 'SELECT * FROM itens WHERE (dt BETWEEN ''2026-01-01'' AND ''2026-12-31'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereBetweenDate_DateTime;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenDate('dt',
    EncodeDateTime(2026, 1, 1, 0, 0, 0, 0),
    EncodeDateTime(2026, 12, 31, 23, 59, 59, 0)).Build;
  AssertEquals('WhereBetweenDate datetime', 'SELECT * FROM itens WHERE (dt BETWEEN ''2026-01-01 00:00:00'' AND ''2026-12-31 23:59:59'')', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereParam('idade', '>=', 'pIdadeMin').Build;
  AssertEquals('WhereParam', 'SELECT * FROM itens WHERE (idade >= :pIdadeMin)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereAndParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('ativo = 1').WhereAndParam('idade', '>=', 'pIdadeMin').Build;
  AssertEquals('WhereAndParam', 'SELECT * FROM itens WHERE (ativo = 1) AND (idade >= :pIdadeMin)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereOrParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('ativo = 1').WhereOrParam('idade', '<', 'pIdadeMin').Build;
  AssertEquals('WhereOrParam', 'SELECT * FROM itens WHERE (ativo = 1) OR (idade < :pIdadeMin)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereEqualParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqualParam('cidade', 'pCidade').Build;
  AssertEquals('WhereEqualParam', 'SELECT * FROM itens WHERE (cidade = :pCidade)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereNotEqualParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqualParam('status', 'pStatus').Build;
  AssertEquals('WhereNotEqualParam', 'SELECT * FROM itens WHERE (status <> :pStatus)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereLikeParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLikeParam('nome', 'pNome').Build;
  AssertEquals('WhereLikeParam', 'SELECT * FROM itens WHERE (nome LIKE :pNome)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereILikeParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereILikeParam('nome', 'pNome').Build;
  AssertEquals('PG WhereILikeParam nativo', 'SELECT * FROM itens WHERE (nome ILIKE :pNome)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestWhereBetweenParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenParam('data', 'pIni', 'pFim').Build;
  AssertEquals('WhereBetweenParam', 'SELECT * FROM itens WHERE (data BETWEEN :pIni AND :pFim)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestOrderBy_Asc;
var
  SQL: string;
begin
  SQL := CreateBuilder.OrderBy('nome').Build;
  AssertEquals('OrderBy default ASC', 'SELECT * FROM itens ORDER BY nome ASC', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestOrderBy_Desc;
var
  SQL: string;
begin
  SQL := CreateBuilder.OrderBy('nome', odDesc).Build;
  AssertEquals('OrderBy DESC', 'SELECT * FROM itens ORDER BY nome DESC', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestOrderByDesc;
var
  SQL: string;
begin
  SQL := CreateBuilder.OrderByDesc('nome').Build;
  AssertEquals('OrderByDesc', 'SELECT * FROM itens ORDER BY nome DESC', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestOrderBy_Multiple;
var
  SQL: string;
begin
  SQL := CreateBuilder.OrderBy('nome', odAsc).OrderBy('id', odDesc).Build;
  AssertEquals('OrderBy multiplo', 'SELECT * FROM itens ORDER BY nome ASC, id DESC', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestPagination_LimitOnly;
var
  SQL: string;
begin
  SQL := CreateBuilder.Limit(10).Build;
  AssertEquals('Limit only', 'SELECT * FROM itens LIMIT 10', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestPagination_LimitAndOffset;
var
  SQL: string;
begin
  SQL := CreateBuilder.Limit(10).Offset(20).Build;
  AssertEquals('Limit + Offset', 'SELECT * FROM itens LIMIT 10 OFFSET 20', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestPagination_OffsetOnly;
var
  SQL: string;
begin
  SQL := CreateBuilder.Offset(20).Build;
  AssertEquals('PG Offset isolado suportado', 'SELECT * FROM itens OFFSET 20', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestBuild_CompleteQuery;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Fields(['id', 'nome', 'preco'])
    .From('produtos')
    .WhereEqual('ativo', True)
    .WhereGreaterThan('preco', 0.0)
    .OrderBy('nome', odAsc)
    .Limit(25)
    .Offset(50)
    .Build;
  AssertEquals('PG Query completa',
    'SELECT id, nome, preco FROM produtos WHERE (ativo = TRUE) AND (preco > 0) ORDER BY nome ASC LIMIT 25 OFFSET 50', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestBuildCount_PreservesFromAndWhere;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .From('produtos')
    .WhereEqual('ativo', True)
    .BuildCount;
  AssertEquals('BuildCount preserva FROM e WHERE', 'SELECT COUNT(*) FROM produtos WHERE (ativo = TRUE)', SQL);
end;

procedure TTestSQLBuilderPostgreSQL.TestBuildCount_IgnoresOrderByAndLimitOffset;
var
  SQL: string;
begin
  SQL := SQLSelect(sdPostgreSQL)
    .Fields(['id', 'nome'])
    .From('produtos')
    .WhereEqual('categoria_id', 5)
    .OrderBy('nome')
    .Limit(10)
    .Offset(20)
    .BuildCount;
  AssertEquals('BuildCount ignora OrderBy, Limit e Offset', 'SELECT COUNT(*) FROM produtos WHERE (categoria_id = 5)', SQL);
end;

{ ============================================================================ }
{ TTestSQLBuilderSQLite                                                        }
{ ============================================================================ }

function TTestSQLBuilderSQLite.CreateBuilder: ISQLSelectBuilder;
begin
  Result := SQLSelect(sdSQLite).From('itens');
end;

procedure TTestSQLBuilderSQLite.TestWhereSingle;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('status = 1').Build;
  AssertEquals('SQLite Where unico', 'SELECT * FROM itens WHERE (status = 1)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereMultiple_ImplicitAnd;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').Where('b = 2').Build;
  AssertEquals('SQLite Where multiplo', 'SELECT * FROM itens WHERE (a = 1) AND (b = 2)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereAnd_Explicit;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').WhereAnd('b = 2').Build;
  AssertEquals('SQLite WhereAnd', 'SELECT * FROM itens WHERE (a = 1) AND (b = 2)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereOr_Explicit;
var
  SQL: string;
begin
  SQL := CreateBuilder.Where('a = 1').WhereOr('b = 2').Build;
  AssertEquals('SQLite WhereOr', 'SELECT * FROM itens WHERE (a = 1) OR (b = 2)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqual_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('nome', 'João').Build;
  AssertEquals('SQLite WhereEqual string', 'SELECT * FROM itens WHERE (nome = ''João'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqual_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('idade', 30).Build;
  AssertEquals('SQLite WhereEqual integer', 'SELECT * FROM itens WHERE (idade = 30)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqual_Boolean_True;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('ativo', True).Build;
  AssertEquals('SQLite WhereEqual boolean True gera 1', 'SELECT * FROM itens WHERE (ativo = 1)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqual_Boolean_False;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('ativo', False).Build;
  AssertEquals('SQLite WhereEqual boolean False gera 0', 'SELECT * FROM itens WHERE (ativo = 0)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqual_Date;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('dt', EncodeDate(2026, 10, 15)).Build;
  AssertEquals('SQLite WhereEqual date', 'SELECT * FROM itens WHERE (dt = ''2026-10-15'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqual_DateTime;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqual('dt', EncodeDateTime(2026, 10, 15, 12, 0, 0, 0)).Build;
  AssertEquals('SQLite WhereEqual datetime', 'SELECT * FROM itens WHERE (dt = ''2026-10-15 12:00:00'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotEqual_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqual('status', 'inativo').Build;
  AssertEquals('SQLite WhereNotEqual string', 'SELECT * FROM itens WHERE (status <> ''inativo'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotEqual_Integer;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqual('tipo', 0).Build;
  AssertEquals('SQLite WhereNotEqual integer', 'SELECT * FROM itens WHERE (tipo <> 0)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotEqual_Boolean;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqual('ativo', True).Build;
  AssertEquals('SQLite WhereNotEqual boolean True gera <> 1', 'SELECT * FROM itens WHERE (ativo <> 1)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereGreaterThan_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterThan('preco', 15.75).Build;
  AssertEquals('SQLite WhereGreaterThan double', 'SELECT * FROM itens WHERE (preco > 15.75)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereLessThan_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessThan('preco', 99.99).Build;
  AssertEquals('SQLite WhereLessThan double', 'SELECT * FROM itens WHERE (preco < 99.99)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereGreaterOrEqual_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereGreaterOrEqual('saldo', 100.5).Build;
  AssertEquals('SQLite WhereGreaterOrEqual double', 'SELECT * FROM itens WHERE (saldo >= 100.5)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereLessOrEqual_Double;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLessOrEqual('saldo', 500.25).Build;
  AssertEquals('SQLite WhereLessOrEqual double', 'SELECT * FROM itens WHERE (saldo <= 500.25)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereLike;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLike('codigo', 'X%').Build;
  AssertEquals('SQLite WhereLike', 'SELECT * FROM itens WHERE (codigo LIKE ''X%'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereILike_GeneratesCollateNoCase;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereILike('nome', '%silva%').Build;
  AssertEquals('SQLite WhereILike traduzido para LIKE ... COLLATE NOCASE',
    'SELECT * FROM itens WHERE (nome LIKE ''%silva%'' COLLATE NOCASE)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereIn_String_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIn('categoria', ['A', 'B']).Build;
  AssertEquals('SQLite WhereIn', 'SELECT * FROM itens WHERE (categoria IN (''A'', ''B''))', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereIn_String_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIn('categoria', []).Build;
  AssertEquals('SQLite WhereIn vazio', 'SELECT * FROM itens WHERE (1 = 0)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereInInt_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereInInt('cod', [10, 20]).Build;
  AssertEquals('SQLite WhereInInt', 'SELECT * FROM itens WHERE (cod IN (10, 20))', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereInInt_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereInInt('cod', []).Build;
  AssertEquals('SQLite WhereInInt vazio', 'SELECT * FROM itens WHERE (1 = 0)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotIn_String_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotIn('categoria', ['X', 'Y']).Build;
  AssertEquals('SQLite WhereNotIn', 'SELECT * FROM itens WHERE (categoria NOT IN (''X'', ''Y''))', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotIn_String_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotIn('categoria', []).Build;
  AssertEquals('SQLite WhereNotIn vazio', 'SELECT * FROM itens', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotInInt_Populated;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotInInt('cod', [98, 99]).Build;
  AssertEquals('SQLite WhereNotInInt', 'SELECT * FROM itens WHERE (cod NOT IN (98, 99))', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotInInt_Empty;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotInInt('cod', []).Build;
  AssertEquals('SQLite WhereNotInInt vazio', 'SELECT * FROM itens', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereIsNull;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIsNull('data_exclusao').Build;
  AssertEquals('SQLite WhereIsNull', 'SELECT * FROM itens WHERE (data_exclusao IS NULL)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereIsNotNull;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereIsNotNull('data_exclusao').Build;
  AssertEquals('SQLite WhereIsNotNull', 'SELECT * FROM itens WHERE (data_exclusao IS NOT NULL)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereBetween_String;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetween('cod', 'A', 'M').Build;
  AssertEquals('SQLite WhereBetween string', 'SELECT * FROM itens WHERE (cod BETWEEN ''A'' AND ''M'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereBetweenInt;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenInt('pontos', 0, 100).Build;
  AssertEquals('SQLite WhereBetweenInt', 'SELECT * FROM itens WHERE (pontos BETWEEN 0 AND 100)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereBetweenDate;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenDate('dt', EncodeDate(2026, 1, 1), EncodeDate(2026, 6, 30)).Build;
  AssertEquals('SQLite WhereBetweenDate', 'SELECT * FROM itens WHERE (dt BETWEEN ''2026-01-01'' AND ''2026-06-30'')', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereEqualParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereEqualParam('cidade', 'pCidade').Build;
  AssertEquals('SQLite WhereEqualParam', 'SELECT * FROM itens WHERE (cidade = :pCidade)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereNotEqualParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereNotEqualParam('status', 'pStatus').Build;
  AssertEquals('SQLite WhereNotEqualParam', 'SELECT * FROM itens WHERE (status <> :pStatus)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereLikeParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereLikeParam('nome', 'pNome').Build;
  AssertEquals('SQLite WhereLikeParam', 'SELECT * FROM itens WHERE (nome LIKE :pNome)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereILikeParam_GeneratesCollateNoCase;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereILikeParam('nome', 'pNome').Build;
  AssertEquals('SQLite WhereILikeParam traduzido para LIKE :param COLLATE NOCASE',
    'SELECT * FROM itens WHERE (nome LIKE :pNome COLLATE NOCASE)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestWhereBetweenParam;
var
  SQL: string;
begin
  SQL := CreateBuilder.WhereBetweenParam('valor', 'pMin', 'pMax').Build;
  AssertEquals('SQLite WhereBetweenParam', 'SELECT * FROM itens WHERE (valor BETWEEN :pMin AND :pMax)', SQL);
end;

procedure TTestSQLBuilderSQLite.TestPagination_LimitOnly;
var
  SQL: string;
begin
  SQL := CreateBuilder.Limit(10).Build;
  AssertEquals('SQLite Limit only', 'SELECT * FROM itens LIMIT 10', SQL);
end;

procedure TTestSQLBuilderSQLite.TestPagination_LimitAndOffset;
var
  SQL: string;
begin
  SQL := CreateBuilder.Limit(10).Offset(20).Build;
  AssertEquals('SQLite Limit + Offset', 'SELECT * FROM itens LIMIT 10 OFFSET 20', SQL);
end;

procedure TTestSQLBuilderSQLite.TestPagination_OffsetOnly_GeneratesLimitMinusOne;
var
  SQL: string;
begin
  SQL := CreateBuilder.Offset(20).Build;
  AssertEquals('SQLite Offset isolado exige LIMIT -1', 'SELECT * FROM itens LIMIT -1 OFFSET 20', SQL);
end;

procedure TTestSQLBuilderSQLite.TestOrderBy_AscAndDesc;
var
  SQL: string;
begin
  SQL := CreateBuilder.OrderBy('nome', odAsc).OrderByDesc('id').Build;
  AssertEquals('SQLite OrderBy', 'SELECT * FROM itens ORDER BY nome ASC, id DESC', SQL);
end;

procedure TTestSQLBuilderSQLite.TestBuild_CompleteQuery;
var
  SQL: string;
begin
  SQL := SQLSelect(sdSQLite)
    .Fields(['id', 'nome', 'ativo'])
    .From('usuarios')
    .WhereEqual('ativo', True)
    .WhereILike('nome', '%carlos%')
    .OrderBy('nome', odAsc)
    .Limit(20)
    .Offset(40)
    .Build;
  AssertEquals('SQLite Query completa',
    'SELECT id, nome, ativo FROM usuarios WHERE (ativo = 1) AND (nome LIKE ''%carlos%'' COLLATE NOCASE) ORDER BY nome ASC LIMIT 20 OFFSET 40', SQL);
end;

procedure TTestSQLBuilderSQLite.TestBuildCount;
var
  SQL: string;
begin
  SQL := SQLSelect(sdSQLite)
    .From('usuarios')
    .WhereEqual('ativo', True)
    .OrderBy('nome')
    .Offset(10)
    .BuildCount;
  AssertEquals('SQLite BuildCount', 'SELECT COUNT(*) FROM usuarios WHERE (ativo = 1)', SQL);
end;

{ ============================================================================ }
{ TTestSQLBuilderParamsAndLifecycle                                            }
{ ============================================================================ }

procedure TTestSQLBuilderParamsAndLifecycle.TestParamSetting_AllTypes;
var
  Builder: ISQLSelectBuilder;
  Dt: TDateTime;
begin
  Dt := EncodeDateTime(2026, 10, 15, 14, 0, 0, 0);
  Builder := SQLSelect(sdSQLite)
    .From('tbl')
    .SetParamStr('pStr', 'texto')
    .SetParamInt('pInt', 100)
    .SetParamInt64('pInt64', 9999999999)
    .SetParamFloat('pFloat', 123.45)
    .SetParamCurrency('pCur', 50.00)
    .SetParamDate('pDate', Dt)
    .SetParamTime('pTime', Dt)
    .SetParamDateTime('pDateTime', Dt)
    .SetParamBool('pBool', True)
    .SetParamNull('pNull');

  AssertEquals('Deve armazenar 10 parametros', 10, Builder.ParamCount);
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestParamUpdating_CaseInsensitive;
var
  Builder: ISQLSelectBuilder;
  Params: TParams;
begin
  Builder := SQLSelect(sdSQLite)
    .From('tbl')
    .SetParamStr('pNome', 'Primeiro')
    .SetParamStr('PNOME', 'Segundo'); // Deve atualizar o mesmo parametro

  AssertEquals('ParamCount deve permanecer 1', 1, Builder.ParamCount);

  Params := TParams.Create(nil);
  try
    Builder.ApplyParams(Params);
    AssertEquals('Params.Count deve ser 1', 1, Params.Count);
    AssertEquals('Valor atualizado', 'Segundo', Params.ParamByName('pNome').AsString);
  finally
    Params.Free;
  end;
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestApplyParams_CreatesNewParams;
var
  Builder: ISQLSelectBuilder;
  Params: TParams;
begin
  Params := TParams.Create(nil);
  try
    Builder := SQLSelect(sdSQLite)
      .From('clientes')
      .SetParamStr('pNome', 'Maria')
      .SetParamInt('pIdade', 28);

    Builder.ApplyParams(Params);

    AssertEquals('Param count criado', 2, Params.Count);
    AssertEquals('Nome', 'Maria', Params.ParamByName('pNome').AsString);
    AssertEquals('Idade', 28, Params.ParamByName('pIdade').AsInteger);
  finally
    Params.Free;
  end;
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestApplyParams_UpdatesExistingParams;
var
  Builder: ISQLSelectBuilder;
  Params: TParams;
begin
  Params := TParams.Create(nil);
  try
    // Parametro pre-existente em Params
    Params.CreateParam(ftString, 'pStatus', ptInput).AsString := 'A';

    Builder := SQLSelect(sdSQLite)
      .From('clientes')
      .SetParamStr('pStatus', 'B');

    Builder.ApplyParams(Params);

    AssertEquals('Param count nao deve duplicar', 1, Params.Count);
    AssertEquals('Status atualizado', 'B', Params.ParamByName('pStatus').AsString);
  finally
    Params.Free;
  end;
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestApplyParams_DataTypesVerification;
var
  Builder: ISQLSelectBuilder;
  Params: TParams;
  Dt: TDateTime;
begin
  Dt := EncodeDateTime(2026, 10, 15, 14, 30, 0, 0);
  Params := TParams.Create(nil);
  try
    Builder := SQLSelect(sdSQLite)
      .From('t')
      .SetParamStr('pStr', 'abc')
      .SetParamInt('pInt', 42)
      .SetParamInt64('pInt64', 1234567890123)
      .SetParamFloat('pFloat', 3.14159)
      .SetParamCurrency('pCur', 199.90)
      .SetParamDate('pDate', Dt)
      .SetParamTime('pTime', Dt)
      .SetParamDateTime('pDateTime', Dt)
      .SetParamBool('pBool', True)
      .SetParamNull('pNull');

    Builder.ApplyParams(Params);

    AssertEquals('ftString', Ord(ftString), Ord(Params.ParamByName('pStr').DataType));
    AssertEquals('ftInteger', Ord(ftInteger), Ord(Params.ParamByName('pInt').DataType));
    AssertEquals('ftLargeint', Ord(ftLargeint), Ord(Params.ParamByName('pInt64').DataType));
    AssertEquals('ftFloat', Ord(ftFloat), Ord(Params.ParamByName('pFloat').DataType));
    AssertEquals('ftCurrency', Ord(ftCurrency), Ord(Params.ParamByName('pCur').DataType));
    AssertEquals('ftDate', Ord(ftDate), Ord(Params.ParamByName('pDate').DataType));
    AssertEquals('ftTime', Ord(ftTime), Ord(Params.ParamByName('pTime').DataType));
    AssertEquals('ftDateTime', Ord(ftDateTime), Ord(Params.ParamByName('pDateTime').DataType));
    AssertEquals('ftBoolean', Ord(ftBoolean), Ord(Params.ParamByName('pBool').DataType));
    AssertTrue('IsNull', Params.ParamByName('pNull').IsNull);
  finally
    Params.Free;
  end;
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestClear_ResetsAllClauses;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect(sdSQLite)
    .FromSchema('sec', 'produtos')
    .Fields(['id', 'nome'])
    .WhereEqual('ativo', True)
    .OrderBy('nome')
    .Limit(10)
    .Offset(5)
    .SetParamStr('pX', '1');

  Builder.Clear;

  AssertEquals('TableName vazio apos clear', '', Builder.TableName);
  AssertEquals('SchemaName vazio apos clear', '', Builder.SchemaName);
  AssertFalse('HasLimit falso apos clear', Builder.HasLimit);
  AssertFalse('HasOffset falso apos clear', Builder.HasOffset);
  AssertEquals('WhereCount zero', 0, Builder.WhereCount);
  AssertEquals('ParamCount zero', 0, Builder.ParamCount);
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestClear_RetainsDialect;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect(sdSQLite).From('tabela');
  Builder.Clear;
  AssertEquals('Clear deve preservar dialeto SQLite', Ord(sdSQLite), Ord(Builder.SQLDialect));

  Builder := SQLSelect(sdPostgreSQL).From('tabela');
  Builder.Clear;
  AssertEquals('Clear deve preservar dialeto PostgreSQL', Ord(sdPostgreSQL), Ord(Builder.SQLDialect));
end;

procedure TTestSQLBuilderParamsAndLifecycle.TestPropertyInspection;
var
  Builder: ISQLSelectBuilder;
begin
  Builder := SQLSelect(sdSQLite)
    .FromSchema('minhaloja', 'produtos')
    .Where('preco > 10')
    .Where('estoque > 0')
    .Limit(25)
    .Offset(50)
    .SetParamInt('p1', 1)
    .SetParamInt('p2', 2);

  AssertEquals('TableName', 'produtos', Builder.TableName);
  AssertEquals('SchemaName', 'minhaloja', Builder.SchemaName);
  AssertTrue('HasLimit', Builder.HasLimit);
  AssertTrue('HasOffset', Builder.HasOffset);
  AssertEquals('LimitValue', 25, Builder.LimitValue);
  AssertEquals('OffsetValue', 50, Builder.OffsetValue);
  AssertEquals('WhereCount', 2, Builder.WhereCount);
  AssertEquals('ParamCount', 2, Builder.ParamCount);
  AssertEquals('SQLDialect', Ord(sdSQLite), Ord(Builder.SQLDialect));
end;

initialization
  RegisterTest(TTestSQLBuilderDialect);
  RegisterTest(TTestSQLBuilderFieldsAndFrom);
  RegisterTest(TTestSQLBuilderPostgreSQL);
  RegisterTest(TTestSQLBuilderSQLite);
  RegisterTest(TTestSQLBuilderParamsAndLifecycle);

end.
