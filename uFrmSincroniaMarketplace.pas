// ============================================================================
// UNIT: uFrmSincroniaMarketplace
// PROJETO: SAT Sincronia Marketplace (executavel proprio, chamado pelo ERP
// principal do cliente - assim como o SATSincronia hoje).
//
// OBJETIVO: Reune, num unico executavel enxuto (sem as dependencias de NFe/
// certificado digital/impressao fiscal que o SATSincronia original carrega),
// a sincronia de produtos entre a loja conectada a um marketplace e a tabela
// local PRODUTOS_MARKETPLACE.
//
// BOTOES:
//   F2 - Envia Dados      -> envia pro marketplace o estoque dos produtos
//                            marcados com ALTERA_MARKETPLACE = 'S' (baixa
//                            de estoque do fisico -> virtual). Implementado
//                            para Shopee, Amazon, Magalu, Mercado Livre e
//                            TikTok Shop.
//                            Roda tambem por timer (sincronia automatica).
//   F3 - Receber Dados    -> busca os produtos cadastrados no marketplace da
//                            loja conectada e grava em PRODUTOS_MARKETPLACE
//                            (CODPRODUTO fica em branco - vinculo com o
//                            produto fisico e feito depois, na tela de
//                            Produtos do ERP principal).
//
// PADRAO VISUAL/ESTRUTURAL: mesmo estilo do SincroniaDePedidos.pas original
// (TrayIcon, minimizar ao inves de fechar, instancia unica com restaurar via
// mensagem de janela, MainMenu) - so que reconstruido do zero, enxuto.
//
// LOJA: agora selecionavel na propria tela (combo no topo), nao mais fixa -
// so os marketplaces/botoes ficam disponiveis depois que uma loja e'
// escolhida no combo.
// ============================================================================
unit uFrmSincroniaMarketplace;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.StrUtils, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.Menus,
  Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Param,
  DMZ, SATFuncoesBD, SATConstantes, SATVariaveis, ConfiguracaoLocal, Funcoes,
  SATFuncoes,
  uMarketplace, Shopee.OpenAPI.Client, Amazon.SPAPI.Client, Magalu.OpenAPI.Client,
  MercadoLivre.OpenAPI.Client, TikTokShop.OpenAPI.Client,
  uFrmPedidosMarketplace, uFrmOfertasMarketplace, uFrmConfigSincroniaAutomatica;
type
  TFrmSincroniaMarketplace = class(TForm)
    TrayIcon: TTrayIcon;
    TrayPopup: TPopupMenu;
    miExibir: TMenuItem;
    N1: TMenuItem;
    miSair: TMenuItem;
    MainMenu1: TMainMenu;
    mnuOpcoes: TMenuItem;
    mnuMinimizar: TMenuItem;
    mnuSair: TMenuItem;
    mnuSincronizar: TMenuItem;
    mnuReceberOfertas: TMenuItem;
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    lblLojaConectada: TLabel;
    lblSelecioneLoja: TLabel;
    cbxLoja: TComboBox;
    pnlLeft: TPanel;
    CmdEnviarDados: TBitBtn;
    CmdReceberDados: TBitBtn;
    CmdPedidos: TBitBtn;
    CmdConfigSincroniaAutomatica: TBitBtn;
    pnlPrincipal: TPanel;
    MemoLog: TMemo;
    lblCompilacao: TLabel;
    TmrSincroniaAutomatica: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TrayIconDblClick(Sender: TObject);
    procedure miExibirClick(Sender: TObject);
    procedure miSairClick(Sender: TObject);
    procedure mnuMinimizarClick(Sender: TObject);
    procedure mnuSairClick(Sender: TObject);
    procedure mnuReceberOfertasClick(Sender: TObject);
    procedure CmdEnviarDadosClick(Sender: TObject);
    procedure CmdReceberDadosClick(Sender: TObject);
    procedure CmdPedidosClick(Sender: TObject);
    procedure CmdConfigSincroniaAutomaticaClick(Sender: TObject);
    procedure cbxLojaChange(Sender: TObject);
    procedure TmrSincroniaAutomaticaTimer(Sender: TObject);
  private
    bFechandoSistema: Boolean;
    FLojaSelecionada: Integer; // 0 = nenhuma loja selecionada ainda
    FCodMarketplace: Integer;
    FTokenDecriptado: string;
    FRefreshTokenDecriptado: string;
    // Validade do access token (MARKETPLACE_BD, texto puro - nao e' sensivel).
    FTokenExpiraEm: TDateTime;
    FAccountIDDecriptado: string;
    // Credenciais de desenvolvedor da loja (agora vem do banco, nao mais de
    // .ini) - lidas em AtualizarStatusConexao, ja escolhendo o par certo
    // (Producao/Homologacao) conforme MARKETPLACE_SANDBOX.
    FDevClientId: string;
    FDevClientSecret: string;
    FDevAppId: string;       // Amazon: Application ID | TikTok: service_id
    FSandbox: Boolean;
    // Sincronia automatica do F2 (Enviar Dados) - configuracao lida do
    // SAT.INI, secao [Terminal] (chaves OnLineSincroniaMarketplaceAutomatica
    // e OnLineSincroniaMarketplaceAutomaticaTempo).
    FSincronizandoAutomaticamente: Boolean; // trava reentrancia
    procedure CarregarLojasDisponiveis;
    procedure AtualizarStatusConexao;
    procedure AtualizarEstadoBotoes;
    procedure Log(const AMsg: string);
    function LojaEstaConectada: Boolean;
    // Renova o access token se estiver vencido/perto de vencer e REGRAVA no
    // banco. Chamar antes de cada operacao: o Sincronia fica horas aberto e o
    // token da Amazon vale 1 hora. False = nao foi possivel renovar.
    function GarantirTokenValido: Boolean;
    procedure EnviarEstoqueShopee;
    procedure EnviarEstoqueAmazon;
    procedure EnviarEstoqueMagalu;
    procedure EnviarEstoqueMercadoLivre;
    procedure EnviarEstoqueTikTokShop;
    procedure CarregarConfigSincroniaAutomatica;
    procedure AtualizarCaptionBotaoSincroniaAutomatica;
    procedure WMShowSincronia(var Msg: TMessage); message WM_SHOWSINCRONIA;
  public
    procedure Restaurar;
    procedure EsconderJanela;
  end;
var
  FrmSincroniaMarketplace: TFrmSincroniaMarketplace;
implementation
{$R *.dfm}
{ TFrmSincroniaMarketplace }
procedure TFrmSincroniaMarketplace.FormCreate(Sender: TObject);
begin
  bFechandoSistema := False;
  FLojaSelecionada := 0;
  FSincronizandoAutomaticamente := False;
  CarregarLojasDisponiveis;
  AtualizarEstadoBotoes; // comeca tudo travado ate escolher uma loja
  CarregarConfigSincroniaAutomatica;
end;
procedure TFrmSincroniaMarketplace.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
begin
  // Fica residente na bandeja em vez de encerrar ao clicar no X - pensando
  // na sincronia automatica por timer que vamos adicionar mais pra frente
  // (o app precisa continuar rodando em segundo plano, sem depender de
  // acao manual do usuario pra enviar/receber ofertas). So sai de fato
  // pelo menu "Opcoes > Sair" (bFechandoSistema = True).
  if not bFechandoSistema then
  begin
    CanClose := False;
    Hide;
  end;
end;
procedure TFrmSincroniaMarketplace.TrayIconDblClick(Sender: TObject);
begin
  Restaurar;
end;
procedure TFrmSincroniaMarketplace.miExibirClick(Sender: TObject);
begin
  Restaurar;
end;
procedure TFrmSincroniaMarketplace.miSairClick(Sender: TObject);
begin
  bFechandoSistema := True;
  Close;
end;
procedure TFrmSincroniaMarketplace.mnuMinimizarClick(Sender: TObject);
begin
  EsconderJanela;
end;
procedure TFrmSincroniaMarketplace.mnuSairClick(Sender: TObject);
begin
  bFechandoSistema := True;
  miSairClick(Self);
end;
procedure TFrmSincroniaMarketplace.mnuReceberOfertasClick(Sender: TObject);
begin
  CmdReceberDadosClick(Self);
end;
procedure TFrmSincroniaMarketplace.WMShowSincronia(var Msg: TMessage);
begin
  Restaurar;
end;
procedure TFrmSincroniaMarketplace.Restaurar;
begin
  Application.ProcessMessages;
  ShowWindow(Application.Handle, SW_RESTORE);
  ShowWindow(Application.Handle, SW_SHOWNORMAL);
  Application.ShowMainForm := True;
  Application.MainForm.Show;
  Application.MainForm.Update;
  WindowState := wsNormal;
  Application.ProcessMessages;
end;
procedure TFrmSincroniaMarketplace.EsconderJanela;
begin
  Application.ShowMainForm := False;
  Application.MainForm.Hide;
  ShowWindow(Application.Handle, SW_HIDE);
  Application.ProcessMessages;
end;
// ----------------------------------------------------------------------------
// Status da conexao / loja
// ----------------------------------------------------------------------------
function TFrmSincroniaMarketplace.LojaEstaConectada: Boolean;
begin
  Result := (FLojaSelecionada <> 0) and (FCodMarketplace <> 0);
end;
procedure TFrmSincroniaMarketplace.CarregarLojasDisponiveis;
var
  Qry: TFDQuery;
begin
  cbxLoja.Items.Clear;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // So lista lojas que ja tem um marketplace definido (MARKETPLACE_COD
    // preenchido) - lojas sem nenhum marketplace vinculado nao tem nada
    // pra essa tela fazer.
    Qry.SQL.Text :=
      'SELECT LOJA, LOJAD FROM LOJAS ' +
      'WHERE MARKETPLACE_COD IS NOT NULL AND MARKETPLACE_COD <> 0 ' +
      'ORDER BY LOJAD';
    Qry.Open;
    while not Qry.Eof do
    begin
      cbxLoja.Items.AddObject(
        Format('%d - %s', [Qry.FieldByName('LOJA').AsInteger, Qry.FieldByName('LOJAD').AsString]),
        TObject(NativeInt(Qry.FieldByName('LOJA').AsInteger)));
      Qry.Next;
    end;
  finally
    Qry.Free;
  end;
  if cbxLoja.Items.Count = 0 then
    lblLojaConectada.Caption := 'Nenhuma loja com marketplace conectado foi encontrada.'
  else
    lblLojaConectada.Caption := 'Selecione uma loja acima para continuar.';
end;
procedure TFrmSincroniaMarketplace.cbxLojaChange(Sender: TObject);
begin
  if cbxLoja.ItemIndex < 0 then
  begin
    FLojaSelecionada := 0;
    lblLojaConectada.Caption := 'Selecione uma loja acima para continuar.';
  end
  else
    FLojaSelecionada := NativeInt(cbxLoja.Items.Objects[cbxLoja.ItemIndex]);
  AtualizarStatusConexao;
  AtualizarEstadoBotoes;
end;
procedure TFrmSincroniaMarketplace.AtualizarEstadoBotoes;
var
  bHabilitado: Boolean;
begin
  bHabilitado := LojaEstaConectada;
  CmdEnviarDados.Enabled := bHabilitado;
  CmdReceberDados.Enabled := bHabilitado;
  CmdPedidos.Enabled := bHabilitado;
end;
// Renova o access token quando ele esta vencido ou perto de vencer, e REGRAVA
// os valores novos na tabela Lojas.
// {POR QUE ISSO EXISTE} ate 05/10/2026 o Sincronia lia o token do banco e
// usava direto, sem nunca renovar. Como o access token da Amazon vale 1 hora,
// o programa parava de funcionar sozinho depois desse tempo e so' voltava
// quando alguem reconectava a loja no SATLojas. A Shopee mascarou o problema
// por anos, porque o token dela dura dias.
// {ATENCAO} regravar nao e' opcional: Magalu e Mercado Livre devolvem um
// refresh token NOVO a cada renovacao e invalidam o anterior. Se o novo ficar
// so' na memoria, a renovacao seguinte falha e a loja cai de vez.
function TFrmSincroniaMarketplace.GarantirTokenValido: Boolean;
var
  Mkt: TDClassPadraoMarketplaces;
  Renovou: Boolean;
  Erro: string;
  Qry: TFDQuery;
begin
  Result := True;
  Renovou := False;
  Mkt := TDClassPadraoMarketplaces.Create(nil);
  try
    Mkt.oMarketplace.AccountID := FAccountIDDecriptado;
    Mkt.oMarketplace.Token := FTokenDecriptado;
    Mkt.oMarketplace.RefreshToken := FRefreshTokenDecriptado;
    Mkt.oMarketplace.TokenExpiraEm := FTokenExpiraEm;
    Mkt.oMarketplace.ClientId := FDevClientId;
    Mkt.oMarketplace.ClientSecret := FDevClientSecret;
    Mkt.oMarketplace.App := FDevAppId;
    Mkt.oMarketplace.Sandbox := FSandbox;
    Erro := Mkt.RenovarTokenSeNecessario(TMarketplaces(FCodMarketplace), Renovou);
    if Erro <> '' then
    begin
      Log('Falha ao renovar o token: ' + Erro);
      ShowMessage(Erro);
      Result := False;
      Exit;
    end;
    if not Renovou then
      Exit;
    // Renovou - leva os valores novos pra memoria e pro banco.
    FTokenDecriptado := Mkt.oMarketplace.Token;
    FRefreshTokenDecriptado := Mkt.oMarketplace.RefreshToken;
    FTokenExpiraEm := Mkt.oMarketplace.TokenExpiraEm;
    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := DZ.ZDatabase;
      Qry.SQL.Text :=
        'UPDATE LOJAS SET MARKETPLACE_TOKEN = :TOKEN, MARKETPLACE_KEY = :KEY, ' +
        'MARKETPLACE_BD = :VALIDADE WHERE LOJA = :LOJA';
      // Mesma criptografia usada pelo SATLojas ao conectar - os dois
      // executaveis precisam gravar igual, senao um nao le o do outro.
      Qry.ParamByName('TOKEN').AsString := Codificar('C', FTokenDecriptado);
      Qry.ParamByName('KEY').AsString := Codificar('C', FRefreshTokenDecriptado);
      Qry.ParamByName('VALIDADE').AsString := DateTimeToStr(FTokenExpiraEm);
      Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
      Qry.ExecSQL;
    finally
      Qry.Free;
    end;
    Log('Token de acesso renovado automaticamente - nova validade: ' +
      DateTimeToStr(FTokenExpiraEm));
  finally
    Mkt.Free;
  end;
end;
procedure TFrmSincroniaMarketplace.AtualizarStatusConexao;
var
  Qry: TFDQuery;
  NomeMkt: string;
begin
  FCodMarketplace := 0;
  if FLojaSelecionada = 0 then
    Exit; // nada selecionado ainda - lblLojaConectada ja foi ajustado por quem chamou
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    Qry.SQL.Text :=
      'SELECT LOJAD, MARKETPLACE_COD, MARKETPLACE_CLIENTID, MARKETPLACE_TOKEN, ' +
      'MARKETPLACE_KEY, MARKETPLACE_SANDBOX, MARKETPLACE_USUARIO, MARKETPLACE_SENHA, ' +
      'MARKETPLACE_BD, ' +
      'MARKETPLACE_APP_DEV_ID, MARKETPLACE_APP_DEV_ID_SANDBOX ' +
      'FROM LOJAS WHERE LOJA = :LOJA';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.Open;
    if Qry.IsEmpty or (Qry.FieldByName('MARKETPLACE_COD').AsInteger = 0) then
    begin
      lblLojaConectada.Caption := 'Essa loja nao esta mais conectada a um marketplace.';
      Exit;
    end;
    FCodMarketplace := Qry.FieldByName('MARKETPLACE_COD').AsInteger;
    // Campos sensiveis foram gravados criptografados (Codificar('C', ...))
    // pela tela de Lojas do SATLojas - precisa descriptografar antes de usar.
    FAccountIDDecriptado := Codificar('D', Qry.FieldByName('MARKETPLACE_CLIENTID').AsString);
    FTokenDecriptado := Codificar('D', Qry.FieldByName('MARKETPLACE_TOKEN').AsString);
    FRefreshTokenDecriptado := Codificar('D', Qry.FieldByName('MARKETPLACE_KEY').AsString);
    // Gravado como texto por DateTimeToStr - 0 quando a loja foi conectada por
    // uma versao antiga, que ainda nao guardava a validade.
    FTokenExpiraEm := StrToDateTimeDef(Qry.FieldByName('MARKETPLACE_BD').AsString, 0);
    // Credenciais de desenvolvedor - a pedido do cliente, agora usam os
    // campos ja existentes MARKETPLACE_USUARIO/MARKETPLACE_SENHA (mesmos
    // campos usados por outros tipos de e-commerce como VTex/Bagy/Tray) em
    // vez de campos dedicados. NAO ha mais separacao Producao/Homologacao -
    // e' o MESMO valor pros dois ambientes.
    // Campo MARKETPLACE_SANDBOX mudou de SmallInt (0/1) pra VARCHAR(1)
    // ('S'/'N') a pedido do cliente.
    FSandbox := Qry.FieldByName('MARKETPLACE_SANDBOX').AsString = 'S';
    // Campos gravados criptografados (Codificar) pela tela de Lojas do
    // SATLojas - precisa descriptografar antes de usar (faltava isso aqui,
    // por isso a Shopee sempre recusava com "Wrong sign": estava mandando
    // o valor criptografado cru como se fosse a credencial real).
    FDevClientId := Codificar('D', Qry.FieldByName('MARKETPLACE_USUARIO').AsString);
    FDevClientSecret := Codificar('D', Qry.FieldByName('MARKETPLACE_SENHA').AsString);
    // O Application ID da Amazon CONTINUA separado por ambiente (uso
    // exclusivo da Amazon, nao mudou).
    if FSandbox then
      FDevAppId := Qry.FieldByName('MARKETPLACE_APP_DEV_ID_SANDBOX').AsString
    else
      FDevAppId := Qry.FieldByName('MARKETPLACE_APP_DEV_ID').AsString;
    NomeMkt := NomeMarketplace(TMarketplaces(FCodMarketplace));
    lblLojaConectada.Caption := Format('Loja %d - %s  |  Conectado a: %s (ID: %s)%s',
      [FLojaSelecionada, Qry.FieldByName('LOJAD').AsString, NomeMkt, FAccountIDDecriptado,
       IfThen(FSandbox, ' [Homologacao]', '')]);
  finally
    Qry.Free;
  end;
end;
procedure TFrmSincroniaMarketplace.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;
// ----------------------------------------------------------------------------
// F2 - Envia Dados (fisico -> virtual, so estoque por enquanto)
// ----------------------------------------------------------------------------
procedure TFrmSincroniaMarketplace.CmdEnviarDadosClick(Sender: TObject);
begin
  AtualizarStatusConexao; // reconfirma antes de cada execucao, nao so no startup
  if not LojaEstaConectada then
  begin
    ShowMessage('Nenhuma loja conectada a um marketplace no momento.' + sLineBreak +
      sLineBreak +
      'Conecte uma loja no SATLojas (Cadastro de Lojas, aba Marketplaces) ' +
      'antes de enviar dados.');
    Exit;
  end;
  // Token pode ter vencido desde a ultima operacao - renova e regrava antes
  // de chamar a API, senao a resposta vem 403 com o token invalido.
  if not GarantirTokenValido then
    Exit;
  case TMarketplaces(FCodMarketplace) of
    TMarketplaces.Shopee: EnviarEstoqueShopee;
    TMarketplaces.Amazon: EnviarEstoqueAmazon;
    TMarketplaces.Magalu: EnviarEstoqueMagalu;
    TMarketplaces.MercadoLivre: EnviarEstoqueMercadoLivre;
    TMarketplaces.TikTokShop: EnviarEstoqueTikTokShop;
  else
    Log('Envio de dados ainda nao implementado para este marketplace.');
  end;
end;
procedure TFrmSincroniaMarketplace.EnviarEstoqueShopee;
var
  Qry, QryAux: TFDQuery;
  Cliente: TShopeeOpenAPIClient;
  ErroMsg, ItemID: string;
  CodProduto, Estoque: Integer;
  iSucesso, iFalha: Integer;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Shopee nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  Log('Buscando produtos com alteracao pendente (ALTERA_MARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // P.LOJA aqui e' sempre a loja FISICA de entrega (sempre 1, regra de
    // negocio confirmada) - achada via LOJAS.CODLOJAENTREGA. O parametro
    // :LOJA (FLojaSelecionada) e' a loja CONECTADA ao marketplace (mesmo
    // valor usado em todo o resto do sistema - Ofertas, Vincular Produto,
    // etc.), tanto pra achar qual LOJAS.CODIGO aponta pra essa loja fisica,
    // quanto pra filtrar PRODUTOS_MARKETPLACE.LOJA (que sempre guarda a
    // loja conectada, nunca a fisica).
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.ALTERA_MARKETPLACE = ''S'' ' +
      'AND EXISTS (SELECT 1 FROM LOJAS L ' +
        'WHERE L.CODLOJAENTREGA = 1 ' +
        'AND L.CODLOJAENTREGA = P.LOJA ' +
        'AND L.LOJA = :LOJA) ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND PM.ATUALIZAR_ESTOQUE_MARKETPLACE = ''S'')';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      Log('Nenhum produto com alteracao pendente no momento.');
      Exit;
    end;
    Log(Format('%d produto(s) com alteracao pendente.', [Qry.RecordCount]));
    QryAux.Connection := DZ.ZDatabase;
    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),
      FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      iSucesso := 0;
      iFalha := 0;
      while not Qry.Eof do
      begin
        CodProduto := Qry.FieldByName('COD').AsInteger;
        Estoque := Qry.FieldByName('QUANT').AsInteger;
        // Busca o item_id da Shopee vinculado a esse produto fisico.
        QryAux.Close;
        QryAux.SQL.Text :=
          'SELECT CODPRODUTONOMARKETPLACE FROM PRODUTOS_MARKETPLACE ' +
          'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
        QryAux.ParamByName('COD').AsInteger := CodProduto;
        QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
        QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
        QryAux.Open;
        if QryAux.IsEmpty then
        begin
          Log('  Produto ' + IntToStr(CodProduto) + ': vinculo nao encontrado - pulando.');
          Inc(iFalha);
        end
        else
        begin
          ItemID := QryAux.FieldByName('CODPRODUTONOMARKETPLACE').AsString;
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE primeiro.
          QryAux.SQL.Text :=
            'UPDATE PRODUTOS_MARKETPLACE SET ESTOQUE = :ESTOQUE, ' +
            'DATAULTIMAALTERACAO = :DATA ' +
            'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
          QryAux.ParamByName('ESTOQUE').AsInteger := Estoque;
          QryAux.ParamByName('DATA').AsDateTime := Now;
          QryAux.ParamByName('COD').AsInteger := CodProduto;
          QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
          QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
          QryAux.ExecSQL;
          // 2) Chama a API da Shopee pra atualizar de verdade.
          // {TODO} AModelID fixo em 0 (item sem variacao) - produtos COM
          // variacao (cor/tamanho) precisam de um model_id especifico, que
          // ainda nao guardamos em PRODUTOS_MARKETPLACE. Se o cliente vender
          // produto com variacao, essa parte precisa ser expandida.
          if Cliente.UpdateStock(FTokenDecriptado, StrToInt64Def(FAccountIDDecriptado, 0),
               StrToInt64Def(ItemID, 0), 0, Estoque, ErroMsg) then
          begin
            Inc(iSucesso);
            // 3) So' limpa a flag do PRO depois de confirmado o envio - assim,
            // se a chamada falhar, o produto continua marcado e sera
            // reprocessado na proxima execucao do F2.
            // {DECISAO DO CLIENTE - 07/09/2026} o ATUALIZAR_ESTOQUE_MARKETPLACE
            // do PRODUTOS_MARKETPLACE NAO e' mais limpo aqui. Ele deixou de ser
            // "tem envio pendente" e passou a ser "este produto participa do
            // sincronismo de estoque", entao fica sempre 'S'. Quem diz o que esta
            // pendente e' o PRO.ALTERA_MARKETPLACE, que e' por loja.
            QryAux.Close;
            QryAux.SQL.Text :=
              'UPDATE PRO SET ALTERA_MARKETPLACE = ''N'' WHERE COD = :COD AND LOJA = :LOJA';
            QryAux.ParamByName('COD').AsInteger := CodProduto;
            QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
            QryAux.ExecSQL;
          end
          else
          begin
            Log('  Falha ao atualizar estoque na Shopee (produto ' +
              IntToStr(CodProduto) + '): ' + ErroMsg);
            Inc(iFalha);
          end;
        end;
        Qry.Next;
      end;
      Log(Format('Concluido: %d sucesso(s), %d falha(s).', [iSucesso, iFalha]));
    finally
      Cliente.Free;
    end;
  finally
    Qry.Free;
    QryAux.Free;
  end;
end;
procedure TFrmSincroniaMarketplace.EnviarEstoqueAmazon;
var
  Qry, QryAux: TFDQuery;
  Cliente: TAmazonSPAPIClient;
  ErroMsg, RespostaJSON, Sku: string;
  CodProduto, Estoque: Integer;
  iSucesso, iFalha: Integer;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Amazon nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  Log('Buscando produtos com alteracao pendente (ALTERA_MARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de P.LOJA (fisica, sempre 1) x :LOJA
    // (conectada ao marketplace) ja usada em EnviarEstoqueShopee - so
    // muda o metodo que efetivamente chama a API no final.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.ALTERA_MARKETPLACE = ''S'' ' +
      'AND EXISTS (SELECT 1 FROM LOJAS L ' +
        'WHERE L.CODLOJAENTREGA = 1 ' +
        'AND L.CODLOJAENTREGA = P.LOJA ' +
        'AND L.LOJA = :LOJA) ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND PM.ATUALIZAR_ESTOQUE_MARKETPLACE = ''S'')';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      Log('Nenhum produto com alteracao pendente no momento.');
      Exit;
    end;
    Log(Format('%d produto(s) com alteracao pendente.', [Qry.RecordCount]));
    QryAux.Connection := DZ.ZDatabase;
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      iSucesso := 0;
      iFalha := 0;
      while not Qry.Eof do
      begin
        CodProduto := Qry.FieldByName('COD').AsInteger;
        Estoque := Qry.FieldByName('QUANT').AsInteger;
        // Busca o SKU da Amazon vinculado a esse produto fisico.
        QryAux.Close;
        QryAux.SQL.Text :=
          'SELECT CODPRODUTONOMARKETPLACE FROM PRODUTOS_MARKETPLACE ' +
          'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
        QryAux.ParamByName('COD').AsInteger := CodProduto;
        QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
        QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
        QryAux.Open;
        if QryAux.IsEmpty then
        begin
          Log('  Produto ' + IntToStr(CodProduto) + ': vinculo nao encontrado - pulando.');
          Inc(iFalha);
        end
        else
        begin
          Sku := QryAux.FieldByName('CODPRODUTONOMARKETPLACE').AsString;
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE primeiro.
          QryAux.SQL.Text :=
            'UPDATE PRODUTOS_MARKETPLACE SET ESTOQUE = :ESTOQUE, ' +
            'DATAULTIMAALTERACAO = :DATA ' +
            'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
          QryAux.ParamByName('ESTOQUE').AsInteger := Estoque;
          QryAux.ParamByName('DATA').AsDateTime := Now;
          QryAux.ParamByName('COD').AsInteger := CodProduto;
          QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
          QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
          QryAux.ExecSQL;
          // 2) Chama a Amazon SP-API pra atualizar de verdade (descobre o
          // productType real do SKU sozinha antes de montar o PATCH).
          if Cliente.UpdateStockQuantity(FTokenDecriptado, FAccountIDDecriptado, Sku,
               Estoque, RespostaJSON, ErroMsg) then
          begin
            Inc(iSucesso);
            // 3) So' limpa a flag do PRO depois de confirmado o envio - assim,
            // se a chamada falhar, o produto continua marcado e sera
            // reprocessado na proxima execucao do F2.
            // {DECISAO DO CLIENTE - 07/09/2026} o ATUALIZAR_ESTOQUE_MARKETPLACE
            // do PRODUTOS_MARKETPLACE NAO e' mais limpo aqui. Ele deixou de ser
            // "tem envio pendente" e passou a ser "este produto participa do
            // sincronismo de estoque", entao fica sempre 'S'. Quem diz o que esta
            // pendente e' o PRO.ALTERA_MARKETPLACE, que e' por loja.
            QryAux.Close;
            QryAux.SQL.Text :=
              'UPDATE PRO SET ALTERA_MARKETPLACE = ''N'' WHERE COD = :COD AND LOJA = :LOJA';
            QryAux.ParamByName('COD').AsInteger := CodProduto;
            QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
            QryAux.ExecSQL;
          end
          else
          begin
            Log('  Falha ao atualizar estoque na Amazon (produto ' +
              IntToStr(CodProduto) + '): ' + ErroMsg);
            Inc(iFalha);
          end;
        end;
        Qry.Next;
      end;
      Log(Format('Concluido: %d sucesso(s), %d falha(s).', [iSucesso, iFalha]));
    finally
      Cliente.Free;
    end;
  finally
    Qry.Free;
    QryAux.Free;
  end;
end;
procedure TFrmSincroniaMarketplace.EnviarEstoqueMagalu;
var
  Qry, QryAux: TFDQuery;
  Cliente: TMagaluOpenAPIClient;
  ErroMsg, Sku: string;
  CodProduto, Estoque: Integer;
  iSucesso, iFalha: Integer;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor do Magalu nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  // {ATENCAO} O endpoint de UpdateStock (Magalu.OpenAPI.Client) ainda NAO
  // foi confirmado com uma chamada real (ver comentario no topo daquele
  // arquivo) - so vamos saber se o path "/v1/portfolio/stocks" esta certo
  // quando testarmos com um vendedor real autorizado.
  //
  // {ATENCAO} O refresh_token do Magalu SO PODE SER USADO UMA VEZ - se em
  // algum momento essa tela passar a renovar o token automaticamente
  // aqui dentro (hoje nao renova, so usa FTokenDecriptado direto), tem
  // que gravar o NOVO refresh_token de volta em MARKETPLACE_KEY
  // imediatamente, senao a proxima renovacao invalida a sessao.
  Log('Buscando produtos com alteracao pendente (ALTERA_MARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de P.LOJA (fisica, sempre 1) x :LOJA
    // (conectada ao marketplace) ja usada em EnviarEstoqueShopee/Amazon -
    // so muda o metodo que efetivamente chama a API no final.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.ALTERA_MARKETPLACE = ''S'' ' +
      'AND EXISTS (SELECT 1 FROM LOJAS L ' +
        'WHERE L.CODLOJAENTREGA = 1 ' +
        'AND L.CODLOJAENTREGA = P.LOJA ' +
        'AND L.LOJA = :LOJA) ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND PM.ATUALIZAR_ESTOQUE_MARKETPLACE = ''S'')';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      Log('Nenhum produto com alteracao pendente no momento.');
      Exit;
    end;
    Log(Format('%d produto(s) com alteracao pendente.', [Qry.RecordCount]));
    QryAux.Connection := DZ.ZDatabase;
    // FAccountIDDecriptado guarda o Tenant ID pro Magalu (mesmo campo
    // generico MARKETPLACE_CLIENTID usado por todos os marketplaces - ver
    // AtualizarStatusConexao e a tela de Cadastro de Lojas do SATLojas).
    Cliente := TMagaluOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', '', FSandbox);
    Cliente.OnLog := Log;
    try
      iSucesso := 0;
      iFalha := 0;
      while not Qry.Eof do
      begin
        CodProduto := Qry.FieldByName('COD').AsInteger;
        Estoque := Qry.FieldByName('QUANT').AsInteger;
        // Busca o SKU do Magalu vinculado a esse produto fisico.
        QryAux.Close;
        QryAux.SQL.Text :=
          'SELECT CODPRODUTONOMARKETPLACE FROM PRODUTOS_MARKETPLACE ' +
          'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
        QryAux.ParamByName('COD').AsInteger := CodProduto;
        QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
        QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
        QryAux.Open;
        if QryAux.IsEmpty then
        begin
          Log('  Produto ' + IntToStr(CodProduto) + ': vinculo nao encontrado - pulando.');
          Inc(iFalha);
        end
        else
        begin
          Sku := QryAux.FieldByName('CODPRODUTONOMARKETPLACE').AsString;
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE primeiro.
          QryAux.SQL.Text :=
            'UPDATE PRODUTOS_MARKETPLACE SET ESTOQUE = :ESTOQUE, ' +
            'DATAULTIMAALTERACAO = :DATA ' +
            'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
          QryAux.ParamByName('ESTOQUE').AsInteger := Estoque;
          QryAux.ParamByName('DATA').AsDateTime := Now;
          QryAux.ParamByName('COD').AsInteger := CodProduto;
          QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
          QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
          QryAux.ExecSQL;
          // 2) Chama a API do Magalu pra atualizar de verdade.
          if Cliente.UpdateStock(FTokenDecriptado, FAccountIDDecriptado, Sku,
               Estoque, ErroMsg) then
          begin
            Inc(iSucesso);
            // 3) So' limpa a flag do PRO depois de confirmado o envio - assim,
            // se a chamada falhar, o produto continua marcado e sera
            // reprocessado na proxima execucao do F2.
            // {DECISAO DO CLIENTE - 07/09/2026} o ATUALIZAR_ESTOQUE_MARKETPLACE
            // do PRODUTOS_MARKETPLACE NAO e' mais limpo aqui. Ele deixou de ser
            // "tem envio pendente" e passou a ser "este produto participa do
            // sincronismo de estoque", entao fica sempre 'S'. Quem diz o que esta
            // pendente e' o PRO.ALTERA_MARKETPLACE, que e' por loja.
            QryAux.Close;
            QryAux.SQL.Text :=
              'UPDATE PRO SET ALTERA_MARKETPLACE = ''N'' WHERE COD = :COD AND LOJA = :LOJA';
            QryAux.ParamByName('COD').AsInteger := CodProduto;
            QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
            QryAux.ExecSQL;
          end
          else
          begin
            Log('  Falha ao atualizar estoque no Magalu (produto ' +
              IntToStr(CodProduto) + '): ' + ErroMsg);
            Inc(iFalha);
          end;
        end;
        Qry.Next;
      end;
      Log(Format('Concluido: %d sucesso(s), %d falha(s).', [iSucesso, iFalha]));
    finally
      Cliente.Free;
    end;
  finally
    Qry.Free;
    QryAux.Free;
  end;
end;
procedure TFrmSincroniaMarketplace.EnviarEstoqueMercadoLivre;
var
  Qry, QryAux: TFDQuery;
  Cliente: TMercadoLivreOpenAPIClient;
  ErroMsg, ItemID: string;
  CodProduto, Estoque: Integer;
  iSucesso, iFalha: Integer;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor do Mercado Livre nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  // {ATENCAO} UpdateStock usa o caminho "classico" do ML (PUT /items/{id}
  // com available_quantity) - vendedor que use "Full" ou "Estoque
  // Distribuido/Flex" gerencia estoque por deposito, num fluxo diferente
  // (user_product_id) que esse metodo NAO cobre. Ver o comentario do
  // metodo em MercadoLivre.OpenAPI.Client - revisar quando tivermos um
  // vendedor real testando.
  //
  // {ATENCAO} Diferente da Shopee (que precisa de item_id + model_id), o
  // ML trata cada variacao como uma variation dentro do mesmo item. Aqui
  // atualizamos o estoque do ITEM inteiro - se o cliente vender produto
  // com variacao, isso precisa crescer pra mexer em variations[], igual a
  // pendencia ja anotada no EnviarEstoqueShopee.
  Log('Buscando produtos com alteracao pendente (ALTERA_MARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de P.LOJA (fisica, sempre 1) x :LOJA
    // (conectada ao marketplace) ja usada em EnviarEstoqueShopee/Amazon/
    // Magalu - so muda o metodo que efetivamente chama a API no final.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.ALTERA_MARKETPLACE = ''S'' ' +
      'AND EXISTS (SELECT 1 FROM LOJAS L ' +
        'WHERE L.CODLOJAENTREGA = 1 ' +
        'AND L.CODLOJAENTREGA = P.LOJA ' +
        'AND L.LOJA = :LOJA) ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND PM.ATUALIZAR_ESTOQUE_MARKETPLACE = ''S'')';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      Log('Nenhum produto com alteracao pendente no momento.');
      Exit;
    end;
    Log(Format('%d produto(s) com alteracao pendente.', [Qry.RecordCount]));
    QryAux.Connection := DZ.ZDatabase;
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      iSucesso := 0;
      iFalha := 0;
      while not Qry.Eof do
      begin
        CodProduto := Qry.FieldByName('COD').AsInteger;
        Estoque := Qry.FieldByName('QUANT').AsInteger;
        // Busca o item_id (MLB...) do Mercado Livre vinculado a esse
        // produto fisico.
        QryAux.Close;
        QryAux.SQL.Text :=
          'SELECT CODPRODUTONOMARKETPLACE FROM PRODUTOS_MARKETPLACE ' +
          'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
        QryAux.ParamByName('COD').AsInteger := CodProduto;
        QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
        QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
        QryAux.Open;
        if QryAux.IsEmpty then
        begin
          Log('  Produto ' + IntToStr(CodProduto) + ': vinculo nao encontrado - pulando.');
          Inc(iFalha);
        end
        else
        begin
          ItemID := QryAux.FieldByName('CODPRODUTONOMARKETPLACE').AsString;
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE primeiro.
          QryAux.SQL.Text :=
            'UPDATE PRODUTOS_MARKETPLACE SET ESTOQUE = :ESTOQUE, ' +
            'DATAULTIMAALTERACAO = :DATA ' +
            'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
          QryAux.ParamByName('ESTOQUE').AsInteger := Estoque;
          QryAux.ParamByName('DATA').AsDateTime := Now;
          QryAux.ParamByName('COD').AsInteger := CodProduto;
          QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
          QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
          QryAux.ExecSQL;
          // 2) Chama a API do Mercado Livre pra atualizar de verdade.
          if Cliente.UpdateStock(FTokenDecriptado, ItemID, Estoque, ErroMsg) then
          begin
            Inc(iSucesso);
            // 3) So' limpa a flag do PRO depois de confirmado o envio - assim,
            // se a chamada falhar, o produto continua marcado e sera
            // reprocessado na proxima execucao do F2.
            // {DECISAO DO CLIENTE - 07/09/2026} o ATUALIZAR_ESTOQUE_MARKETPLACE
            // do PRODUTOS_MARKETPLACE NAO e' mais limpo aqui. Ele deixou de ser
            // "tem envio pendente" e passou a ser "este produto participa do
            // sincronismo de estoque", entao fica sempre 'S'. Quem diz o que esta
            // pendente e' o PRO.ALTERA_MARKETPLACE, que e' por loja.
            QryAux.Close;
            QryAux.SQL.Text :=
              'UPDATE PRO SET ALTERA_MARKETPLACE = ''N'' WHERE COD = :COD AND LOJA = :LOJA';
            QryAux.ParamByName('COD').AsInteger := CodProduto;
            QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
            QryAux.ExecSQL;
          end
          else
          begin
            Log('  Falha ao atualizar estoque no Mercado Livre (produto ' +
              IntToStr(CodProduto) + '): ' + ErroMsg);
            Inc(iFalha);
          end;
        end;
        Qry.Next;
      end;
      Log(Format('Concluido: %d sucesso(s), %d falha(s).', [iSucesso, iFalha]));
    finally
      Cliente.Free;
    end;
  finally
    Qry.Free;
    QryAux.Free;
  end;
end;
procedure TFrmSincroniaMarketplace.EnviarEstoqueTikTokShop;
var
  Qry, QryAux: TFDQuery;
  Cliente: TTikTokShopOpenAPIClient;
  Depositos: TTikTokShopWarehouseArray;
  ErroMsg, ChaveTikTok, ProductId, SkuId, ShopId, ShopCipher, WarehouseId: string;
  CodProduto, Estoque, I: Integer;
  iSucesso, iFalha: Integer;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor do TikTok Shop nao cadastradas para esta ' +
      'loja/ambiente (app_key/app_secret em MARKETPLACE_USUARIO/MARKETPLACE_SENHA).');
    Exit;
  end;
  // O TikTok identifica a loja pelo shop_cipher, nao pelo shop_id - os dois
  // ficam gravados juntos em MARKETPLACE_CLIENTID (ver uMarketplace).
  SepararShopIdECipherTikTok(FAccountIDDecriptado, ShopId, ShopCipher);
  if ShopCipher = '' then
  begin
    Log('Vinculo do TikTok incompleto: falta o shop_cipher. Desconecte e conecte ' +
      'a loja novamente no SATLojas.');
    Exit;
  end;
  Log('Buscando produtos com alteracao pendente (ALTERA_MARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de P.LOJA (fisica, sempre 1) x :LOJA
    // (conectada ao marketplace) usada pelos outros quatro.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.ALTERA_MARKETPLACE = ''S'' ' +
      'AND EXISTS (SELECT 1 FROM LOJAS L ' +
        'WHERE L.CODLOJAENTREGA = 1 ' +
        'AND (P.LOJA = L.LOJA OR P.LOJA = L.CODLOJAENTREGA)' +
        'AND L.LOJA = :LOJA) ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND PM.ATUALIZAR_ESTOQUE_MARKETPLACE = ''S'')';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      Log('Nenhum produto com alteracao pendente no momento.');
      Exit;
    end;
    Log(Format('%d produto(s) com alteracao pendente.', [Qry.RecordCount]));
    QryAux.Connection := DZ.ZDatabase;
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      FDevAppId, FSandbox);
    Cliente.OnLog := Log;
    try
      // {ATENCAO} o TikTok NAO tem "deposito padrao": o update de estoque
      // exige warehouse_id. Busca os depositos UMA vez, antes do laco, e usa
      // o primeiro de venda - loja com mais de um deposito de venda vai
      // precisar de escolha por produto, o que fica pra quando aparecer.
      WarehouseId := '';
      if Cliente.GetWarehouses(FTokenDecriptado, ShopCipher, Depositos, ErroMsg) then
      begin
        for I := Low(Depositos) to High(Depositos) do
          if SameText(Depositos[I].Tipo, 'SALES_WAREHOUSE') then
          begin
            WarehouseId := Depositos[I].Id;
            Log('Deposito de venda: ' + Depositos[I].Nome + ' (' + WarehouseId + ')');
            Break;
          end;
        // Nenhum marcado como SALES_WAREHOUSE: cai pro primeiro da lista, em
        // vez de abortar - o nome do tipo pode variar por regiao.
        if (WarehouseId = '') and (Length(Depositos) > 0) then
        begin
          WarehouseId := Depositos[0].Id;
          Log('Aviso: nenhum deposito marcado como SALES_WAREHOUSE - usando o ' +
            'primeiro da lista (' + Depositos[0].Nome + ').');
        end;
      end
      else
        Log('Falha ao listar depositos: ' + ErroMsg);
      if WarehouseId = '' then
      begin
        Log('Sem deposito disponivel - nao da para atualizar estoque no TikTok.');
        Exit;
      end;
      iSucesso := 0;
      iFalha := 0;
      while not Qry.Eof do
      begin
        CodProduto := Qry.FieldByName('COD').AsInteger;
        Estoque := Qry.FieldByName('QUANT').AsInteger;
        // Busca a chave "product_id|sku_id" vinculada a esse produto fisico.
        QryAux.Close;
        QryAux.SQL.Text :=
          'SELECT CODPRODUTONOMARKETPLACE FROM PRODUTOS_MARKETPLACE ' +
          'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
        QryAux.ParamByName('COD').AsInteger := CodProduto;
        QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
        QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
        QryAux.Open;
        if QryAux.IsEmpty then
        begin
          Log('  Produto ' + IntToStr(CodProduto) + ': vinculo nao encontrado - pulando.');
          Inc(iFalha);
        end
        else
        begin
          ChaveTikTok := QryAux.FieldByName('CODPRODUTONOMARKETPLACE').AsString;
          SepararProdutoESkuTikTok(ChaveTikTok, ProductId, SkuId);
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE primeiro.
          QryAux.SQL.Text :=
            'UPDATE PRODUTOS_MARKETPLACE SET ESTOQUE = :ESTOQUE, ' +
            'DATAULTIMAALTERACAO = :DATA ' +
            'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
          QryAux.ParamByName('ESTOQUE').AsInteger := Estoque;
          QryAux.ParamByName('DATA').AsDateTime := Now;
          QryAux.ParamByName('COD').AsInteger := CodProduto;
          QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
          QryAux.ParamByName('MKT').AsInteger := FCodMarketplace;
          QryAux.ExecSQL;
          // 2) Chama a API do TikTok pra atualizar de verdade.
          if Cliente.UpdateInventory(FTokenDecriptado, ShopCipher, ProductId, SkuId,
               WarehouseId, Estoque, ErroMsg) then
          begin
            Inc(iSucesso);
            // 3) So' limpa a flag do PRO depois de confirmado o envio - assim,
            // se a chamada falhar, o produto continua marcado e sera
            // reprocessado na proxima execucao do F2.
            // {DECISAO DO CLIENTE - 07/09/2026} o ATUALIZAR_ESTOQUE_MARKETPLACE
            // do PRODUTOS_MARKETPLACE NAO e' mais limpo aqui. Ele deixou de ser
            // "tem envio pendente" e passou a ser "este produto participa do
            // sincronismo de estoque", entao fica sempre 'S'. Quem diz o que esta
            // pendente e' o PRO.ALTERA_MARKETPLACE, que e' por loja.
            QryAux.Close;
            QryAux.SQL.Text :=
              'UPDATE PRO SET ALTERA_MARKETPLACE = ''N'' WHERE COD = :COD AND LOJA = :LOJA';
            QryAux.ParamByName('COD').AsInteger := CodProduto;
            QryAux.ParamByName('LOJA').AsInteger := FLojaSelecionada;
            QryAux.ExecSQL;
          end
          else
          begin
            Log('  Falha ao atualizar estoque no TikTok (produto ' +
              IntToStr(CodProduto) + '): ' + ErroMsg);
            Inc(iFalha);
          end;
        end;
        Qry.Next;
      end;
      Log(Format('Concluido: %d sucesso(s), %d falha(s).', [iSucesso, iFalha]));
    finally
      Cliente.Free;
    end;
  finally
    Qry.Free;
    QryAux.Free;
  end;
end;
// ----------------------------------------------------------------------------
// Sincronia automatica do F2 (Enviar Dados) - configurada via SAT.INI,
// secao [Terminal] (OnLineSincroniaMarketplaceAutomatica/Tempo), com opcao
// de ativar/desativar e mudar o intervalo direto pela tela tambem.
// ----------------------------------------------------------------------------
procedure TFrmSincroniaMarketplace.CarregarConfigSincroniaAutomatica;
var
  Ativo: Boolean;
  TempoSegundos: Integer;
begin
  TFrmConfigSincroniaAutomatica.LerConfig(Ativo, TempoSegundos);
  TmrSincroniaAutomatica.Interval := TempoSegundos * 1000;
  TmrSincroniaAutomatica.Enabled := Ativo;
  AtualizarCaptionBotaoSincroniaAutomatica;
  if Ativo then
    Log(Format('Sincronia automatica ATIVADA (a cada %d segundos).', [TempoSegundos]))
  else
    Log('Sincronia automatica desativada.');
end;
procedure TFrmSincroniaMarketplace.AtualizarCaptionBotaoSincroniaAutomatica;
var
  Ativo: Boolean;
  TempoSegundos: Integer;
begin
  TFrmConfigSincroniaAutomatica.LerConfig(Ativo, TempoSegundos);
  if Ativo then
    CmdConfigSincroniaAutomatica.Caption := Format('Auto: ON (%ds)', [TempoSegundos])
  else
    CmdConfigSincroniaAutomatica.Caption := 'Auto: OFF';
end;
procedure TFrmSincroniaMarketplace.CmdConfigSincroniaAutomaticaClick(Sender: TObject);
var
  Ativo: Boolean;
  TempoSegundos: Integer;
begin
  if TFrmConfigSincroniaAutomatica.Configurar(Ativo, TempoSegundos) then
  begin
    // Aplica na hora - nao precisa reiniciar o programa pra pegar a mudanca.
    TmrSincroniaAutomatica.Interval := TempoSegundos * 1000;
    TmrSincroniaAutomatica.Enabled := Ativo;
    AtualizarCaptionBotaoSincroniaAutomatica;
    if Ativo then
      Log(Format('Sincronia automatica ATIVADA (a cada %d segundos).', [TempoSegundos]))
    else
      Log('Sincronia automatica DESATIVADA.');
  end;
end;
procedure TFrmSincroniaMarketplace.TmrSincroniaAutomaticaTimer(Sender: TObject);
begin
  // Trava reentrancia - se uma sincronia anterior ainda estiver rodando
  // (ex: demorou mais que o intervalo configurado), nao inicia outra em cima.
  if FSincronizandoAutomaticamente then
    Exit;
  // Sem loja selecionada ainda, nao ha' o que sincronizar.
  if FLojaSelecionada = 0 then
    Exit;
  FSincronizandoAutomaticamente := True;
  try
    Log('--- Sincronia automatica (F2) iniciada ---');
    // Reaproveita a mesma logica do botao manual - ja faz o
    // AtualizarStatusConexao/checagem de loja conectada por conta propria.
    CmdEnviarDadosClick(Sender);
  finally
    FSincronizandoAutomaticamente := False;
  end;
end;
procedure TFrmSincroniaMarketplace.CmdPedidosClick(Sender: TObject);
begin
  AtualizarStatusConexao; // reconfirma antes de abrir, nao so no startup
  if not LojaEstaConectada then
  begin
    ShowMessage('Nenhuma loja conectada a um marketplace no momento.' + sLineBreak +
      sLineBreak +
      'Conecte uma loja no SATLojas (Cadastro de Lojas, aba Marketplaces) ' +
      'antes de gerenciar pedidos.');
    Exit;
  end;
  // Token pode ter vencido desde a ultima operacao - renova e regrava antes
  // de chamar a API, senao a resposta vem 403 com o token invalido.
  if not GarantirTokenValido then
    Exit;
  TFrmPedidosMarketplace.AbrirParaLoja(FLojaSelecionada, FCodMarketplace, FAccountIDDecriptado,
    FTokenDecriptado, FRefreshTokenDecriptado, FDevClientId, FDevClientSecret, FSandbox);
end;
// ----------------------------------------------------------------------------
// F3 - Receber Ofertas (produtos do marketplace)
// ----------------------------------------------------------------------------
procedure TFrmSincroniaMarketplace.CmdReceberDadosClick(Sender: TObject);
begin
  AtualizarStatusConexao; // reconfirma antes de cada execucao, nao so no startup
  if not LojaEstaConectada then
  begin
    ShowMessage('Nenhuma loja conectada a um marketplace no momento.' + sLineBreak +
      sLineBreak +
      'Conecte uma loja no SATLojas (Cadastro de Lojas, aba Marketplaces) ' +
      'antes de receber os dados.');
    Exit;
  end;
  // Token pode ter vencido desde a ultima operacao - renova e regrava antes
  // de chamar a API, senao a resposta vem 403 com o token invalido.
  if not GarantirTokenValido then
    Exit;
  // A busca/gravacao de verdade agora acontece na tela visual (grid), nao
  // mais silenciosa aqui - permite conferir antes de gravar, e escolher
  // atualizar tudo ou so' um produto selecionado.
  TFrmOfertasMarketplace.AbrirParaLoja(FLojaSelecionada, FCodMarketplace, FAccountIDDecriptado,
    FTokenDecriptado, FDevClientId, FDevClientSecret, FSandbox);
end;
end.
