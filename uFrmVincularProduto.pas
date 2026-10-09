// ============================================================================

// UNIT: uFrmVincularProduto

// OBJETIVO: Tela modal que lista os produtos fisicos da loja (join entre

// PRO - estoque por loja - e PROD - cadastro do produto) e devolve o codigo

// do produto escolhido pra quem chamou vincular na tabela PRODUTOS_MARKETPLACE.

//

// Nao grava nada sozinha - so' devolve o codigo escolhido (ou 0 se

// cancelado). Quem chama (uFrmOfertasMarketplace) e' quem faz o UPDATE.

// ============================================================================



unit uFrmVincularProduto;



interface



uses

  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,

  System.Classes, System.StrUtils, Vcl.Graphics, Vcl.Controls, Vcl.Forms,

  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.Grids,

  Data.DB, FireDAC.Comp.Client, DMZ;



const

  COL_COD = 0;

  COL_PRODUTO = 1;

  COL_ESTOQUE = 2;



type

  TFrmVincularProduto = class(TForm)

    pnlTopo: TPanel;

    lblTitulo: TLabel;

    lblFiltro: TLabel;

    edtFiltro: TEdit;

    CmdBuscar: TBitBtn;

    Grid: TStringGrid;

    pnlRodape: TPanel;

    CmdSelecionar: TBitBtn;

    CmdCancelar: TBitBtn;

    procedure FormCreate(Sender: TObject);

    procedure CmdBuscarClick(Sender: TObject);

    procedure edtFiltroKeyPress(Sender: TObject; var Key: Char);

    procedure CmdSelecionarClick(Sender: TObject);

    procedure CmdCancelarClick(Sender: TObject);

    procedure GridDblClick(Sender: TObject);

  private

    FLoja: Integer;

    FCodSelecionado: Integer;

    procedure CarregarProdutos;

  public

    // Devolve o codigo do produto (PROD.COD / PRO.COD) escolhido, ou 0 se o

    // usuario cancelou.

    class function SelecionarProduto(const ALoja: Integer): Integer;

  end;



implementation



{$R *.dfm}



{ TFrmVincularProduto }



class function TFrmVincularProduto.SelecionarProduto(const ALoja: Integer): Integer;

var

  Frm: TFrmVincularProduto;

begin

  Result := 0;

  Frm := TFrmVincularProduto.Create(Application);

  try

    Frm.FLoja := ALoja;

    Frm.CarregarProdutos;

    if Frm.ShowModal = mrOk then

      Result := Frm.FCodSelecionado;

  finally

    Frm.Free;

  end;

end;



procedure TFrmVincularProduto.FormCreate(Sender: TObject);

begin

  Grid.ColCount := 3;

  Grid.RowCount := 2; // FixedRows precisa ser sempre < RowCount

  Grid.FixedRows := 1;

  Grid.Cells[COL_COD, 0] := 'Código';

  Grid.Cells[COL_PRODUTO, 0] := 'Produto';

  Grid.Cells[COL_ESTOQUE, 0] := 'Estoque';

end;



procedure TFrmVincularProduto.CarregarProdutos;

var

  Qry: TFDQuery;

  I: Integer;

  Filtro: string;

begin

  Filtro := Trim(edtFiltro.Text);



  Qry := TFDQuery.Create(nil);

  try

    Qry.Connection := DZ.ZDatabase;

    Qry.SQL.Text :=

      'SELECT pr.produto, p.* ' +

      'FROM pro p ' +

      'INNER JOIN prod pr ON pr.COD = p.COD ' +

      'WHERE p.loja = :loja' +

      IfThen(Filtro <> '', ' AND UPPER(pr.produto) LIKE :filtro', '');

    Qry.ParamByName('loja').AsInteger := FLoja;

    if Filtro <> '' then

      Qry.ParamByName('filtro').AsString := '%' + UpperCase(Filtro) + '%';

    Qry.Open;



    Grid.RowCount := Qry.RecordCount + 1;

    if Grid.RowCount < 2 then

      Grid.RowCount := 2;



    for I := 1 to Grid.RowCount - 1 do

    begin

      Grid.Cells[COL_COD, I] := '';

      Grid.Cells[COL_PRODUTO, I] := '';

      Grid.Cells[COL_ESTOQUE, I] := '';

    end;



    I := 1;

    while not Qry.Eof do

    begin

      Grid.Cells[COL_COD, I] := Qry.FieldByName('COD').AsString;

      Grid.Cells[COL_PRODUTO, I] := Qry.FieldByName('produto').AsString;

      Grid.Cells[COL_ESTOQUE, I] := Qry.FieldByName('QUANT').AsString;

      Inc(I);

      Qry.Next;

    end;

  finally

    Qry.Free;

  end;

end;



procedure TFrmVincularProduto.CmdBuscarClick(Sender: TObject);

begin

  CarregarProdutos;

end;



procedure TFrmVincularProduto.edtFiltroKeyPress(Sender: TObject; var Key: Char);

begin

  if Key = #13 then

  begin

    Key := #0;

    CarregarProdutos;

  end;

end;



procedure TFrmVincularProduto.GridDblClick(Sender: TObject);

begin

  CmdSelecionarClick(Sender);

end;



procedure TFrmVincularProduto.CmdSelecionarClick(Sender: TObject);

begin

  if (Grid.Row < 1) or (Grid.Row >= Grid.RowCount) or

     (Trim(Grid.Cells[COL_COD, Grid.Row]) = '') then

  begin

    ShowMessage('Selecione um produto na lista primeiro.');

    Exit;

  end;



  FCodSelecionado := StrToIntDef(Grid.Cells[COL_COD, Grid.Row], 0);

  ModalResult := mrOk;

end;



procedure TFrmVincularProduto.CmdCancelarClick(Sender: TObject);

begin

  ModalResult := mrCancel;

end;



end.

