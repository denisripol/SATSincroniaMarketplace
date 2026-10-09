// ============================================================================

// UNIT: uFrmPedidosMarketplace

// OBJETIVO: Tela isolada (F4 - Pedidos) para listar os pedidos do marketplace

// conectado e executar as acoes disponiveis sobre um pedido selecionado:

//   - Despachar (confirma o envio - logistics/ship_order)

//   - Cancelar (cancelamento pelo vendedor - order/cancel_order)

//   - Aprovar Cancelamento (aceita pedido de cancelamento do comprador)

//   - Reprovar Cancelamento (recusa pedido de cancelamento do comprador)

//

// COBERTURA HOJE (ver o handler de cada botao pra mensagem exata):

//   Listar pedidos e Baixar Pedido SAT -> Shopee, Amazon, Magalu, ML e TikTok

//   Despachar                          -> Shopee, Amazon e Magalu

//   Cancelar / Aprovar / Reprovar      -> so Shopee (os demais nao tem

//                                         endpoint - avisam e saem)

//   Etiqueta                           -> Shopee (gerar + baixar), ML e

//                                         TikTok (so baixar - os dois ja

//                                         geram sozinhos; o TikTok devolve

//                                         URL, entao abre no navegador)

//   Nota Fiscal                        -> Shopee (baixar/enviar) e Amazon

//                                         (enviar XML + consultar status)

// ============================================================================



unit uFrmPedidosMarketplace;



interface



uses

  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils, System.Variants,

  System.Classes, System.StrUtils, System.IOUtils, System.DateUtils, System.JSON,
  Vcl.Graphics, Vcl.Controls,

  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.Grids,

  uMarketplace, Shopee.OpenAPI.Client, Amazon.SPAPI.Client, Magalu.OpenAPI.Client,
  uFrmDespacharAmazon, Data.DB, FireDAC.Comp.Client, DMZ, uBaixaPedidoSAT,
  MercadoLivre.OpenAPI.Client, TikTokShop.OpenAPI.Client;



type

  TFrmPedidosMarketplace = class(TForm)

    pnlTopo: TPanel;

    lblTitulo: TLabel;

    lblFiltro: TLabel;

    edtDiasAtras: TEdit;

    CmdAtualizar: TBitBtn;

    Grid: TStringGrid;

    pnlAcoes: TPanel;

    CmdDespachar: TBitBtn;

    CmdCancelar: TBitBtn;

    CmdAprovarCancelamento: TBitBtn;

    CmdReprovarCancelamento: TBitBtn;

    CmdGerarEtiqueta: TBitBtn;

    CmdBaixarEtiqueta: TBitBtn;

    CmdBaixarNF: TBitBtn;

    CmdEnviarNF: TBitBtn;

    CmdBaixarPedidoSAT: TBitBtn;

    SaveDialog1: TSaveDialog;

    OpenDialog1: TOpenDialog;

    MemoLog: TMemo;

    procedure FormCreate(Sender: TObject);

    procedure CmdAtualizarClick(Sender: TObject);

    procedure GridClick(Sender: TObject);

    procedure CmdDespacharClick(Sender: TObject);

    procedure CmdCancelarClick(Sender: TObject);

    procedure CmdAprovarCancelamentoClick(Sender: TObject);

    procedure CmdReprovarCancelamentoClick(Sender: TObject);

    procedure CmdGerarEtiquetaClick(Sender: TObject);

    procedure CmdBaixarEtiquetaClick(Sender: TObject);

    procedure CmdBaixarNFClick(Sender: TObject);

    procedure CmdEnviarNFClick(Sender: TObject);

    procedure CmdBaixarPedidoSATClick(Sender: TObject);

  private

    FLoja: Integer;

    FCodMarketplace: Integer;

    FAccountID: string;

    FToken: string;

    FRefreshToken: string;

    FOrders: TShopeeOrderArray;

    FAmazonOrders: TAmazonOrderArray;

    FMercadoLivreOrders: TMercadoLivreOrderArray;

    FTikTokOrders: TTikTokShopOrderArray;
    FMagaluOrders: TMagaluOrderArray;

    // Credenciais de desenvolvedor da loja (agora vem do banco, ja lidas e

    // resolvidas pelo form principal antes de abrir esta tela).

    FDevClientId: string;

    FDevClientSecret: string;

    FSandbox: Boolean;

    function MontarDadosPedidoShopee(const AOrderSN: string;

      out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

    function MontarDadosPedidoAmazon(const AOrderSN: string;

      out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

    function MontarDadosPedidoMagalu(const AOrderSN: string;

      out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

    function MontarDadosPedidoMercadoLivre(const AOrderSN: string;

      out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

    function MontarDadosPedidoTikTokShop(const AOrderSN: string;

      out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;



    procedure Log(const AMsg: string);

    procedure CarregarPedidos;

    procedure CarregarPedidosShopee;

    procedure CarregarPedidosAmazon;

    procedure CarregarPedidosMagalu;

    procedure CarregarPedidosMercadoLivre;

    procedure CarregarPedidosTikTokShop;

    function PedidoSelecionado(out AOrderSN: string): Boolean;

    function StatusIndicaDespachado(const AStatus: string): Boolean;

    procedure ExecutarAcaoShopee(const AAcao: string);

    function AcaoIndisponivelNesteMarketplace(const AAcao: string): Boolean;

    function PrepararCancelamentoTikTok(out AOrderSN, AShopCipher,

      ACancelId: string): Boolean;

    procedure SalvarPdfEmDisco(const APdfBytes: TBytes; const ANomeSugerido: string);

  public

    // Ponto de entrada - recebe os dados ja descriptografados da loja

    // conectada e as credenciais de desenvolvedor ja resolvidas (o form

    // principal ja fez essa parte).

    class procedure AbrirParaLoja(const ALoja, ACodMarketplace: Integer;

      const AAccountID, AToken, ARefreshToken: string;

      const ADevClientId, ADevClientSecret: string; const ASandbox: Boolean);

  end;



implementation



{$R *.dfm}



{ TFrmPedidosMarketplace }



class procedure TFrmPedidosMarketplace.AbrirParaLoja(const ALoja, ACodMarketplace: Integer;

  const AAccountID, AToken, ARefreshToken: string;

  const ADevClientId, ADevClientSecret: string; const ASandbox: Boolean);

var

  Frm: TFrmPedidosMarketplace;

begin

  Frm := TFrmPedidosMarketplace.Create(Application);

  try

    // FormCreate ja disparou aqui (o Create do TForm chama OnCreate antes

    // de devolver o controle) - por isso os campos so' sao preenchidos

    // DEPOIS, e so' entao chamamos CarregarPedidos manualmente (o

    // FormCreate NAO chama mais, exatamente por causa disso).

    Frm.FLoja := ALoja;

    Frm.FCodMarketplace := ACodMarketplace;

    Frm.FAccountID := AAccountID;

    Frm.FToken := AToken;

    Frm.FRefreshToken := ARefreshToken;

    Frm.FDevClientId := ADevClientId;

    Frm.FDevClientSecret := ADevClientSecret;

    Frm.FSandbox := ASandbox;

    Frm.lblTitulo.Caption := 'Pedidos - ' + NomeMarketplace(TMarketplaces(ACodMarketplace));

    Frm.CarregarPedidos;

    Frm.ShowModal;

  finally

    Frm.Free;

  end;

end;



procedure TFrmPedidosMarketplace.FormCreate(Sender: TObject);

begin

  Grid.ColCount := 4;

  Grid.RowCount := 2; // FixedRows precisa ser sempre < RowCount

  Grid.FixedRows := 1;

  Grid.Cells[0, 0] := 'Order SN';

  Grid.Cells[1, 0] := 'Status';

  Grid.Cells[2, 0] := 'Data';

  Grid.Cells[3, 0] := 'Total';



  edtDiasAtras.Text := '15';

  // CarregarPedidos NAO e' chamado aqui - nesse momento FCodMarketplace/

  // FToken/etc ainda nao foram preenchidos pelo AbrirParaLoja (ver comentario

  // la). E' chamado explicitamente logo apos o Create, no proprio AbrirParaLoja.

end;



procedure TFrmPedidosMarketplace.Log(const AMsg: string);

begin

  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);

end;



procedure TFrmPedidosMarketplace.CmdAtualizarClick(Sender: TObject);

begin

  CarregarPedidos;

end;



procedure TFrmPedidosMarketplace.CarregarPedidos;

begin

  case TMarketplaces(FCodMarketplace) of

    TMarketplaces.Shopee:
      begin
        // A Shopee limita a busca de pedidos a no maximo 15 dias por
        // chamada (erro "order.order_list_invalid_time" se passar disso)
        // - a Amazon nao tem esse limite, entao a validacao e' so aqui,
        // especifica da Shopee, mesmo os dois usando o mesmo campo
        // edtDiasAtras.
        if StrToIntDef(edtDiasAtras.Text, 15) > 15 then
        begin
          ShowMessage('A Shopee limita a busca de pedidos a no maximo 15 dias por vez. ' +
            'Ajuste o campo "Ultimos (dias)" para 15 ou menos e tente novamente.');
          Exit;
        end;
        CarregarPedidosShopee;
      end;

    TMarketplaces.Amazon: CarregarPedidosAmazon;

    TMarketplaces.Magalu: CarregarPedidosMagalu;

    TMarketplaces.MercadoLivre: CarregarPedidosMercadoLivre;

    TMarketplaces.TikTokShop: CarregarPedidosTikTokShop;

  else

    Log('Gestao de pedidos ainda nao implementada para este marketplace.');

  end;

end;



procedure TFrmPedidosMarketplace.CarregarPedidosShopee;

var

  Cliente: TShopeeOpenAPIClient;

  ErroMsg: string;

  I, DiasAtras: Integer;

begin

  if (FDevClientId = '') or (FDevClientSecret = '') then

  begin

    Log('Credenciais de desenvolvedor da Shopee nao cadastradas para esta ' +

      'loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV na tabela Lojas).');

    Exit;

  end;



  DiasAtras := StrToIntDef(edtDiasAtras.Text, 15);



  Screen.Cursor := crHourGlass;

  try

    Log(Format('Buscando pedidos dos ultimos %d dia(s)...', [DiasAtras]));



    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

      FDevClientSecret, '', FSandbox);

    Cliente.OnLog := Log;

    try

      if not Cliente.GetOrderList(FToken, StrToInt64Def(FAccountID, 0),

           FOrders, ErroMsg, DiasAtras) then

      begin

        Log('Erro ao buscar pedidos: ' + ErroMsg);

        Exit;

      end;

    finally

      Cliente.Free;

    end;



    Log(Format('%d pedido(s) encontrado(s).', [Length(FOrders)]));



    Grid.RowCount := Length(FOrders) + 1;

    if Grid.RowCount < 2 then

      Grid.RowCount := 2; // FixedRows = 1 exige RowCount >= 2, mesmo sem pedidos



    // Limpa eventuais linhas de uma consulta anterior maior que a atual

    for I := 1 to Grid.RowCount - 1 do

    begin

      Grid.Cells[0, I] := '';

      Grid.Cells[1, I] := '';

      Grid.Cells[2, I] := '';

      Grid.Cells[3, I] := '';

    end;



    for I := Low(FOrders) to High(FOrders) do

    begin

      Grid.Cells[0, I + 1] := FOrders[I].OrderSN;

      Grid.Cells[1, I + 1] := FOrders[I].OrderStatus;

      Grid.Cells[2, I + 1] := DateTimeToStr(FOrders[I].CreateTime);

      Grid.Cells[3, I + 1] := FOrders[I].Currency + ' ' + FOrders[I].TotalAmount;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



procedure TFrmPedidosMarketplace.CarregarPedidosAmazon;

var

  Cliente: TAmazonSPAPIClient;

  ErroMsg, CreatedAfterISO: string;

  I, DiasAtras: Integer;

begin

  if (FDevClientId = '') or (FDevClientSecret = '') then

  begin

    Log('Credenciais de desenvolvedor da Amazon nao cadastradas para esta ' +

      'loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV na tabela Lojas).');

    Exit;

  end;



  DiasAtras := StrToIntDef(edtDiasAtras.Text, 15);

  // Orders API pede "CreatedAfter" em ISO8601 UTC - nao e' "ultimos N dias"

  // direto, e' uma data-limite pra tras.

  CreatedAfterISO := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',

    TTimeZone.Local.ToUniversalTime(IncDay(Now, -DiasAtras)));



  Screen.Cursor := crHourGlass;

  try

    Log(Format('Buscando pedidos dos ultimos %d dia(s)...', [DiasAtras]));



    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',

      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);

    Cliente.OnLog := Log;

    try

      if not Cliente.GetOrders(FToken, CreatedAfterISO, FAmazonOrders, ErroMsg) then

      begin

        Log('Erro ao buscar pedidos: ' + ErroMsg);

        Exit;

      end;

    finally

      Cliente.Free;

    end;



    Log(Format('%d pedido(s) encontrado(s).', [Length(FAmazonOrders)]));



    Grid.RowCount := Length(FAmazonOrders) + 1;

    if Grid.RowCount < 2 then

      Grid.RowCount := 2;



    for I := 1 to Grid.RowCount - 1 do

    begin

      Grid.Cells[0, I] := '';

      Grid.Cells[1, I] := '';

      Grid.Cells[2, I] := '';

      Grid.Cells[3, I] := '';

    end;



    for I := Low(FAmazonOrders) to High(FAmazonOrders) do

    begin

      Grid.Cells[0, I + 1] := FAmazonOrders[I].AmazonOrderId;

      Grid.Cells[1, I + 1] := FAmazonOrders[I].OrderStatus;

      // PurchaseDate ja vem como string ISO8601 da propria API - exibe cru

      // mesmo, sem reformatar (evita erro de parsing por fuso/formato).

      Grid.Cells[2, I + 1] := FAmazonOrders[I].PurchaseDate;

      Grid.Cells[3, I + 1] := FAmazonOrders[I].CurrencyCode + ' ' + FAmazonOrders[I].TotalAmount;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



procedure TFrmPedidosMarketplace.CarregarPedidosMagalu;

var

  Cliente: TMagaluOpenAPIClient;

  ErroMsg: string;

  I: Integer;

begin

  if (FDevClientId = '') or (FDevClientSecret = '') then

  begin

    Log('Credenciais de desenvolvedor do Magalu nao cadastradas para esta ' +

      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');

    Exit;

  end;

  // {ATENCAO} O endpoint de GetOrders (Magalu.OpenAPI.Client) ainda NAO

  // foi confirmado com uma chamada real (ver comentario no topo daquele

  // arquivo) - o path usado ("/v1/orders") e' um palpite baseado no

  // endpoint de sandbox "/v1/samples/orders". So' vamos confirmar de

  // verdade com o primeiro vendedor autorizado. Ao contrario da Amazon,

  // nao ha filtro de data aqui ainda (GetOrders do Magalu nao aceita

  // parametro de periodo por enquanto - traz tudo que a API devolver).

  Screen.Cursor := crHourGlass;

  try

    Log('Buscando pedidos no Magalu...');

    // FAccountID guarda o Tenant ID pro Magalu (mesmo campo generico

    // usado por todos os marketplaces - ver AbrirParaLoja/tela de Lojas).

    Cliente := TMagaluOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', '', FSandbox);

    Cliente.OnLog := Log;

    try

      if not Cliente.GetOrders(FToken, FAccountID, FMagaluOrders, ErroMsg) then

      begin

        Log('Erro ao buscar pedidos: ' + ErroMsg);

        Exit;

      end;

    finally

      Cliente.Free;

    end;



    Log(Format('%d pedido(s) encontrado(s).', [Length(FMagaluOrders)]));



    Grid.RowCount := Length(FMagaluOrders) + 1;

    if Grid.RowCount < 2 then

      Grid.RowCount := 2;



    for I := 1 to Grid.RowCount - 1 do

    begin

      Grid.Cells[0, I] := '';

      Grid.Cells[1, I] := '';

      Grid.Cells[2, I] := '';

      Grid.Cells[3, I] := '';

    end;



    for I := Low(FMagaluOrders) to High(FMagaluOrders) do

    begin

      Grid.Cells[0, I + 1] := FMagaluOrders[I].IdOrder;

      Grid.Cells[1, I + 1] := FMagaluOrders[I].Status;

      Grid.Cells[2, I + 1] := FMagaluOrders[I].OrderDate;

      Grid.Cells[3, I + 1] := FMagaluOrders[I].TotalAmount;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



procedure TFrmPedidosMarketplace.CarregarPedidosMercadoLivre;

var

  Cliente: TMercadoLivreOpenAPIClient;

  ErroMsg: string;

  TodosOsPedidos: TMercadoLivreOrderArray;

  PedidosFiltrados: TMercadoLivreOrderArray;

  I, DiasAtras, Total: Integer;

  DataCorte: TDateTime;

begin

  if (FDevClientId = '') or (FDevClientSecret = '') then

  begin

    Log('Credenciais de desenvolvedor do Mercado Livre nao cadastradas para esta ' +

      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');

    Exit;

  end;



  DiasAtras := StrToIntDef(edtDiasAtras.Text, 15);

  DataCorte := IncDay(Now, -DiasAtras);



  Screen.Cursor := crHourGlass;

  try

    Log(Format('Buscando pedidos dos ultimos %d dia(s)...', [DiasAtras]));



    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);

    Cliente.OnLog := Log;

    try

      if not Cliente.GetOrders(FToken, FAccountID, TodosOsPedidos, ErroMsg) then

      begin

        Log('Erro ao buscar pedidos: ' + ErroMsg);

        Exit;

      end;

    finally

      Cliente.Free;

    end;



    // {ATENCAO} orders/search NAO tem um parametro de filtro por data

    // confirmado (diferente do CreatedAfter da Amazon ou do time_range da

    // Shopee) - filtra em memoria mesmo, depois de buscar tudo. Se o

    // vendedor tiver muitos pedidos, isso pode ficar lento - revisar se

    // virar um problema real com volume.

    SetLength(PedidosFiltrados, Length(TodosOsPedidos));

    Total := 0;

    for I := Low(TodosOsPedidos) to High(TodosOsPedidos) do

      if TodosOsPedidos[I].DateCreated >= DataCorte then

      begin

        PedidosFiltrados[Total] := TodosOsPedidos[I];

        Inc(Total);

      end;

    SetLength(PedidosFiltrados, Total);

    FMercadoLivreOrders := PedidosFiltrados;



    Log(Format('%d pedido(s) encontrado(s) (de %d no total).',

      [Length(FMercadoLivreOrders), Length(TodosOsPedidos)]));



    Grid.RowCount := Length(FMercadoLivreOrders) + 1;

    if Grid.RowCount < 2 then

      Grid.RowCount := 2;



    for I := 1 to Grid.RowCount - 1 do

    begin

      Grid.Cells[0, I] := '';

      Grid.Cells[1, I] := '';

      Grid.Cells[2, I] := '';

      Grid.Cells[3, I] := '';

    end;



    for I := Low(FMercadoLivreOrders) to High(FMercadoLivreOrders) do

    begin

      Grid.Cells[0, I + 1] := FMercadoLivreOrders[I].OrderId;

      Grid.Cells[1, I + 1] := FMercadoLivreOrders[I].Status;

      Grid.Cells[2, I + 1] := FormatDateTime('dd/mm/yy hh:nn:ss', FMercadoLivreOrders[I].DateCreated);

      Grid.Cells[3, I + 1] := 'BRL ' + FormatFloat('0.00', FMercadoLivreOrders[I].TotalAmount);

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



procedure TFrmPedidosMarketplace.GridClick(Sender: TObject);

var

  OrderSN, Status: string;

  TemPedidoSelecionado: Boolean;

begin

  TemPedidoSelecionado := PedidoSelecionado(OrderSN);



  if TemPedidoSelecionado then

    Status := Grid.Cells[1, Grid.Row]

  else

    Status := '';



  // {FIX} Antes essas acoes so ficavam habilitadas pra Shopee (restricao

  // "and EhShopee" que sobrou de quando so a Shopee tinha as acoes

  // implementadas) - como Amazon e Magalu ja tem Despachar/Cancelar/etc

  // implementados nos handlers, essa restricao so estava travando o

  // acesso a esses botoes sem motivo. Removida.



  // Habilita as acoes de acordo com o status do pedido selecionado -

  // evita chamar uma acao que o marketplace com certeza vai rejeitar.

  // {ATENCAO} os valores de status abaixo (READY_TO_SHIP, IN_CANCEL etc)

  // sao especificos da Shopee - Amazon/Magalu ainda usam essa mesma

  // checagem generica "TemPedidoSelecionado" sem status, ja que os

  // handlers deles mostram mensagem apropriada quando a acao nao se

  // aplica (Cancelar/Etiqueta/NF ainda nao tem status exato mapeado pra

  // esses dois marketplaces).

  case TMarketplaces(FCodMarketplace) of

    TMarketplaces.Shopee:

      begin

        CmdDespachar.Enabled := TemPedidoSelecionado and (Status = 'READY_TO_SHIP');

        CmdCancelar.Enabled := TemPedidoSelecionado and (Status <> 'CANCELLED') and

          (Status <> 'COMPLETED');

        // Confirmado em teste real: a Shopee usa o status "IN_CANCEL" pra

        // pedido com cancelamento solicitado pelo comprador, aguardando

        // decisao do vendedor (erro visto: "Invalid order_status.The

        // order status should be IN_CANCEL").

        CmdAprovarCancelamento.Enabled := TemPedidoSelecionado and (Status = 'IN_CANCEL');

        CmdReprovarCancelamento.Enabled := TemPedidoSelecionado and (Status = 'IN_CANCEL');

        // Etiqueta e nota fiscal - nao temos certeza absoluta de QUAL

        // status exato a Shopee exige pra cada uma (nao documentado com

        // clareza) - deixa habilitado pra qualquer pedido nao cancelado,

        // e a propria API retorna erro se nao for aplicavel naquele

        // momento (mesmo padrao usado no Despachar/Cancelar).

        CmdGerarEtiqueta.Enabled := TemPedidoSelecionado and (Status <> 'CANCELLED');

        CmdBaixarEtiqueta.Enabled := CmdGerarEtiqueta.Enabled;

        CmdBaixarNF.Enabled := CmdGerarEtiqueta.Enabled;

        CmdEnviarNF.Enabled := CmdGerarEtiqueta.Enabled;

      end;

  else

    // Amazon e Magalu - os handlers ja sabem mostrar a mensagem certa

    // ("nao implementado", "use Seller Central" etc) quando a acao nao se

    // aplica, entao aqui so garante que da pra CLICAR (antes ficavam

    // travados por causa do "and EhShopee" que foi removido).

    CmdDespachar.Enabled := TemPedidoSelecionado;

    CmdCancelar.Enabled := TemPedidoSelecionado;

    CmdAprovarCancelamento.Enabled := TemPedidoSelecionado;

    CmdReprovarCancelamento.Enabled := TemPedidoSelecionado;

    CmdGerarEtiqueta.Enabled := TemPedidoSelecionado;

    CmdBaixarEtiqueta.Enabled := TemPedidoSelecionado;

    CmdBaixarNF.Enabled := TemPedidoSelecionado;

    CmdEnviarNF.Enabled := TemPedidoSelecionado;

  end;



  // "Baixar Pedido SAT" - unico botao valido pros 3 marketplaces (e' o

  // mesmo fluxo generico, uBaixaPedidoSAT), habilitado so quando o pedido

  // ja foi despachado (antes disso nao faz sentido gerar a venda no SAT).

  CmdBaixarPedidoSAT.Enabled := TemPedidoSelecionado and StatusIndicaDespachado(Status);

end;



function TFrmPedidosMarketplace.PedidoSelecionado(out AOrderSN: string): Boolean;

begin

  AOrderSN := '';

  Result := (Grid.Row >= 1) and (Grid.Row < Grid.RowCount) and

    (Trim(Grid.Cells[0, Grid.Row]) <> '');

  if Result then

    AOrderSN := Grid.Cells[0, Grid.Row];

end;



// Confere se o status do pedido selecionado corresponde a "ja despachado"

// no marketplace correspondente - cada marketplace usa um vocabulario

// diferente pra isso. Aceita tanto "despachado" quanto qualquer status

// POSTERIOR (entregue/concluido), ja que se o pedido chegou ate ali, com

// certeza ja foi despachado antes.

function TFrmPedidosMarketplace.StatusIndicaDespachado(const AStatus: string): Boolean;

begin

  case TMarketplaces(FCodMarketplace) of

    TMarketplaces.Shopee:

      // SHIPPED = despachado; COMPLETED = ja foi alem (entregue/concluido).

      Result := SameText(AStatus, 'SHIPPED') or SameText(AStatus, 'COMPLETED');

    TMarketplaces.Amazon:

      // A Amazon devolve o OrderStatus em PascalCase ("Shipped", nao

      // "SHIPPED") - SameText ja cobre isso sem se importar com caixa.

      Result := SameText(AStatus, 'Shipped');

    TMarketplaces.Magalu:

      // {ATENCAO} Fluxo de status do Magalu com confianca menor (ver

      // observacoes nas planilhas de-para) - SHIPPED e DELIVERED sao os

      // dois nomes mais prováveis pra "despachado em diante".

      Result := SameText(AStatus, 'SHIPPED') or SameText(AStatus, 'DELIVERED');

    TMarketplaces.TikTokShop:

      // Vocabulario proprio do TikTok. AWAITING_COLLECTION (pacote pronto,

      // esperando a transportadora) NAO entra: o vendedor ainda pode

      // cancelar nesse ponto, entao nao conta como despachado.

      Result := SameText(AStatus, 'IN_TRANSIT') or SameText(AStatus, 'DELIVERED') or

        SameText(AStatus, 'COMPLETED');

  else

    Result := False;

  end;

end;



procedure TFrmPedidosMarketplace.CmdDespacharClick(Sender: TObject);

var

  AmazonOrderId, CarrierCode, CarrierName, TrackingNumber, ErroMsg: string;

  ShipDate: TDateTime;

  ClienteAmazon: TAmazonSPAPIClient;

  ClienteMagalu: TMagaluOpenAPIClient;

  Items: TAmazonOrderItemArray;

  MagaluOrderId, DeliveryId: string;

  Deliveries: TMagaluDeliveryArray;

  ClienteTikTok: TTikTokShopOpenAPIClient;

  DetalheTikTok: TTikTokShopOrderDetail;

  TikTokOrderId, ShopIdTikTok, ShopCipherTikTok: string;

  TransportadorasTikTok: TTikTokShopTransportadoraArray;

  ShippingProviderId, ListaTransp, EscolhaTransp: string;

  I: Integer;

begin

  case TMarketplaces(FCodMarketplace) of

    TMarketplaces.Shopee:

      if MessageDlg('Confirma o despacho deste pedido?', mtConfirmation,

           [mbYes, mbNo], 0) = mrYes then

        ExecutarAcaoShopee('DESPACHAR');

    TMarketplaces.Amazon:

      begin

        if not PedidoSelecionado(AmazonOrderId) then

        begin

          ShowMessage('Selecione um pedido na lista primeiro.');

          Exit;

        end;

        // A Amazon exige transportadora/rastreio/data - a Shopee so pede

        // confirmacao, por isso esse fluxo usa uma tela dedicada em vez

        // do MessageDlg simples usado pra Shopee.

        if not TFrmDespacharAmazon.Coletar(CarrierCode, CarrierName,

             TrackingNumber, ShipDate) then

          Exit; // usuario cancelou

        Screen.Cursor := crHourGlass;

        try

          ClienteAmazon := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',

            uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);

          ClienteAmazon.OnLog := Log;

          try

            if not ClienteAmazon.GetOrderItems(FToken, AmazonOrderId, Items, ErroMsg) then

            begin

              Log('Falha ao buscar itens do pedido: ' + ErroMsg);

              ShowMessage('Falha ao buscar itens do pedido: ' + ErroMsg);

              Exit;

            end;

            if not ClienteAmazon.ConfirmShipment(FToken, AmazonOrderId, CarrierCode,

                 CarrierName, TrackingNumber, ShipDate, Items, ErroMsg) then

            begin

              Log('Falha ao despachar pedido: ' + ErroMsg);

              ShowMessage('Falha ao despachar pedido: ' + ErroMsg);

              Exit;

            end;

            ShowMessage('Pedido despachado com sucesso!');

            CarregarPedidos;

          finally

            ClienteAmazon.Free;

          end;

        finally

          Screen.Cursor := crDefault;

        end;

      end;

    TMarketplaces.Magalu:

      begin

        if not PedidoSelecionado(MagaluOrderId) then

        begin

          ShowMessage('Selecione um pedido na lista primeiro.');

          Exit;

        end;

        // {ATENCAO} O Magalu trata "pedido" e "entrega" como recursos

        // separados - o despacho precisa do ID da ENTREGA, nao do

        // pedido. Primeiro busca a(s) entrega(s) do pedido selecionado.

        if not InputQuery('Rastreio (opcional)',

             'Codigo de rastreio (deixe vazio se nao tiver ainda):', TrackingNumber) then

          Exit; // usuario cancelou

        Screen.Cursor := crHourGlass;

        try

          ClienteMagalu := TMagaluOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', '',

            FSandbox);

          ClienteMagalu.OnLog := Log;

          try

            if not ClienteMagalu.GetDeliveries(FToken, FAccountID, MagaluOrderId,

                 Deliveries, ErroMsg) then

            begin

              Log('Falha ao buscar entregas do pedido: ' + ErroMsg);

              ShowMessage('Falha ao buscar entregas do pedido: ' + ErroMsg);

              Exit;

            end;

            if Length(Deliveries) = 0 then

            begin

              ShowMessage('Nenhuma entrega encontrada pra esse pedido.');

              Exit;

            end;

            // Usa a primeira entrega encontrada - {ATENCAO} se um pedido

            // puder ter mais de uma entrega/pacote, isso precisa virar

            // uma escolha pro usuario em vez de pegar so a primeira.

            DeliveryId := Deliveries[0].Id;

            if not ClienteMagalu.MarkDeliveryShipped(FToken, FAccountID, DeliveryId,

                 TrackingNumber, ErroMsg) then

            begin

              Log('Falha ao despachar entrega: ' + ErroMsg);

              ShowMessage('Falha ao despachar entrega: ' + ErroMsg);

              Exit;

            end;

            ShowMessage('Pedido despachado com sucesso!');

            CarregarPedidos;

          finally

            ClienteMagalu.Free;

          end;

        finally

          Screen.Cursor := crDefault;

        end;

      end;

    TMarketplaces.TikTokShop:

      begin

        if not PedidoSelecionado(TikTokOrderId) then

        begin

          ShowMessage('Selecione um pedido na lista primeiro.');

          Exit;

        end;

        SepararShopIdECipherTikTok(FAccountID, ShopIdTikTok, ShopCipherTikTok);

        if ShopCipherTikTok = '' then

        begin

          ShowMessage('Vinculo do TikTok incompleto: falta o shop_cipher. ' +

            'Desconecte e conecte a loja novamente no SATLojas.');

          Exit;

        end;

        // {IMPORTANTE} no TikTok o despacho e' por PACOTE, nao por pedido -

        // por isso busca o detalhe antes, pra descobrir o package_id.

        // Rastreio vazio = "TikTok Shipping" (a plataforma envia); rastreio

        // preenchido = "Seller Shipping" (transportadora do vendedor).

        TrackingNumber := '';

        if not InputQuery('Rastreio (opcional)',

             'Codigo de rastreio - deixe VAZIO se o envio e por conta do TikTok:',

             TrackingNumber) then

          Exit; // usuario cancelou

        Screen.Cursor := crHourGlass;

        try

          ClienteTikTok := TTikTokShopOpenAPIClient.Create(FDevClientId,

            FDevClientSecret, '', FSandbox);

          ClienteTikTok.OnLog := Log;

          try

            if not ClienteTikTok.GetOrderDetail(FToken, ShopCipherTikTok,

                 TikTokOrderId, DetalheTikTok, ErroMsg) then

            begin

              Log('Falha ao buscar detalhe do pedido: ' + ErroMsg);

              ShowMessage('Falha ao buscar detalhe do pedido: ' + ErroMsg);

              Exit;

            end;

            if Length(DetalheTikTok.PackageIds) = 0 then

            begin

              ShowMessage('Este pedido ainda nao tem pacote gerado no TikTok - ' +

                'nao ha o que despachar.');

              Exit;

            end;

            if Length(DetalheTikTok.PackageIds) > 1 then

              Log(Format('Aviso: o pedido tem %d pacotes - despachando apenas o ' +

                'primeiro (%s). Os demais precisam ser despachados pelo painel ' +

                'do TikTok.', [Length(DetalheTikTok.PackageIds),

                DetalheTikTok.PackageIds[0]]));

            // {ATENCAO} no modo Seller Shipping o TikTok EXIGE o shipping_provider_id

            // junto do rastreio. Sem ele recusa de duas formas: 21004030 ("empty

            // provider id") quando nao vai rastreio, e 36009004 ("ShippingProviderId of

            // SelfShipment is a required field") quando vai. A lista vem do

            // GetShippingProviders; se ela falhar, deixa digitar o id na mao em vez de

            // travar o despacho.

            ShippingProviderId := '';

            if Trim(TrackingNumber) <> '' then

            begin

              if ClienteTikTok.GetShippingProviders(FToken, ShopCipherTikTok,

                   DetalheTikTok.DeliveryOptionId, TransportadorasTikTok, ErroMsg) and

                 (Length(TransportadorasTikTok) > 0) then

              begin

                ListaTransp := '';

                for I := Low(TransportadorasTikTok) to High(TransportadorasTikTok) do

                  ListaTransp := ListaTransp + IntToStr(I + 1) + ') ' +

                    TransportadorasTikTok[I].Nome + sLineBreak;

                EscolhaTransp := '1';

                if not InputQuery('Transportadora',

                     'Digite o NUMERO da transportadora:' + sLineBreak + sLineBreak +

                     ListaTransp, EscolhaTransp) then

                  Exit;

                I := StrToIntDef(Trim(EscolhaTransp), 0) - 1;

                if (I < Low(TransportadorasTikTok)) or (I > High(TransportadorasTikTok)) then

                begin

                  ShowMessage('Numero de transportadora invalido.');

                  Exit;

                end;

                ShippingProviderId := TransportadorasTikTok[I].Id;

              end

              else

              begin

                if ErroMsg <> '' then

                  Log('Nao foi possivel listar as transportadoras: ' + ErroMsg)

                else

                  Log('O TikTok nao devolveu transportadora nenhuma para esta loja.');

                if not InputQuery('Transportadora',

                     'Nao foi possivel listar as transportadoras do TikTok.' + sLineBreak +

                     'Digite o shipping_provider_id manualmente:', ShippingProviderId) then

                  Exit;

                if Trim(ShippingProviderId) = '' then

                begin

                  ShowMessage('Sem a transportadora o TikTok recusa o despacho.');

                  Exit;

                end;

              end;

            end;

            if not ClienteTikTok.ShipPackage(FToken, ShopCipherTikTok,

                 DetalheTikTok.PackageIds[0], TrackingNumber, ShippingProviderId, ErroMsg) then

            begin

              Log('Falha ao despachar pedido: ' + ErroMsg);

              ShowMessage('Falha ao despachar pedido: ' + ErroMsg);

              Exit;

            end;

            ShowMessage('Pedido despachado com sucesso!' + sLineBreak +

              'A etiqueta so fica disponivel para download a partir de agora.');

            CarregarPedidos;

          finally

            ClienteTikTok.Free;

          end;

        finally

          Screen.Cursor := crDefault;

        end;

      end;

  else

    Log('Despachar ainda nao implementado para este marketplace.');

  end;

end;



// Guarda das acoes de pedido que AINDA nao tem fluxo proprio pro Mercado

// Livre. Sem esse guard, elas caem no 'else' final, que e' o caminho da

// Shopee - e o ML acabaria chamando a API da Shopee com o token dele.

// {NOTA} o TikTok saiu daqui: com o scope seller.return_refund.basic, os

// cancelamentos passaram a ter fluxo proprio (ver os handlers). Onde ele

// ainda nao tem fluxo - as duas acoes de nota fiscal - o aviso e' dado por

// um 'if' explicito no proprio handler, igual Amazon e Magalu.

function TFrmPedidosMarketplace.AcaoIndisponivelNesteMarketplace(const AAcao: string): Boolean;

begin

  Result := TMarketplaces(FCodMarketplace) = TMarketplaces.MercadoLivre;

  if Result then

    ShowMessage(AAcao + ' ainda nao implementado para o Mercado Livre - esse'

      + ' fluxo ainda nao foi mapeado para a API dele nesta tela. Favor'

      + ' utilizar o portal do Mercado Livre (Vendas) para essa operacao.');

end;

// Prepara uma acao de cancelamento do TikTok: valida o vinculo da loja,

// localiza o pedido selecionado e busca o cancelamento PENDENTE dele.

// O TikTok identifica o pedido de cancelamento por "cancel_id", e a grade so'

// tem o id do pedido - por isso essa busca existe. Devolve False (ja tendo

// avisado o usuario) quando nao ha nada a decidir.

function TFrmPedidosMarketplace.PrepararCancelamentoTikTok(out AOrderSN,

  AShopCipher, ACancelId: string): Boolean;

var

  Cliente: TTikTokShopOpenAPIClient;

  ShopId, CancelStatus, ErroMsg: string;

begin

  Result := False;

  ACancelId := '';

  if not PedidoSelecionado(AOrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;

  SepararShopIdECipherTikTok(FAccountID, ShopId, AShopCipher);

  if AShopCipher = '' then

  begin

    ShowMessage('Vinculo do TikTok incompleto: falta o shop_cipher. Desconecte ' +

      'e conecte a loja novamente no SATLojas.');

    Exit;

  end;

  Screen.Cursor := crHourGlass;

  try

    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret,

      '', FSandbox);

    Cliente.OnLog := Log;

    try

      if not Cliente.SearchCancellations(FToken, AShopCipher, AOrderSN, ACancelId,

           CancelStatus, ErroMsg) then

      begin

        Log('Falha ao buscar o cancelamento: ' + ErroMsg);

        ShowMessage('Falha ao buscar o cancelamento: ' + ErroMsg);

        Exit;

      end;

    finally

      Cliente.Free;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

  if ACancelId = '' then

  begin

    ShowMessage('Este pedido nao tem pedido de cancelamento aguardando decisao.');

    Exit;

  end;

  Log('Cancelamento ' + ACancelId + ' (status: ' + CancelStatus + ')');

  Result := True;

end;

procedure TFrmPedidosMarketplace.CmdCancelarClick(Sender: TObject);

begin

  if AcaoIndisponivelNesteMarketplace('Cancelar pedido') then

    Exit;

  // {TODO} O TikTok TEM o endpoint de cancelamento pelo vendedor

  // (POST /return_refund/202309/cancellations, no scope

  // seller.return_refund.basic), mas ele exige um codigo de motivo de uma

  // lista propria - diferente da lista de recusa usada no Reprovar, e que

  // ainda nao foi mapeada. Implementar as cegas geraria pedido cancelado com

  // motivo errado, entao aqui avisa em vez de arriscar.

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    ShowMessage('Cancelamento pelo vendedor ainda nao implementado para o TikTok ' +

      'Shop - a API exige um codigo de motivo que ainda precisa ser mapeado. ' +

      'Favor utilizar o Seller Center do TikTok para essa operacao.' + sLineBreak +

      sLineBreak + 'Aprovar e Reprovar cancelamento pedido pelo COMPRADOR ja ' +

      'funcionam normalmente aqui.');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Amazon then

  begin

    ShowMessage('Cancelamento ainda nao implementado para a Amazon via API ' +

      '(exige a Feeds API, com submissao assincrona de arquivo, diferente do ' +

      'fluxo simples usado nos outros marketplaces). Favor utilizar a Seller ' +

      'Central para essa operacao.');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

  begin

    ShowMessage('Cancelamento nao esta disponivel via API para o Magalu - a Open API ' +

      'atual nao tem esse endpoint (cancelamento passa por abrir um protocolo dentro ' +

      'do Atendimento/SAC). Favor utilizar o Portal do Seller para essa operacao.');

    Exit;

  end;

  // {ATENCAO - PESQUISA INCONCLUSIVA 30/08/2026} pro Mercado Livre, tentamos

  // reconferir se existe endpoint de cancelamento pelo vendedor e NAO deu pra

  // confirmar nem descartar: o portal de developers do ML devolve HTTP 403 pra

  // leitura automatizada. O que se achou indica que o cancelamento dele passa

  // pelo sistema de RECLAMACOES/MEDIACOES (o tipo "cancel_sale" aparece la como

  // registro de cancelamento pelo vendedor), e nao por um endpoint simples como

  // o da Shopee. Ou seja: o guard abaixo continua valendo, mas por falta de

  // confirmacao, nao por certeza de ausencia - vale reabrir se alguem tiver

  // acesso logado a doc do ML.

  if MessageDlg('Confirma o cancelamento deste pedido?' + sLineBreak +

       '(so funciona em pedidos ainda nao pagos, ou com acordo previo do comprador)',

       mtConfirmation, [mbYes, mbNo], 0) = mrYes then

    ExecutarAcaoShopee('CANCELAR');

end;



procedure TFrmPedidosMarketplace.CmdAprovarCancelamentoClick(Sender: TObject);

var

  ClienteTikTok: TTikTokShopOpenAPIClient;

  OrderSNTikTok, ShopCipherTikTok, CancelIdTikTok, ErroMsgTikTok: string;

begin

  if AcaoIndisponivelNesteMarketplace('Aprovar cancelamento') then

    Exit;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    if not PrepararCancelamentoTikTok(OrderSNTikTok, ShopCipherTikTok,

         CancelIdTikTok) then

      Exit;

    if MessageDlg('Confirma a APROVACAO do cancelamento solicitado pelo comprador?',

         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then

      Exit;

    Screen.Cursor := crHourGlass;

    try

      ClienteTikTok := TTikTokShopOpenAPIClient.Create(FDevClientId,

        FDevClientSecret, '', FSandbox);

      ClienteTikTok.OnLog := Log;

      try

        if not ClienteTikTok.ApproveCancellation(FToken, ShopCipherTikTok,

             CancelIdTikTok, ErroMsgTikTok) then

        begin

          Log('Falha ao aprovar o cancelamento: ' + ErroMsgTikTok);

          ShowMessage('Falha ao aprovar o cancelamento: ' + ErroMsgTikTok);

          Exit;

        end;

      finally

        ClienteTikTok.Free;

      end;

    finally

      Screen.Cursor := crDefault;

    end;

    ShowMessage('Cancelamento aprovado com sucesso!');

    CarregarPedidos;

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Amazon then

  begin

    ShowMessage('Aprovar cancelamento nao esta disponivel via API para a Amazon ' +

      '(pedidos MFN nao tem esse fluxo de API - o comprador solicita e o ' +

      'vendedor trata direto no Seller Central). Favor utilizar a Seller ' +

      'Central para essa operacao.');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

  begin

    ShowMessage('Aprovar cancelamento nao esta disponivel via API para o Magalu - a ' +

      'Open API atual nao tem esse endpoint (fica dentro do fluxo de protocolo do ' +

      'Atendimento/SAC). Favor utilizar o Portal do Seller para essa operacao.');

    Exit;

  end;

  if MessageDlg('Confirma a APROVACAO do cancelamento solicitado pelo comprador?',

       mtConfirmation, [mbYes, mbNo], 0) = mrYes then

    ExecutarAcaoShopee('APROVAR_CANCELAMENTO');

end;



procedure TFrmPedidosMarketplace.CmdReprovarCancelamentoClick(Sender: TObject);

var

  ClienteTikTok: TTikTokShopOpenAPIClient;

  OrderSNTikTok, ShopCipherTikTok, CancelIdTikTok, ErroMsgTikTok: string;

  MotivosTikTok: TArray<string>;

  ListaMotivos, EscolhaMotivo: string;

  I: Integer;

begin

  if AcaoIndisponivelNesteMarketplace('Reprovar cancelamento') then

    Exit;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    if not PrepararCancelamentoTikTok(OrderSNTikTok, ShopCipherTikTok,

         CancelIdTikTok) then

      Exit;

    Screen.Cursor := crHourGlass;

    try

      ClienteTikTok := TTikTokShopOpenAPIClient.Create(FDevClientId,

        FDevClientSecret, '', FSandbox);

      ClienteTikTok.OnLog := Log;

      try

        // {ATENCAO} o motivo da recusa NAO e' texto livre - tem que ser uma

        // das chaves que o proprio TikTok aceita PARA ESTE cancelamento.

        if not ClienteTikTok.GetRejectReasons(FToken, ShopCipherTikTok,

             CancelIdTikTok, MotivosTikTok, ErroMsgTikTok) then

        begin

          Log('Falha ao listar os motivos de recusa: ' + ErroMsgTikTok);

          ShowMessage('Falha ao listar os motivos de recusa: ' + ErroMsgTikTok);

          Exit;

        end;

        if Length(MotivosTikTok) = 0 then

        begin

          ShowMessage('O TikTok nao devolveu nenhum motivo de recusa aplicavel a ' +

            'este cancelamento - pode ser que ele ja nao aceite mais recusa.');

          Exit;

        end;

        // Monta a lista numerada. {TODO} trocar por uma tela de escolha se o

        // cliente reclamar - hoje e' um InputQuery com o numero do motivo,

        // que resolve sem inventar formulario novo.

        ListaMotivos := '';

        for I := Low(MotivosTikTok) to High(MotivosTikTok) do

          ListaMotivos := ListaMotivos + IntToStr(I + 1) + ') ' +

            Copy(MotivosTikTok[I], Pos('|', MotivosTikTok[I]) + 1, MaxInt) + sLineBreak;

        EscolhaMotivo := '1';

        if not InputQuery('Motivo da recusa',

             'Digite o NUMERO do motivo:' + sLineBreak + sLineBreak + ListaMotivos,

             EscolhaMotivo) then

          Exit;

        I := StrToIntDef(Trim(EscolhaMotivo), 0) - 1;

        if (I < Low(MotivosTikTok)) or (I > High(MotivosTikTok)) then

        begin

          ShowMessage('Numero de motivo invalido.');

          Exit;

        end;

        // Envia a CHAVE (parte antes do "|"), nao o texto mostrado.

        if not ClienteTikTok.RejectCancellation(FToken, ShopCipherTikTok,

             CancelIdTikTok,

             Copy(MotivosTikTok[I], 1, Pos('|', MotivosTikTok[I]) - 1),

             ErroMsgTikTok) then

        begin

          Log('Falha ao reprovar o cancelamento: ' + ErroMsgTikTok);

          ShowMessage('Falha ao reprovar o cancelamento: ' + ErroMsgTikTok);

          Exit;

        end;

      finally

        ClienteTikTok.Free;

      end;

    finally

      Screen.Cursor := crDefault;

    end;

    ShowMessage('Cancelamento reprovado com sucesso!');

    CarregarPedidos;

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Amazon then

  begin

    ShowMessage('Reprovar cancelamento nao esta disponivel via API para a Amazon ' +

      '(pedidos MFN nao tem esse fluxo de API - o comprador solicita e o ' +

      'vendedor trata direto no Seller Central). Favor utilizar a Seller ' +

      'Central para essa operacao.');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

  begin

    ShowMessage('Reprovar cancelamento nao esta disponivel via API para o Magalu - a ' +

      'Open API atual nao tem esse endpoint (fica dentro do fluxo de protocolo do ' +

      'Atendimento/SAC). Favor utilizar o Portal do Seller para essa operacao.');

    Exit;

  end;

  if MessageDlg('Confirma a REPROVACAO do cancelamento solicitado pelo comprador?',

       mtConfirmation, [mbYes, mbNo], 0) = mrYes then

    ExecutarAcaoShopee('REPROVAR_CANCELAMENTO');

end;



procedure TFrmPedidosMarketplace.SalvarPdfEmDisco(const APdfBytes: TBytes;

  const ANomeSugerido: string);

begin

  if Length(APdfBytes) = 0 then

  begin

    Log('Nada para salvar - o arquivo recebido veio vazio.');

    Exit;

  end;



  SaveDialog1.FileName := ANomeSugerido;

  SaveDialog1.Filter := 'Arquivo PDF (*.pdf)|*.pdf';

  SaveDialog1.DefaultExt := 'pdf';



  if SaveDialog1.Execute then

  begin

    TFile.WriteAllBytes(SaveDialog1.FileName, APdfBytes);

    Log('Arquivo salvo em: ' + SaveDialog1.FileName);

    if MessageDlg('Arquivo salvo com sucesso. Deseja abrir agora?', mtConfirmation,

         [mbYes, mbNo], 0) = mrYes then

      ShellExecute(0, 'open', PChar(SaveDialog1.FileName), nil, nil, SW_SHOWNORMAL);

  end;

end;



procedure TFrmPedidosMarketplace.CmdGerarEtiquetaClick(Sender: TObject);

var

  Cliente: TShopeeOpenAPIClient;

  OrderSN, ErroMsg: string;

begin

  if TMarketplaces(FCodMarketplace) = TMarketplaces.MercadoLivre then

  begin

    ShowMessage('O Mercado Livre nao tem passo de "gerar etiqueta" - a etiqueta do ' +

      'Mercado Envios ja fica pronta assim que o envio e criado. Use direto o botao ' +

      '"Baixar Etiqueta".');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    ShowMessage('O TikTok Shop nao tem passo de "gerar etiqueta": a etiqueta so ' +

      'passa a existir DEPOIS que o pedido e despachado.' + sLineBreak + sLineBreak +

      'A ordem correta e: 1) "Despachar"  ->  2) "Baixar Etiqueta".');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Amazon then

  begin

    ShowMessage('Gerar Etiqueta nao esta disponivel via API para a Amazon nesse ' +

      'marketplace - a Merchant Fulfillment API nao cobre o Brasil (so Canada, EUA, ' +

      'Mexico, Espanha, Reino Unido, Franca, Alemanha, Italia e India). Favor usar ' +

      'sua transportadora diretamente.');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

  begin

    ShowMessage('Gerar Etiqueta ainda nao implementado para o Magalu - so se aplica ' +

      'a quem usa o servico "Magalu Entregas" (opcional), e nao encontramos o ' +

      'endpoint na Open API atual (so na API antiga/Integra, possivelmente ' +

      'depreciada). Favor gerar a etiqueta pelo Portal do Seller.');

    Exit;

  end;

  if not PedidoSelecionado(OrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;



  Screen.Cursor := crHourGlass;

  try

    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

      FDevClientSecret, '', FSandbox);

    Cliente.OnLog := Log;

    try

      if Cliente.CreateShippingDocument(FToken, StrToInt64Def(FAccountID, 0),

           OrderSN, ErroMsg) then

        Log('Etiqueta solicitada com sucesso para o pedido ' + OrderSN +

          '. Aguarde alguns segundos e clique em "Baixar Etiqueta".')

      else

        Log('Falha ao solicitar etiqueta do pedido ' + OrderSN + ': ' + ErroMsg);

    finally

      Cliente.Free;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



procedure TFrmPedidosMarketplace.CmdBaixarEtiquetaClick(Sender: TObject);

var

  Cliente: TShopeeOpenAPIClient;

  OrderSN, ErroMsg, StatusEtiqueta: string;

  ClienteML: TMercadoLivreOpenAPIClient;

  DetalheML: TMercadoLivreOrderDetail;

  ClienteTikTok: TTikTokShopOpenAPIClient;

  DetalheTikTok: TTikTokShopOrderDetail;

  ShopIdTikTok, ShopCipherTikTok, UrlEtiqueta, TipoDocTikTok: string;

  PdfBytes: TBytes;

begin

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Amazon then

  begin

    ShowMessage('Baixar Etiqueta nao esta disponivel via API para a Amazon nesse ' +

      'marketplace - a Merchant Fulfillment API nao cobre o Brasil. Favor usar sua ' +

      'transportadora diretamente.');

    Exit;

  end;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

  begin

    ShowMessage('Baixar Etiqueta ainda nao implementado para o Magalu - endpoint da ' +

      'Open API atual nao confirmado. Favor gerar/baixar a etiqueta pelo Portal do ' +

      'Seller (se usar o servico "Magalu Entregas").');

    Exit;

  end;

  if not PedidoSelecionado(OrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;


  // Mercado Livre: a etiqueta do Mercado Envios ja nasce pronta junto com o

  // envio - nao existe o passo de "gerar" que a Shopee tem, so' o download.

  // O PDF e' buscado pelo shipping.id, entao pega o detalhe do pedido antes.

  if TMarketplaces(FCodMarketplace) = TMarketplaces.MercadoLivre then

  begin

    Screen.Cursor := crHourGlass;

    try

      ClienteML := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,

        '', FSandbox);

      ClienteML.OnLog := Log;

      try

        if not ClienteML.GetOrderDetail(FToken, OrderSN, DetalheML, ErroMsg) then

        begin

          Log('Falha ao buscar detalhe do pedido: ' + ErroMsg);

          ShowMessage('Falha ao buscar detalhe do pedido: ' + ErroMsg);

          Exit;

        end;

        if Trim(DetalheML.ShippingId) = '' then

        begin

          ShowMessage('Este pedido nao tem envio do Mercado Envios associado - ' +

            'nao ha etiqueta para baixar.');

          Exit;

        end;

        if not ClienteML.DownloadShipmentLabel(FToken, DetalheML.ShippingId,

             PdfBytes, ErroMsg) then

        begin

          Log('Falha ao baixar etiqueta: ' + ErroMsg);

          ShowMessage('Falha ao baixar etiqueta: ' + ErroMsg);

          Exit;

        end;

      finally

        ClienteML.Free;

      end;

    finally

      Screen.Cursor := crDefault;

    end;

    SalvarPdfEmDisco(PdfBytes, 'etiqueta_' + OrderSN + '.pdf');

    Exit;

  end;



  // TikTok Shop: a etiqueta e' por PACOTE, e a API NAO devolve o PDF - ela

  // devolve uma URL temporaria. Por isso aqui nao ha SalvarPdfEmDisco: abre

  // a URL no navegador padrao e o usuario salva/imprime de la.

  // {IMPORTANTE} confirmado na descricao do scope seller.fulfillment.basic no

  // Partner Center: "To obtain the shipping documents URL via this API, first

  // call Ship Package". Ou seja, a etiqueta so' existe DEPOIS do despacho -

  // por isso a mensagem de erro abaixo manda despachar, e nao "aguardar".

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    SepararShopIdECipherTikTok(FAccountID, ShopIdTikTok, ShopCipherTikTok);

    if ShopCipherTikTok = '' then

    begin

      ShowMessage('Vinculo do TikTok incompleto: falta o shop_cipher. Desconecte e ' +

        'conecte a loja novamente no SATLojas.');

      Exit;

    end;

    Screen.Cursor := crHourGlass;

    try

      ClienteTikTok := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret,

        '', FSandbox);

      ClienteTikTok.OnLog := Log;

      try

        if not ClienteTikTok.GetOrderDetail(FToken, ShopCipherTikTok, OrderSN,

             DetalheTikTok, ErroMsg) then

        begin

          Log('Falha ao buscar detalhe do pedido: ' + ErroMsg);

          ShowMessage('Falha ao buscar detalhe do pedido: ' + ErroMsg);

          Exit;

        end;

        if Length(DetalheTikTok.PackageIds) = 0 then

        begin

          ShowMessage('Este pedido ainda nao tem pacote gerado no TikTok - nao ha ' +

            'etiqueta para baixar.');

          Exit;

        end;

        if not StatusIndicaDespachado(Grid.Cells[1, Grid.Row]) then

          if MessageDlg('Este pedido ainda nao aparece como despachado. No TikTok a ' +

               'etiqueta so fica disponivel DEPOIS do despacho, entao a chamada ' +

               'provavelmente vai falhar.' + sLineBreak + sLineBreak +

               'Tentar mesmo assim?', mtWarning, [mbYes, mbNo], 0) <> mrYes then

            Exit;

        // Um pedido pode ter mais de um pacote (envio parcial). Baixa o

        // primeiro e avisa quando houver outros, em vez de abrir varias

        // abas de navegador sem o usuario pedir.

        // {ATENCAO} pedido "Shipped by seller" nao tem etiqueta do TikTok - a

        // transportadora e do lojista, entao quem emite o documento de transporte e

        // ela. Pedir SHIPPING_LABEL nesse caso volta com o erro 21042103. Tenta a

        // LISTA DE SEPARACAO, que e o PDF que o Seller Center oferece em "Imprimir".

        if SameText(Trim(DetalheTikTok.ShippingType), 'SELLER') then

          TipoDocTikTok := 'PACKING_SLIP'

        else

          TipoDocTikTok := 'SHIPPING_LABEL';

        if not ClienteTikTok.GetShippingLabelUrl(FToken, ShopCipherTikTok,

             DetalheTikTok.PackageIds[0], TipoDocTikTok, UrlEtiqueta, ErroMsg) then

        begin

          Log('Falha ao obter a etiqueta: ' + ErroMsg);

          if SameText(Trim(DetalheTikTok.ShippingType), 'SELLER') then

            ShowMessage('Este pedido e "Shipped by seller": o envio e por conta da' +

              ' loja, entao o TikTok nao emite etiqueta para ele.' + sLineBreak +

              sLineBreak + 'Use a opcao Imprimir no Seller Center, ou a etiqueta da' +

              ' propria transportadora.' + sLineBreak + sLineBreak + 'Retorno: ' + ErroMsg)

          else

            ShowMessage('Falha ao obter a etiqueta: ' + ErroMsg);


          Exit;

        end;

        if Length(DetalheTikTok.PackageIds) > 1 then

          Log(Format('Aviso: o pedido tem %d pacotes - abrindo a etiqueta do ' +

            'primeiro (%s). Os demais precisam ser baixados pelo painel do TikTok.',

            [Length(DetalheTikTok.PackageIds), DetalheTikTok.PackageIds[0]]));

      finally

        ClienteTikTok.Free;

      end;

    finally

      Screen.Cursor := crDefault;

    end;

    Log('Etiqueta disponivel em: ' + UrlEtiqueta);

    ShellExecute(0, 'open', PChar(UrlEtiqueta), nil, nil, SW_SHOWNORMAL);

    Exit;

  end;



  Screen.Cursor := crHourGlass;

  try

    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

      FDevClientSecret, '', FSandbox);

    Cliente.OnLog := Log;

    try

      if not Cliente.GetShippingDocumentResult(FToken, StrToInt64Def(FAccountID, 0),

           OrderSN, StatusEtiqueta, ErroMsg) then

      begin

        Log('Falha ao consultar status da etiqueta: ' + ErroMsg);

        Exit;

      end;



      Log('Status da etiqueta: ' + StatusEtiqueta);



      // {ATENCAO} nao tenho certeza absoluta do texto exato que a Shopee usa

      // pra "pronto" (pode ser "READY"/"SUCCESS"/etc) - tratando qualquer

      // coisa que nao pareca "ainda processando" ou "falhou" como pronto pra

      // tentar baixar. Se vier um status diferente do esperado, o log acima

      // ja mostra o texto exato pra gente ajustar.

      if StatusEtiqueta.ToUpper.Contains('PROCESS') then

      begin

        ShowMessage('A etiqueta ainda esta sendo gerada (status: ' + StatusEtiqueta +

          '). Aguarde mais alguns segundos e tente novamente.');

        Exit;

      end;



      if StatusEtiqueta.ToUpper.Contains('FAIL') then

      begin

        ShowMessage('Falha ao gerar a etiqueta (status: ' + StatusEtiqueta + ').');

        Exit;

      end;



      if not Cliente.DownloadShippingDocument(FToken, StrToInt64Def(FAccountID, 0),

           OrderSN, PdfBytes, ErroMsg) then

      begin

        Log('Falha ao baixar etiqueta: ' + ErroMsg);

        Exit;

      end;



      SalvarPdfEmDisco(PdfBytes, 'etiqueta_' + OrderSN + '.pdf');

    finally

      Cliente.Free;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



procedure TFrmPedidosMarketplace.CmdBaixarNFClick(Sender: TObject);

var

  ClienteShopee: TShopeeOpenAPIClient;

  ClienteAmazon: TAmazonSPAPIClient;

  OrderSN, ErroMsg, StatusNF: string;

  PdfBytes: TBytes;

begin

  if AcaoIndisponivelNesteMarketplace('Baixar Nota Fiscal') then

    Exit;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    ShowMessage('Nota fiscal ainda nao implementada para o TikTok Shop nesta tela. ' +

      'Favor utilizar o Seller Center do TikTok para essa operacao.');

    Exit;

  end;

  if not PedidoSelecionado(OrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;



  case TMarketplaces(FCodMarketplace) of

    TMarketplaces.Amazon:

      begin

        // A Amazon nao gera/devolve o documento - quem emite a NF-e e' o
        // proprio vendedor (fora da Amazon). Aqui so' da pra consultar o
        // STATUS do que ja foi enviado, nao baixar um arquivo.

        Screen.Cursor := crHourGlass;

        try

          ClienteAmazon := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',

            uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);

          ClienteAmazon.OnLog := Log;

          try

            if ClienteAmazon.GetDeliveryInvoiceStatus(FToken, OrderSN, StatusNF, ErroMsg) then

              ShowMessage('Status da nota fiscal do pedido ' + OrderSN + ': ' + StatusNF)

            else

              begin

                Log('Falha ao consultar status da nota fiscal: ' + ErroMsg);

                ShowMessage('Falha ao consultar status da nota fiscal: ' + ErroMsg);

              end;

          finally

            ClienteAmazon.Free;

          end;

        finally

          Screen.Cursor := crDefault;

        end;

      end;

  else

    if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

    begin

      ShowMessage('Baixar Nota Fiscal ainda nao implementado para o Magalu. ' +

        'Favor utilizar o Portal do Seller para essa operacao.');

      Exit;

    end;



    Screen.Cursor := crHourGlass;

    try

      ClienteShopee := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

        FDevClientSecret, '', FSandbox);

      ClienteShopee.OnLog := Log;

      try

        if not ClienteShopee.DownloadInvoiceDoc(FToken, StrToInt64Def(FAccountID, 0),

             OrderSN, PdfBytes, ErroMsg) then

        begin

          Log('Falha ao baixar nota fiscal: ' + ErroMsg);

          Exit;

        end;



        SalvarPdfEmDisco(PdfBytes, 'nota_fiscal_' + OrderSN + '.pdf');

      finally

        ClienteShopee.Free;

      end;

    finally

      Screen.Cursor := crDefault;

    end;

  end;

end;



procedure TFrmPedidosMarketplace.CmdEnviarNFClick(Sender: TObject);

var

  ClienteShopee: TShopeeOpenAPIClient;

  ClienteAmazon: TAmazonSPAPIClient;

  OrderSN, ErroMsg: string;

  FileBytes: TBytes;

begin

  if AcaoIndisponivelNesteMarketplace('Enviar Nota Fiscal') then

    Exit;

  if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

  begin

    ShowMessage('Nota fiscal ainda nao implementada para o TikTok Shop nesta tela. ' +

      'Favor utilizar o Seller Center do TikTok para essa operacao.');

    Exit;

  end;

  if not PedidoSelecionado(OrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;



  case TMarketplaces(FCodMarketplace) of

    TMarketplaces.Amazon:

      begin

        // A Amazon quer o XML da NF-e (ja emitida no seu sistema fiscal),
        // NAO um PDF - por isso o filtro do dialogo e' diferente do
        // usado pra Shopee.

        OpenDialog1.Filter := 'Arquivo XML (*.xml)|*.xml';

        if not OpenDialog1.Execute then

          Exit;

        if MessageDlg('Confirma o envio do arquivo' + sLineBreak + OpenDialog1.FileName +

             sLineBreak + 'como XML da nota fiscal do pedido ' + OrderSN + '?' + sLineBreak +

             '(ATENCAO: essa API exige aprovacao previa da Amazon - role "Tax Invoicing ' +

             'Restricted" - pode falhar com HTTP 403 se ainda nao tiver sido aprovada)',

             mtConfirmation, [mbYes, mbNo], 0) <> mrYes then

          Exit;

        Screen.Cursor := crHourGlass;

        try

          FileBytes := TFile.ReadAllBytes(OpenDialog1.FileName);

          ClienteAmazon := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',

            uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);

          ClienteAmazon.OnLog := Log;

          try

            if ClienteAmazon.SubmitDeliveryInvoice(FToken, OrderSN, FileBytes, ErroMsg) then

              ShowMessage('Nota fiscal enviada com sucesso para o pedido ' + OrderSN + '.')

            else

              begin

                Log('Falha ao enviar nota fiscal do pedido ' + OrderSN + ': ' + ErroMsg);

                ShowMessage('Falha ao enviar nota fiscal: ' + ErroMsg);

              end;

          finally

            ClienteAmazon.Free;

          end;

        finally

          Screen.Cursor := crDefault;

        end;

      end;

  else

    if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

    begin

      ShowMessage('Enviar Nota Fiscal ainda nao implementado para o Magalu. ' +

        'Favor utilizar o Portal do Seller para essa operacao.');

      Exit;

    end;



    OpenDialog1.Filter := 'Arquivo PDF (*.pdf)|*.pdf';

    if not OpenDialog1.Execute then

      Exit;



    if MessageDlg('Confirma o envio do arquivo' + sLineBreak + OpenDialog1.FileName +

         sLineBreak + 'como nota fiscal do pedido ' + OrderSN + '?',

         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then

      Exit;



    Screen.Cursor := crHourGlass;

    try

      FileBytes := TFile.ReadAllBytes(OpenDialog1.FileName);



      ClienteShopee := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

        FDevClientSecret, '', FSandbox);

      ClienteShopee.OnLog := Log;

      try

        if ClienteShopee.UploadInvoiceDoc(FToken, StrToInt64Def(FAccountID, 0),

             OrderSN, FileBytes, ErroMsg) then

          Log('Nota fiscal enviada com sucesso para o pedido ' + OrderSN + '.')

        else

          Log('Falha ao enviar nota fiscal do pedido ' + OrderSN + ': ' + ErroMsg);

      finally

        ClienteShopee.Free;

      end;

    finally

      Screen.Cursor := crDefault;

    end;

  end;

end;



procedure TFrmPedidosMarketplace.ExecutarAcaoShopee(const AAcao: string);

var

  Cliente: TShopeeOpenAPIClient;

  OrderSN, ErroMsg: string;

  Sucesso: Boolean;

begin

  if not PedidoSelecionado(OrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;



  if (FDevClientId = '') or (FDevClientSecret = '') then

  begin

    Log('Credenciais de desenvolvedor da Shopee nao cadastradas para esta ' +

      'loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV na tabela Lojas).');

    Exit;

  end;



  Screen.Cursor := crHourGlass;

  try

    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

      FDevClientSecret, '', FSandbox);

    Cliente.OnLog := Log;

    try

      Sucesso := False;

      case AnsiIndexStr(AAcao,

        ['DESPACHAR', 'CANCELAR', 'APROVAR_CANCELAMENTO', 'REPROVAR_CANCELAMENTO']) of

        0: Sucesso := Cliente.ShipOrder(FToken, StrToInt64Def(FAccountID, 0),

             OrderSN, ErroMsg);

        1: Sucesso := Cliente.CancelOrder(FToken, StrToInt64Def(FAccountID, 0),

             OrderSN, 'OUT_OF_STOCK', ErroMsg);

        2: Sucesso := Cliente.HandleBuyerCancellation(FToken,

             StrToInt64Def(FAccountID, 0), OrderSN, 'ACCEPT', ErroMsg);

        3: Sucesso := Cliente.HandleBuyerCancellation(FToken,

             StrToInt64Def(FAccountID, 0), OrderSN, 'REJECT', ErroMsg);

      end;



      if Sucesso then

      begin

        Log('OK - ' + AAcao + ' aplicado ao pedido ' + OrderSN + '.');

        CarregarPedidos; // atualiza a lista/status

      end

      else

        Log('Falha (' + AAcao + ') no pedido ' + OrderSN + ': ' + ErroMsg);

    finally

      Cliente.Free;

    end;

  finally

    Screen.Cursor := crDefault;

  end;

end;



// ----------------------------------------------------------------------------
// Baixar Pedido SAT - mapeamentos de campo "-> OBS" (Nome em portugues,
// vindo da Descricao da planilha de-para, nao o nome cru da API) para
// Shopee. Usados pra montar o texto de oe.obs / ioe.obs no formato
// "Nome -> Valor" pedido pelo cliente.
// ----------------------------------------------------------------------------
type
  TMapeamentoObs = record
    Caminho: string; // caminho no JSON (ponto-separado se for campo aninhado)
    Rotulo: string;  // nome em portugues, da coluna "Descricao" do de-para
  end;

const
  // Pedido (get_order_detail) - vao pra oe.obs
  MAPA_OBS_PEDIDO: array[0..17] of TMapeamentoObs = (
    (Caminho: 'pay_time'; Rotulo: 'Data/hora do pagamento'),
    (Caminho: 'currency'; Rotulo: 'Moeda'),
    (Caminho: 'estimated_shipping_fee'; Rotulo: 'Frete estimado'),
    (Caminho: 'actual_shipping_fee_confirmed'; Rotulo: 'Se o frete real ja foi confirmado'),
    (Caminho: 'package_list'; Rotulo: 'Lista de pacotes do pedido'),
    (Caminho: 'split_up'; Rotulo: 'Se o pedido foi dividido em multiplos pacotes'),
    (Caminho: 'payment_method'; Rotulo: 'Forma de pagamento'),
    (Caminho: 'credit_card_number'; Rotulo: 'Ultimos digitos do cartao'),
    (Caminho: 'buyer_cancel_reason'; Rotulo: 'Motivo de cancelamento informado pelo comprador'),
    (Caminho: 'cancel_by'; Rotulo: 'Quem cancelou'),
    (Caminho: 'cancel_reason'; Rotulo: 'Motivo do cancelamento'),
    (Caminho: 'note'; Rotulo: 'Observacao do vendedor sobre o pedido'),
    (Caminho: 'note_update_time'; Rotulo: 'Data/hora da ultima alteracao da observacao'),
    (Caminho: 'dropshipper'; Rotulo: 'Nome do dropshipper'),
    (Caminho: 'dropshipper_phone'; Rotulo: 'Telefone do dropshipper'),
    (Caminho: 'goods_to_declare'; Rotulo: 'Declaracao alfandegaria'),
    (Caminho: 'fulfillment_flag'; Rotulo: 'Indicador de tipo de atendimento'),
    (Caminho: 'invoice_data'; Rotulo: 'Dados de nota fiscal')
  );
  // Pagamento (get_escrow_detail) - tambem vao pra oe.obs (junto com os
  // de cima, no mesmo campo - e' assim que o de-para do cliente pediu)
  MAPA_OBS_PAGAMENTO: array[0..18] of TMapeamentoObs = (
    (Caminho: 'buyer_total_amount'; Rotulo: 'Valor total pago pelo comprador'),
    (Caminho: 'buyer_payment_info.payment_method'; Rotulo: 'Forma de pagamento usada pelo comprador'),
    (Caminho: 'buyer_payment_info.card_no'; Rotulo: 'Ultimos digitos do cartao (pagamento)'),
    (Caminho: 'actual_shipping_fee'; Rotulo: 'Frete real (financeiro)'),
    (Caminho: 'buyer_paid_shipping_fee'; Rotulo: 'Frete pago pelo comprador'),
    (Caminho: 'shipping_fee_rebate_from_shopee'; Rotulo: 'Reembolso de frete dado pela Shopee'),
    (Caminho: 'reverse_shipping_fee'; Rotulo: 'Frete de devolucao'),
    (Caminho: 'transaction_fee'; Rotulo: 'Taxa de transacao'),
    (Caminho: 'commission_fee'; Rotulo: 'Comissao da Shopee'),
    (Caminho: 'service_fee'; Rotulo: 'Taxa de servico'),
    (Caminho: 'buyer_transaction_fee'; Rotulo: 'Taxa de transacao cobrada do comprador'),
    (Caminho: 'insurance_fee'; Rotulo: 'Taxa de seguro'),
    (Caminho: 'vat'; Rotulo: 'Imposto (VAT)'),
    (Caminho: 'seller_withholding_tax'; Rotulo: 'Imposto retido na fonte do vendedor'),
    (Caminho: 'coins'; Rotulo: 'Moedas Shopee usadas pelo comprador'),
    (Caminho: 'voucher_from_seller'; Rotulo: 'Cupom de desconto custeado pelo vendedor'),
    (Caminho: 'voucher_from_shopee'; Rotulo: 'Cupom de desconto custeado pela Shopee'),
    (Caminho: 'credit_card_promotion'; Rotulo: 'Promocao de cartao de credito aplicada'),
    (Caminho: 'return_order_sn_list'; Rotulo: 'Lista de numeros de devolucao vinculados')
  );
  // Itens do pedido (item_list, dentro do get_order_detail) - vao pra ioe.obs
  MAPA_OBS_ITEM: array[0..5] of TMapeamentoObs = (
    (Caminho: 'item_name'; Rotulo: 'Nome do produto'),
    (Caminho: 'model_id'; Rotulo: 'ID da variacao'),
    (Caminho: 'model_sku'; Rotulo: 'SKU da variacao'),
    (Caminho: 'promotion_group_id'; Rotulo: 'ID de promocao aplicada'),
    (Caminho: 'product_location_id'; Rotulo: 'Localizacao/armazem do produto'),
    // {DECISAO DO CLIENTE - 24/08} order_item_id nao vai mais pra
    // ioe.id_item (que passou a ser incremental/gerado pelo banco) -
    // agora entra aqui no OBS.
    (Caminho: 'order_item_id'; Rotulo: 'ID do item do pedido no marketplace')
  );
  // Detalhamento financeiro por item (get_escrow_detail.items[]) - tambem
  // vao pra ioe.obs. {ATENCAO} estrutura do items[] dentro do escrow
  // NAO confirmada contra resposta real ainda - ExtrairCamposObsItemEscrow
  // busca por item_id/order_item_id dentro do array, mas se o formato
  // real for diferente, esses campos simplesmente ficam vazios (nao
  // quebra nada, so' nao preenche).
  MAPA_OBS_ITEM_ESCROW: array[0..8] of TMapeamentoObs = (
    (Caminho: 'original_price'; Rotulo: 'Preco original (detalhamento financeiro)'),
    (Caminho: 'sale_price'; Rotulo: 'Preco de venda'),
    (Caminho: 'discounted_price'; Rotulo: 'Preco ja com desconto'),
    (Caminho: 'seller_discount'; Rotulo: 'Desconto custeado pelo vendedor'),
    (Caminho: 'shopee_discount'; Rotulo: 'Desconto custeado pela Shopee'),
    (Caminho: 'is_wholesale'; Rotulo: 'Se e venda no atacado'),
    (Caminho: 'is_add_on_deal'; Rotulo: 'Se e item de oferta adicional'),
    (Caminho: 'is_main_item'; Rotulo: 'Se e o item principal do pedido'),
    (Caminho: 'weight'; Rotulo: 'Peso do item')
  );

  // --- Amazon (Orders API v0) - MAPEAMENTO PROPOSTO, nao confirmado
  // formalmente pelo cliente ainda (a Amazon nao teve de-para respondido
  // como a Shopee teve). Montado por analogia com o padrao ja aprovado
  // da Shopee, usando os mesmos campos reais do SAT ja testados. Path
  // aqui e' direto (campo do payload da Amazon), sem pontos aninhados
  // como na Shopee.
  MAPA_OBS_PEDIDO_AMAZON: array[0..12] of TMapeamentoObs = (
    (Caminho: 'SalesChannel'; Rotulo: 'Canal de venda'),
    (Caminho: 'FulfillmentChannel'; Rotulo: 'Canal de atendimento (MFN/AFN)'),
    (Caminho: 'ShipServiceLevel'; Rotulo: 'Nivel de servico de envio'),
    (Caminho: 'NumberOfItemsShipped'; Rotulo: 'Quantidade de itens ja enviados'),
    (Caminho: 'NumberOfItemsUnshipped'; Rotulo: 'Quantidade de itens ainda nao enviados'),
    (Caminho: 'PaymentMethod'; Rotulo: 'Forma de pagamento'),
    (Caminho: 'IsBusinessOrder'; Rotulo: 'Se e pedido empresarial (Amazon Business)'),
    (Caminho: 'IsPrime'; Rotulo: 'Se e pedido Prime'),
    (Caminho: 'EarliestShipDate'; Rotulo: 'Data mais cedo prevista para envio'),
    (Caminho: 'LatestShipDate'; Rotulo: 'Data limite para envio'),
    (Caminho: 'SellerOrderId'; Rotulo: 'Numero do pedido no sistema do vendedor'),
    (Caminho: 'OrderType'; Rotulo: 'Tipo do pedido'),
    (Caminho: 'ElectronicInvoiceStatus'; Rotulo: 'Status da nota fiscal eletronica exigida pela Amazon')
  );

  // Campos do GET /orders/{id} do Mercado Livre que nao tem coluna
  // dedicada na OE - vao todos pro oe.OBS no formato "Rotulo -> Valor".
  // Diferente da Amazon, aqui o JSON da resposta JA e' o pedido (nao ha
  // um envelope "payload" em volta), por isso o caminho comeca na raiz.
  MAPA_OBS_PEDIDO_MERCADOLIVRE: array[0..12] of TMapeamentoObs = (
    (Caminho: 'status_detail'; Rotulo: 'Detalhe do status'),
    (Caminho: 'date_closed'; Rotulo: 'Data de fechamento do pedido'),
    (Caminho: 'currency_id'; Rotulo: 'Moeda'),
    (Caminho: 'buyer.id'; Rotulo: 'ID do comprador no Mercado Livre'),
    (Caminho: 'buyer.nickname'; Rotulo: 'Apelido do comprador'),
    (Caminho: 'shipping.id'; Rotulo: 'ID do envio'),
    (Caminho: 'pack_id'; Rotulo: 'ID do pacote (carrinho com varios pedidos)'),
    (Caminho: 'tags'; Rotulo: 'Marcadores do pedido'),
    (Caminho: 'context.channel'; Rotulo: 'Canal de venda'),
    (Caminho: 'context.site'; Rotulo: 'Site do Mercado Livre'),
    (Caminho: 'taxes.amount'; Rotulo: 'Valor de impostos'),
    (Caminho: 'coupon.amount'; Rotulo: 'Valor do cupom de desconto'),
    (Caminho: 'expiration_date'; Rotulo: 'Data de expiracao do pedido')
  );

// Le um valor de dentro de um TJSONObject seguindo um "caminho"
// separado por ponto (ex: "buyer_payment_info.payment_method") - devolve
// '' se qualquer parte do caminho nao existir ou nao for encontrada.
function ValorJSONPorCaminho(ARaiz: TJSONObject; const ACaminho: string): string;
var
  Partes: TArray<string>;
  Atual: TJSONValue;
  I: Integer;
begin
  Result := '';
  if not Assigned(ARaiz) then
    Exit;
  Partes := ACaminho.Split(['.']);
  Atual := ARaiz;
  for I := 0 to High(Partes) do
  begin
    if not (Atual is TJSONObject) then
      Exit;
    Atual := TJSONObject(Atual).GetValue(Partes[I]);
    if not Assigned(Atual) then
      Exit;
  end;
  if Atual is TJSONString then
    Result := TJSONString(Atual).Value
  else if not (Atual is TJSONObject) and not (Atual is TJSONArray) then
    Result := Atual.Value // numero/bool em texto simples
  else
    Result := Atual.ToJSON; // objeto/array composto - joga o JSON bruto mesmo
end;

// Monta os pares (Rotulo, Valor) pra um mapa de campos, buscando dentro
// do objeto do PEDIDO (response.order_list[0]) do get_order_detail.
function ExtrairCamposObsPedido(const ARawJSON: string;
  const AMapa: array of TMapeamentoObs): TCamposObsArray;
var
  Root: TJSONValue;
  RespObj, OrderObj: TJSONObject;
  OrderListArr: TJSONArray;
  I: Integer;
begin
  SetLength(Result, 0);
  Root := TJSONObject.ParseJSONValue(ARawJSON);
  if not Assigned(Root) then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    if not TJSONObject(Root).TryGetValue<TJSONObject>('response', RespObj) then
      Exit;
    if not RespObj.TryGetValue<TJSONArray>('order_list', OrderListArr) or
       (OrderListArr.Count = 0) then
      Exit;
    OrderObj := OrderListArr.Items[0] as TJSONObject;
    SetLength(Result, Length(AMapa));
    for I := 0 to High(AMapa) do
      Result[I] := TCampoObs.Create(AMapa[I].Rotulo,
        ValorJSONPorCaminho(OrderObj, AMapa[I].Caminho));
  finally
    Root.Free;
  end;
end;

// Igual ExtrairCamposObsPedido, mas pro formato da Amazon: o pedido fica
// direto em payload (nao tem array "order_list" nem chave "response" -
// GetOrderDetail busca UM pedido especifico, nao uma lista).
function ExtrairCamposObsAmazon(const ARawJSON: string;
  const AMapa: array of TMapeamentoObs): TCamposObsArray;
var
  Root: TJSONValue;
  PayloadObj: TJSONObject;
  I: Integer;
begin
  SetLength(Result, 0);
  Root := TJSONObject.ParseJSONValue(ARawJSON);
  if not Assigned(Root) then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    if not TJSONObject(Root).TryGetValue<TJSONObject>('payload', PayloadObj) then
      Exit;
    SetLength(Result, Length(AMapa));
    for I := 0 to High(AMapa) do
      Result[I] := TCampoObs.Create(AMapa[I].Rotulo,
        ValorJSONPorCaminho(PayloadObj, AMapa[I].Caminho));
  finally
    Root.Free;
  end;
end;

// Idem, mas buscando dentro do JSON do get_escrow_detail (response.
// order_income - com fallback pra response direto, pra cobrir campos
// como buyer_payment_info.* que ficam fora do order_income).
function ExtrairCamposObsEscrow(const ARawJSON: string;
  const AMapa: array of TMapeamentoObs): TCamposObsArray;
var
  Root: TJSONValue;
  RespObj, OrderIncomeObj: TJSONObject;
  I: Integer;
  Valor: string;
begin
  SetLength(Result, 0);
  Root := TJSONObject.ParseJSONValue(ARawJSON);
  if not Assigned(Root) then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    if not TJSONObject(Root).TryGetValue<TJSONObject>('response', RespObj) then
      Exit;
    RespObj.TryGetValue<TJSONObject>('order_income', OrderIncomeObj); // pode nao existir - segue mesmo assim
    SetLength(Result, Length(AMapa));
    for I := 0 to High(AMapa) do
    begin
      Valor := '';
      if Assigned(OrderIncomeObj) then
        Valor := ValorJSONPorCaminho(OrderIncomeObj, AMapa[I].Caminho);
      if Valor = '' then
        Valor := ValorJSONPorCaminho(RespObj, AMapa[I].Caminho);
      Result[I] := TCampoObs.Create(AMapa[I].Rotulo, Valor);
    end;
  finally
    Root.Free;
  end;
end;

// Monta os campos OBS de UM item (mistura o mapa fixo item_list com o
// detalhamento financeiro do escrow, se achar o item correspondente
// dentro de response.order_income.items[] por item_id/order_item_id).
function ExtrairCamposObsItem(const AItem: TShopeeOrderItemDetail;
  const AEscrowRawJSON: string): TCamposObsArray;
var
  Root: TJSONValue;
  RespObj, OrderIncomeObj, ItemObj, CandidatoObj: TJSONObject;
  ItemsArr: TJSONArray;
  I, N: Integer;
  IdCandidato: string;
begin
  SetLength(Result, Length(MAPA_OBS_ITEM));
  N := 0;
  // item_name, model_id, model_sku, promotion_group_id, product_location_id,
  // order_item_id - esses vem do proprio record (ja parseados pelo GetOrderDetail).
  Result[N] := TCampoObs.Create(MAPA_OBS_ITEM[0].Rotulo, AItem.ItemName); Inc(N);
  Result[N] := TCampoObs.Create(MAPA_OBS_ITEM[1].Rotulo, AItem.ModelID); Inc(N);
  Result[N] := TCampoObs.Create(MAPA_OBS_ITEM[2].Rotulo, AItem.ModelSKU); Inc(N);
  Result[N] := TCampoObs.Create(MAPA_OBS_ITEM[3].Rotulo, AItem.PromotionGroupID); Inc(N);
  Result[N] := TCampoObs.Create(MAPA_OBS_ITEM[4].Rotulo, AItem.ProductLocationID); Inc(N);
  Result[N] := TCampoObs.Create(MAPA_OBS_ITEM[5].Rotulo, AItem.OrderItemID); Inc(N);

  // Detalhamento financeiro do escrow - busca o item correspondente
  // dentro de order_income.items[] (se existir esse array na resposta).
  ItemObj := nil;
  Root := TJSONObject.ParseJSONValue(AEscrowRawJSON);
  if Assigned(Root) then
  try
    if (Root is TJSONObject) and
       TJSONObject(Root).TryGetValue<TJSONObject>('response', RespObj) and
       RespObj.TryGetValue<TJSONObject>('order_income', OrderIncomeObj) and
       OrderIncomeObj.TryGetValue<TJSONArray>('items', ItemsArr) then
    begin
      for I := 0 to ItemsArr.Count - 1 do
      begin
        CandidatoObj := ItemsArr.Items[I] as TJSONObject;
        IdCandidato := '';
        if not CandidatoObj.TryGetValue<string>('item_id', IdCandidato) then
          if Assigned(CandidatoObj.GetValue('item_id')) then
            IdCandidato := CandidatoObj.GetValue<Int64>('item_id').ToString;
        if IdCandidato = AItem.ItemID then
        begin
          ItemObj := CandidatoObj;
          Break;
        end;
      end;
    end;
    SetLength(Result, N + Length(MAPA_OBS_ITEM_ESCROW));
    for I := 0 to High(MAPA_OBS_ITEM_ESCROW) do
    begin
      Result[N] := TCampoObs.Create(MAPA_OBS_ITEM_ESCROW[I].Rotulo,
        ValorJSONPorCaminho(ItemObj, MAPA_OBS_ITEM_ESCROW[I].Caminho));
      Inc(N);
    end;
  finally
    Root.Free;
  end;
end;

// Monta os campos OBS de um item da Amazon - mais simples que o da
// Shopee, ja que o GetOrderItems ja parseia tudo que precisamos direto
// no record (Title, ConditionId, ASIN, ShippingPrice), sem precisar
// reler o JSON bruto.
// Extrai os campos OBS do pedido do Mercado Livre. Diferente da Amazon,
// o JSON da resposta do GET /orders/{id} JA e' o pedido - nao ha um
// envelope "payload" em volta, entao le direto da raiz.
function ExtrairCamposObsMercadoLivre(const ARawJSON: string;
  const AMapa: array of TMapeamentoObs): TCamposObsArray;
var
  Root: TJSONValue;
  I: Integer;
begin
  SetLength(Result, 0);
  Root := TJSONObject.ParseJSONValue(ARawJSON);
  if not Assigned(Root) then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    SetLength(Result, Length(AMapa));
    for I := 0 to High(AMapa) do
      Result[I] := TCampoObs.Create(AMapa[I].Rotulo,
        ValorJSONPorCaminho(TJSONObject(Root), AMapa[I].Caminho));
  finally
    Root.Free;
  end;
end;

// Campos OBS por item do Mercado Livre - o GetOrderDetail ja parseia tudo
// que precisamos direto no record, sem precisar reler o JSON bruto.
function MontarCamposObsItemMercadoLivre(const AItem: TMercadoLivreOrderItem): TCamposObsArray;
begin
  SetLength(Result, 5);
  Result[0] := TCampoObs.Create('Nome do produto', AItem.Title);
  Result[1] := TCampoObs.Create('ID do anuncio no Mercado Livre', AItem.ItemId);
  Result[2] := TCampoObs.Create('SKU do vendedor', AItem.SellerSku);
  Result[3] := TCampoObs.Create('ID da variacao', AItem.VariationId);
  if AItem.SaleFee <> 0 then
    Result[4] := TCampoObs.Create('Tarifa de venda do Mercado Livre neste item',
      FormatFloat('0.00', AItem.SaleFee))
  else
    Result[4] := TCampoObs.Create('Tarifa de venda do Mercado Livre neste item', '');
end;

function MontarCamposObsItemAmazon(const AItem: TAmazonOrderItem): TCamposObsArray;
begin
  SetLength(Result, 4);
  Result[0] := TCampoObs.Create('Nome do produto', AItem.Title);
  Result[1] := TCampoObs.Create('Condicao do item', AItem.ConditionId);
  Result[2] := TCampoObs.Create('ASIN (identificador do produto na Amazon)', AItem.ASIN);
  if AItem.ShippingPrice <> 0 then
    Result[3] := TCampoObs.Create('Frete deste item', FormatFloat('0.00', AItem.ShippingPrice))
  else
    Result[3] := TCampoObs.Create('Frete deste item', '');
end;

// Converte nome de estado por extenso pra sigla (UF) - defensivo, caso a
// Shopee devolva o nome completo em vez da sigla no recipient_address
// (nao confirmado contra uma resposta real ainda). Se ja vier como
// sigla de 2 letras, devolve sem alterar; se nao reconhecer, devolve o
// valor original sem alterar (nunca descarta informacao).
function NormalizarUF(const AEstado: string): string;
const
  NOMES: array[0..26] of string = (
    'Acre', 'Alagoas', 'Amapa', 'Amazonas', 'Bahia', 'Ceara',
    'Distrito Federal', 'Espirito Santo', 'Goias', 'Maranhao',
    'Mato Grosso', 'Mato Grosso do Sul', 'Minas Gerais', 'Para',
    'Paraiba', 'Parana', 'Pernambuco', 'Piaui', 'Rio de Janeiro',
    'Rio Grande do Norte', 'Rio Grande do Sul', 'Rondonia', 'Roraima',
    'Santa Catarina', 'Sao Paulo', 'Sergipe', 'Tocantins'
  );
  SIGLAS: array[0..26] of string = (
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT',
    'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO',
    'RR', 'SC', 'SP', 'SE', 'TO'
  );
var
  I: Integer;
  EstadoSemAcento: string;

  // Remove acentos comuns pra comparar sem depender de exatamente como o
  // texto foi acentuado ("São Paulo" vs "Sao Paulo" vs "SÃO PAULO").
  function RemoverAcentos(const S: string): string;
  begin
    Result := S;
    Result := StringReplace(Result, 'á', 'a', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'â', 'a', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ã', 'a', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'é', 'e', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ê', 'e', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'í', 'i', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ó', 'o', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ô', 'o', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'õ', 'o', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ú', 'u', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ç', 'c', [rfReplaceAll, rfIgnoreCase]);
  end;

begin
  Result := AEstado;
  if Trim(AEstado) = '' then
    Exit;
  // Ja veio como sigla de 2 letras - nao mexe.
  if Length(Trim(AEstado)) = 2 then
    Exit;
  EstadoSemAcento := RemoverAcentos(Trim(AEstado));
  for I := Low(NOMES) to High(NOMES) do
    if SameText(EstadoSemAcento, RemoverAcentos(NOMES[I])) then
    begin
      Result := SIGLAS[I];
      Exit;
    end;
  // Nao reconheceu - devolve como veio, sem alterar (nunca descarta
  // informacao so por nao bater com a lista).
end;

function TFrmPedidosMarketplace.MontarDadosPedidoShopee(const AOrderSN: string;

  out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

var

  ClienteShopee: TShopeeOpenAPIClient;

  Detalhe: TShopeeOrderDetail;

  EscrowRawJSON, EscrowPaymentMethod: string;

  EscrowAmount, EscrowBuyerTotal: Double;

  I: Integer;

begin

  Result := False;

  AErroMsg := '';

  ClienteShopee := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),

    FDevClientSecret, '', FSandbox);

  ClienteShopee.OnLog := Log;

  try

    if not ClienteShopee.GetOrderDetail(FToken, StrToInt64Def(FAccountID, 0),

         AOrderSN, Detalhe, AErroMsg) then

      Exit;



    // Escrow (financeiro) so fica disponivel depois de despachado/

    // concluido - por isso NAO trata falha aqui como erro fatal, so loga

    // e segue sem os campos financeiros (ficam vazios no OBS).

    EscrowRawJSON := '';

    if not ClienteShopee.GetEscrowDetail(FToken, StrToInt64Def(FAccountID, 0),

         AOrderSN, EscrowAmount, EscrowBuyerTotal, EscrowPaymentMethod,

         EscrowRawJSON, AErroMsg) then

      Log('Aviso: detalhe financeiro (escrow) ainda nao disponivel pra ' +

        AOrderSN + ' - ' + AErroMsg);

    AErroMsg := ''; // o aviso acima nao e' erro fatal - limpa antes de seguir



    ADados.Loja := FLoja;

    ADados.CodMarketplace := FCodMarketplace;

    ADados.CodPedidoMarketplace := Detalhe.OrderSN;

    ADados.StatusMarketplace := Detalhe.OrderStatus;

    ADados.DataCriacao := Detalhe.CreateTime;

    ADados.DataUltimaAtualizacao := Detalhe.UpdateTime;

    ADados.ValorTotalPedido := Detalhe.TotalAmount;

    ADados.FreteReal := Detalhe.ActualShippingFee;

    ADados.Transportadora := Detalhe.ShippingCarrier;

    ADados.DataColeta := Detalhe.PickupDoneTime;

    ADados.ValorRepasse := EscrowAmount;

    ADados.CodClienteMarketplace := Detalhe.BuyerUserID;

    ADados.NomeCliente := Detalhe.BuyerUsername;

    ADados.CpfCliente := Detalhe.BuyerCpfId;

    ADados.TelefoneEntrega := Detalhe.RecipientPhone;

    ADados.EnderecoEntrega := Detalhe.RecipientFullAddress;

    ADados.CidadeEntrega := Detalhe.RecipientCity;

    ADados.EstadoEntrega := NormalizarUF(Detalhe.RecipientState);

    ADados.CepEntrega := Detalhe.RecipientZipcode;

    ADados.PaisEntrega := Detalhe.RecipientCountry;



    // Campos OBS do cabecalho = Pedido + Pagamento juntos (o de-para

    // manda os dois pro mesmo oe.obs).

    ADados.CamposObs := ExtrairCamposObsPedido(Detalhe.RawJSON, MAPA_OBS_PEDIDO) +

      ExtrairCamposObsEscrow(EscrowRawJSON, MAPA_OBS_PAGAMENTO);



    SetLength(ADados.Itens, Length(Detalhe.Items));

    for I := Low(Detalhe.Items) to High(Detalhe.Items) do

    begin

      ADados.Itens[I].ItemIdMarketplace := Detalhe.Items[I].ItemID;

      ADados.Itens[I].CodigoDeBarras := Detalhe.Items[I].ItemSKU;

      ADados.Itens[I].IdItemPedido := Detalhe.Items[I].OrderItemID;

      ADados.Itens[I].Tamanho := Detalhe.Items[I].ModelName;

      ADados.Itens[I].Quantidade := Detalhe.Items[I].ModelQuantityPurchased;

      ADados.Itens[I].PrecoDeVenda := Detalhe.Items[I].ModelOriginalPrice;

      ADados.Itens[I].Valor := Detalhe.Items[I].ModelDiscountedPrice;

      ADados.Itens[I].CamposObs := ExtrairCamposObsItem(Detalhe.Items[I], EscrowRawJSON);

    end;



    Result := True;

  finally

    ClienteShopee.Free;

  end;

end;



// Mapeamento PROPOSTO por analogia com a Shopee (ver mensagem do

// usuario em 24/08 e as 3 decisoes registradas nos comentarios abaixo) -

// a Amazon ainda nao teve de-para formalmente respondido pelo cliente,

// mas a Orders API v0 e' publica/estavel havendo bastante confianca no

// mapeamento de campos em si.

function TFrmPedidosMarketplace.MontarDadosPedidoAmazon(const AOrderSN: string;

  out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

var

  ClienteAmazon: TAmazonSPAPIClient;

  Detalhe: TAmazonOrderDetail;

  Items: TAmazonOrderItemArray;

  I: Integer;

  SomaFrete: Double;

  NetAmount: Double;

  NetAmountRawJSON, ErroFinanceiro: string;

begin

  Result := False;

  AErroMsg := '';

  ClienteAmazon := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',

    uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);

  ClienteAmazon.OnLog := Log;

  try

    if not ClienteAmazon.GetOrderDetail(FToken, AOrderSN, Detalhe, AErroMsg) then

      Exit;



    if not ClienteAmazon.GetOrderItems(FToken, AOrderSN, Items, AErroMsg) then

      Exit;



    ADados.Loja := FLoja;

    ADados.CodMarketplace := FCodMarketplace;

    ADados.CodPedidoMarketplace := Detalhe.AmazonOrderId;

    ADados.StatusMarketplace := Detalhe.OrderStatus;

    ADados.DataCriacao := Detalhe.PurchaseDate;

    ADados.DataUltimaAtualizacao := Detalhe.LastUpdateDate;

    ADados.ValorTotalPedido := Detalhe.TotalAmount;



    // Frete (decisao do usuario 24/08): a Amazon nao devolve frete no

    // nivel do PEDIDO como a Shopee - soma o ShippingPrice de todos os

    // itens.

    SomaFrete := 0;

    for I := Low(Items) to High(Items) do

      SomaFrete := SomaFrete + Items[I].ShippingPrice;

    ADados.FreteReal := SomaFrete;



    // Transportadora (decisao do usuario 24/08): a Amazon nao devolve

    // isso numa consulta de leitura - so sabemos qual foi usada se FOMOS

    // nos que despachamos pelo botao Despachar do SAT (que ja pede a

    // transportadora ao usuario). Fica em branco quando nao sabemos, sem

    // tentar adivinhar.

    ADados.Transportadora := '';

    ADados.DataColeta := 0;



    // Repasse: agora usa a Finances API v2024-06-19 (listTransactions)

    // pra pegar o valor liquido real (ja com taxas/comissao descontadas).

    // {DECISAO - 05/10/2026} essa API exige a role "Finance and Accounting",

    // que a Amazon NEGOU no caso 21741162671. O motivo nao foi tecnico: para

    // liberar o papel restrito ela exige perfil de Solution Provider publico,

    // com site comercial proprio (dominio independente, preco publicado) e um

    // questionario de seguranca RDA de 11 controles. O cliente avaliou e

    // decidiu NAO seguir enquanto a integracao atender so a SAT - o custo nao

    // se paga por um campo de valor.

    // Ou seja: o fallback abaixo NAO e' temporario, e o estado definitivo da

    // Amazon hoje. Se um dia o CPIntegra for licenciado a outros lojistas, o

    // site e o questionario serao necessarios de qualquer forma, e ai vale

    // reabrir o pedido - mas nao antes disso.

    if not ClienteAmazon.GetOrderNetAmount(FToken, AOrderSN, Detalhe.PurchaseDate,

         NetAmount, NetAmountRawJSON, ErroFinanceiro) then

    begin

      Log('Repasse aproximado para o pedido ' + AOrderSN + ': a role de'

        + ' financeiro da Amazon nao foi liberada (ver nota acima) - gravando o'

        + ' TOTAL do pedido, sem descontar tarifas. (' + ErroFinanceiro + ')');

      ADados.ValorRepasse := Detalhe.TotalAmount;

    end

    else

      ADados.ValorRepasse := NetAmount;



    ADados.NomeCliente := Detalhe.BuyerName;

    // {ATENCAO} a Amazon nao devolve CPF/CNPJ de forma direta e confiavel no

    // getOrder (so em circunstancias especificas, dentro de BuyerTaxInfo,

    // quando aplicavel) - fica vazio.

    // {DECISAO DO CLIENTE - 30/08/2026} isso NAO impede mais a criacao do

    // cliente: o BuscarOuCriarCliente insere em CLI com CPF NULL e devolve o

    // CODCLI, que vai pra OE.CODCLI normalmente. O efeito colateral aceito e'

    // que comprador recorrente vira mais de um registro em CLI, porque sem

    // CPF nao ha chave pra deduplicar.

    ADados.CpfCliente := '';

    ADados.TelefoneEntrega := Detalhe.ShippingPhone;

    ADados.EnderecoEntrega := Detalhe.ShippingAddressLine;

    ADados.CidadeEntrega := Detalhe.ShippingCity;

    ADados.EstadoEntrega := NormalizarUF(Detalhe.ShippingState);

    ADados.CepEntrega := Detalhe.ShippingPostalCode;

    ADados.PaisEntrega := Detalhe.ShippingCountryCode;



    ADados.CamposObs := ExtrairCamposObsAmazon(Detalhe.RawJSON, MAPA_OBS_PEDIDO_AMAZON);



    SetLength(ADados.Itens, Length(Items));

    for I := Low(Items) to High(Items) do

    begin

      ADados.Itens[I].ItemIdMarketplace := Items[I].ASIN;

      ADados.Itens[I].CodigoDeBarras := Items[I].SellerSKU;

      ADados.Itens[I].IdItemPedido := Items[I].OrderItemId;

      ADados.Itens[I].Tamanho := ''; // Amazon nao tem conceito de "variacao/tamanho" separado como a Shopee

      ADados.Itens[I].Quantidade := Items[I].QuantityOrdered;

      // ItemPriceAmount e' o valor TOTAL da linha (nao unitario) - divide

      // pela quantidade pra achar o preco unitario (a Shopee ja devolve

      // por unidade, por isso nao precisou dessa divisao la).

      if Items[I].QuantityOrdered > 0 then

      begin

        ADados.Itens[I].PrecoDeVenda := Items[I].ItemPriceAmount / Items[I].QuantityOrdered;

        ADados.Itens[I].Valor := Items[I].ItemPriceAmount / Items[I].QuantityOrdered;

      end

      else

      begin

        ADados.Itens[I].PrecoDeVenda := 0;

        ADados.Itens[I].Valor := 0;

      end;

      ADados.Itens[I].CamposObs := MontarCamposObsItemAmazon(Items[I]);

    end;



    Result := True;

  finally

    ClienteAmazon.Free;

  end;

end;



// {ATENCAO} Implementacao 100% baseada em estimativa - a API de pedidos

// do Magalu nunca foi testada contra uma loja real (travado no CNAE do

// cliente). Path, nomes de campo de comprador/endereco e formato de

// resposta do GetOrderDetail/GetDeliveries sao os melhores palpites

// possiveis, documentados em detalhe no Magalu.OpenAPI.Client.pas -

// quando a loja for aprovada, testar e ajustar aqui e la conforme

// necessario.

function TFrmPedidosMarketplace.MontarDadosPedidoMagalu(const AOrderSN: string;

  out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;

var

  ClienteMagalu: TMagaluOpenAPIClient;

  Detalhe: TMagaluOrderDetail;

  Deliveries: TMagaluDeliveryArray;

  TodosItens: TItensPedidoSATArray;

  I, J, Total: Integer;

begin

  Result := False;

  AErroMsg := '';

  ClienteMagalu := TMagaluOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', '', FSandbox);

  ClienteMagalu.OnLog := Log;

  try

    if not ClienteMagalu.GetOrderDetail(FToken, FAccountID, AOrderSN, Detalhe, AErroMsg) then

      Exit;



    // Itens vem de dentro das ENTREGAS (recurso separado do pedido no

    // Magalu, ja confirmado desde o Despachar) - busca todas as entregas

    // desse pedido e junta os itens de todas numa lista so, ja que a IOE

    // nao distingue de qual entrega fisica cada item veio.

    if not ClienteMagalu.GetDeliveries(FToken, FAccountID, AOrderSN, Deliveries, AErroMsg) then

      Exit;



    ADados.Loja := FLoja;

    ADados.CodMarketplace := FCodMarketplace;

    ADados.CodPedidoMarketplace := Detalhe.IdOrder;

    ADados.StatusMarketplace := Detalhe.Status;

    ADados.DataCriacao := Detalhe.OrderDate;

    ADados.DataUltimaAtualizacao := Detalhe.OrderDate; // Magalu nao tem campo separado de "ultima atualizacao" confirmado - usa a mesma data

    ADados.ValorTotalPedido := Detalhe.TotalAmount;

    ADados.FreteReal := 0; // {ATENCAO} nao ha campo de frete confirmado no pedido/entrega do Magalu ainda

    ADados.Transportadora := ''; // mesmo caso da Amazon - so sabemos se formos nos que despachamos

    ADados.DataColeta := 0;

    ADados.ValorRepasse := Detalhe.TotalAmount; // {ATENCAO} aproximacao - Magalu nao tem API de financeiro/repasse confirmada (ver planilha de-para)



    ADados.NomeCliente := Detalhe.BuyerName;

    ADados.CpfCliente := Detalhe.BuyerDocument;

    ADados.TelefoneEntrega := Detalhe.BuyerPhone;

    ADados.EnderecoEntrega := Trim(Detalhe.ShippingStreet + ' ' + Detalhe.ShippingNumber +

      IfThen(Detalhe.ShippingComplement <> '', ' - ' + Detalhe.ShippingComplement, '') +

      IfThen(Detalhe.ShippingNeighborhood <> '', ', ' + Detalhe.ShippingNeighborhood, ''));

    ADados.CidadeEntrega := Detalhe.ShippingCity;

    ADados.EstadoEntrega := NormalizarUF(Detalhe.ShippingState);

    ADados.CepEntrega := Detalhe.ShippingZipCode;

    ADados.PaisEntrega := 'Brasil'; // Magalu so opera no Brasil, sem campo de pais na resposta



    SetLength(ADados.CamposObs, 1);

    ADados.CamposObs[0] := TCampoObs.Create('Forma de pagamento', Detalhe.PaymentMethod);



    // Achata os itens de todas as entregas numa lista so.

    Total := 0;

    for I := Low(Deliveries) to High(Deliveries) do

      Total := Total + Length(Deliveries[I].Items);

    SetLength(TodosItens, Total);

    Total := 0;

    for I := Low(Deliveries) to High(Deliveries) do

      for J := Low(Deliveries[I].Items) to High(Deliveries[I].Items) do

      begin

        TodosItens[Total].ItemIdMarketplace := Deliveries[I].Items[J].Sku;

        TodosItens[Total].CodigoDeBarras := Deliveries[I].Items[J].Sku;

        TodosItens[Total].IdItemPedido := ''; // {ATENCAO} Magalu nao tem um "order_item_id" confirmado

        TodosItens[Total].Tamanho := '';

        TodosItens[Total].Quantidade := Deliveries[I].Items[J].Quantity;

        TodosItens[Total].PrecoDeVenda := Deliveries[I].Items[J].Price;

        TodosItens[Total].Valor := Deliveries[I].Items[J].Price;

        SetLength(TodosItens[Total].CamposObs, 1);

        TodosItens[Total].CamposObs[0] := TCampoObs.Create('Descrição do produto',

          Deliveries[I].Items[J].Description);

        Inc(Total);

      end;

    ADados.Itens := TodosItens;



    Result := True;

  finally

    ClienteMagalu.Free;

  end;

end;



// {ATENCAO} Este mapeamento NAO veio de uma planilha de-para respondida
// pelo cliente - foi montado por analogia com o da Shopee (unico
// confirmado) e com o da Amazon, usando a estrutura da API do Mercado
// Livre confirmada na documentacao oficial (26/08/2026):
//   GET /orders/{id}                  -> itens, pagamento, id do envio
//   GET /orders/{id}/billing_info     -> nome real + CPF/CNPJ do comprador
//                                        (header 'x-version: 2', so' assim
//                                        no Brasil)
//   GET /shipments/{id}               -> endereco de ENTREGA + rastreio
//                                        (header 'x-format-new: true')
// Sao 3 chamadas porque o Mercado Livre deixou de devolver dado pessoal do
// comprador dentro do /orders em pedidos com Mercado Envios 2 - nome,
// documento e endereco vivem em recursos separados.
function TFrmPedidosMarketplace.MontarDadosPedidoMercadoLivre(const AOrderSN: string;
  out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;
var
  ClienteML: TMercadoLivreOpenAPIClient;
  Detalhe: TMercadoLivreOrderDetail;
  Billing: TMercadoLivreBillingInfo;
  Envio: TMercadoLivreShipment;
  TemBilling, TemEnvio: Boolean;
  ErroBilling, ErroEnvio: string;
  SomaTarifas: Double;
  I, N: Integer;
begin
  Result := False;
  AErroMsg := '';
  ClienteML := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
    '', FSandbox);
  ClienteML.OnLog := Log;
  try
    // 1) Pedido em si - essa e' a unica chamada obrigatoria; se falhar,
    // nao ha o que baixar.
    if not ClienteML.GetOrderDetail(FToken, AOrderSN, Detalhe, AErroMsg) then
      Exit;

    // 2) Dados do comprador. Nao aborta se falhar - um pedido sem
    // billing_info ainda pode ser baixado (o cliente fica sem CPF, e o
    // upsert por CPF simplesmente nao acha/cria ninguem, igual acontece
    // hoje com a Amazon).
    TemBilling := ClienteML.GetOrderBillingInfo(FToken, AOrderSN, Billing, ErroBilling);
    if not TemBilling then
      Log('Aviso: nao foi possivel obter os dados de faturamento do comprador do ' +
        'pedido ' + AOrderSN + ' (' + ErroBilling + ') - nome e CPF ficarao vazios.');

    // 3) Endereco de entrega e rastreio. Tambem nao aborta: pedido sem
    // envio associado, ou com endereco ainda oculto (o Mercado Livre so'
    // libera o destino depois de confirmar o pagamento), continua podendo
    // ser baixado.
    TemEnvio := False;
    if Detalhe.ShippingId <> '' then
    begin
      TemEnvio := ClienteML.GetShipment(FToken, Detalhe.ShippingId, Envio, ErroEnvio);
      if not TemEnvio then
        Log('Aviso: nao foi possivel obter o envio ' + Detalhe.ShippingId +
          ' do pedido ' + AOrderSN + ' (' + ErroEnvio + ') - endereco de entrega ' +
          'ficara vazio.');
    end
    else
      Log('Aviso: pedido ' + AOrderSN + ' nao tem envio associado (shipping.id ' +
        'vazio) - endereco de entrega ficara vazio.');

    ADados.Loja := FLoja;
    ADados.CodMarketplace := FCodMarketplace;
    ADados.CodPedidoMarketplace := Detalhe.OrderId;
    ADados.StatusMarketplace := Detalhe.Status;
    ADados.DataCriacao := Detalhe.DateCreated;
    if Detalhe.LastUpdated <> 0 then
      ADados.DataUltimaAtualizacao := Detalhe.LastUpdated
    else
      ADados.DataUltimaAtualizacao := Detalhe.DateClosed;
    ADados.ValorTotalPedido := Detalhe.TotalAmount;

    // Frete: o Mercado Livre devolve o custo de envio dentro do pagamento
    // (payments[].shipping_cost), nao num campo de frete no nivel do
    // pedido como a Shopee. Fica 0 quando o pagamento nao traz esse campo.
    ADados.FreteReal := Detalhe.ShippingCost;

    // Transportadora: mesma decisao ja tomada pra Amazon e Magalu - fica
    // em branco quando nao sabemos. O Mercado Livre nao devolve um nome de
    // transportadora numa consulta de leitura; o que existe e' o MODO de
    // logistica (me1/me2/self_service) e o codigo de rastreio, que vao pro
    // oe.OBS logo abaixo em vez de forcar um valor cru aqui.
    ADados.Transportadora := '';
    ADados.DataColeta := 0;

    // Repasse: {ATENCAO} aproximacao. O Mercado Livre nao tem, nesta
    // integracao, um equivalente implementado da Finances API da Amazon.
    // O unico desconto que conseguimos ver de forma confiavel no proprio
    // pedido e' a tarifa de venda por item (order_items[].sale_fee), entao
    // usamos total - soma das tarifas. Isso NAO desconta frete pago pelo
    // vendedor nem eventuais ajustes posteriores.
    SomaTarifas := 0;
    for I := Low(Detalhe.Items) to High(Detalhe.Items) do
      SomaTarifas := SomaTarifas + Detalhe.Items[I].SaleFee;
    if SomaTarifas > 0 then
      ADados.ValorRepasse := Detalhe.TotalAmount - SomaTarifas
    else
    begin
      ADados.ValorRepasse := Detalhe.TotalAmount;
      Log('Aviso: o pedido ' + AOrderSN + ' nao trouxe tarifa de venda ' +
        '(sale_fee) - o valor de repasse esta sendo gravado como o total do ' +
        'pedido, sem descontar nada.');
    end;

    // Cliente: o nome real vem do billing_info; o apelido do /orders serve
    // so' de ultimo recurso, pra nao gravar cliente sem nome nenhum.
    ADados.CodClienteMarketplace := Detalhe.BuyerId;
    if TemBilling and (Trim(Billing.Nome) <> '') then
      ADados.NomeCliente := Billing.Nome
    else
      ADados.NomeCliente := Detalhe.BuyerNickname;
    if TemBilling then
      ADados.CpfCliente := Billing.DocNumero
    else
      ADados.CpfCliente := '';

    // {ATENCAO} o Mercado Livre ofusca o telefone do destinatario no
    // /shipments - so' vem de verdade em pedidos Mercado Envios 1.
    if TemEnvio then
      ADados.TelefoneEntrega := Envio.ReceiverPhone
    else
      ADados.TelefoneEntrega := '';

    // Endereco: preferencia pro de ENTREGA (o que o SAT usa em cli.endr e
    // o que vai na nota). So' cai pro endereco de COBRANCA do billing_info
    // quando o envio nao veio - sao coisas diferentes, entao quando isso
    // acontecer fica registrado no log.
    if TemEnvio and (Trim(Envio.Cep) <> '') then
    begin
      if Trim(Envio.AddressLine) <> '' then
        ADados.EnderecoEntrega := Envio.AddressLine
      else
        ADados.EnderecoEntrega := Trim(Envio.Rua + ' ' + Envio.Numero);
      if Trim(Envio.Complemento) <> '' then
        ADados.EnderecoEntrega := ADados.EnderecoEntrega + ' - ' + Envio.Complemento;
      if Trim(Envio.Bairro) <> '' then
        ADados.EnderecoEntrega := ADados.EnderecoEntrega + ', ' + Envio.Bairro;
      ADados.CidadeEntrega := Envio.Cidade;
      ADados.EstadoEntrega := NormalizarUF(Envio.Estado);
      ADados.CepEntrega := Envio.Cep;
      if Trim(Envio.Pais) <> '' then
        ADados.PaisEntrega := Envio.Pais
      else
        ADados.PaisEntrega := 'Brasil';
    end
    else if TemBilling and (Trim(Billing.Cep) <> '') then
    begin
      Log('Aviso: usando o endereco de COBRANCA do comprador no pedido ' +
        AOrderSN + ' porque o endereco de entrega nao estava disponivel - ' +
        'conferir antes de emitir a nota.');
      ADados.EnderecoEntrega := Trim(Billing.Rua + ' ' + Billing.Numero);
      if Trim(Billing.Complemento) <> '' then
        ADados.EnderecoEntrega := ADados.EnderecoEntrega + ' - ' + Billing.Complemento;
      if Trim(Billing.Bairro) <> '' then
        ADados.EnderecoEntrega := ADados.EnderecoEntrega + ', ' + Billing.Bairro;
      ADados.CidadeEntrega := Billing.Cidade;
      ADados.EstadoEntrega := NormalizarUF(Billing.Estado);
      ADados.CepEntrega := Billing.Cep;
      if Trim(Billing.Pais) <> '' then
        ADados.PaisEntrega := Billing.Pais
      else
        ADados.PaisEntrega := 'Brasil';
    end
    else
    begin
      ADados.EnderecoEntrega := '';
      ADados.CidadeEntrega := '';
      ADados.EstadoEntrega := '';
      ADados.CepEntrega := '';
      ADados.PaisEntrega := 'Brasil';
    end;

    // OBS do pedido: os campos do proprio /orders (pelo mapa) mais o que
    // so' existe no envio e no pagamento, que nao estao naquele JSON.
    ADados.CamposObs := ExtrairCamposObsMercadoLivre(Detalhe.RawJSON,
      MAPA_OBS_PEDIDO_MERCADOLIVRE);
    N := Length(ADados.CamposObs);
    SetLength(ADados.CamposObs, N + 8);
    ADados.CamposObs[N] := TCampoObs.Create('Forma de pagamento', Detalhe.PaymentMethod);
    ADados.CamposObs[N + 1] := TCampoObs.Create('Status do pagamento', Detalhe.PaymentStatus);
    ADados.CamposObs[N + 2] := TCampoObs.Create('ID do pagamento', Detalhe.PaymentId);
    if Detalhe.PaymentDateApproved <> 0 then
      ADados.CamposObs[N + 3] := TCampoObs.Create('Data/Hora do pagamento',
        FormatDateTime('dd/mm/yyyy hh:nn:ss', Detalhe.PaymentDateApproved))
    else
      ADados.CamposObs[N + 3] := TCampoObs.Create('Data/Hora do pagamento', '');
    if Detalhe.TotalPaidAmount <> 0 then
      ADados.CamposObs[N + 4] := TCampoObs.Create('Valor total pago pelo comprador',
        FormatFloat('0.00', Detalhe.TotalPaidAmount))
    else
      ADados.CamposObs[N + 4] := TCampoObs.Create('Valor total pago pelo comprador', '');
    if TemEnvio then
    begin
      ADados.CamposObs[N + 5] := TCampoObs.Create('Codigo de rastreio', Envio.TrackingNumber);
      ADados.CamposObs[N + 6] := TCampoObs.Create('Modo de logistica', Envio.LogisticMode);
      ADados.CamposObs[N + 7] := TCampoObs.Create('Status do envio',
        Trim(Envio.Status + ' ' + Envio.Substatus));
    end
    else
    begin
      ADados.CamposObs[N + 5] := TCampoObs.Create('Codigo de rastreio', '');
      ADados.CamposObs[N + 6] := TCampoObs.Create('Modo de logistica', '');
      ADados.CamposObs[N + 7] := TCampoObs.Create('Status do envio', '');
    end;

    // Itens.
    SetLength(ADados.Itens, Length(Detalhe.Items));
    for I := Low(Detalhe.Items) to High(Detalhe.Items) do
    begin
      // {IMPORTANTE} a chave de lookup em PRODUTOS_MARKETPLACE precisa ser
      // a MESMA que a tela de Ofertas grava em CODPRODUTONOMARKETPLACE -
      // e la (GravarProdutoMercadoLivre) e' o ItemId do anuncio, nao o SKU.
      ADados.Itens[I].ItemIdMarketplace := Detalhe.Items[I].ItemId;
      // Codigo de barras: usa o SKU do vendedor quando existe; se o anuncio
      // nao tem SKU cadastrado, cai pro ItemId pra nao gravar vazio.
      if Trim(Detalhe.Items[I].SellerSku) <> '' then
        ADados.Itens[I].CodigoDeBarras := Detalhe.Items[I].SellerSku
      else
        ADados.Itens[I].CodigoDeBarras := Detalhe.Items[I].ItemId;
      // {ATENCAO} o Mercado Livre nao tem um "order_item_id" por linha do
      // pedido como Shopee e Amazon - o item e' identificado pelo proprio
      // ItemId (+ variacao). Fica vazio aqui; o ItemId ja vai pro OBS.
      ADados.Itens[I].IdItemPedido := '';
      ADados.Itens[I].Tamanho := ''; // variacao vem como lista de atributos, sem um "tamanho" unico
      ADados.Itens[I].Quantidade := Detalhe.Items[I].Quantity;
      // unit_price JA e' unitario (diferente da Amazon, que manda o total
      // da linha e obriga a dividir pela quantidade).
      ADados.Itens[I].PrecoDeVenda := Detalhe.Items[I].UnitPrice;
      ADados.Itens[I].Valor := Detalhe.Items[I].UnitPrice;
      ADados.Itens[I].CamposObs := MontarCamposObsItemMercadoLivre(Detalhe.Items[I]);
    end;

    Result := True;
  finally
    ClienteML.Free;
  end;
end;

procedure TFrmPedidosMarketplace.CarregarPedidosTikTokShop;
var
  Cliente: TTikTokShopOpenAPIClient;
  ErroMsg, ShopId, ShopCipher: string;
  DiasAtras, I: Integer;
  DataCorte: TDateTime;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor do TikTok Shop nao cadastradas para esta ' +
      'loja/ambiente (app_key/app_secret em MARKETPLACE_USUARIO/MARKETPLACE_SENHA).');
    Exit;
  end;
  SepararShopIdECipherTikTok(FAccountID, ShopId, ShopCipher);
  if ShopCipher = '' then
  begin
    Log('Vinculo do TikTok incompleto: falta o shop_cipher. Desconecte e conecte ' +
      'a loja novamente no SATLojas.');
    Exit;
  end;
  DiasAtras := StrToIntDef(edtDiasAtras.Text, 15);
  DataCorte := IncDay(Now, -DiasAtras);
  Screen.Cursor := crHourGlass;
  try
    Log(Format('Buscando pedidos dos ultimos %d dia(s)...', [DiasAtras]));
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      // Diferente do Mercado Livre (que nao tem filtro de data e obriga a
      // filtrar em memoria), o TikTok aceita create_time_ge no proprio corpo
      // da busca - o corte ja vem pronto do servidor.
      if not Cliente.GetOrders(FToken, ShopCipher, DataCorte, FTikTokOrders, ErroMsg) then
      begin
        Log('Erro ao buscar pedidos: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    Log(Format('%d pedido(s) encontrado(s).', [Length(FTikTokOrders)]));
    Grid.RowCount := Length(FTikTokOrders) + 1;
    if Grid.RowCount < 2 then
      Grid.RowCount := 2;
    for I := 1 to Grid.RowCount - 1 do
    begin
      Grid.Cells[0, I] := '';
      Grid.Cells[1, I] := '';
      Grid.Cells[2, I] := '';
      Grid.Cells[3, I] := '';
    end;
    for I := Low(FTikTokOrders) to High(FTikTokOrders) do
    begin
      Grid.Cells[0, I + 1] := FTikTokOrders[I].OrderId;
      Grid.Cells[1, I + 1] := FTikTokOrders[I].Status;
      Grid.Cells[2, I + 1] := FormatDateTime('dd/mm/yy hh:nn:ss', FTikTokOrders[I].CreateTime);
      Grid.Cells[3, I + 1] :=
        IfThen(FTikTokOrders[I].Currency <> '', FTikTokOrders[I].Currency, 'BRL') + ' ' +
        FormatFloat('0.00', FTikTokOrders[I].TotalAmount);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

function TFrmPedidosMarketplace.MontarDadosPedidoTikTokShop(const AOrderSN: string;
  out ADados: TDadosPedidoSAT; out AErroMsg: string): Boolean;
var
  Cliente: TTikTokShopOpenAPIClient;
  Detalhe: TTikTokShopOrderDetail;
  ShopId, ShopCipher: string;
  Repasse, TarifasTikTok: Double;
  MoedaRepasse, ErroRepasse: string;
  I, N: Integer;
begin
  Result := False;
  AErroMsg := '';
  SepararShopIdECipherTikTok(FAccountID, ShopId, ShopCipher);
  if ShopCipher = '' then
  begin
    AErroMsg := 'Vinculo do TikTok incompleto: falta o shop_cipher. Desconecte e ' +
      'conecte a loja novamente no SATLojas.';
    Exit;
  end;
  Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
  Cliente.OnLog := Log;
  try
    // Uma chamada so': diferente do Mercado Livre (pedido + billing + envio),
    // o detalhe do TikTok ja traz destinatario, endereco, pagamento e itens.
    if not Cliente.GetOrderDetail(FToken, ShopCipher, AOrderSN, Detalhe, AErroMsg) then
      Exit;

    ADados.Loja := FLoja;
    ADados.CodMarketplace := FCodMarketplace;
    ADados.CodPedidoMarketplace := Detalhe.OrderId;
    ADados.StatusMarketplace := Detalhe.Status;
    ADados.DataCriacao := Detalhe.CreateTime;
    ADados.DataUltimaAtualizacao := Detalhe.UpdateTime;
    ADados.ValorTotalPedido := Detalhe.TotalAmount;
    ADados.FreteReal := Detalhe.ShippingFee;
    // O TikTok devolve o nome da transportadora no proprio pedido
    // (shipping_provider) - aqui, diferente de Amazon/Magalu/ML, da' pra
    // preencher. {ATENCAO} mesmo campo oe.MOTIVO_E que o cliente ja pediu
    // pra aumentar por causa da Shopee.
    ADados.Transportadora := Detalhe.ShippingProvider;
    ADados.DataColeta := Detalhe.DeliveryTime;

    // Repasse: valor LIQUIDO de verdade, vindo da Finance API do TikTok
    // (scope seller.finance.info). Mesmo padrao da Amazon - se a consulta
    // falhar, ou se o TikTok ainda nao tiver LIQUIDADO o pedido, cai pro total
    // do pedido e registra no log, em vez de travar a baixa.
    if Cliente.GetOrderSettlement(FToken, ShopCipher, AOrderSN, Repasse,
         TarifasTikTok, MoedaRepasse, ErroRepasse) then
    begin
      ADados.ValorRepasse := Repasse;
      Log(Format('Repasse do pedido %s: %s (tarifas descontadas: %s)',
        [AOrderSN, FormatFloat('0.00', Repasse), FormatFloat('0.00', TarifasTikTok)]));
    end
    else
    begin
      ADados.ValorRepasse := Detalhe.TotalAmount;
      TarifasTikTok := 0;
      Log('Aviso: repasse indisponivel para o pedido ' + AOrderSN + ' (' +
        ErroRepasse + ') - gravando o TOTAL do pedido, sem descontar tarifas.');
    end;

    // {CORRIGIDO 06/09/2026} o TikTok DEVOLVE o CPF do comprador, nos campos
    // "cpf" e "cpf_name" do pedido - confirmado em pedido real de loja de
    // teste BR. O comentario anterior aqui dizia o contrario e estava errado,
    // e por causa dele todo pedido do TikTok caia no caminho "cliente sem
    // CPF", que cria um cadastro NOVO em CLI a cada pedido, por nao ter chave
    // pra deduplicar.
    // {ATENCAO} a decisao do cliente de 30/08/2026 (criar cliente mesmo sem
    // CPF) continua valendo como FALLBACK: se por algum motivo o pedido vier
    // sem cpf, o BuscarOuCriarCliente segue o caminho antigo.
    ADados.CodClienteMarketplace := Detalhe.BuyerEmail;
    // Nome: prefere o TITULAR do CPF. O recipient_address.name e' o
    // destinatario da entrega, que pode ser outra pessoa - e gravar um nome
    // que nao bate com o CPF quebraria a nota fiscal.
    if Trim(Detalhe.CpfName) <> '' then
      ADados.NomeCliente := Detalhe.CpfName
    else
      ADados.NomeCliente := Detalhe.RecipientName;
    ADados.CpfCliente := Trim(Detalhe.Cpf);
    ADados.TelefoneEntrega := Detalhe.RecipientPhone;

    ADados.EnderecoEntrega := Detalhe.EnderecoLinha;
    if Trim(Detalhe.Bairro) <> '' then
      ADados.EnderecoEntrega := Trim(ADados.EnderecoEntrega + ', ' + Detalhe.Bairro);
    ADados.CidadeEntrega := Detalhe.Cidade;
    ADados.EstadoEntrega := NormalizarUF(Detalhe.Estado);
    ADados.CepEntrega := Detalhe.Cep;
    if Trim(Detalhe.Pais) <> '' then
      ADados.PaisEntrega := Detalhe.Pais
    else
      ADados.PaisEntrega := 'Brasil';

    // OBS do pedido. Montado campo a campo (e nao por mapa de JSON como no
    // Mercado Livre) porque o de-para do TikTok ainda nao existe - quando o
    // cliente responder, e' aqui que muda.
    N := 0;
    SetLength(ADados.CamposObs, 10);
    ADados.CamposObs[N] := TCampoObs.Create('Forma de pagamento', Detalhe.PaymentMethod);
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('E-mail do comprador', Detalhe.BuyerEmail);
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('Recado do comprador', Detalhe.BuyerMessage);
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('Codigo de rastreio', Detalhe.TrackingNumber);
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('Transportadora', Detalhe.ShippingProvider);
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('Moeda', Detalhe.Currency);
    Inc(N);
    if Detalhe.PaidTime <> 0 then
      ADados.CamposObs[N] := TCampoObs.Create('Data/Hora do pagamento',
        FormatDateTime('dd/mm/yyyy hh:nn:ss', Detalhe.PaidTime))
    else
      ADados.CamposObs[N] := TCampoObs.Create('Data/Hora do pagamento', '');
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('Total dos produtos (sem frete)',
      FormatFloat('0.00', Detalhe.OriginalTotalProduct));
    Inc(N);
    ADados.CamposObs[N] := TCampoObs.Create('Pacotes',
      String.Join(', ', Detalhe.PackageIds));
    Inc(N);
    // Tarifas descontadas pelo TikTok - nao ha coluna dedicada na OE, e o
    // cliente pediu que campo sem coluna va pra OBS. Fica zero quando o
    // pedido ainda nao foi liquidado.
    ADados.CamposObs[N] := TCampoObs.Create('Tarifas descontadas pelo TikTok',
      FormatFloat('0.00', TarifasTikTok));

    // Itens.
    SetLength(ADados.Itens, Length(Detalhe.Itens));
    for I := Low(Detalhe.Itens) to High(Detalhe.Itens) do
    begin
      // {IMPORTANTE} a chave de lookup em PRODUTOS_MARKETPLACE precisa ser a
      // MESMA que a tela de Ofertas grava em CODPRODUTONOMARKETPLACE - e la
      // (GravarProdutoTikTokShop) e' "product_id|sku_id", porque no TikTok
      // quem tem preco e estoque e' o SKU, nao o produto.
      ADados.Itens[I].ItemIdMarketplace :=
        MontarChaveProdutoTikTok(Detalhe.Itens[I].ProductId, Detalhe.Itens[I].SkuId);
      // Codigo de barras: SKU do vendedor quando existir; senao o sku_id,
      // pra nao gravar vazio.
      if Trim(Detalhe.Itens[I].SellerSku) <> '' then
        ADados.Itens[I].CodigoDeBarras := Detalhe.Itens[I].SellerSku
      else
        ADados.Itens[I].CodigoDeBarras := Detalhe.Itens[I].SkuId;
      // line_item_id: quando a mesma variacao aparece varias vezes, vem a
      // lista separada por virgula (ver AgruparItensTikTok no client).
      ADados.Itens[I].IdItemPedido := Detalhe.Itens[I].LineItemId;
      // sku_name e' o texto da variacao ("Azul, M") - e' o que mais se
      // aproxima do "tamanho"/model_name da Shopee.
      ADados.Itens[I].Tamanho := Detalhe.Itens[I].SkuName;
      ADados.Itens[I].Quantidade := Detalhe.Itens[I].Quantidade;
      // original_price = preco cheio; sale_price = o que o comprador pagou.
      // Mesmo par de campos que a Shopee usa em model_original_price x
      // model_discounted_price.
      ADados.Itens[I].PrecoDeVenda := Detalhe.Itens[I].OriginalPrice;
      ADados.Itens[I].Valor := Detalhe.Itens[I].SalePrice;
      SetLength(ADados.Itens[I].CamposObs, 3);
      ADados.Itens[I].CamposObs[0] := TCampoObs.Create('Nome do produto',
        Detalhe.Itens[I].ProductName);
      ADados.Itens[I].CamposObs[1] := TCampoObs.Create('ID do produto no TikTok',
        Detalhe.Itens[I].ProductId);
      ADados.Itens[I].CamposObs[2] := TCampoObs.Create('ID do SKU no TikTok',
        Detalhe.Itens[I].SkuId);
    end;

    Result := True;
  finally
    Cliente.Free;
  end;
end;

procedure TFrmPedidosMarketplace.CmdBaixarPedidoSATClick(Sender: TObject);

var

  OrderSN, ErroMsg: string;

  Dados: TDadosPedidoSAT;

  Qry: TFDQuery;

  RetornoProcedure: Integer;

  ErroInfoAdicional: string;

  MontagemOk: Boolean;

begin

  if not (TMarketplaces(FCodMarketplace) in

       [TMarketplaces.Shopee, TMarketplaces.Amazon, TMarketplaces.Magalu,

        TMarketplaces.MercadoLivre, TMarketplaces.TikTokShop]) then

  begin

    ShowMessage('Baixar Pedido SAT nao esta disponivel para este marketplace.');

    Exit;

  end;



  if not PedidoSelecionado(OrderSN) then

  begin

    ShowMessage('Selecione um pedido na lista primeiro.');

    Exit;

  end;



  Qry := TFDQuery.Create(nil);

  try

    Qry.Connection := DZ.ZDatabase;



    // Checa duplicidade JA AQUI, antes de gastar tempo buscando detalhe

    // do pedido na API - BaixarPedidoSAT tambem checa de novo por

    // seguranca, mas isso evita chamadas de API desnecessarias no

    // caminho mais comum (usuario clicando de novo sem querer).

    if PedidoJaBaixado(Qry, FLoja, FCodMarketplace, OrderSN) then

    begin

      ShowMessage('Este pedido ja foi baixado no SAT anteriormente.');

      Exit;

    end;



    if TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu then

      if MessageDlg('ATENCAO: o mapeamento de campos do Magalu ainda nao foi ' +

           'confirmado pelo cliente nem testado contra uma conta real (loja ' +

           'ainda pendente de aprovacao). Os dados gravados podem estar ' +

           'incorretos. Confirma mesmo assim?', mtWarning, [mbYes, mbNo], 0) <> mrYes then

        Exit;



    // {NOTA} o Mercado Livre NAO tem mais aviso aqui: o cliente respondeu a

    // planilha dele em 30/08/2026, campo a campo, e o que ficou decidido bate

    // com o que ja estava implementado - Transportadora, Data de Coleta,

    // Telefone e Tamanho ficam sem gravar de proposito, e o calculo do

    // repasse (total menos as tarifas de venda) foi aceito como esta.

    // TikTok: nao ha mais pendencia de MAPEAMENTO - o CPF foi resolvido em

    // 30/08/2026 (cliente criado sem CPF) e o repasse agora vem da Finance API

    // (GetOrderSettlement), nao mais do total do pedido. O aviso que sobra e'

    // so' que nada do TikTok foi exercitado contra o servidor real ainda.

    if TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop then

      if MessageDlg('ATENCAO: a integracao com o TikTok Shop ainda nao foi ' +

           'testada contra um pedido real. O mapeamento de campos esta ' +

           'completo, mas vale conferir os valores gravados neste primeiro ' +

           'pedido antes de confiar na baixa. Confirma?',

           mtWarning, [mbYes, mbNo], 0) <> mrYes then

        Exit;



    Screen.Cursor := crHourGlass;

    try

      case TMarketplaces(FCodMarketplace) of

        TMarketplaces.Shopee: MontagemOk := MontarDadosPedidoShopee(OrderSN, Dados, ErroMsg);

        TMarketplaces.Amazon: MontagemOk := MontarDadosPedidoAmazon(OrderSN, Dados, ErroMsg);

        TMarketplaces.Magalu: MontagemOk := MontarDadosPedidoMagalu(OrderSN, Dados, ErroMsg);

        TMarketplaces.MercadoLivre: MontagemOk := MontarDadosPedidoMercadoLivre(OrderSN, Dados, ErroMsg);

        TMarketplaces.TikTokShop: MontagemOk := MontarDadosPedidoTikTokShop(OrderSN, Dados, ErroMsg);

      else

        MontagemOk := False;

        ErroMsg := 'Marketplace nao suportado.';

      end;



      if not MontagemOk then

      begin

        Log('Falha ao buscar detalhe do pedido: ' + ErroMsg);

        ShowMessage('Falha ao buscar detalhe do pedido: ' + ErroMsg);

        Exit;

      end;



      if BaixarPedidoSAT(Qry, Dados, RetornoProcedure, ErroInfoAdicional, ErroMsg) then

      begin

        // Loga os 2 retornos da procedure MESMO no caminho de sucesso -

        // o cliente pediu visibilidade dos dois valores sempre, nao so

        // quando da erro.

        Log(Format('VENDA_EMITIR_251103A - RETORNO: %d | ' +

          'ERROINFORMACAOADICIONAL: %s', [RetornoProcedure,

          IfThen(ErroInfoAdicional = '', '(vazio)', ErroInfoAdicional)]));

        Log('Pedido ' + OrderSN + ' baixado no SAT com sucesso.');

        ShowMessage('Pedido baixado no SAT com sucesso!');

        GridClick(Self); // reavalia os botoes (esse pedido agora ja foi baixado)

      end

      else

      begin

        // Mesmo em falha, RetornoProcedure/ErroInfoAdicional podem vir

        // preenchidos (se a falha foi a propria procedure recusando o

        // pedido, em vez de um erro de SQL antes dela) - loga sempre que

        // RetornoProcedure <> -1 (-1 = sentinela de "nem chegou a

        // executar a procedure"; RETORNO = 0 e' SUCESSO de verdade,

        // confirmado pelo cliente).

        if RetornoProcedure <> -1 then

          Log(Format('VENDA_EMITIR_251103A - RETORNO: %d | ' +

            'ERROINFORMACAOADICIONAL: %s', [RetornoProcedure,

            IfThen(ErroInfoAdicional = '', '(vazio)', ErroInfoAdicional)]));

        Log('Falha ao baixar pedido ' + OrderSN + ' no SAT: ' + ErroMsg);

        ShowMessage('Falha ao baixar pedido no SAT: ' + ErroMsg);

      end;

    finally

      Screen.Cursor := crDefault;

    end;

  finally

    Qry.Free;

  end;

end;



end.
