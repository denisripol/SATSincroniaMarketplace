// ============================================================================
// UNIT: uFrmConfigSincroniaAutomatica
// OBJETIVO: Modal simples pra ativar/desativar a sincronia automatica do F2
// (Enviar Dados) e definir o intervalo em segundos. Le/grava direto no
// SAT.INI, secao [Terminal], chaves OnLineSincroniaMarketplaceAutomatica
// (0/1) e OnLineSincroniaMarketplaceAutomaticaTempo (segundos).
// ============================================================================
unit uFrmConfigSincroniaAutomatica;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.IniFiles, System.IOUtils, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons;
const
  SAT_INI_SECAO_TERMINAL = 'Terminal';
  SAT_INI_CHAVE_ATIVO = 'OnLineSincroniaMarketplaceAutomatica';
  SAT_INI_CHAVE_TEMPO = 'OnLineSincroniaMarketplaceAutomaticaTempo';
  SAT_INI_TEMPO_MINIMO_SEGUNDOS = 10; // seguranca minima, evita martelar a API
type
  TFrmConfigSincroniaAutomatica = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    chkAtivo: TCheckBox;
    lblIntervalo: TLabel;
    edtIntervalo: TEdit;
    lblSegundos: TLabel;
    pnlRodape: TPanel;
    CmdSalvar: TBitBtn;
    CmdCancelar: TBitBtn;
    procedure FormCreate(Sender: TObject);
    procedure CmdSalvarClick(Sender: TObject);
    procedure CmdCancelarClick(Sender: TObject);
  public
    // Caminho do SAT.INI - por padrao, ao lado do executavel (mesmo padrao
    // ja usado no resto do projeto). Se o ConfiguracaoLocal ja expuser o
    // caminho certo em algum lugar, pode trocar essa funcao pra reaproveitar.
    class function CaminhoSATIni: string;
    // Le a config atual do SAT.INI - AAtivo e ATempoSegundos recebem os
    // valores gravados (ou os padroes: desativado, 120s, se o arquivo/chave
    // nao existir ainda).
    class procedure LerConfig(out AAtivo: Boolean; out ATempoSegundos: Integer);
    class procedure GravarConfig(const AAtivo: Boolean; const ATempoSegundos: Integer);
    // Abre o modal - devolve True se o usuario salvou (AAtivo/ATempoSegundos
    // ja saem atualizados com o que foi salvo). False se cancelou.
    class function Configurar(out AAtivo: Boolean; out ATempoSegundos: Integer): Boolean;
  end;
implementation
{$R *.dfm}
{ TFrmConfigSincroniaAutomatica }
class function TFrmConfigSincroniaAutomatica.CaminhoSATIni: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'SAT.INI');
end;
class procedure TFrmConfigSincroniaAutomatica.LerConfig(out AAtivo: Boolean;
  out ATempoSegundos: Integer);
var
  Ini: TIniFile;
begin
  AAtivo := False;
  ATempoSegundos := 120;
  if not FileExists(CaminhoSATIni) then
    Exit;
  Ini := TIniFile.Create(CaminhoSATIni);
  try
    AAtivo := Ini.ReadInteger(SAT_INI_SECAO_TERMINAL, SAT_INI_CHAVE_ATIVO, 0) = 1;
    ATempoSegundos := Ini.ReadInteger(SAT_INI_SECAO_TERMINAL, SAT_INI_CHAVE_TEMPO, 120);
  finally
    Ini.Free;
  end;
  if ATempoSegundos < SAT_INI_TEMPO_MINIMO_SEGUNDOS then
    ATempoSegundos := SAT_INI_TEMPO_MINIMO_SEGUNDOS;
end;
class procedure TFrmConfigSincroniaAutomatica.GravarConfig(const AAtivo: Boolean;
  const ATempoSegundos: Integer);
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(CaminhoSATIni);
  try
    if AAtivo then
      Ini.WriteInteger(SAT_INI_SECAO_TERMINAL, SAT_INI_CHAVE_ATIVO, 1)
    else
      Ini.WriteInteger(SAT_INI_SECAO_TERMINAL, SAT_INI_CHAVE_ATIVO, 0);
    Ini.WriteInteger(SAT_INI_SECAO_TERMINAL, SAT_INI_CHAVE_TEMPO, ATempoSegundos);
  finally
    Ini.Free;
  end;
end;
class function TFrmConfigSincroniaAutomatica.Configurar(out AAtivo: Boolean;
  out ATempoSegundos: Integer): Boolean;
var
  Frm: TFrmConfigSincroniaAutomatica;
  AtivoAtual: Boolean;
  TempoAtual: Integer;
begin
  LerConfig(AtivoAtual, TempoAtual);
  Frm := TFrmConfigSincroniaAutomatica.Create(Application);
  try
    Frm.chkAtivo.Checked := AtivoAtual;
    Frm.edtIntervalo.Text := IntToStr(TempoAtual);
    if Frm.ShowModal = mrOk then
    begin
      AAtivo := Frm.chkAtivo.Checked;
      ATempoSegundos := StrToIntDef(Frm.edtIntervalo.Text, 120);
      if ATempoSegundos < SAT_INI_TEMPO_MINIMO_SEGUNDOS then
        ATempoSegundos := SAT_INI_TEMPO_MINIMO_SEGUNDOS;
      GravarConfig(AAtivo, ATempoSegundos);
      Result := True;
    end
    else
      Result := False;
  finally
    Frm.Free;
  end;
end;
procedure TFrmConfigSincroniaAutomatica.FormCreate(Sender: TObject);
begin
  // nada a fazer aqui - os valores sao preenchidos pelo Configurar antes do ShowModal
end;
procedure TFrmConfigSincroniaAutomatica.CmdSalvarClick(Sender: TObject);
var
  Tempo: Integer;
begin
  if chkAtivo.Checked then
  begin
    if not TryStrToInt(edtIntervalo.Text, Tempo) or (Tempo <= 0) then
    begin
      ShowMessage('Informe um intervalo válido, em segundos (número inteiro maior que zero).');
      edtIntervalo.SetFocus;
      Exit;
    end;
    if Tempo < SAT_INI_TEMPO_MINIMO_SEGUNDOS then
    begin
      ShowMessage(Format('O intervalo mínimo é de %d segundos, para evitar sobrecarregar a API.',
        [SAT_INI_TEMPO_MINIMO_SEGUNDOS]));
      edtIntervalo.SetFocus;
      Exit;
    end;
  end;
  ModalResult := mrOk;
end;
procedure TFrmConfigSincroniaAutomatica.CmdCancelarClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;
end.
