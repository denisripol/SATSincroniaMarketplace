// ============================================================================
// UNIT: uFrmEscolherTipoCadastro
// OBJETIVO: Modal leve com um "card" por modo de cadastro suportado
// (ver uModosCadastroProduto) - so aparece quando o marketplace suporta
// MAIS de um modo (hoje, so a Amazon). Os cards sao criados em tempo de
// execucao a partir do set recebido, entao a tela ja funciona pra 3+
// modos no futuro sem precisar de nenhum ajuste de layout.
// ============================================================================
unit uFrmEscolherTipoCadastro;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, uModosCadastroProduto;
type
  TFrmEscolherTipoCadastro = class(TForm)
    lblTitulo: TLabel;
    pnlCards: TScrollBox;
    CmdCancelar: TBitBtn;
    procedure CmdCancelarClick(Sender: TObject);
  private
    FEscolhido: TModoCadastroProduto;
    procedure CriarCard(const AModo: TModoCadastroProduto; const ATop, AAltura: Integer);
    procedure CmdCardClick(Sender: TObject);
  public
    // Devolve True se o usuario escolheu um modo (AEscolhido preenchido);
    // False se cancelou.
    class function Escolher(const AModos: TModosCadastroProduto;
      out AEscolhido: TModoCadastroProduto): Boolean;
  end;
implementation
{$R *.dfm}
const
  ALTURA_CARD = 96;
  ESPACO_ENTRE_CARDS = 8;
  ALTURA_MAXIMA_LISTA = 400;
{ TFrmEscolherTipoCadastro }
class function TFrmEscolherTipoCadastro.Escolher(const AModos: TModosCadastroProduto;
  out AEscolhido: TModoCadastroProduto): Boolean;
var
  Frm: TFrmEscolherTipoCadastro;
  Modo: TModoCadastroProduto;
  Topo, AlturaTotal, AlturaLista: Integer;
begin
  Frm := TFrmEscolherTipoCadastro.Create(Application);
  try
    Topo := 8;
    for Modo := Low(TModoCadastroProduto) to High(TModoCadastroProduto) do
      if Modo in AModos then
      begin
        Frm.CriarCard(Modo, Topo, ALTURA_CARD);
        Inc(Topo, ALTURA_CARD + ESPACO_ENTRE_CARDS);
      end;
    AlturaTotal := Topo;
    AlturaLista := AlturaTotal;
    if AlturaLista > ALTURA_MAXIMA_LISTA then
      AlturaLista := ALTURA_MAXIMA_LISTA;
    Frm.pnlCards.Height := AlturaLista;
    Frm.ClientHeight := Frm.pnlCards.Top + AlturaLista + 56;
    Frm.CmdCancelar.Top := Frm.ClientHeight - 46;
    Result := Frm.ShowModal = mrOk;
    if Result then
      AEscolhido := Frm.FEscolhido;
  finally
    Frm.Free;
  end;
end;
procedure TFrmEscolherTipoCadastro.CriarCard(const AModo: TModoCadastroProduto;
  const ATop, AAltura: Integer);
var
  Pnl: TPanel;
  LblTitulo, LblSubtitulo: TLabel;
  Cmd: TBitBtn;
begin
  Pnl := TPanel.Create(Self);
  Pnl.Parent := pnlCards;
  Pnl.SetBounds(4, ATop, pnlCards.ClientWidth - 24, AAltura);
  Pnl.Anchors := [akLeft, akTop, akRight];
  Pnl.BevelOuter := bvLowered;
  Pnl.ParentBackground := False;
  Pnl.Color := clWhite;
  LblTitulo := TLabel.Create(Self);
  LblTitulo.Parent := Pnl;
  LblTitulo.SetBounds(12, 10, Pnl.Width - 130, 20);
  LblTitulo.Anchors := [akLeft, akTop, akRight];
  LblTitulo.Font.Style := [fsBold];
  LblTitulo.Caption := TituloModoCadastro(AModo);
  LblSubtitulo := TLabel.Create(Self);
  LblSubtitulo.Parent := Pnl;
  LblSubtitulo.SetBounds(12, 34, Pnl.Width - 140, 50);
  LblSubtitulo.Anchors := [akLeft, akTop, akRight];
  LblSubtitulo.WordWrap := True;
  LblSubtitulo.Caption := SubtituloModoCadastro(AModo);
  Cmd := TBitBtn.Create(Self);
  Cmd.Parent := Pnl;
  Cmd.SetBounds(Pnl.Width - 112, 28, 96, 32);
  Cmd.Anchors := [akTop, akRight];
  Cmd.Caption := 'Escolher';
  // TModoCadastroProduto tem so 2 valores hoje - cabe tranquilo num
  // Integer via Ord/cast, sem precisar de objeto auxiliar.
  Cmd.Tag := Ord(AModo);
  Cmd.OnClick := CmdCardClick;
end;
procedure TFrmEscolherTipoCadastro.CmdCardClick(Sender: TObject);
begin
  FEscolhido := TModoCadastroProduto((Sender as TBitBtn).Tag);
  ModalResult := mrOk;
end;
procedure TFrmEscolherTipoCadastro.CmdCancelarClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;
end.
