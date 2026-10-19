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
//                            marcados em PRO.ALTERARNOECOMMERCE = 'T' (estoque)
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
    // Qual dos quatro precos do produto (PVend..PVend4) esta loja usa. Vai como
    // string porque e'' isso que o Funcoes.BuscarPrecoDeVenda espera.
    FPrecoPadraoLoja: string;
    // LOJAS.CODLOJAENTREGA da loja conectada - o F2 le o estoque (PRO.QUANT)
    // dessa loja. 0 = nao cadastrada, e o F2 nao envia nada.
    FCodLojaEntrega: Integer;
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
    // Preco de venda do produto para a loja conectada. Devolve False quando nao
    // foi possivel calcular - nesse caso o F2 envia so'' o estoque.
    function PrecoDeVendaDoProduto(const ACodProduto: Integer;
      out APreco: Double): Boolean;
    // Calcula o preco e ja grava na foto local. False = nao ha preco pra enviar.
    function PrepararPrecoParaEnvio(const ACodProduto: Integer;
      out APreco: Double): Boolean;
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
  FCodLojaEntrega := 0;
  if FLojaSelecionada = 0 then
    Exit; // nada selecionado ainda - lblLojaConectada ja foi ajustado por quem chamou
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    Qry.SQL.Text :=
      'SELECT LOJAD, MARKETPLACE_COD, MARKETPLACE_CLIENTID, MARKETPLACE_TOKEN, ' +
      'MARKETPLACE_KEY, MARKETPLACE_SANDBOX, MARKETPLACE_USUARIO, MARKETPLACE_SENHA, ' +
      'MARKETPLACE_BD, PRECODEVENDAPADRAO, CODLOJAENTREGA, ' +
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
    // Vazio ou 0 significa ''Preco 1'' - mesma leitura que o cadastro de Lojas faz.
    FPrecoPadraoLoja := Trim(Qry.FieldByName('PRECODEVENDAPADRAO').AsString);
    if StrToIntDef(FPrecoPadraoLoja, 0) = 0 then
      FPrecoPadraoLoja := '1';
    FCodLojaEntrega := Qry.FieldByName('CODLOJAENTREGA').AsInteger;
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
  // Sem loja de entrega nao ha de onde tirar o estoque. Usar a propria loja
  // conectada no lugar poderia zerar o estoque no marketplace, entao para.
  if FCodLojaEntrega = 0 then
  begin
    Log('Loja ' + IntToStr(FLojaSelecionada) + ' sem loja de entrega ' +
      '(LOJAS.CODLOJAENTREGA) - nada enviado.');
    ShowMessage('A loja conectada nao tem Loja de Entrega cadastrada.' +
      sLineBreak + sLineBreak +
      'O estoque enviado ao marketplace sai da loja de entrega. Cadastre-a ' +
      'no Cadastro de Lojas e tente novamente.');
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
// Preco de venda do produto para a loja conectada ao marketplace.
// {IMPORTANTE} nao reimplementa regra de preco nenhuma: chama a MESMA funcao
// que as telas de venda do SAT usam (Funcoes.BuscarPrecoDeVenda), entao gestao
// de precos, promocao por data/dia-da-semana/quantidade e a escolha entre
// PVend 1..4 conforme a loja saem identicas ao que o operador ve no balcao.
// A funcao tambem resolve sozinha qual versao datada da procedure chamar, pela
// constante Versao_Necessaria_BuscarPrecoDeVenda.
// {DECISAO} envia o PRECO DE VENDA, nao o promocional. Promocao de loja fisica
// tem prazo e regra propria (dia da semana, quantidade minima) que marketplace
// nenhum dos cinco representa igual - replicar isso venderia com desconto fora
// das condicoes que o justificam. Quando os dois diferem, o log registra, pra
// o cliente poder rever essa escolha com numero na mao.
function TFrmSincroniaMarketplace.PrecoDeVendaDoProduto(const ACodProduto: Integer;
  out APreco: Double): Boolean;
var
  QryProd: TFDQuery;
  PrecoDeVenda, PrecoPromocional, QtdePromocional: Real;
begin
  Result := False;
  APreco := 0;
  QryProd := TFDQuery.Create(nil);
  try
    QryProd.Connection := DZ.ZDatabase;
    // SELECT * porque a funcao le PVend, PVend2, PVend3, PVend4, COD e, quando
    // existe, UTILIZARPRECOSDIFERENCIADOS - direto deste dataset.
    QryProd.SQL.Text := 'SELECT * FROM PROD WHERE COD = :COD';
    QryProd.ParamByName('COD').AsInteger := ACodProduto;
    QryProd.Open;
    if QryProd.IsEmpty then
    begin
      Log('  Produto ' + IntToStr(ACodProduto) + ' nao encontrado em PROD - ' +
        'preco nao enviado (estoque segue normalmente).');
      Exit;
    end;
    PrecoDeVenda := 0;
    PrecoPromocional := 0;
    QtdePromocional := 0;
    APreco := Funcoes.BuscarPrecoDeVenda(QryProd, FPrecoPadraoLoja, 1,
      FLojaSelecionada, vg.dDataAtual, '', PrecoDeVenda, PrecoPromocional,
      QtdePromocional);
    if APreco <= 0 then
    begin
      // Preco zerado quase sempre e' cadastro incompleto. Enviar zero pro
      // marketplace seria pior que nao enviar: coloca o produto a venda de
      // graca. Entao avisa e deixa o preco como esta la'.
      Log('  Produto ' + IntToStr(ACodProduto) + ' com preco zerado - preco NAO ' +
        'enviado, para nao publicar o item a R$ 0,00. Confira o cadastro.');
      APreco := 0;
      Exit;
    end;
    if (PrecoPromocional > 0) and (PrecoPromocional < PrecoDeVenda) then
      Log(Format('  Produto %d tem promocao vigente (R$ %s) - enviando o preco ' +
        'normal (R$ %s), conforme definido.',
        [ACodProduto, FormatFloat('0.00', PrecoPromocional),
         FormatFloat('0.00', APreco)]));
    Result := True;
  finally
    QryProd.Free;
  end;
end;

// Calcula o preco do produto e ja atualiza a "foto" em PRODUTOS_MARKETPLACE.
// Devolve False quando nao ha preco valido - nesse caso o chamador NAO deve
// chamar a API de preco do marketplace.
// {DECISAO} o preco e' BEST-EFFORT, separado do estoque: se o envio de preco
// falhar, o estoque ja' enviado continua valendo e a flag do PRO e' limpa do
// mesmo jeito. O contrario (deixar o produto pendente ate o preco passar) faria
// o F2 reenviar estoque indefinidamente num produto cujo preco a Amazon recusa
// por limite minimo/maximo, por exemplo. A falha fica registrada no log.
function TFrmSincroniaMarketplace.PrepararPrecoParaEnvio(const ACodProduto: Integer;
  out APreco: Double): Boolean;
var
  QryPreco: TFDQuery;
begin
  APreco := 0;
  Result := PrecoDeVendaDoProduto(ACodProduto, APreco);
  if not Result then
    Exit;
  QryPreco := TFDQuery.Create(nil);
  try
    QryPreco.Connection := DZ.ZDatabase;
    QryPreco.SQL.Text :=
      'UPDATE PRODUTOS_MARKETPLACE SET PRECO = :PRECO, DATAULTIMAALTERACAO = :DATA ' +
      'WHERE CODPRODUTO = :COD AND LOJA = :LOJA AND CODMARKETPLACE = :MKT';
    QryPreco.ParamByName('PRECO').AsFloat := APreco;
    QryPreco.ParamByName('DATA').AsDateTime := Now;
    QryPreco.ParamByName('COD').AsInteger := ACodProduto;
    QryPreco.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    QryPreco.ParamByName('MKT').AsInteger := FCodMarketplace;
    QryPreco.ExecSQL;
  finally
    QryPreco.Free;
  end;
end;

procedure TFrmSincroniaMarketplace.EnviarEstoqueShopee;
var
  Qry, QryAux: TFDQuery;
  Cliente: TShopeeOpenAPIClient;
  ErroMsg, ItemID: string;
  CodProduto, Estoque: Integer;
  iSucesso, iFalha: Integer;
  Preco: Double;
  EnviarEstoque, EnviarPreco, OKEstoque: Boolean;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Shopee nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  Log('Buscando produtos marcados para envio (estoque: ALTERARNOECOMMERCE = T; ' +
    'preco: ATUALIZARMARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // {DECISAO DO CLIENTE - 19/10/2026} o estoque SEMPRE sai da loja de
    // entrega: :LOJAENTREGA = LOJAS.CODLOJAENTREGA da loja conectada (lido em
    // AtualizarStatusConexao), e o PRO e' filtrado direto por ela. O :LOJA
    // (FLojaSelecionada) continua sendo a loja CONECTADA ao marketplace, que
    // e' a que PRODUTOS_MARKETPLACE.LOJA guarda (Ofertas, Vincular Produto).
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.LOJA = :LOJAENTREGA ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND ((P.ALTERARNOECOMMERCE = ''T'' ' +
             'AND COALESCE(PM.ESTOQUE_INFINITO, 0) <> 1) ' +
          'OR PM.ATUALIZARMARKETPLACE = ''S''))';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.ParamByName('LOJAENTREGA').AsInteger := FCodLojaEntrega;
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
          'SELECT CODPRODUTONOMARKETPLACE, ' +
          'COALESCE(ESTOQUE_INFINITO, 0) AS ESTOQUE_INFINITO, ' +
          'COALESCE(ATUALIZARMARKETPLACE, ''N'') AS ATUALIZARMARKETPLACE ' +
          'FROM PRODUTOS_MARKETPLACE ' +
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

          // {DECISAO DO CLIENTE - 14/10/2026} dois gates INDEPENDENTES:

          //   ESTOQUE -> PRO.ALTERARNOECOMMERCE = 'T', e NAO envia quando o

          //              produto esta marcado como estoque infinito.

          //   PRECO   -> PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE = 'S'.

          // Um produto pode entrar na lista por um gate e nao pelo outro, por

          // isso os dois sao avaliados aqui, por produto, e nao na consulta.

          // {ATENCAO} nenhum dos dois campos e' limpo por esta rotina - quem

          // gerencia e' o cliente, por rotina propria (PRO) e por tela (PM).

          EnviarEstoque := (Trim(Qry.FieldByName('ALTERARNOECOMMERCE').AsString) = 'T') and

            (QryAux.FieldByName('ESTOQUE_INFINITO').AsInteger <> 1);

          EnviarPreco := QryAux.FieldByName('ATUALIZARMARKETPLACE').AsString = 'S';
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE - so quando o estoque

          // vai mesmo ser enviado, senao a foto mostraria uma quantidade que o

          // marketplace nunca recebeu (caso do estoque infinito).

          if EnviarEstoque then

          begin
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

          end;
          // 2) Chama a API da Shopee pra atualizar de verdade.
          // {TODO} AModelID fixo em 0 (item sem variacao) - produtos COM
          // variacao (cor/tamanho) precisam de um model_id especifico, que
          // ainda nao guardamos em PRODUTOS_MARKETPLACE. Se o cliente vender
          // produto com variacao, essa parte precisa ser expandida.
          OKEstoque := True;

          if EnviarEstoque then

            OKEstoque := Cliente.UpdateStock(FTokenDecriptado, StrToInt64Def(FAccountIDDecriptado, 0),
                 StrToInt64Def(ItemID, 0), 0, Estoque, ErroMsg);

          if OKEstoque then
          begin
            Inc(iSucesso);
            // Preco: enviado logo apos o estoque, como passo separado. Falha aqui

            // NAO desfaz o estoque nem segura a flag - ver PrepararPrecoParaEnvio.

            if EnviarPreco and PrepararPrecoParaEnvio(CodProduto, Preco) then
            if not Cliente.UpdatePrice(FTokenDecriptado,

                 StrToInt64Def(FAccountIDDecriptado, 0), StrToInt64Def(ItemID, 0), 0,

                 Preco, ErroMsg) then
              Log('  Aviso: estoque enviado, mas o preco do produto ' +

                IntToStr(CodProduto) + ' falhou: ' + ErroMsg);

            // {DECISAO DO CLIENTE - 14/10/2026} esta rotina NAO limpa mais flag

            // nenhuma. O PRO.ALTERARNOECOMMERCE e' gerenciado por rotina propria do

            // cliente, e o PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE por uma tela de

            // produtos que eles vao criar. Enquanto as marcas ficarem ligadas, o F2

            // reenvia os mesmos produtos a cada execucao - e isso e' esperado.
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
  Preco: Double;
  EnviarEstoque, EnviarPreco, OKEstoque: Boolean;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Amazon nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  Log('Buscando produtos marcados para envio (estoque: ALTERARNOECOMMERCE = T; ' +
    'preco: ATUALIZARMARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de :LOJAENTREGA (estoque) x :LOJA
    // (conectada ao marketplace) ja usada em EnviarEstoqueShopee - so
    // muda o metodo que efetivamente chama a API no final.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.LOJA = :LOJAENTREGA ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND ((P.ALTERARNOECOMMERCE = ''T'' ' +
             'AND COALESCE(PM.ESTOQUE_INFINITO, 0) <> 1) ' +
          'OR PM.ATUALIZARMARKETPLACE = ''S''))';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.ParamByName('LOJAENTREGA').AsInteger := FCodLojaEntrega;
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
          'SELECT CODPRODUTONOMARKETPLACE, ' +
          'COALESCE(ESTOQUE_INFINITO, 0) AS ESTOQUE_INFINITO, ' +
          'COALESCE(ATUALIZARMARKETPLACE, ''N'') AS ATUALIZARMARKETPLACE ' +
          'FROM PRODUTOS_MARKETPLACE ' +
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

          // {DECISAO DO CLIENTE - 14/10/2026} dois gates INDEPENDENTES:

          //   ESTOQUE -> PRO.ALTERARNOECOMMERCE = 'T', e NAO envia quando o

          //              produto esta marcado como estoque infinito.

          //   PRECO   -> PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE = 'S'.

          // Um produto pode entrar na lista por um gate e nao pelo outro, por

          // isso os dois sao avaliados aqui, por produto, e nao na consulta.

          // {ATENCAO} nenhum dos dois campos e' limpo por esta rotina - quem

          // gerencia e' o cliente, por rotina propria (PRO) e por tela (PM).

          EnviarEstoque := (Trim(Qry.FieldByName('ALTERARNOECOMMERCE').AsString) = 'T') and

            (QryAux.FieldByName('ESTOQUE_INFINITO').AsInteger <> 1);

          EnviarPreco := QryAux.FieldByName('ATUALIZARMARKETPLACE').AsString = 'S';
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE - so quando o estoque

          // vai mesmo ser enviado, senao a foto mostraria uma quantidade que o

          // marketplace nunca recebeu (caso do estoque infinito).

          if EnviarEstoque then

          begin
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

          end;
          // 2) Chama a Amazon SP-API pra atualizar de verdade (descobre o
          // productType real do SKU sozinha antes de montar o PATCH).
          OKEstoque := True;

          if EnviarEstoque then

            OKEstoque := Cliente.UpdateStockQuantity(FTokenDecriptado, FAccountIDDecriptado, Sku,
                 Estoque, RespostaJSON, ErroMsg);

          if OKEstoque then
          begin
            Inc(iSucesso);
            // Preco: enviado logo apos o estoque, como passo separado. Falha aqui

            // NAO desfaz o estoque nem segura a flag - ver PrepararPrecoParaEnvio.

            if EnviarPreco and PrepararPrecoParaEnvio(CodProduto, Preco) then
            if not Cliente.UpdateSalePrice(FTokenDecriptado, FAccountIDDecriptado,

                 Sku, Preco, RespostaJSON, ErroMsg) then
              Log('  Aviso: estoque enviado, mas o preco do produto ' +

                IntToStr(CodProduto) + ' falhou: ' + ErroMsg);

            // {DECISAO DO CLIENTE - 14/10/2026} esta rotina NAO limpa mais flag

            // nenhuma. O PRO.ALTERARNOECOMMERCE e' gerenciado por rotina propria do

            // cliente, e o PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE por uma tela de

            // produtos que eles vao criar. Enquanto as marcas ficarem ligadas, o F2

            // reenvia os mesmos produtos a cada execucao - e isso e' esperado.
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
  Preco: Double;
  EnviarEstoque, EnviarPreco, OKEstoque: Boolean;
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
  Log('Buscando produtos marcados para envio (estoque: ALTERARNOECOMMERCE = T; ' +
    'preco: ATUALIZARMARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de :LOJAENTREGA (estoque) x :LOJA
    // (conectada ao marketplace) ja usada em EnviarEstoqueShopee/Amazon -
    // so muda o metodo que efetivamente chama a API no final.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.LOJA = :LOJAENTREGA ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND ((P.ALTERARNOECOMMERCE = ''T'' ' +
             'AND COALESCE(PM.ESTOQUE_INFINITO, 0) <> 1) ' +
          'OR PM.ATUALIZARMARKETPLACE = ''S''))';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.ParamByName('LOJAENTREGA').AsInteger := FCodLojaEntrega;
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
          'SELECT CODPRODUTONOMARKETPLACE, ' +
          'COALESCE(ESTOQUE_INFINITO, 0) AS ESTOQUE_INFINITO, ' +
          'COALESCE(ATUALIZARMARKETPLACE, ''N'') AS ATUALIZARMARKETPLACE ' +
          'FROM PRODUTOS_MARKETPLACE ' +
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

          // {DECISAO DO CLIENTE - 14/10/2026} dois gates INDEPENDENTES:

          //   ESTOQUE -> PRO.ALTERARNOECOMMERCE = 'T', e NAO envia quando o

          //              produto esta marcado como estoque infinito.

          //   PRECO   -> PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE = 'S'.

          // Um produto pode entrar na lista por um gate e nao pelo outro, por

          // isso os dois sao avaliados aqui, por produto, e nao na consulta.

          // {ATENCAO} nenhum dos dois campos e' limpo por esta rotina - quem

          // gerencia e' o cliente, por rotina propria (PRO) e por tela (PM).

          EnviarEstoque := (Trim(Qry.FieldByName('ALTERARNOECOMMERCE').AsString) = 'T') and

            (QryAux.FieldByName('ESTOQUE_INFINITO').AsInteger <> 1);

          EnviarPreco := QryAux.FieldByName('ATUALIZARMARKETPLACE').AsString = 'S';
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE - so quando o estoque

          // vai mesmo ser enviado, senao a foto mostraria uma quantidade que o

          // marketplace nunca recebeu (caso do estoque infinito).

          if EnviarEstoque then

          begin
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

          end;
          // 2) Chama a API do Magalu pra atualizar de verdade.
          OKEstoque := True;

          if EnviarEstoque then

            OKEstoque := Cliente.UpdateStock(FTokenDecriptado, FAccountIDDecriptado, Sku,
                 Estoque, ErroMsg);

          if OKEstoque then
          begin
            Inc(iSucesso);
            // Preco: enviado logo apos o estoque, como passo separado. Falha aqui

            // NAO desfaz o estoque nem segura a flag - ver PrepararPrecoParaEnvio.

            if EnviarPreco and PrepararPrecoParaEnvio(CodProduto, Preco) then
            if not Cliente.UpdatePrice(FTokenDecriptado, FAccountIDDecriptado,

                 Sku, Preco, ErroMsg) then
              Log('  Aviso: estoque enviado, mas o preco do produto ' +

                IntToStr(CodProduto) + ' falhou: ' + ErroMsg);

            // {DECISAO DO CLIENTE - 14/10/2026} esta rotina NAO limpa mais flag

            // nenhuma. O PRO.ALTERARNOECOMMERCE e' gerenciado por rotina propria do

            // cliente, e o PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE por uma tela de

            // produtos que eles vao criar. Enquanto as marcas ficarem ligadas, o F2

            // reenvia os mesmos produtos a cada execucao - e isso e' esperado.
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
  Preco: Double;
  EnviarEstoque, EnviarPreco, OKEstoque: Boolean;
  QtdML: Integer;
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
  Log('Buscando produtos marcados para envio (estoque: ALTERARNOECOMMERCE = T; ' +
    'preco: ATUALIZARMARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de :LOJAENTREGA (estoque) x :LOJA
    // (conectada ao marketplace) ja usada em EnviarEstoqueShopee/Amazon/
    // Magalu - so muda o metodo que efetivamente chama a API no final.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.LOJA = :LOJAENTREGA ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND ((P.ALTERARNOECOMMERCE = ''T'' ' +
             'AND COALESCE(PM.ESTOQUE_INFINITO, 0) <> 1) ' +
          'OR PM.ATUALIZARMARKETPLACE = ''S''))';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.ParamByName('LOJAENTREGA').AsInteger := FCodLojaEntrega;
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
          'SELECT CODPRODUTONOMARKETPLACE, ' +
          'COALESCE(ESTOQUE_INFINITO, 0) AS ESTOQUE_INFINITO, ' +
          'COALESCE(ATUALIZARMARKETPLACE, ''N'') AS ATUALIZARMARKETPLACE ' +
          'FROM PRODUTOS_MARKETPLACE ' +
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

          // {DECISAO DO CLIENTE - 14/10/2026} dois gates INDEPENDENTES:

          //   ESTOQUE -> PRO.ALTERARNOECOMMERCE = 'T', e NAO envia quando o

          //              produto esta marcado como estoque infinito.

          //   PRECO   -> PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE = 'S'.

          // Um produto pode entrar na lista por um gate e nao pelo outro, por

          // isso os dois sao avaliados aqui, por produto, e nao na consulta.

          // {ATENCAO} nenhum dos dois campos e' limpo por esta rotina - quem

          // gerencia e' o cliente, por rotina propria (PRO) e por tela (PM).

          EnviarEstoque := (Trim(Qry.FieldByName('ALTERARNOECOMMERCE').AsString) = 'T') and

            (QryAux.FieldByName('ESTOQUE_INFINITO').AsInteger <> 1);

          EnviarPreco := QryAux.FieldByName('ATUALIZARMARKETPLACE').AsString = 'S';
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE - so quando o estoque

          // vai mesmo ser enviado, senao a foto mostraria uma quantidade que o

          // marketplace nunca recebeu (caso do estoque infinito).

          if EnviarEstoque then

          begin
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

          end;
          // 2) Chama a API do Mercado Livre pra atualizar de verdade.

          // {ML} unico dos cinco em que estoque e preco vao na MESMA chamada - o

          // PUT /items/{id} aceita os dois campos no mesmo corpo. Por isso aqui o

          // preco e calculado ANTES, e nao depois como nos outros quatro.

          Preco := 0;

          if EnviarPreco then

            if not PrepararPrecoParaEnvio(CodProduto, Preco) then

              Preco := 0; // sem preco valido no cadastro: nao manda preco

          // Quantidade negativa diz ao cliente do ML pra NAO mandar estoque -

          // necessario porque aqui os dois campos vao na mesma requisicao.

          if EnviarEstoque then

            QtdML := Estoque

          else

            QtdML := -1;

          if Cliente.UpdateStockAndPrice(FTokenDecriptado, ItemID, QtdML, Preco,

               ErroMsg) then

          begin

            Inc(iSucesso);

            // {DECISAO DO CLIENTE - 14/10/2026} esta rotina NAO limpa mais flag

            // nenhuma. O PRO.ALTERARNOECOMMERCE e' gerenciado por rotina propria do

            // cliente, e o PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE por uma tela de

            // produtos que eles vao criar. Enquanto as marcas ficarem ligadas, o F2

            // reenvia os mesmos produtos a cada execucao - e isso e' esperado.
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
  Preco: Double;
  EnviarEstoque, EnviarPreco, OKEstoque: Boolean;
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
  Log('Buscando produtos marcados para envio (estoque: ALTERARNOECOMMERCE = T; ' +
    'preco: ATUALIZARMARKETPLACE = S)...');
  Qry := TFDQuery.Create(nil);
  QryAux := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // Mesma consulta/mesma logica de :LOJAENTREGA (estoque) x :LOJA
    // (conectada ao marketplace) usada pelos outros quatro.
    Qry.SQL.Text :=
      'SELECT * FROM PRO P ' +
      'WHERE P.LOJA = :LOJAENTREGA ' +
      'AND EXISTS (SELECT 1 FROM PRODUTOS_MARKETPLACE PM ' +
        'WHERE PM.CODPRODUTO = P.COD ' +
        'AND PM.LOJA = :LOJA ' +
        'AND ((P.ALTERARNOECOMMERCE = ''T'' ' +
             'AND COALESCE(PM.ESTOQUE_INFINITO, 0) <> 1) ' +
          'OR PM.ATUALIZARMARKETPLACE = ''S''))';
    Qry.ParamByName('LOJA').AsInteger := FLojaSelecionada;
    Qry.ParamByName('LOJAENTREGA').AsInteger := FCodLojaEntrega;
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
          'SELECT CODPRODUTONOMARKETPLACE, ' +
          'COALESCE(ESTOQUE_INFINITO, 0) AS ESTOQUE_INFINITO, ' +
          'COALESCE(ATUALIZARMARKETPLACE, ''N'') AS ATUALIZARMARKETPLACE ' +
          'FROM PRODUTOS_MARKETPLACE ' +
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

          // {DECISAO DO CLIENTE - 14/10/2026} dois gates INDEPENDENTES:

          //   ESTOQUE -> PRO.ALTERARNOECOMMERCE = 'T', e NAO envia quando o

          //              produto esta marcado como estoque infinito.

          //   PRECO   -> PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE = 'S'.

          // Um produto pode entrar na lista por um gate e nao pelo outro, por

          // isso os dois sao avaliados aqui, por produto, e nao na consulta.

          // {ATENCAO} nenhum dos dois campos e' limpo por esta rotina - quem

          // gerencia e' o cliente, por rotina propria (PRO) e por tela (PM).

          EnviarEstoque := (Trim(Qry.FieldByName('ALTERARNOECOMMERCE').AsString) = 'T') and

            (QryAux.FieldByName('ESTOQUE_INFINITO').AsInteger <> 1);

          EnviarPreco := QryAux.FieldByName('ATUALIZARMARKETPLACE').AsString = 'S';
          SepararProdutoESkuTikTok(ChaveTikTok, ProductId, SkuId);
          QryAux.Close;
          // 1) Atualiza a "foto" na PRODUTOS_MARKETPLACE - so quando o estoque

          // vai mesmo ser enviado, senao a foto mostraria uma quantidade que o

          // marketplace nunca recebeu (caso do estoque infinito).

          if EnviarEstoque then

          begin
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

          end;
          // 2) Chama a API do TikTok pra atualizar de verdade.
          OKEstoque := True;

          if EnviarEstoque then

            OKEstoque := Cliente.UpdateInventory(FTokenDecriptado, ShopCipher, ProductId, SkuId,
                 WarehouseId, Estoque, ErroMsg);

          if OKEstoque then
          begin
            Inc(iSucesso);
            // Preco: enviado logo apos o estoque, como passo separado. Falha aqui

            // NAO desfaz o estoque nem segura a flag - ver PrepararPrecoParaEnvio.

            if EnviarPreco and PrepararPrecoParaEnvio(CodProduto, Preco) then
            if not Cliente.UpdatePrice(FTokenDecriptado, ShopCipher, ProductId,

                 SkuId, Preco, ErroMsg) then
              Log('  Aviso: estoque enviado, mas o preco do produto ' +

                IntToStr(CodProduto) + ' falhou: ' + ErroMsg);

            // {DECISAO DO CLIENTE - 14/10/2026} esta rotina NAO limpa mais flag

            // nenhuma. O PRO.ALTERARNOECOMMERCE e' gerenciado por rotina propria do

            // cliente, e o PRODUTOS_MARKETPLACE.ATUALIZARMARKETPLACE por uma tela de

            // produtos que eles vao criar. Enquanto as marcas ficarem ligadas, o F2

            // reenvia os mesmos produtos a cada execucao - e isso e' esperado.
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
