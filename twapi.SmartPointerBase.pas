unit twapi.SmartPointerBase;

{$mode Delphi}{$H+}

{* Uso

******************************
****Com construtor Simples****
******************************
var
  vWhereList: TSmartPointer<TStringList>;
begin
  vWhereList.Value.Add('Teste'); //Não é necessário dar create no SmartPointer, pois ele é um record
end;

*************************************
****Com construtor Com parametros****
*************************************
var
  vSQLQuery: TSmartPointer<TFDQuery>;
begin
  vSQLQuery:= THelper.GetQuery(AConexao); //ou vSQLQuery:= TFDQuery.Create(nil);
  vSQLQuery.Value.Open('SELECT * FROM GAC_PESSOA'); //Não é necessário Free
end;

*}

interface

uses
  DB;

type

  TSmartPointer<T: class> = record
  strict private
    FValue: T;
    FFreeTheValue: IInterface;
    function GetValue: T;
  public
    class operator Implicit(smart: TSmartPointer<T>): T;
    class operator Implicit(AValue: T): TSmartPointer<T>;
    constructor Create(aValue: T);
    property Value: T read GetValue;
  end;

  TFreeTheValue = class(TInterfacedObject)
  private
    fObjetToFree: TObject;
  public
    constructor Create(anObjectToFree: TObject);
    destructor Destroy; override;
  end;

implementation

{ TSmartPointer<T> }

constructor TSmartPointer<T>.Create(aValue: T);
begin
  Self.FValue:= aValue;
  Self.FFreeTheValue:= TFreeTheValue.Create(FValue);
end;

function TSmartPointer<T>.GetValue: T;
begin
  //if not Assigned(Self.FFreeTheValue) then
  //  Self:= TSmartPointer<T>.Create(T.Create);
  Result:= FValue;
end;

class operator TSmartPointer<T>.Implicit(AValue: T): TSmartPointer<T>;
begin
  Result:= TSmartPointer<T>.Create(AValue);
end;

class operator TSmartPointer<T>.Implicit(smart: TSmartPointer<T>): T;
begin
  Result:= smart.Value;
end;

{ TFreeTheValue }

constructor TFreeTheValue.Create(anObjectToFree: TObject);
begin
  Self.fObjetToFree:= anObjectToFree;
end;

destructor TFreeTheValue.Destroy;
begin
  if Self.fObjetToFree is TDataSet then
  begin
    (Self.fObjetToFree as TDataSet).Close;
  end;
  Self.fObjetToFree.Free;
  inherited;
end;

end.
