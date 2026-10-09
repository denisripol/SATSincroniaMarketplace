// ============================================================================
// UNIT: uFrmDespacharAmazon
// OBJETIVO: Modal simples pra coletar os dados que o ConfirmShipment da
// Amazon exige (transportadora, codigo de rastreio, data de envio) antes
// de despachar um pedido - a Amazon exige um "carrierCode" de uma lista
// controlada (ou "Other" + nome da transportadora), diferente da Shopee
// que so pede confirmar o despacho.
// ============================================================================
unit uFrmDespacharAmazon;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.ComCtrls;
type
  TFrmDespacharAmazon = class(TForm)
    lblTitulo: TLabel;
    lblCarrierCode: TLabel;
    cbCarrierCode: TComboBox;
    lblCarrierName: TLabel;
    edtCarrierName: TEdit;
    lblTrackingNumber: TLabel;
    edtTrackingNumber: TEdit;
    lblShipDate: TLabel;
    dtShipDate: TDateTimePicker;
    CmdConfirmar: TBitBtn;
    CmdCancelar: TBitBtn;
    procedure FormCreate(Sender: TObject);
    procedure cbCarrierCodeChange(Sender: TObject);
    procedure CmdConfirmarClick(Sender: TObject);
  private
    FCarrierCode, FCarrierName, FTrackingNumber: string;
    FShipDate: TDateTime;
  public
    // Devolve True se o usuario confirmou (campos preenchidos em
    // ACarrierCode/ACarrierName/ATrackingNumber/AShipDate); False se cancelou.
    class function Coletar(out ACarrierCode, ACarrierName, ATrackingNumber: string;
      out AShipDate: TDateTime): Boolean;
  end;
implementation
{$R *.dfm}
{ TFrmDespacharAmazon }
class function TFrmDespacharAmazon.Coletar(out ACarrierCode, ACarrierName,
  ATrackingNumber: string; out AShipDate: TDateTime): Boolean;
var
  Frm: TFrmDespacharAmazon;
begin
  Frm := TFrmDespacharAmazon.Create(Application);
  try
    Result := Frm.ShowModal = mrOk;
    if Result then
    begin
      ACarrierCode := Frm.FCarrierCode;
      ACarrierName := Frm.FCarrierName;
      ATrackingNumber := Frm.FTrackingNumber;
      AShipDate := Frm.FShipDate;
    end;
  finally
    Frm.Free;
  end;
end;
procedure TFrmDespacharAmazon.FormCreate(Sender: TObject);
begin
  // {ATENCAO} Lista curta com os codigos mais comuns no Brasil - a lista
  // OFICIAL completa de "Acceptable CarrierCode values" da Amazon e' bem
  // maior e muda por marketplace/pais. Se a transportadora usada nao
  // estiver aqui, escolha "Other" e digite o nome em "Nome da
  // Transportadora" (campo obrigatorio nesse caso).
  cbCarrierCode.Items.Add('CORREIOS');
  cbCarrierCode.Items.Add('UPS');
  cbCarrierCode.Items.Add('FEDEX');
  cbCarrierCode.Items.Add('DHL');
  cbCarrierCode.Items.Add('JADLOG');
  cbCarrierCode.Items.Add('LOGGI');
  cbCarrierCode.Items.Add('Other');
  cbCarrierCode.ItemIndex := 0;
  dtShipDate.DateTime := Now;
  edtCarrierName.Enabled := False;
end;
procedure TFrmDespacharAmazon.cbCarrierCodeChange(Sender: TObject);
begin
  edtCarrierName.Enabled := SameText(cbCarrierCode.Text, 'Other');
  if not edtCarrierName.Enabled then
    edtCarrierName.Clear;
end;
procedure TFrmDespacharAmazon.CmdConfirmarClick(Sender: TObject);
begin
  if Trim(edtTrackingNumber.Text) = '' then
  begin
    ShowMessage('Informe o codigo de rastreio.');
    Exit;
  end;
  if SameText(cbCarrierCode.Text, 'Other') and (Trim(edtCarrierName.Text) = '') then
  begin
    ShowMessage('Transportadora "Other" selecionada - informe o nome dela.');
    Exit;
  end;
  FCarrierCode := cbCarrierCode.Text;
  FCarrierName := Trim(edtCarrierName.Text);
  FTrackingNumber := Trim(edtTrackingNumber.Text);
  FShipDate := dtShipDate.DateTime;
  ModalResult := mrOk;
end;
end.
