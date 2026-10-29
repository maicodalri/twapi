# 🚀 Tiny Web API (twapi)

[![Free Pascal](https://img.shields.io/badge/Free%20Pascal-3.2%2B-blue?logo=pascal)](https://www.freepascal.org/)
[![Lazarus](https://img.shields.io/badge/Lazarus-IDE-orange)](https://www.lazarus-ide.org/)
[![Horse](https://img.shields.io/badge/Horse-Web%20Framework-success)](https://github.com/HashLoad/horse)
[![ZeosDB](https://img.shields.io/badge/ZeosDB-SQLite%20%7C%20PostgreSQL-informational)](https://sourceforge.net/projects/zeoslib/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](#licença)

**Tiny Web API (`twapi`)** é um micro-framework leve, modular e thread-safe para **Lazarus / Free Pascal**, construído sobre o [Horse](https://github.com/HashLoad/horse), [ZeosDB](https://sourceforge.net/projects/zeoslib/) e [DataSet-Serialize](https://github.com/viniciussanchez/dataset-serialize).

Seu objetivo principal é **expor tabelas de banco de dados automaticamente como APIs RESTful JSON completas** em poucas linhas de código, oferecendo suporte nativo a **Multi-Tenancy (banco por token)**, **Pool de Conexões Thread-Safe**, **Autenticação Bearer Token com persistência de sessão**, **SQL Builder Fluente multi-dialeto (PostgreSQL e SQLite)**, **Paginação**, **Filtros Dinâmicos**, **Soft Delete** e **Hooks de Ciclo de Vida**.

---

## ✨ Principais Funcionalidades

- ⚡ **Auto-CRUD RESTful (`TTWApiController`)**: Mapeia qualquer tabela para endpoints `GET` (lista paginada), `GET /:id`, `POST`, `PUT /:id` e `DELETE /:id` instantaneamente.
- 🏢 **Arquitetura Multi-Tenant Nativa**: Cada token de autenticação carrega de forma segura e assinada o banco de dados (`tenant`) do cliente. O chaveamento de conexão ocorre automaticamente a cada requisição.
- 🔄 **Pool de Conexões ZeosDB (`TZeosConnectionPool`)**: Gerenciamento thread-safe de conexões por tenant, com reconexão automática (`PingServer`), rollback preventivo de transações pendentes e reciclagem de conexões ociosas.
- 🔐 **Autenticação & Sessão Persistente (`twapi.Auth`)**:
  - Middleware global para o Horse (`HorseAuthMiddleware`).
  - Assinatura criptográfica (`SHA-1` + `Base64`) com segredo (`JWTSecret`) gerado e persistido automaticamente no arquivo `.conf`.
  - Persistência e validação de sessões ativas em banco local SQLite (`tb_sessions`) com expurgo automático de tokens expirados.
  - Proteção contra *Path Traversal* e nomes de bancos inválidos.
- 🛠️ **SQL Builder Fluente (`twapi.SQLBuilder`)**:
  - Construção programática e encadeada (*Fluent Interface*) de comandos `SELECT` (`ISQLSelectBuilder`) e `CREATE TABLE` / `CREATE INDEX` (`ISQLCreateTableBuilder`).
  - Tradução transparente entre **PostgreSQL** e **SQLite** (ex.: `ILIKE` $\rightarrow$ `LIKE ... COLLATE NOCASE`, `BOOLEAN` `TRUE/FALSE` $\rightarrow$ `1/0`, `SERIAL/BIGSERIAL` $\rightarrow$ `AUTOINCREMENT`, `OFFSET` isolado com `LIMIT -1`, omissão inteligente do schema `public` no SQLite).
  - Gerenciamento automático de memória via interfaces COM (`{$interfaces com}`).
- 🎭 **Mapeamento de Campos / Aliases (`AddFieldMapping`)**: Oculte colunas sensíveis e exponha apenas os campos desejados com nomes amigáveis no JSON (tradução bidirecional no `GET`, `POST`, `PUT`, filtros de URL e ordenação).
- 📄 **Paginação e Filtros Automáticos**:
  - Paginação via Query String (`?page=1&limit=50`) com metadados nos headers HTTP (`X-Total-Count`, `X-Total-Pages`, `X-Page`, `X-Limit`).
  - Filtros automáticos por qualquer campo na Query String (busca exata `=` ou parcial `LIKE` quando contém `%`), 100% parametrizados contra *SQL Injection*.
  - Ordenação dinâmica via headers HTTP (`X-Sort` e `X-Order`).
- 🗑️ **Soft Delete Configurável**: Exclusão lógica automática por coluna de status/flag ou timestamp sem remover o registro físico.
- 🪝 **Lifecycle Hooks (Eventos CRUD)**: Intercepte, valide ou modifique dados antes e depois de cada operação (`OnBeforeCreate`, `OnAfterCreate`, `OnBeforeUpdate`, `OnAfterUpdate`, `OnBeforeDelete`, `OnAfterDelete`).
- 🧠 **Smart Pointers (`TSmartPointer<T>`) & Logger Thread-Safe (`TFileTextLog`)**: Utilitários integrados para evitar vazamentos de memória (*Memory Leaks*) e registrar logs em arquivo sem bloqueio de concorrência.

---

## 📂 Estrutura do Projeto

| Unit | Descrição |
| :--- | :--- |
| `twapi.Controller.pas` | Controlador principal (`TTWApiController`) que registra rotas no Horse e executa o CRUD, paginação, filtros, aliases, soft delete e hooks. |
| `twapi.Controller.PoolConn.pas` | Pool de conexões thread-safe para ZeosDB (`TZeosConnectionPool`) e leitor de configuração de banco (`TTempleteConn`). |
| `twapi.Auth.pas` | Geração/validação de tokens, middleware de autenticação do Horse (`HorseAuthMiddleware`), rota de login (`RegisterLoginRoute`) e persistência SQLite (`TPersistToken`). |
| `twapi.SQLBuilder.pas` | Gerador fluente de SQL (`ISQLSelectBuilder` e `ISQLCreateTableBuilder`) com suporte aos dialetos PostgreSQL e SQLite. |
| `twapi.SQLBuilder.Tests.pas` | Suíte completa de testes unitários (`FPCUnit`) cobrindo todos os recursos e dialetos do `twapi.SQLBuilder`. |
| `twapi.Types.pas` | Tipos, constantes globais e gerenciamento thread-safe de configurações de ambiente (`GConfigEnv` / `TConfigEnv`). |
| `twapi.SmartPointerBase.pas` | Implementação genérica de `TSmartPointer<T>` com fechamento automático de `TDataSet` e liberação de memória por escopo. |
| `twapi.TextFileLog.pas` | Sistema de log em arquivo (`TFileTextLog`) thread-safe com níveis de severidade (`Debug`, `Info`, `Erro`, `Critical`) e callback em tempo real. |

---

## 📋 Pré-requisitos e Dependências

Para utilizar o **Tiny Web API** em seu projeto Lazarus, você precisará de:

1. **Free Pascal (FPC) 3.2.0+** e **Lazarus IDE**.
2. **[Horse](https://github.com/HashLoad/horse)** (Framework Web).
3. **[DataSet-Serialize](https://github.com/viniciussanchez/dataset-serialize)** (Serialização entre `TDataSet` e JSON).
4. **[ZeosLib (ZeosDB)](https://sourceforge.net/projects/zeoslib/)** (Componentes `ZConnection` e `ZDataset`).
5. Biblioteca cliente do banco de dados na pasta do executável:
   - `sqlite3.dll` (necessária no Windows para persistência local de sessões do `twapi.Auth` e/ou caso utilize SQLite nos tenants).
   - `libpq.dll` (caso utilize PostgreSQL).

### Instalação

1. Clone este repositório:
   ```bash
   git clone https://github.com/SEU_USUARIO/twapi.git
   ```
2. No **Lazarus**, adicione o diretório do `twapi` ao **Other unit files (`-Fu`)** nas opções do seu projeto (*Project* $\rightarrow$ *Project Options* $\rightarrow$ *Compiler Options* $\rightarrow$ *Paths*).
3. Certifique-se de que os pacotes do **ZeosDB** (`zcomponent`), **Horse** e **DataSet-Serialize** estejam referenciados no seu projeto.

---

## ⚙️ Arquivo de Configuração (`.conf`)

O framework procura automaticamente um arquivo de configuração com o mesmo nome do executável e extensão `.conf` (ex.: se o executável for `meu_servidor.exe`, o arquivo será `meu_servidor.conf`).

```ini
[BASE]
; Gerado automaticamente na primeira execução caso omitido (256-bit hex)
JWTSecret=

[DB]
; Protocolo do ZeosDB: postgresql ou sqlite
Protocol=postgresql
Host=localhost
Port=5432
Database=masterdb
User=postgres
Paswd=sua_senha
Lib=C:\caminho\para\libpq.dll
```

> **Nota:** Para o controle de sessões de login (`TPersistToken`), o `twapi.Auth` cria automaticamente um arquivo SQLite local (`<nome_do_executavel>.db`) utilizando a `sqlite3.dll` presente no diretório da aplicação.

---

## 🚀 Guia Rápido de Uso (Quick Start)

Veja como criar um servidor REST completo com autenticação Multi-Tenant e endpoints CRUD automáticos:

```pascal
program MeuServidorAPI;

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, fpjson, ZConnection,
  Horse,
  twapi.Types,
  twapi.Auth,
  twapi.Controller,
  twapi.Controller.PoolConn,
  twapi.TextFileLog;

type
  TAuthHandler = class
  public
    function OnAuthenticate(const AUser, APass, ATenantAlias: string;
      const AIdSistem: Integer; out ADataBase: string; out AUserId: Integer;
      out AErrorMsg, ATipoUser, ALogoBase64: string): Boolean;
  end;

  TClienteHooks = class
  public
    procedure BeforeCreateCliente(Sender: TTWApiController; AJSONObject: TJSONObject;
      var AAllow: Boolean; var AErrorMessage: string; var DBConn: TZConnection);
  end;

function TAuthHandler.OnAuthenticate(const AUser, APass, ATenantAlias: string;
  const AIdSistem: Integer; out ADataBase: string; out AUserId: Integer;
  out AErrorMsg, ATipoUser, ALogoBase64: string): Boolean;
begin
  // Exemplo de validação (aqui você pode consultar seu banco master de clientes/tenants)
  if (AUser = 'admin') and (APass = '123456') then
  begin
    Result := True;
    AUserId := 1;
    ATipoUser := 'A'; // 'A' = Administrador
    ADataBase := 'db_' + LowerCase(ATenantAlias); // Define o banco do Tenant!
    ALogoBase64 := '';
  end
  else
  begin
    Result := False;
    AErrorMsg := 'Credenciais inválidas!';
  end;
end;

procedure TClienteHooks.BeforeCreateCliente(Sender: TTWApiController;
  AJSONObject: TJSONObject; var AAllow: Boolean; var AErrorMessage: string;
  var DBConn: TZConnection);
begin
  if Trim(AJSONObject.Get('nome_cliente', '')) = '' then
  begin
    AAllow := False;
    AErrorMessage := 'O nome do cliente é obrigatório!';
  end;
end;

var
  AuthHandler: TAuthHandler;
  ClienteHooks: TClienteHooks;
  ClientesController: TTWApiController;
begin
  GConfigEnv.Debug := True;
  AuthHandler := TAuthHandler.Create;
  ClienteHooks := TClienteHooks.Create;

  // 1. Define o prefixo global das rotas de dados (padrão é '/db')
  // Importante: O middleware de autenticação protege automaticamente rotas iniciadas por '/api/'
  TTWApiController.RoutePrefix := '/api/v1';

  // 2. Registra a rota de Login
  RegisterLoginRoute('/api/login', AuthHandler.OnAuthenticate);

  // 3. Cria o Controller para a tabela 'clientes' (PK = 'id')
  ClientesController := TTWApiController.Create('clientes', 'id', True);

  // Opcional: Mapeia colunas físicas do banco para apelidos no JSON (oculta colunas não listadas)
  ClientesController.AddFieldMapping('id', 'codigo');
  ClientesController.AddFieldMapping('nome', 'nome_cliente');
  ClientesController.AddFieldMapping('email', 'email');
  ClientesController.AddFieldMapping('ativo', 'ativo');

  // Opcional: Define ordenação padrão e Soft Delete
  ClientesController.DefaultSortField := 'nome_cliente';
  ClientesController.SoftDeleteField := 'ativo';
  ClientesController.SoftDeleteActiveValue := 'S';
  ClientesController.SoftDeleteDeletedValue := 'N';

  // Opcional: Associa eventos de ciclo de vida (Hooks)
  ClientesController.OnBeforeCreate := ClienteHooks.BeforeCreateCliente;

  // 4. Registra as rotas CRUD: /api/v1/clientes e /api/v1/clientes/:_id
  ClientesController.RegisterRoutes('/clientes');

  WriteLog('Servidor iniciando na porta 9000...', ltInfo);
  THorse.Listen(9000);
end.
```

---

## 🌐 Endpoints Gerados Automaticamente

Ao chamar `ClientesController.RegisterRoutes('/clientes')` (com `RoutePrefix := '/api/v1'`), os seguintes endpoints ficam disponíveis imediatamente:

| Método | Rota | Descrição | Retorno HTTP |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/login` | Autentica o usuário/tenant e retorna o Bearer Token | `200 OK` / `401 Unauthorized` |
| `GET` | `/api/v1/clientes` | Lista registros com paginação, filtros e ordenação | `200 OK` (JSON Array) |
| `GET` | `/api/v1/clientes/:_id` | Busca um registro específico pela chave primária | `200 OK` / `404 Not Found` |
| `POST` | `/api/v1/clientes` | Insere um novo registro na tabela | `201 Created` (JSON Object) |
| `PUT` | `/api/v1/clientes/:_id` | Atualiza parcialmente/totalmente um registro existente | `200 OK` / `404 Not Found` |
| `DELETE` | `/api/v1/clientes/:_id` | Remove o registro (física ou logicamente via Soft Delete) | `204 No Content` |

### 1. Autenticação (`POST /api/login`)

**Request Body:**
```json
{
  "usuario": "admin",
  "senha": "123456",
  "tenantalias": "empresa_x",
  "systemid": 1
}
```

**Response (`200 OK`):**
```json
{
  "token": "eyJpZCI6MSwidXN1YXJpbyI6ImFkbWluIi... .4a8f9c...",
  "user_type": "A",
  "logo": ""
}
```

Nas requisições seguintes para rotas `/api/*`, envie o cabeçalho:
```http
Authorization: Bearer <seu_token>
```

### 2. Paginação, Filtros e Ordenação (`GET`)

- **Paginação**: `?page=1&limit=25` (padrão: `page=1`, `limit=50`, teto máximo de segurança: `1000`).
  - Os cabeçalhos de resposta incluem:
    - `X-Total-Count`: Total de registros encontrados.
    - `X-Total-Pages`: Total de páginas.
    - `X-Page`: Página atual.
    - `X-Limit`: Limite por página.
- **Filtros Dinâmicos**: Qualquer parâmetro adicional na URL vira filtro `WHERE` seguro (usando tanto o apelido JSON quanto o nome físico):
  - Busca exata (`=`): `GET /api/v1/clientes?codigo=10`
  - Busca parcial (`LIKE`): `GET /api/v1/clientes?nome_cliente=%Silva%`
- **Ordenação via Headers HTTP**:
  - `X-Sort: nome_cliente`
  - `X-Order: ASC` (ou `DESC`)
- **Filtro de Escopo por Usuário (`OptionalListCondition`)**:
  - Permite restringir registros listados para usuários não-administradores (`UserType <> 'A'`) usando a macro `:USERID`:
    ```pascal
    PedidosController.OptionalListCondition := 'id_vendedor = :USERID';
    ```

---

## 🛠️ Uso do SQL Builder (`twapi.SQLBuilder`)

O módulo `twapi.SQLBuilder` pode ser usado de forma independente em qualquer parte do seu projeto para construir queries `SELECT` e `CREATE TABLE` compatíveis com **PostgreSQL** e **SQLite** sem se preocupar com diferenças de sintaxe:

### Construindo consultas `SELECT` (`ISQLSelectBuilder`)

```pascal
uses
  twapi.SQLBuilder;

var
  LSQL: ISQLSelectBuilder;
begin
  // Criação fluente (gerenciamento automático de memória via Interface)
  LSQL := SQLSelect(sdSQLite)
    .Fields(['id', 'nome', 'email', 'datacadastro'])
    .From('clientes')
    .WhereILikeParam('nome', 'pNome')     // No PG: ILIKE :pNome | No SQLite: LIKE :pNome COLLATE NOCASE
    .WhereEqualParam('ativo', 'pAtivo')
    .SetParamStr('pNome', '%maico%')
    .SetParamBool('pAtivo', True)
    .OrderBy('nome', odAsc)
    .Limit(20)
    .Offset(0);

  // Aplicando diretamente em um TZQuery ou TSQLQuery
  MinhaQuery.SQL.Text := LSQL.Build;
  LSQL.ApplyParams(MinhaQuery.Params);
  MinhaQuery.Open;

  // Gerando query de contagem total (ignora automaticamente ORDER BY, LIMIT e OFFSET)
  QueryCount.SQL.Text := LSQL.BuildCount;
  LSQL.ApplyParams(QueryCount.Params);
  QueryCount.Open;
end;
```

### Criando tabelas e índices (`ISQLCreateTableBuilder`)

```pascal
uses
  twapi.SQLBuilder;

var
  LTable: ISQLCreateTableBuilder;
begin
  LTable := SQLCreateTable('produtos', sdPostgreSQL)
    .IfNotExists
    .AddPrimaryKey('id', True)                        // SERIAL PRIMARY KEY no PG | INTEGER PRIMARY KEY AUTOINCREMENT no SQLite
    .AddVarchar('descricao', 150, True)
    .AddCurrency('preco_venda', True, True)           // NUMERIC(15, 2) NOT NULL DEFAULT 0.00
    .AddBoolean('ativo', True, True, True)            // DEFAULT TRUE no PG | DEFAULT 1 no SQLite
    .AddDateTime('criado_em', False, True)            // DEFAULT CURRENT_TIMESTAMP
    .AddForeignKey('id_categoria', 'categorias', 'id', fkRestrict, fkCascade);

  // SQL de verificação no catálogo (information_schema no PG / sqlite_master no SQLite)
  CheckQuery.SQL.Text := LTable.BuildCheckTableExists;

  // Executa DDL da tabela e de índice
  Conn.ExecuteDirect(LTable.Build);
  Conn.ExecuteDirect(LTable.BuildCreateIndex('idx_produtos_descricao', ['descricao']));
end;
```

---

## 🧠 Utilitários Inclusos

### Smart Pointer (`twapi.SmartPointerBase`)
Evita blocos `try..finally..Free` repetitivos e fecha automaticamente instâncias de `TDataSet` ao sair do escopo:

```pascal
uses
  twapi.SmartPointerBase, ZDataset;

procedure MinhaRotina;
var
  LQuery: TSmartPointer<TZQuery>;
begin
  LQuery := TZQuery.Create(nil);
  LQuery.Value.Connection := MinhaConexao;
  LQuery.Value.SQL.Text := 'SELECT * FROM usuarios';
  LQuery.Value.Open;
  // Ao sair da procedure, o DataSet é fechado (Close) e destruído (Free) automaticamente!
end;
```

### Logger Thread-Safe (`twapi.TextFileLog`)
Grava logs formatados com data/hora e milissegundos em `<executavel>.log` com proteção `TCriticalSection`:

```pascal
uses
  twapi.TextFileLog;

begin
  // Opcional: interceptar logs para exibir em um Memo ou Console
  TFileTextLog.OnLog := MeuCallbackDeLog;

  WriteLog('Servidor iniciado com sucesso', ltInfo);
  WriteLogFmt('Usuário %d autenticado no banco %s', [10, 'db_empresa'], ltInfo);
  WriteLogDbg('Mensagem exibida apenas quando GConfigEnv.Debug = True');
  WriteLog('Falha crítica ao conectar no banco!', ltCritical);
end;
```

---

## 🧪 Testes Unitários

O repositório inclui a unit `twapi.SQLBuilder.Tests.pas` com dezenas de testes automatizados baseados no **FPCUnit**, validando:
- Conversão e configuração global/local de dialetos (`PostgreSQL` e `SQLite`).
- Geração de cláusulas `SELECT`, `DISTINCT`, `FROM`, `WHERE`, `IN`, `BETWEEN`, `IS NULL`, `LIKE` e `ILIKE`.
- Aplicação tipada de parâmetros (`ApplyParams`) e limpeza de estado (`Clear`).
- Criação de tabelas (`CREATE TABLE`), chaves primárias, chaves estrangeiras, constraints (`UNIQUE`, `CHECK`), índices e consultas de catálogo.

Para executar os testes, basta criar um projeto **FPCUnit Test Application** no Lazarus e incluir a unit `twapi.SQLBuilder.Tests`.

---

## 🤝 Contribuições

Contribuições são muito bem-vindas! Sinta-se à vontade para abrir *Issues* relatando bugs, sugerindo melhorias ou enviando *Pull Requests*.

1. Faça um *Fork* do projeto
2. Crie uma *Branch* para sua feature (`git checkout -b feature/MinhaFeature`)
3. Faça o *Commit* de suas alterações (`git commit -m 'Adiciona MinhaFeature'`)
4. Faça o *Push* para a *Branch* (`git push origin feature/MinhaFeature`)
5. Abra um *Pull Request*

---

## 📄 Licença

Este projeto é distribuído sob a licença **MIT**. Isso significa que você pode usar, copiar, modificar, mesclar, publicar, distribuir, sublicenciar e/ou vender cópias do software livremente, tanto em projetos pessoais quanto comerciais.
