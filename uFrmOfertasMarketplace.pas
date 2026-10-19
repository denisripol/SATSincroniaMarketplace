// ============================================================================
// UNIT: uFrmOfertasMarketplace
// OBJETIVO: Tela visual (F3 - Receber Ofertas) que busca os produtos da loja
// virtual (marketplace conectado) e permite conferir/gravar em
// PRODUTOS_MARKETPLACE - substitui o antigo F3 "silencioso" (que gravava
// tudo direto sem grade nenhuma pra conferir antes).
//
// FLUXO:
//   1. Ao abrir, so' mostra a tela com filtros padrao (ultimos 30 dias,
//      todos os status) - NAO busca nada automaticamente.
//   2. "Consultar"              -> busca na Shopee respeitando os filtros
//                                  preenchidos (data de atualizacao e status
//                                  vao pro servidor; nome/Item ID sao
//                                  aplicados aqui, depois da resposta, ja
//                                  que a Shopee nao suporta filtro por nome
//                                  nessa API).
//   3. "Atualizar Todos"       -> grava (insere ou atualiza) TODOS os itens
//                                  que estao na grid (ja filtrados).
//   4. "Atualizar Selecionado" -> grava so' o item selecionado na grid.
//   5. "Incluir Produto"       -> {TODO} aguardando definicao, com o cliente,
//                                  do campo que marca "produto do fisico
//                                  disponivel pro marketplace" na tela de
//                                  Produtos - por enquanto so' avisa que
//                                  ainda nao esta disponivel.
//
// FILTROS: pensados pra valer pra qualquer marketplace no futuro (nao so
// Shopee) - a UI e' generica, quem muda por marketplace e' so a chamada por
// baixo dos panos.
//
// {DECISAO DO CLIENTE - 07/09/2026} toda insercao E toda atualizacao gravam
// ATUALIZAR_ESTOQUE_MARKETPLACE = 'S'. Motivo: esse e' o campo que o F2 le
// pra saber quais produtos precisam ter o estoque enviado, e ate aqui NADA no
// sistema o marcava - nem codigo, nem gatilho. O F2 so' sabe LIMPAR pra 'N'
// depois de enviar. Sem isso o produto entrava na tabela com o campo nulo e
// nunca era sincronizado.
// {ATENCAO} quem cria produto pelas telas de "Incluir Produto" continua
// gravando nulo - se aparecer produto que nao sincroniza, conferir por ali.
//
// O que e' gravado por item (insercao ou atualizacao):
//   - CODPRODUTONOMARKETPLACE, CODMARKETPLACE, LOJA (chave de busca)
//   - DESCRICAO, ESTOQUE, PRECO (ultima "foto" conhecida da loja virtual)
//   - DATAULTIMAALTERACAO
//   - CODPRODUTO NUNCA e' mexido aqui (o vinculo com o fisico e' feito na
//     tela de Produtos, nao aqui) - se ja existir vinculo, permanece intacto.
//
// COBERTURA HOJE: consulta e gravacao de ofertas funcionam para Shopee,
// Amazon, Magalu, Mercado Livre e TikTok Shop. Ja "Incluir Produto"
// (cadastro) so' existe para Shopee, Amazon e Mercado Livre - Magalu e
// TikTok ainda nao tem (ver uModosCadastroProduto).
//
// {ATENCAO} o TikTok e' o unico em que uma linha da grade e' um SKU, nao um
// anuncio: um produto com 3 variacoes vira 3 linhas, cada uma com sua chave
// "product_id|sku_id" e seu proprio vinculo com o produto fisico.
// ============================================================================
unit uFrmOfertasMarketplace;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.StrUtils, System.DateUtils, System.Math, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Vcl.Grids,
  Vcl.ComCtrls,
  Data.DB, FireDAC.Comp.Client,
  DMZ, uMarketplace, Shopee.OpenAPI.Client, Amazon.SPAPI.Client,
  Magalu.OpenAPI.Client, MercadoLivre.OpenAPI.Client, TikTokShop.OpenAPI.Client,
  uFrmVincularProduto, uRoteadorIncluirProduto;
const
  COL_ITEMID = 0;
  COL_DESCRICAO = 1;
  COL_SKU = 2;
  COL_STATUS = 3;
  COL_PRECO = 4;
  COL_ESTOQUE = 5;
  COL_ESTOQUE_INFINITO = 6;
  COL_VINCULO_FISICO = 7;
  COL_VINCULO_VIRTUAL = 8;
  // Data da ultima edicao do anuncio, como o PROPRIO marketplace informa na
  // API (nao vem da PRODUTOS_MARKETPLACE). Campo de cada um:
  //   Shopee ........ update_time          Mercado Livre ... last_updated
  //   Amazon ........ lastUpdatedDate      TikTok Shop ..... update_time
  //   Magalu ........ nao confirmado (updated_at/updatedAt/last_update)
  // {ATENCAO} Na Shopee, alterar estoque ou preco por API NAO muda essa data.
  COL_ULTIMA_ALTERACAO = 9;
type
  // O TikTok e' o unico marketplace do projeto em que a unidade vendida
  // (SKU) nao coincide com o anuncio (produto): um produto tem N SKUs, cada
  // um com preco e estoque proprios. A grade, o vinculo com o produto fisico
  // e o F2 de estoque trabalham por SKU - por isso a lista vem "achatada",
  // um registro por SKU, ja com a chave composta "product_id|sku_id" pronta.
  TOfertaTikTok = record
    Chave: string;        // product_id|sku_id -> CODPRODUTONOMARKETPLACE
    ProductId: string;
    SkuId: string;
    SellerSku: string;    // SKU do vendedor - pode vir vazio
    Titulo: string;
    Status: string;
    Preco: Double;
    Estoque: Integer;
    UpdateTime: TDateTime; // update_time do produto (hora local) - 0 = nao veio
  end;
  TOfertaTikTokArray = TArray<TOfertaTikTok>;

  TFrmOfertasMarketplace = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    pnlFiltros: TPanel;
    lblDataDe: TLabel;
    dtpDataDe: TDateTimePicker;
    lblDataAte: TLabel;
    dtpDataAte: TDateTimePicker;
    lblStatus: TLabel;
    cbxStatus: TComboBox;
    lblFiltroNome: TLabel;
    edtFiltroNome: TEdit;
    lblFiltroItemID: TLabel;
    edtFiltroItemID: TEdit;
    CmdConsultar: TBitBtn;
    Grid: TStringGrid;
    pnlAcoes: TPanel;
    CmdAtualizarTodos: TBitBtn;
    CmdAtualizarSelecionado: TBitBtn;
    CmdVincularProduto: TBitBtn;
    CmdIncluirProduto: TBitBtn;
    MemoLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure CmdConsultarClick(Sender: TObject);
    procedure CmdAtualizarTodosClick(Sender: TObject);
    procedure CmdAtualizarSelecionadoClick(Sender: TObject);
    procedure CmdVincularProdutoClick(Sender: TObject);
    procedure CmdIncluirProdutoClick(Sender: TObject);
  private
    FLoja: Integer;
    FCodMarketplace: Integer;
    FAccountID: string;
    FToken: string;
    FDevClientId: string;
    FDevClientSecret: string;
    FSandbox: Boolean;
    FItems: TShopeeItemArray;
    FAmazonItems: TAmazonListingItemArray;

    FMercadoLivreItems: TMercadoLivreItemArray;
    FTikTokItems: TOfertaTikTokArray;
    FMagaluItems: TMagaluOfferArray;
    procedure Log(const AMsg: string);
    procedure BuscarOfertas;
    procedure BuscarOfertasShopee;
    procedure BuscarOfertasAmazon;
    procedure BuscarOfertasMagalu;
    procedure BuscarOfertasMercadoLivre;
    procedure BuscarOfertasTikTokShop;
    procedure PreencherGrid;
    procedure PreencherGridShopee;
    procedure PreencherGridAmazon;
    procedure PreencherGridMagalu;
    procedure PreencherGridMercadoLivre;
    procedure PreencherGridTikTokShop;
    function BuscarCodigoExistente(AQuery: TFDQuery;
      const ACodProdutoNoMarketplace: string; out ACodProdutoVinculado: Integer;
      out AEstoqueInfinito: Boolean): Integer;
    // Data de edicao do anuncio vinda da API -> texto da grade (vazio se 0).
    function FormatarDataAnuncio(AData: TDateTime): string;
    // Mesma data -> parametro :ULTIMA_ALT_MARKETPLACE (NULL se 0).
    procedure DefinirUltimaAltMarketplace(AQuery: TFDQuery; AData: TDateTime);
    function ProximoCodigoProdutoMarketplace(AQuery: TFDQuery): Integer;
    procedure AtualizarEstoqueFisico(AQuery: TFDQuery;
      const ACodProduto, ANovoEstoque: Integer);
    procedure GravarProduto(AQuery: TFDQuery; const AItem: TShopeeItem);
    procedure GravarProdutoAmazon(AQuery: TFDQuery; const AItem: TAmazonListingItem);
    procedure GravarProdutoMercadoLivre(AQuery: TFDQuery; const AItem: TMercadoLivreItem);
    procedure GravarProdutoTikTokShop(AQuery: TFDQuery; const AItem: TOfertaTikTok);
    procedure GravarProdutoMagalu(AQuery: TFDQuery; const AItem: TMagaluOffer);
    procedure GravarTodos;
    procedure GravarSelecionado;
  public
    // Ponto de entrada - recebe a loja escolhida no combo da tela principal,
    // os dados ja descriptografados da loja conectada e as credenciais de
    // desenvolvedor ja resolvidas (o form principal ja fez essa parte).
    class procedure AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
      const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
      const ASandbox: Boolean);
  end;
implementation
{$R *.dfm}
{ TFrmOfertasMarketplace }
class procedure TFrmOfertasMarketplace.AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
  const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
  const ASandbox: Boolean);
var
  Frm: TFrmOfertasMarketplace;
begin
  Frm := TFrmOfertasMarketplace.Create(Application);
  try
    // FormCreate ja disparou aqui - os campos so' sao preenchidos DEPOIS.
    // Diferente de antes, NAO busca mais automaticamente - o usuario ajusta
    // os filtros (ja vem com um padrao razoavel) e clica em "Consultar".
    Frm.FLoja := ALoja;
    Frm.FCodMarketplace := ACodMarketplace;
    Frm.FAccountID := AAccountID;
    Frm.FToken := AToken;
    Frm.FDevClientId := ADevClientId;
    Frm.FDevClientSecret := ADevClientSecret;
    Frm.FSandbox := ASandbox;
    Frm.lblTitulo.Caption := 'Ofertas - ' + NomeMarketplace(TMarketplaces(ACodMarketplace));
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;
procedure TFrmOfertasMarketplace.FormCreate(Sender: TObject);
begin
  Grid.ColCount := 10;
  Grid.RowCount := 2; // FixedRows precisa ser sempre < RowCount
  Grid.FixedRows := 1;
  Grid.Cells[COL_ITEMID, 0] := 'Item ID';
  Grid.Cells[COL_DESCRICAO, 0] := 'Descrição';
  Grid.Cells[COL_SKU, 0] := 'SKU';
  Grid.Cells[COL_STATUS, 0] := 'Status';
  Grid.Cells[COL_PRECO, 0] := 'Preço';
  Grid.Cells[COL_ESTOQUE, 0] := 'Estoque';
  Grid.Cells[COL_ESTOQUE_INFINITO, 0] := 'Estoque Inf.';
  Grid.Cells[COL_VINCULO_FISICO, 0] := 'Vínculo Físico';
  Grid.Cells[COL_VINCULO_VIRTUAL, 0] := 'Vínculo Virtual';
  Grid.Cells[COL_ULTIMA_ALTERACAO, 0] := 'Anúncio alterado em';
  // Filtros com um padrao razoavel - ultimos 30 dias de atualizacao, todos
  // os status, sem filtro de texto. O usuario ajusta e clica em "Consultar".
  // {ATENCAO} um ANO pra tras, nao 30 dias. Essa data filtra pela ULTIMA
  // EDICAO DO ANUNCIO no marketplace - e alterar estoque ou preco por API NAO
  // conta como edicao (confirmado na Shopee em 14/10/2026: anuncio editado em
  // 31/07 manteve update_time de 31/07 depois do F2 mexer nos dois). Com 30
  // dias, produto ativo e vendendo havia meses simplesmente nao aparecia, e a
  // tela dizia "0 produtos" como se a loja estivesse vazia.
  // A Shopee nao limita o tamanho dessa janela (testado com 286 dias).
  dtpDataDe.Date := IncYear(Now, -1);
  dtpDataAte.Date := Now;
  cbxStatus.Items.Clear;
  cbxStatus.Items.Add('Todos');
  cbxStatus.Items.Add('NORMAL (Ativo)');
  cbxStatus.Items.Add('BANNED (Violação)');
  cbxStatus.Items.Add('REVIEWING (Sob análise)');
  cbxStatus.Items.Add('UNLIST (Não publicado)');
  cbxStatus.ItemIndex := 0;
  edtFiltroNome.Clear;
  edtFiltroItemID.Clear;
end;
procedure TFrmOfertasMarketplace.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;
procedure TFrmOfertasMarketplace.BuscarOfertas;
begin
  case TMarketplaces(FCodMarketplace) of
    TMarketplaces.Shopee: BuscarOfertasShopee;
    TMarketplaces.Amazon: BuscarOfertasAmazon;
    TMarketplaces.Magalu: BuscarOfertasMagalu;
    TMarketplaces.MercadoLivre: BuscarOfertasMercadoLivre;
    TMarketplaces.TikTokShop: BuscarOfertasTikTokShop;
  else
    Log('Consulta de ofertas ainda nao implementada para este marketplace.');
  end;
end;
procedure TFrmOfertasMarketplace.BuscarOfertasShopee;
var
  Cliente: TShopeeOpenAPIClient;
  ErroMsg, StatusFiltro, FiltroNome, FiltroItemID: string;
  UpdateTimeFrom, UpdateTimeTo: Int64;
  ItensBrutos: TShopeeItemArray;
  I, Total: Integer;
  Passa: Boolean;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Shopee nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV na tabela Lojas).');
    Exit;
  end;
  // Data de/ate -> Unix timestamp (a Shopee so filtra por DATA DE
  // ATUALIZACAO, nao tem filtro de data de criacao nessa API).
  UpdateTimeFrom := DateTimeToUnix(dtpDataDe.Date, False);
  // Ate' o FIM do dia selecionado (23:59:59), senao o dia de hoje ficaria
  // de fora quase todo (Date sozinho e' meia-noite).
  UpdateTimeTo := DateTimeToUnix(IncSecond(IncDay(Trunc(dtpDataAte.Date), 1), -1), False);
  // Status: "Todos" (index 0) nao manda filtro nenhum (usa o padrao interno
  // do GetItemList, que ja cobre os 4 status normais). Qualquer outro
  // indice manda so' aquele status especifico.
  StatusFiltro := '';
  case cbxStatus.ItemIndex of
    1: StatusFiltro := 'NORMAL';
    2: StatusFiltro := 'BANNED';
    3: StatusFiltro := 'REVIEWING';
    4: StatusFiltro := 'UNLIST';
  end;
  FiltroNome := Trim(edtFiltroNome.Text);
  FiltroItemID := Trim(edtFiltroItemID.Text);
  Screen.Cursor := crHourGlass;
  try
    Log('Buscando produtos na Shopee' + IfThen(FSandbox, ' (Sandbox)', '') + '...');
    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),
      FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.GetItemList(FToken, StrToInt64Def(FAccountID, 0), ItensBrutos, ErroMsg,
           UpdateTimeFrom, UpdateTimeTo, StatusFiltro) then
      begin
        Log('Erro ao buscar produtos: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    Log(Format('%d produto(s) encontrado(s) na Shopee (antes do filtro de texto).',
      [Length(ItensBrutos)]));
    // Filtro de nome/Item ID - a Shopee nao suporta isso na API, entao e'
    // aplicado aqui, depois da resposta. Se os dois campos estiverem
    // vazios, mantem tudo (nenhum filtro de texto aplicado).
    if (FiltroNome = '') and (FiltroItemID = '') then
      FItems := ItensBrutos
    else
    begin
      SetLength(FItems, Length(ItensBrutos));
      Total := 0;
      for I := Low(ItensBrutos) to High(ItensBrutos) do
      begin
        Passa := True;
        if FiltroNome <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroNome), UpperCase(ItensBrutos[I].ItemName)) > 0);
        if FiltroItemID <> '' then
          Passa := Passa and (Pos(FiltroItemID, IntToStr(ItensBrutos[I].ItemID)) > 0);
        if Passa then
        begin
          FItems[Total] := ItensBrutos[I];
          Inc(Total);
        end;
      end;
      SetLength(FItems, Total);
    end;
    Log(Format('%d produto(s) apos aplicar filtro de nome/Item ID.', [Length(FItems)]));
    PreencherGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmOfertasMarketplace.BuscarOfertasAmazon;
var
  Cliente: TAmazonSPAPIClient;
  ErroMsg, FiltroNome, FiltroItemID: string;
  ItensBrutos: TAmazonListingItemArray;
  I, Total: Integer;
  Passa: Boolean;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Amazon nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  // {TODO} A Amazon nao filtra por data/status na mesma chamada como a
  // Shopee (searchListingsItems tem parametros proprios, tipo
  // createdAfter/lastUpdatedAfter, ainda nao mapeados aqui) - por enquanto
  // busca o catalogo inteiro (o cliente ja pagina sozinho, entao vem tudo
  // mesmo, nao so' 20 itens) e aplica so o filtro de texto (nome/SKU), igual
  // ja fazia na Shopee como fallback. Vendedor com catalogo grande sente na
  // demora: e' uma chamada a cada 20 ofertas.
  FiltroNome := Trim(edtFiltroNome.Text);
  FiltroItemID := Trim(edtFiltroItemID.Text);
  Screen.Cursor := crHourGlass;
  try
    Log('Buscando ofertas na Amazon' + IfThen(FSandbox, ' (Sandbox)', '') + '...');
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.SearchListingsItems(FToken, FAccountID, ItensBrutos, ErroMsg) then
      begin
        Log('Erro ao buscar ofertas: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    Log(Format('%d oferta(s) encontrada(s) na Amazon (antes do filtro de texto).',
      [Length(ItensBrutos)]));
    if (FiltroNome = '') and (FiltroItemID = '') then
      FAmazonItems := ItensBrutos
    else
    begin
      SetLength(FAmazonItems, Length(ItensBrutos));
      Total := 0;
      for I := Low(ItensBrutos) to High(ItensBrutos) do
      begin
        Passa := True;
        if FiltroNome <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroNome), UpperCase(ItensBrutos[I].ItemName)) > 0);
        if FiltroItemID <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroItemID), UpperCase(ItensBrutos[I].SKU)) > 0);
        if Passa then
        begin
          FAmazonItems[Total] := ItensBrutos[I];
          Inc(Total);
        end;
      end;
      SetLength(FAmazonItems, Total);
    end;
    Log(Format('%d oferta(s) apos aplicar filtro de nome/SKU.', [Length(FAmazonItems)]));
    PreencherGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmOfertasMarketplace.BuscarOfertasMercadoLivre;
var
  Cliente: TMercadoLivreOpenAPIClient;
  ErroMsg, FiltroNome, FiltroItemID: string;
  TodosOsIds: TArray<string>;
  LoteIds: TArray<string>;
  ItensBrutos, ItensLote: TMercadoLivreItemArray;
  I, J, TamanhoLote, TotalItens, Total: Integer;
  Passa: Boolean;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor do Mercado Livre nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  FiltroNome := Trim(edtFiltroNome.Text);
  FiltroItemID := Trim(edtFiltroItemID.Text);
  Screen.Cursor := crHourGlass;
  try
    Log('Buscando ofertas no Mercado Livre...');
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.GetItemIds(FToken, FAccountID, TodosOsIds, ErroMsg) then
      begin
        Log('Erro ao buscar IDs de ofertas: ' + ErroMsg);
        Exit;
      end;

      // GetItemsDetails so aceita ate 20 IDs por chamada (limite da API de
      // multiget do Mercado Livre) - divide em lotes.
      SetLength(ItensBrutos, 0);
      TotalItens := 0;
      I := 0;
      while I <= High(TodosOsIds) do
      begin
        TamanhoLote := Min(20, Length(TodosOsIds) - I);
        SetLength(LoteIds, TamanhoLote);
        for J := 0 to TamanhoLote - 1 do
          LoteIds[J] := TodosOsIds[I + J];

        if not Cliente.GetItemsDetails(FToken, LoteIds, ItensLote, ErroMsg) then
        begin
          Log('Erro ao buscar detalhe de ofertas (lote a partir do indice ' +
            IntToStr(I) + '): ' + ErroMsg);
          Exit;
        end;

        SetLength(ItensBrutos, TotalItens + Length(ItensLote));
        for J := Low(ItensLote) to High(ItensLote) do
        begin
          ItensBrutos[TotalItens] := ItensLote[J];
          Inc(TotalItens);
        end;

        Inc(I, TamanhoLote);
      end;
    finally
      Cliente.Free;
    end;
    Log(Format('%d oferta(s) encontrada(s) no Mercado Livre (antes do filtro de texto).',
      [Length(ItensBrutos)]));
    if (FiltroNome = '') and (FiltroItemID = '') then
      FMercadoLivreItems := ItensBrutos
    else
    begin
      SetLength(FMercadoLivreItems, Length(ItensBrutos));
      Total := 0;
      for I := Low(ItensBrutos) to High(ItensBrutos) do
      begin
        Passa := True;
        if FiltroNome <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroNome), UpperCase(ItensBrutos[I].Title)) > 0);
        if FiltroItemID <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroItemID), UpperCase(ItensBrutos[I].ItemId)) > 0);
        if Passa then
        begin
          FMercadoLivreItems[Total] := ItensBrutos[I];
          Inc(Total);
        end;
      end;
      SetLength(FMercadoLivreItems, Total);
    end;
    Log(Format('%d oferta(s) apos aplicar filtro de nome/SKU.', [Length(FMercadoLivreItems)]));
    PreencherGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmOfertasMarketplace.BuscarOfertasMagalu;
var
  Cliente: TMagaluOpenAPIClient;
  ErroMsg, FiltroNome, FiltroItemID: string;
  ItensBrutos: TMagaluOfferArray;
  I, Total: Integer;
  Passa: Boolean;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor do Magalu nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  // O Magalu tambem nao filtra por data/status na mesma chamada - busca
  // tudo e aplica so o filtro de texto (nome/SKU) aqui, igual Amazon.
  FiltroNome := Trim(edtFiltroNome.Text);
  FiltroItemID := Trim(edtFiltroItemID.Text);
  Screen.Cursor := crHourGlass;
  try
    Log('Buscando ofertas no Magalu' + IfThen(FSandbox, ' (Sandbox)', '') + '...');
    Cliente := TMagaluOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.GetSkus(FToken, FAccountID, ItensBrutos, ErroMsg) then
      begin
        Log('Erro ao buscar ofertas: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    Log(Format('%d oferta(s) encontrada(s) no Magalu (antes do filtro de texto).',
      [Length(ItensBrutos)]));
    if (FiltroNome = '') and (FiltroItemID = '') then
      FMagaluItems := ItensBrutos
    else
    begin
      SetLength(FMagaluItems, Length(ItensBrutos));
      Total := 0;
      for I := Low(ItensBrutos) to High(ItensBrutos) do
      begin
        Passa := True;
        if FiltroNome <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroNome), UpperCase(ItensBrutos[I].Description)) > 0);
        if FiltroItemID <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroItemID), UpperCase(ItensBrutos[I].Sku)) > 0);
        if Passa then
        begin
          FMagaluItems[Total] := ItensBrutos[I];
          Inc(Total);
        end;
      end;
      SetLength(FMagaluItems, Total);
    end;
    Log(Format('%d oferta(s) apos aplicar filtro de nome/SKU.', [Length(FMagaluItems)]));
    PreencherGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmOfertasMarketplace.CmdConsultarClick(Sender: TObject);
begin
  BuscarOfertas;
end;
procedure TFrmOfertasMarketplace.PreencherGrid;
begin
  case TMarketplaces(FCodMarketplace) of
    TMarketplaces.Shopee: PreencherGridShopee;
    TMarketplaces.Amazon: PreencherGridAmazon;
    TMarketplaces.Magalu: PreencherGridMagalu;
    TMarketplaces.MercadoLivre: PreencherGridMercadoLivre;
    TMarketplaces.TikTokShop: PreencherGridTikTokShop;
  end;
end;
procedure TFrmOfertasMarketplace.PreencherGridShopee;
var
  Qry: TFDQuery;
  I: Integer;
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
begin
  Grid.RowCount := Length(FItems) + 1;
  if Grid.RowCount < 2 then
    Grid.RowCount := 2; // FixedRows = 1 exige RowCount >= 2
  for I := 1 to Grid.RowCount - 1 do
  begin
    Grid.Cells[COL_ITEMID, I] := '';
    Grid.Cells[COL_DESCRICAO, I] := '';
    Grid.Cells[COL_SKU, I] := '';
    Grid.Cells[COL_STATUS, I] := '';
    Grid.Cells[COL_PRECO, I] := '';
    Grid.Cells[COL_ESTOQUE, I] := '';
    Grid.Cells[COL_ESTOQUE_INFINITO, I] := '';
    Grid.Cells[COL_VINCULO_FISICO, I] := '';
    Grid.Cells[COL_VINCULO_VIRTUAL, I] := '';
    Grid.Cells[COL_ULTIMA_ALTERACAO, I] := '';
  end;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    for I := Low(FItems) to High(FItems) do
    begin
      // O proprio Result de BuscarCodigoExistente ja diz se o registro
      // existe em PRODUTOS_MARKETPLACE (0 = nao existe ainda) - e' isso que
      // vira o "Vinculo Virtual". CodProdutoVinculado (fora, so preenchido
      // se ja existir a linha) e' o "Vinculo Fisico" (CODPRODUTO setado).
      CodExistente := BuscarCodigoExistente(Qry, IntToStr(FItems[I].ItemID),
        CodProdutoVinculado, EstoqueInfinito);
      Grid.Cells[COL_ITEMID, I + 1] := IntToStr(FItems[I].ItemID);
      Grid.Cells[COL_DESCRICAO, I + 1] := FItems[I].ItemName;
      Grid.Cells[COL_SKU, I + 1] := FItems[I].ItemSKU;
      Grid.Cells[COL_STATUS, I + 1] := FItems[I].ItemStatus;
      Grid.Cells[COL_PRECO, I + 1] := FormatFloat('0.00', FItems[I].OriginalPrice);
      Grid.Cells[COL_ESTOQUE, I + 1] := IntToStr(FItems[I].Stock);
      Grid.Cells[COL_ESTOQUE_INFINITO, I + 1] := IfThen(EstoqueInfinito, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_FISICO, I + 1] := IfThen(CodProdutoVinculado <> 0, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_VIRTUAL, I + 1] := IfThen(CodExistente <> 0, 'Sim', 'Não');
      Grid.Cells[COL_ULTIMA_ALTERACAO, I + 1] := FormatarDataAnuncio(FItems[I].UpdateTime);
    end;
  finally
    Qry.Free;
  end;
end;
procedure TFrmOfertasMarketplace.PreencherGridAmazon;
var
  Qry: TFDQuery;
  I: Integer;
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
begin
  Grid.RowCount := Length(FAmazonItems) + 1;
  if Grid.RowCount < 2 then
    Grid.RowCount := 2;
  for I := 1 to Grid.RowCount - 1 do
  begin
    Grid.Cells[COL_ITEMID, I] := '';
    Grid.Cells[COL_DESCRICAO, I] := '';
    Grid.Cells[COL_SKU, I] := '';
    Grid.Cells[COL_STATUS, I] := '';
    Grid.Cells[COL_PRECO, I] := '';
    Grid.Cells[COL_ESTOQUE, I] := '';
    Grid.Cells[COL_ESTOQUE_INFINITO, I] := '';
    Grid.Cells[COL_VINCULO_FISICO, I] := '';
    Grid.Cells[COL_VINCULO_VIRTUAL, I] := '';
    Grid.Cells[COL_ULTIMA_ALTERACAO, I] := '';
  end;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    for I := Low(FAmazonItems) to High(FAmazonItems) do
    begin
      // Amazon nao tem um "item_id" numerico como a Shopee - o SKU e' a
      // chave que usamos como CODPRODUTONOMARKETPLACE pra esse marketplace.
      CodExistente := BuscarCodigoExistente(Qry, FAmazonItems[I].SKU,
        CodProdutoVinculado, EstoqueInfinito);
      // Item ID (coluna reaproveitada) mostra o SKU pra Amazon; a coluna
      // SKU (que na Shopee mostra o SKU tambem) mostra o ASIN aqui, ja que
      // nao ha um "SKU" separado do que ja vai na primeira coluna.
      Grid.Cells[COL_ITEMID, I + 1] := FAmazonItems[I].SKU;
      Grid.Cells[COL_DESCRICAO, I + 1] := FAmazonItems[I].ItemName;
      Grid.Cells[COL_SKU, I + 1] := FAmazonItems[I].ASIN;
      Grid.Cells[COL_STATUS, I + 1] := FAmazonItems[I].Status;
      Grid.Cells[COL_PRECO, I + 1] := FormatFloat('0.00', FAmazonItems[I].Price);
      Grid.Cells[COL_ESTOQUE, I + 1] := IntToStr(FAmazonItems[I].Stock);
      Grid.Cells[COL_ESTOQUE_INFINITO, I + 1] := IfThen(EstoqueInfinito, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_FISICO, I + 1] := IfThen(CodProdutoVinculado <> 0, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_VIRTUAL, I + 1] := IfThen(CodExistente <> 0, 'Sim', 'Não');
      Grid.Cells[COL_ULTIMA_ALTERACAO, I + 1] := FormatarDataAnuncio(FAmazonItems[I].LastUpdated);
    end;
  finally
    Qry.Free;
  end;
end;
procedure TFrmOfertasMarketplace.PreencherGridMercadoLivre;
var
  Qry: TFDQuery;
  I: Integer;
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
begin
  Grid.RowCount := Length(FMercadoLivreItems) + 1;
  if Grid.RowCount < 2 then
    Grid.RowCount := 2;
  for I := 1 to Grid.RowCount - 1 do
  begin
    Grid.Cells[COL_ITEMID, I] := '';
    Grid.Cells[COL_DESCRICAO, I] := '';
    Grid.Cells[COL_SKU, I] := '';
    Grid.Cells[COL_STATUS, I] := '';
    Grid.Cells[COL_PRECO, I] := '';
    Grid.Cells[COL_ESTOQUE, I] := '';
    Grid.Cells[COL_ESTOQUE_INFINITO, I] := '';
    Grid.Cells[COL_VINCULO_FISICO, I] := '';
    Grid.Cells[COL_VINCULO_VIRTUAL, I] := '';
    Grid.Cells[COL_ULTIMA_ALTERACAO, I] := '';
  end;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    for I := Low(FMercadoLivreItems) to High(FMercadoLivreItems) do
    begin
      // {ATENCAO} o Mercado Livre nao tem um "SKU do vendedor" separado
      // exposto nesse metodo simplificado de GetItemsDetails (existiria
      // em seller_custom_field/attributes, nao mapeado ainda) - o
      // ItemId (identificador do anuncio, tipo "MLB123456789") e' a
      // chave usada como CODPRODUTONOMARKETPLACE.
      CodExistente := BuscarCodigoExistente(Qry, FMercadoLivreItems[I].ItemId,
        CodProdutoVinculado, EstoqueInfinito);
      Grid.Cells[COL_ITEMID, I + 1] := FMercadoLivreItems[I].ItemId;
      Grid.Cells[COL_DESCRICAO, I + 1] := FMercadoLivreItems[I].Title;
      Grid.Cells[COL_SKU, I + 1] := FMercadoLivreItems[I].ItemId;
      Grid.Cells[COL_STATUS, I + 1] := FMercadoLivreItems[I].Status;
      Grid.Cells[COL_PRECO, I + 1] := FormatFloat('0.00', FMercadoLivreItems[I].Price);
      Grid.Cells[COL_ESTOQUE, I + 1] := IntToStr(FMercadoLivreItems[I].AvailableQuantity);
      Grid.Cells[COL_ESTOQUE_INFINITO, I + 1] := IfThen(EstoqueInfinito, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_FISICO, I + 1] := IfThen(CodProdutoVinculado <> 0, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_VIRTUAL, I + 1] := IfThen(CodExistente <> 0, 'Sim', 'Não');
      Grid.Cells[COL_ULTIMA_ALTERACAO, I + 1] := FormatarDataAnuncio(FMercadoLivreItems[I].LastUpdated);
    end;
  finally
    Qry.Free;
  end;
end;
procedure TFrmOfertasMarketplace.PreencherGridMagalu;
var
  Qry: TFDQuery;
  I: Integer;
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
begin
  Grid.RowCount := Length(FMagaluItems) + 1;
  if Grid.RowCount < 2 then
    Grid.RowCount := 2;
  for I := 1 to Grid.RowCount - 1 do
  begin
    Grid.Cells[COL_ITEMID, I] := '';
    Grid.Cells[COL_DESCRICAO, I] := '';
    Grid.Cells[COL_SKU, I] := '';
    Grid.Cells[COL_STATUS, I] := '';
    Grid.Cells[COL_PRECO, I] := '';
    Grid.Cells[COL_ESTOQUE, I] := '';
    Grid.Cells[COL_ESTOQUE_INFINITO, I] := '';
    Grid.Cells[COL_VINCULO_FISICO, I] := '';
    Grid.Cells[COL_VINCULO_VIRTUAL, I] := '';
    Grid.Cells[COL_ULTIMA_ALTERACAO, I] := '';
  end;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    for I := Low(FMagaluItems) to High(FMagaluItems) do
    begin
      // Magalu tambem nao tem um "item_id" numerico separado - o SKU e' a
      // chave, igual na Amazon.
      CodExistente := BuscarCodigoExistente(Qry, FMagaluItems[I].Sku,
        CodProdutoVinculado, EstoqueInfinito);
      Grid.Cells[COL_ITEMID, I + 1] := FMagaluItems[I].Sku;
      Grid.Cells[COL_DESCRICAO, I + 1] := FMagaluItems[I].Description;
      Grid.Cells[COL_SKU, I + 1] := FMagaluItems[I].Sku;
      Grid.Cells[COL_STATUS, I + 1] := FMagaluItems[I].Status;
      Grid.Cells[COL_PRECO, I + 1] := FormatFloat('0.00', FMagaluItems[I].Price);
      Grid.Cells[COL_ESTOQUE, I + 1] := IntToStr(FMagaluItems[I].Stock);
      Grid.Cells[COL_ESTOQUE_INFINITO, I + 1] := IfThen(EstoqueInfinito, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_FISICO, I + 1] := IfThen(CodProdutoVinculado <> 0, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_VIRTUAL, I + 1] := IfThen(CodExistente <> 0, 'Sim', 'Não');
      Grid.Cells[COL_ULTIMA_ALTERACAO, I + 1] := FormatarDataAnuncio(FMagaluItems[I].LastUpdated);
    end;
  finally
    Qry.Free;
  end;
end;
// ----------------------------------------------------------------------------
// PRODUTOS_MARKETPLACE (leitura/gravacao)
// ----------------------------------------------------------------------------
function TFrmOfertasMarketplace.ProximoCodigoProdutoMarketplace(AQuery: TFDQuery): Integer;
begin
  // {TODO} Placeholder - se existir um GEN_ID proprio pra essa tabela no
  // banco, trocar por: SELECT GEN_ID(GEN_NOME_AQUI, 1) FROM RDB$DATABASE
  AQuery.Close;
  AQuery.SQL.Text :=
    'SELECT COALESCE(MAX(CODPRODUTOS_MARKETPLACE), 0) + 1 AS PROXIMO ' +
    'FROM PRODUTOS_MARKETPLACE';
  AQuery.Open;
  Result := AQuery.FieldByName('PROXIMO').AsInteger;
  AQuery.Close;
end;
function TFrmOfertasMarketplace.BuscarCodigoExistente(AQuery: TFDQuery;
  const ACodProdutoNoMarketplace: string; out ACodProdutoVinculado: Integer;
  out AEstoqueInfinito: Boolean): Integer;
begin
  AQuery.Close;
  AQuery.SQL.Text :=
    'SELECT CODPRODUTOS_MARKETPLACE, CODPRODUTO, ESTOQUE_INFINITO ' +
    'FROM PRODUTOS_MARKETPLACE ' +
    'WHERE CODMARKETPLACE = :CODMARKETPLACE ' +
    'AND CODPRODUTONOMARKETPLACE = :CODPRODUTONOMARKETPLACE ' +
    'AND LOJA = :LOJA';
  AQuery.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
  AQuery.ParamByName('CODPRODUTONOMARKETPLACE').AsString := ACodProdutoNoMarketplace;
  AQuery.ParamByName('LOJA').AsInteger := FLoja;
  AQuery.Open;
  if AQuery.IsEmpty then
  begin
    Result := 0;
    ACodProdutoVinculado := 0;
    AEstoqueInfinito := False;
  end
  else
  begin
    Result := AQuery.FieldByName('CODPRODUTOS_MARKETPLACE').AsInteger;
    ACodProdutoVinculado := AQuery.FieldByName('CODPRODUTO').AsInteger;
    AEstoqueInfinito := AQuery.FieldByName('ESTOQUE_INFINITO').AsInteger = 1;
  end;
  AQuery.Close;
end;
function TFrmOfertasMarketplace.FormatarDataAnuncio(AData: TDateTime): string;
begin
  // 0 = o marketplace nao mandou a data: celula em branco, e nao 30/12/1899.
  if AData > 0 then
    Result := FormatDateTime('dd/mm/yyyy hh:nn', AData)
  else
    Result := '';
end;
// {PEDIDO DO CLIENTE - 19/10/2026} PRODUTOS_MARKETPLACE.ULTIMA_ALT_MARKETPLACE
// guarda a data de edicao do anuncio informada pela API (a mesma da coluna
// "Anuncio alterado em"). Nao confundir com DATAULTIMAALTERACAO, que e' quando
// o SAT gravou o registro.
procedure TFrmOfertasMarketplace.DefinirUltimaAltMarketplace(AQuery: TFDQuery;
  AData: TDateTime);
begin
  if AData > 0 then
    AQuery.ParamByName('ULTIMA_ALT_MARKETPLACE').AsDateTime := AData
  else
  begin
    // Tipo explicito: parametro sem tipo e sem valor o Firebird recusa.
    AQuery.ParamByName('ULTIMA_ALT_MARKETPLACE').DataType := ftTimeStamp;
    AQuery.ParamByName('ULTIMA_ALT_MARKETPLACE').Clear;
  end;
end;
procedure TFrmOfertasMarketplace.AtualizarEstoqueFisico(AQuery: TFDQuery;
  const ACodProduto, ANovoEstoque: Integer);
begin
  // Empurra o estoque da PRODUTOS_MARKETPLACE (a "foto" que acabou de vir
  // da Shopee) pra tabela fisica de estoque por loja (PRO.QUANT) - so' e'
  // chamado quando ja existe vinculo e o produto nao esta marcado como
  // ESTOQUE_INFINITO (essas duas checagens ja acontecem em quem chama).
  AQuery.Close;
  AQuery.SQL.Text := 'UPDATE PRO SET QUANT = :QUANT WHERE COD = :COD AND LOJA = :LOJA';
  AQuery.ParamByName('QUANT').AsInteger := ANovoEstoque;
  AQuery.ParamByName('COD').AsInteger := ACodProduto;
  AQuery.ParamByName('LOJA').AsInteger := FLoja;
  AQuery.ExecSQL;
  Log('  Estoque fisico atualizado: produto ' + IntToStr(ACodProduto) + ' -> ' +
    IntToStr(ANovoEstoque) + ' un.');
end;
procedure TFrmOfertasMarketplace.GravarProduto(AQuery: TFDQuery; const AItem: TShopeeItem);
var
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
  NovoCodigo: Integer;
  SqlUpdate: string;
begin
  CodExistente := BuscarCodigoExistente(AQuery, IntToStr(AItem.ItemID),
    CodProdutoVinculado, EstoqueInfinito);
  if CodExistente = 0 then
  begin
    // Novo - insere. CODPRODUTO fica em branco (vinculo e' feito depois, na
    // tela de Produtos), CODTABELADEPRECOS em branco (ver observacao no
    // primeiro rascunho dessa tela). ESTOQUE_INFINITO nao existe ainda pra
    // um produto novo (fica 0/NULL por padrao) - so' passa a valer depois
    // que alguem marcar manualmente pra esse produto.
    NovoCodigo := ProximoCodigoProdutoMarketplace(AQuery);
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO PRODUTOS_MARKETPLACE ' +
      '(CODPRODUTOS_MARKETPLACE, CODPRODUTO, CODMARKETPLACE, ' +
      'CODPRODUTONOMARKETPLACE, DISPONIBILIZARMARKETPLACE, ' +
      'ATUALIZARMARKETPLACE, EXCLUIDO, ATUALIZAR_ESTOQUE_MARKETPLACE, ' +
      'DESCRICAO, ESTOQUE, PRECO, ' +
      'DATAULTIMAALTERACAO, ULTIMA_ALT_MARKETPLACE, LOJA) ' +
      'VALUES (:CODPRODUTOS_MARKETPLACE, NULL, :CODMARKETPLACE, ' +
      ':CODPRODUTONOMARKETPLACE, ''N'', ''N'', ''N'', ''S'', :DESCRICAO, ' +
      ':ESTOQUE, :PRECO, :DATAULTIMAALTERACAO, :ULTIMA_ALT_MARKETPLACE, :LOJA)';
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := NovoCodigo;
    AQuery.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
    AQuery.ParamByName('CODPRODUTONOMARKETPLACE').AsString := IntToStr(AItem.ItemID);
    AQuery.ParamByName('DESCRICAO').AsString := AItem.ItemName;
    AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Stock;
    AQuery.ParamByName('PRECO').AsFloat := AItem.OriginalPrice;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    AQuery.ParamByName('LOJA').AsInteger := FLoja;
    DefinirUltimaAltMarketplace(AQuery, AItem.UpdateTime);
    AQuery.ExecSQL;
    Log('  Novo: ' + AItem.ItemName + ' (ID ' + IntToStr(AItem.ItemID) + ')');
  end
  else
  begin
    // Ja existe - so atualiza a "foto" (Descricao/Estoque/Preco/Data).
    // CODPRODUTO NUNCA e' mexido aqui - o vinculo com o fisico e' feito na
    // tela de Produtos, permanece intacto (vinculado ou nao) do jeito que
    // ja estava.
    // Se ESTOQUE_INFINITO = 1 (produto que o cliente marcou como "nao
    // controla estoque"), NAO sobrescreve o ESTOQUE com o valor vindo da
    // Shopee - mantem o que ja estava gravado.
    SqlUpdate :=
      'UPDATE PRODUTOS_MARKETPLACE SET DESCRICAO = :DESCRICAO, ' +
      'PRECO = :PRECO, DATAULTIMAALTERACAO = :DATAULTIMAALTERACAO, ' +
      'ATUALIZAR_ESTOQUE_MARKETPLACE = ''S''';
    if not EstoqueInfinito then
      SqlUpdate := SqlUpdate + ', ESTOQUE = :ESTOQUE';
    // Data de edicao do anuncio vinda da API. Se o marketplace nao mandou
    // (0), nao mexe no que ja estava gravado.
    if AItem.UpdateTime > 0 then
      SqlUpdate := SqlUpdate + ', ULTIMA_ALT_MARKETPLACE = :ULTIMA_ALT_MARKETPLACE';
    SqlUpdate := SqlUpdate + ' WHERE CODPRODUTOS_MARKETPLACE = :CODPRODUTOS_MARKETPLACE';
    AQuery.Close;
    AQuery.SQL.Text := SqlUpdate;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.ItemName;
    AQuery.ParamByName('PRECO').AsFloat := AItem.OriginalPrice;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    if not EstoqueInfinito then
      AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Stock;
    if AItem.UpdateTime > 0 then
      DefinirUltimaAltMarketplace(AQuery, AItem.UpdateTime);
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := CodExistente;
    AQuery.ExecSQL;
    if EstoqueInfinito then
      Log('  Atualizado (estoque ignorado - ESTOQUE_INFINITO): ' + AItem.ItemName);
    { A atualizacao de estoque fisico a partir daqui (Ofertas) foi
      desativada por decisao do cliente - o estoque fisico vai ser
      atualizado de outra forma, atraves do processamento de pedidos
      (tabelas de Pedido/Itens do Pedido, igual uma venda no SAT), ainda a
      ser detalhado. Deixando comentado (nao removido) pra facilitar
      reverter se precisar.
    else if CodProdutoVinculado <> 0 then
      // So' atualiza o estoque fisico se ja tiver vinculo com um produto e
      // nao for estoque infinito. Sem vinculo, nao ha' onde gravar ainda.
      AtualizarEstoqueFisico(AQuery, CodProdutoVinculado, AItem.Stock);
    }
  end;
end;
procedure TFrmOfertasMarketplace.GravarProdutoAmazon(AQuery: TFDQuery; const AItem: TAmazonListingItem);
var
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
  NovoCodigo: Integer;
  SqlUpdate: string;
begin
  // Mesma logica do GravarProduto da Shopee - so troca a chave
  // (CODPRODUTONOMARKETPLACE = SKU, string, em vez de item_id numerico).
  CodExistente := BuscarCodigoExistente(AQuery, AItem.SKU,
    CodProdutoVinculado, EstoqueInfinito);
  if CodExistente = 0 then
  begin
    NovoCodigo := ProximoCodigoProdutoMarketplace(AQuery);
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO PRODUTOS_MARKETPLACE ' +
      '(CODPRODUTOS_MARKETPLACE, CODPRODUTO, CODMARKETPLACE, ' +
      'CODPRODUTONOMARKETPLACE, DISPONIBILIZARMARKETPLACE, ' +
      'ATUALIZARMARKETPLACE, EXCLUIDO, ATUALIZAR_ESTOQUE_MARKETPLACE, ' +
      'DESCRICAO, ESTOQUE, PRECO, ' +
      'DATAULTIMAALTERACAO, ULTIMA_ALT_MARKETPLACE, LOJA) ' +
      'VALUES (:CODPRODUTOS_MARKETPLACE, NULL, :CODMARKETPLACE, ' +
      ':CODPRODUTONOMARKETPLACE, ''N'', ''N'', ''N'', ''S'', :DESCRICAO, ' +
      ':ESTOQUE, :PRECO, :DATAULTIMAALTERACAO, :ULTIMA_ALT_MARKETPLACE, :LOJA)';
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := NovoCodigo;
    AQuery.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
    AQuery.ParamByName('CODPRODUTONOMARKETPLACE').AsString := AItem.SKU;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.ItemName;
    AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Stock;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Price;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    AQuery.ParamByName('LOJA').AsInteger := FLoja;
    DefinirUltimaAltMarketplace(AQuery, AItem.LastUpdated);
    AQuery.ExecSQL;
    Log('  Novo: ' + AItem.ItemName + ' (SKU ' + AItem.SKU + ')');
  end
  else
  begin
    SqlUpdate :=
      'UPDATE PRODUTOS_MARKETPLACE SET DESCRICAO = :DESCRICAO, ' +
      'PRECO = :PRECO, DATAULTIMAALTERACAO = :DATAULTIMAALTERACAO, ' +
      'ATUALIZAR_ESTOQUE_MARKETPLACE = ''S''';
    if not EstoqueInfinito then
      SqlUpdate := SqlUpdate + ', ESTOQUE = :ESTOQUE';
    // Data de edicao do anuncio vinda da API. Se o marketplace nao mandou
    // (0), nao mexe no que ja estava gravado.
    if AItem.LastUpdated > 0 then
      SqlUpdate := SqlUpdate + ', ULTIMA_ALT_MARKETPLACE = :ULTIMA_ALT_MARKETPLACE';
    SqlUpdate := SqlUpdate + ' WHERE CODPRODUTOS_MARKETPLACE = :CODPRODUTOS_MARKETPLACE';
    AQuery.Close;
    AQuery.SQL.Text := SqlUpdate;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.ItemName;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Price;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    if not EstoqueInfinito then
      AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Stock;
    if AItem.LastUpdated > 0 then
      DefinirUltimaAltMarketplace(AQuery, AItem.LastUpdated);
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := CodExistente;
    AQuery.ExecSQL;
    if EstoqueInfinito then
      Log('  Atualizado (estoque ignorado - ESTOQUE_INFINITO): ' + AItem.ItemName);
    // Mesma decisao do cliente que ja vale pra Shopee - nao atualiza
    // estoque fisico daqui, isso vai ser feito via processamento de
    // pedidos futuramente.
  end;
end;
procedure TFrmOfertasMarketplace.GravarProdutoMercadoLivre(AQuery: TFDQuery; const AItem: TMercadoLivreItem);
var
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
  NovoCodigo: Integer;
  SqlUpdate: string;
begin
  // Mesma logica da Amazon - chave e' o ItemId (string, tipo "MLB123456789").
  CodExistente := BuscarCodigoExistente(AQuery, AItem.ItemId,
    CodProdutoVinculado, EstoqueInfinito);
  if CodExistente = 0 then
  begin
    NovoCodigo := ProximoCodigoProdutoMarketplace(AQuery);
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO PRODUTOS_MARKETPLACE ' +
      '(CODPRODUTOS_MARKETPLACE, CODPRODUTO, CODMARKETPLACE, ' +
      'CODPRODUTONOMARKETPLACE, DISPONIBILIZARMARKETPLACE, ' +
      'ATUALIZARMARKETPLACE, EXCLUIDO, ATUALIZAR_ESTOQUE_MARKETPLACE, ' +
      'DESCRICAO, ESTOQUE, PRECO, ' +
      'DATAULTIMAALTERACAO, ULTIMA_ALT_MARKETPLACE, LOJA) ' +
      'VALUES (:CODPRODUTOS_MARKETPLACE, NULL, :CODMARKETPLACE, ' +
      ':CODPRODUTONOMARKETPLACE, ''N'', ''N'', ''N'', ''S'', :DESCRICAO, ' +
      ':ESTOQUE, :PRECO, :DATAULTIMAALTERACAO, :ULTIMA_ALT_MARKETPLACE, :LOJA)';
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := NovoCodigo;
    AQuery.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
    AQuery.ParamByName('CODPRODUTONOMARKETPLACE').AsString := AItem.ItemId;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.Title;
    AQuery.ParamByName('ESTOQUE').AsInteger := AItem.AvailableQuantity;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Price;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    AQuery.ParamByName('LOJA').AsInteger := FLoja;
    DefinirUltimaAltMarketplace(AQuery, AItem.LastUpdated);
    AQuery.ExecSQL;
    Log('  Novo: ' + AItem.Title + ' (' + AItem.ItemId + ')');
  end
  else
  begin
    SqlUpdate :=
      'UPDATE PRODUTOS_MARKETPLACE SET DESCRICAO = :DESCRICAO, ' +
      'PRECO = :PRECO, DATAULTIMAALTERACAO = :DATAULTIMAALTERACAO, ' +
      'ATUALIZAR_ESTOQUE_MARKETPLACE = ''S''';
    if not EstoqueInfinito then
      SqlUpdate := SqlUpdate + ', ESTOQUE = :ESTOQUE';
    // Data de edicao do anuncio vinda da API. Se o marketplace nao mandou
    // (0), nao mexe no que ja estava gravado.
    if AItem.LastUpdated > 0 then
      SqlUpdate := SqlUpdate + ', ULTIMA_ALT_MARKETPLACE = :ULTIMA_ALT_MARKETPLACE';
    SqlUpdate := SqlUpdate + ' WHERE CODPRODUTOS_MARKETPLACE = :CODPRODUTOS_MARKETPLACE';
    AQuery.Close;
    AQuery.SQL.Text := SqlUpdate;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.Title;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Price;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    if not EstoqueInfinito then
      AQuery.ParamByName('ESTOQUE').AsInteger := AItem.AvailableQuantity;
    if AItem.LastUpdated > 0 then
      DefinirUltimaAltMarketplace(AQuery, AItem.LastUpdated);
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := CodExistente;
    AQuery.ExecSQL;
    if EstoqueInfinito then
      Log('  Atualizado (estoque ignorado - ESTOQUE_INFINITO): ' + AItem.Title);
  end;
end;
procedure TFrmOfertasMarketplace.GravarProdutoMagalu(AQuery: TFDQuery; const AItem: TMagaluOffer);
var
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
  NovoCodigo: Integer;
  SqlUpdate: string;
begin
  // Mesma logica da Amazon - chave e' o SKU (string).
  CodExistente := BuscarCodigoExistente(AQuery, AItem.Sku,
    CodProdutoVinculado, EstoqueInfinito);
  if CodExistente = 0 then
  begin
    NovoCodigo := ProximoCodigoProdutoMarketplace(AQuery);
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO PRODUTOS_MARKETPLACE ' +
      '(CODPRODUTOS_MARKETPLACE, CODPRODUTO, CODMARKETPLACE, ' +
      'CODPRODUTONOMARKETPLACE, DISPONIBILIZARMARKETPLACE, ' +
      'ATUALIZARMARKETPLACE, EXCLUIDO, ATUALIZAR_ESTOQUE_MARKETPLACE, ' +
      'DESCRICAO, ESTOQUE, PRECO, ' +
      'DATAULTIMAALTERACAO, ULTIMA_ALT_MARKETPLACE, LOJA) ' +
      'VALUES (:CODPRODUTOS_MARKETPLACE, NULL, :CODMARKETPLACE, ' +
      ':CODPRODUTONOMARKETPLACE, ''N'', ''N'', ''N'', ''S'', :DESCRICAO, ' +
      ':ESTOQUE, :PRECO, :DATAULTIMAALTERACAO, :ULTIMA_ALT_MARKETPLACE, :LOJA)';
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := NovoCodigo;
    AQuery.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
    AQuery.ParamByName('CODPRODUTONOMARKETPLACE').AsString := AItem.Sku;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.Description;
    AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Stock;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Price;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    AQuery.ParamByName('LOJA').AsInteger := FLoja;
    DefinirUltimaAltMarketplace(AQuery, AItem.LastUpdated);
    AQuery.ExecSQL;
    Log('  Novo: ' + AItem.Description + ' (SKU ' + AItem.Sku + ')');
  end
  else
  begin
    SqlUpdate :=
      'UPDATE PRODUTOS_MARKETPLACE SET DESCRICAO = :DESCRICAO, ' +
      'PRECO = :PRECO, DATAULTIMAALTERACAO = :DATAULTIMAALTERACAO, ' +
      'ATUALIZAR_ESTOQUE_MARKETPLACE = ''S''';
    if not EstoqueInfinito then
      SqlUpdate := SqlUpdate + ', ESTOQUE = :ESTOQUE';
    // Data de edicao do anuncio vinda da API. Se o marketplace nao mandou
    // (0), nao mexe no que ja estava gravado.
    if AItem.LastUpdated > 0 then
      SqlUpdate := SqlUpdate + ', ULTIMA_ALT_MARKETPLACE = :ULTIMA_ALT_MARKETPLACE';
    SqlUpdate := SqlUpdate + ' WHERE CODPRODUTOS_MARKETPLACE = :CODPRODUTOS_MARKETPLACE';
    AQuery.Close;
    AQuery.SQL.Text := SqlUpdate;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.Description;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Price;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    if not EstoqueInfinito then
      AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Stock;
    if AItem.LastUpdated > 0 then
      DefinirUltimaAltMarketplace(AQuery, AItem.LastUpdated);
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := CodExistente;
    AQuery.ExecSQL;
    if EstoqueInfinito then
      Log('  Atualizado (estoque ignorado - ESTOQUE_INFINITO): ' + AItem.Description);
  end;
end;
procedure TFrmOfertasMarketplace.BuscarOfertasTikTokShop;
var
  Cliente: TTikTokShopOpenAPIClient;
  Produtos: TTikTokShopProductArray;
  Achatadas: TOfertaTikTokArray;
  ErroMsg, FiltroNome, FiltroItemID, ShopId, ShopCipher: string;
  I, J, Total: Integer;
  Passa: Boolean;
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
  FiltroNome := Trim(edtFiltroNome.Text);
  FiltroItemID := Trim(edtFiltroItemID.Text);
  Screen.Cursor := crHourGlass;
  try
    Log('Buscando ofertas no TikTok Shop...');
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.SearchProducts(FToken, ShopCipher, Produtos, ErroMsg) then
      begin
        Log('Erro ao buscar ofertas: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;

    // "Achata" produto x SKU: a grade e o vinculo com o produto fisico
    // trabalham por SKU, que e' a unidade que tem preco e estoque proprios.
    SetLength(Achatadas, 0);
    Total := 0;
    for I := Low(Produtos) to High(Produtos) do
    begin
      if Length(Produtos[I].Skus) = 0 then
      begin
        // Produto sem SKU e' rascunho/incompleto no TikTok - nao da' pra
        // vincular nem controlar estoque, entao so' registra no log.
        Log('  Produto sem SKU (ignorado): ' + Produtos[I].Title +
          ' (' + Produtos[I].ProductId + ')');
        Continue;
      end;
      SetLength(Achatadas, Total + Length(Produtos[I].Skus));
      for J := Low(Produtos[I].Skus) to High(Produtos[I].Skus) do
      begin
        Achatadas[Total].ProductId := Produtos[I].ProductId;
        Achatadas[Total].SkuId := Produtos[I].Skus[J].SkuId;
        Achatadas[Total].Chave := MontarChaveProdutoTikTok(Produtos[I].ProductId,
          Produtos[I].Skus[J].SkuId);
        Achatadas[Total].SellerSku := Produtos[I].Skus[J].SellerSku;
        Achatadas[Total].Status := Produtos[I].Status;
        Achatadas[Total].Preco := Produtos[I].Skus[J].Preco;
        Achatadas[Total].Estoque := Produtos[I].Skus[J].Estoque;
        // A API so' informa a data por PRODUTO - todos os SKUs dele herdam.
        Achatadas[Total].UpdateTime := Produtos[I].UpdateTime;
        // Produto com mais de um SKU: poe o SKU do vendedor no titulo, senao
        // a grade mostra varias linhas com a MESMA descricao e nao da' pra
        // saber qual e' qual na hora de vincular ao produto fisico.
        if (Length(Produtos[I].Skus) > 1) and (Produtos[I].Skus[J].SellerSku <> '') then
          Achatadas[Total].Titulo := Produtos[I].Title + ' - ' + Produtos[I].Skus[J].SellerSku
        else
          Achatadas[Total].Titulo := Produtos[I].Title;
        Inc(Total);
      end;
    end;
    SetLength(Achatadas, Total);
    Log(Format('%d oferta(s)/SKU encontrada(s) no TikTok (antes do filtro de texto).',
      [Length(Achatadas)]));

    if (FiltroNome = '') and (FiltroItemID = '') then
      FTikTokItems := Achatadas
    else
    begin
      SetLength(FTikTokItems, Length(Achatadas));
      Total := 0;
      for I := Low(Achatadas) to High(Achatadas) do
      begin
        Passa := True;
        if FiltroNome <> '' then
          Passa := Passa and (Pos(UpperCase(FiltroNome), UpperCase(Achatadas[I].Titulo)) > 0);
        if FiltroItemID <> '' then
          // Casa tanto com a chave composta quanto com o SKU do vendedor -
          // quem digita aqui normalmente tem em maos um dos dois.
          Passa := Passa and
            ((Pos(UpperCase(FiltroItemID), UpperCase(Achatadas[I].Chave)) > 0) or
             (Pos(UpperCase(FiltroItemID), UpperCase(Achatadas[I].SellerSku)) > 0));
        if Passa then
        begin
          FTikTokItems[Total] := Achatadas[I];
          Inc(Total);
        end;
      end;
      SetLength(FTikTokItems, Total);
    end;
    Log(Format('%d oferta(s) apos aplicar filtro de nome/SKU.', [Length(FTikTokItems)]));
    PreencherGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmOfertasMarketplace.PreencherGridTikTokShop;
var
  Qry: TFDQuery;
  I: Integer;
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
begin
  Grid.RowCount := Length(FTikTokItems) + 1;
  if Grid.RowCount < 2 then
    Grid.RowCount := 2;
  for I := 1 to Grid.RowCount - 1 do
  begin
    Grid.Cells[COL_ITEMID, I] := '';
    Grid.Cells[COL_DESCRICAO, I] := '';
    Grid.Cells[COL_SKU, I] := '';
    Grid.Cells[COL_STATUS, I] := '';
    Grid.Cells[COL_PRECO, I] := '';
    Grid.Cells[COL_ESTOQUE, I] := '';
    Grid.Cells[COL_ESTOQUE_INFINITO, I] := '';
    Grid.Cells[COL_VINCULO_FISICO, I] := '';
    Grid.Cells[COL_VINCULO_VIRTUAL, I] := '';
    Grid.Cells[COL_ULTIMA_ALTERACAO, I] := '';
  end;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    for I := Low(FTikTokItems) to High(FTikTokItems) do
    begin
      CodExistente := BuscarCodigoExistente(Qry, FTikTokItems[I].Chave,
        CodProdutoVinculado, EstoqueInfinito);
      Grid.Cells[COL_ITEMID, I + 1] := FTikTokItems[I].Chave;
      Grid.Cells[COL_DESCRICAO, I + 1] := FTikTokItems[I].Titulo;
      // Mostra o SKU do vendedor quando existir; sem ele, repete a chave -
      // a coluna nunca fica vazia, que confunde na hora de conferir.
      Grid.Cells[COL_SKU, I + 1] := IfThen(FTikTokItems[I].SellerSku <> '',
        FTikTokItems[I].SellerSku, FTikTokItems[I].Chave);
      Grid.Cells[COL_STATUS, I + 1] := FTikTokItems[I].Status;
      Grid.Cells[COL_PRECO, I + 1] := FormatFloat('0.00', FTikTokItems[I].Preco);
      Grid.Cells[COL_ESTOQUE, I + 1] := IntToStr(FTikTokItems[I].Estoque);
      Grid.Cells[COL_ESTOQUE_INFINITO, I + 1] := IfThen(EstoqueInfinito, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_FISICO, I + 1] := IfThen(CodProdutoVinculado <> 0, 'Sim', 'Não');
      Grid.Cells[COL_VINCULO_VIRTUAL, I + 1] := IfThen(CodExistente <> 0, 'Sim', 'Não');
      Grid.Cells[COL_ULTIMA_ALTERACAO, I + 1] := FormatarDataAnuncio(FTikTokItems[I].UpdateTime);
    end;
  finally
    Qry.Free;
  end;
end;

procedure TFrmOfertasMarketplace.GravarProdutoTikTokShop(AQuery: TFDQuery;
  const AItem: TOfertaTikTok);
var
  CodExistente, CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
  NovoCodigo: Integer;
  SqlUpdate: string;
begin
  // {IMPORTANTE} a chave e' "product_id|sku_id" - a MESMA usada no F2 de
  // estoque (EnviarEstoqueTikTokShop) e no lookup da baixa de pedido. Gravar
  // so' o product_id aqui quebraria os dois, porque estoque e item de pedido
  // no TikTok sao por SKU.
  CodExistente := BuscarCodigoExistente(AQuery, AItem.Chave,
    CodProdutoVinculado, EstoqueInfinito);
  if CodExistente = 0 then
  begin
    NovoCodigo := ProximoCodigoProdutoMarketplace(AQuery);
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO PRODUTOS_MARKETPLACE ' +
      '(CODPRODUTOS_MARKETPLACE, CODPRODUTO, CODMARKETPLACE, ' +
      'CODPRODUTONOMARKETPLACE, DISPONIBILIZARMARKETPLACE, ' +
      'ATUALIZARMARKETPLACE, EXCLUIDO, ATUALIZAR_ESTOQUE_MARKETPLACE, ' +
      'DESCRICAO, ESTOQUE, PRECO, ' +
      'DATAULTIMAALTERACAO, ULTIMA_ALT_MARKETPLACE, LOJA) ' +
      'VALUES (:CODPRODUTOS_MARKETPLACE, NULL, :CODMARKETPLACE, ' +
      ':CODPRODUTONOMARKETPLACE, ''N'', ''N'', ''N'', ''S'', :DESCRICAO, ' +
      ':ESTOQUE, :PRECO, :DATAULTIMAALTERACAO, :ULTIMA_ALT_MARKETPLACE, :LOJA)';
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := NovoCodigo;
    AQuery.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
    AQuery.ParamByName('CODPRODUTONOMARKETPLACE').AsString := AItem.Chave;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.Titulo;
    AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Estoque;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Preco;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    AQuery.ParamByName('LOJA').AsInteger := FLoja;
    DefinirUltimaAltMarketplace(AQuery, AItem.UpdateTime);
    AQuery.ExecSQL;
    Log('  Novo: ' + AItem.Titulo + ' (' + AItem.Chave + ')');
  end
  else
  begin
    SqlUpdate :=
      'UPDATE PRODUTOS_MARKETPLACE SET DESCRICAO = :DESCRICAO, ' +
      'PRECO = :PRECO, DATAULTIMAALTERACAO = :DATAULTIMAALTERACAO, ' +
      'ATUALIZAR_ESTOQUE_MARKETPLACE = ''S''';
    if not EstoqueInfinito then
      SqlUpdate := SqlUpdate + ', ESTOQUE = :ESTOQUE';
    // Data de edicao do anuncio vinda da API. Se o marketplace nao mandou
    // (0), nao mexe no que ja estava gravado.
    if AItem.UpdateTime > 0 then
      SqlUpdate := SqlUpdate + ', ULTIMA_ALT_MARKETPLACE = :ULTIMA_ALT_MARKETPLACE';
    SqlUpdate := SqlUpdate + ' WHERE CODPRODUTOS_MARKETPLACE = :CODPRODUTOS_MARKETPLACE';
    AQuery.Close;
    AQuery.SQL.Text := SqlUpdate;
    AQuery.ParamByName('DESCRICAO').AsString := AItem.Titulo;
    AQuery.ParamByName('PRECO').AsFloat := AItem.Preco;
    AQuery.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    if not EstoqueInfinito then
      AQuery.ParamByName('ESTOQUE').AsInteger := AItem.Estoque;
    if AItem.UpdateTime > 0 then
      DefinirUltimaAltMarketplace(AQuery, AItem.UpdateTime);
    AQuery.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := CodExistente;
    AQuery.ExecSQL;
    if EstoqueInfinito then
      Log('  Atualizado (estoque ignorado - ESTOQUE_INFINITO): ' + AItem.Titulo);
  end;
end;

procedure TFrmOfertasMarketplace.GravarTodos;
var
  Qry: TFDQuery;
  I, iNovos, iAtualizados: Integer;
  CodProdutoVinculado: Integer;
  EstoqueInfinito: Boolean;
begin
  if (TMarketplaces(FCodMarketplace) = TMarketplaces.Shopee) and (Length(FItems) = 0) then
  begin
    ShowMessage('Nenhum produto carregado. Clique em uma loja conectada e reabra esta tela.');
    Exit;
  end;
  if (TMarketplaces(FCodMarketplace) = TMarketplaces.Amazon) and (Length(FAmazonItems) = 0) then
  begin
    ShowMessage('Nenhum produto carregado. Clique em uma loja conectada e reabra esta tela.');
    Exit;
  end;
  if (TMarketplaces(FCodMarketplace) = TMarketplaces.Magalu) and (Length(FMagaluItems) = 0) then
  begin
    ShowMessage('Nenhum produto carregado. Clique em uma loja conectada e reabra esta tela.');
    Exit;
  end;
  if (TMarketplaces(FCodMarketplace) = TMarketplaces.MercadoLivre) and (Length(FMercadoLivreItems) = 0) then
  begin
    ShowMessage('Nenhum produto carregado. Clique em uma loja conectada e reabra esta tela.');
    Exit;
  end;
  if (TMarketplaces(FCodMarketplace) = TMarketplaces.TikTokShop) and (Length(FTikTokItems) = 0) then
  begin
    ShowMessage('Nenhum produto carregado. Clique em uma loja conectada e reabra esta tela.');
    Exit;
  end;
  iNovos := 0;
  iAtualizados := 0;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    case TMarketplaces(FCodMarketplace) of
      TMarketplaces.Shopee:
        for I := Low(FItems) to High(FItems) do
        begin
          if BuscarCodigoExistente(Qry, IntToStr(FItems[I].ItemID), CodProdutoVinculado,
               EstoqueInfinito) <> 0 then
            Inc(iAtualizados)
          else
            Inc(iNovos);
          GravarProduto(Qry, FItems[I]);
        end;
      TMarketplaces.Amazon:
        for I := Low(FAmazonItems) to High(FAmazonItems) do
        begin
          if BuscarCodigoExistente(Qry, FAmazonItems[I].SKU, CodProdutoVinculado,
               EstoqueInfinito) <> 0 then
            Inc(iAtualizados)
          else
            Inc(iNovos);
          GravarProdutoAmazon(Qry, FAmazonItems[I]);
        end;
      TMarketplaces.Magalu:
        for I := Low(FMagaluItems) to High(FMagaluItems) do
        begin
          if BuscarCodigoExistente(Qry, FMagaluItems[I].Sku, CodProdutoVinculado,
               EstoqueInfinito) <> 0 then
            Inc(iAtualizados)
          else
            Inc(iNovos);
          GravarProdutoMagalu(Qry, FMagaluItems[I]);
        end;
      TMarketplaces.MercadoLivre:
        for I := Low(FMercadoLivreItems) to High(FMercadoLivreItems) do
        begin
          if BuscarCodigoExistente(Qry, FMercadoLivreItems[I].ItemId, CodProdutoVinculado,
               EstoqueInfinito) <> 0 then
            Inc(iAtualizados)
          else
            Inc(iNovos);
          GravarProdutoMercadoLivre(Qry, FMercadoLivreItems[I]);
        end;
      TMarketplaces.TikTokShop:
        for I := Low(FTikTokItems) to High(FTikTokItems) do
        begin
          if BuscarCodigoExistente(Qry, FTikTokItems[I].Chave, CodProdutoVinculado,
               EstoqueInfinito) <> 0 then
            Inc(iAtualizados)
          else
            Inc(iNovos);
          GravarProdutoTikTokShop(Qry, FTikTokItems[I]);
        end;
    end;
  finally
    Qry.Free;
  end;
  Log(Format('Concluido: %d novo(s), %d ja existente(s) (dados atualizados).',
    [iNovos, iAtualizados]));
  PreencherGrid; // atualiza a coluna "Vinculo" (nenhum vinculo muda aqui, mas
                  // deixa a grid coerente caso algo tenha sido inserido agora)
end;
procedure TFrmOfertasMarketplace.GravarSelecionado;
var
  Qry: TFDQuery;
  ItemIDSelecionado: string;
  I, Idx: Integer;
begin
  if (Grid.Row < 1) or (Grid.Row >= Grid.RowCount) or
     (Trim(Grid.Cells[COL_ITEMID, Grid.Row]) = '') then
  begin
    ShowMessage('Selecione um produto na lista primeiro.');
    Exit;
  end;
  ItemIDSelecionado := Grid.Cells[COL_ITEMID, Grid.Row];
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    case TMarketplaces(FCodMarketplace) of
      TMarketplaces.Shopee:
        begin
          Idx := -1;
          for I := Low(FItems) to High(FItems) do
            if IntToStr(FItems[I].ItemID) = ItemIDSelecionado then
            begin
              Idx := I;
              Break;
            end;
          if Idx = -1 then
          begin
            ShowMessage('Nao foi possivel localizar os dados desse produto - atualize a lista e tente novamente.');
            Exit;
          end;
          GravarProduto(Qry, FItems[Idx]);
        end;
      TMarketplaces.Amazon:
        begin
          Idx := -1;
          for I := Low(FAmazonItems) to High(FAmazonItems) do
            if FAmazonItems[I].SKU = ItemIDSelecionado then
            begin
              Idx := I;
              Break;
            end;
          if Idx = -1 then
          begin
            ShowMessage('Nao foi possivel localizar os dados desse produto - atualize a lista e tente novamente.');
            Exit;
          end;
          GravarProdutoAmazon(Qry, FAmazonItems[Idx]);
        end;
      TMarketplaces.Magalu:
        begin
          Idx := -1;
          for I := Low(FMagaluItems) to High(FMagaluItems) do
            if FMagaluItems[I].Sku = ItemIDSelecionado then
            begin
              Idx := I;
              Break;
            end;
          if Idx = -1 then
          begin
            ShowMessage('Nao foi possivel localizar os dados desse produto - atualize a lista e tente novamente.');
            Exit;
          end;
          GravarProdutoMagalu(Qry, FMagaluItems[Idx]);
        end;
      TMarketplaces.MercadoLivre:
        begin
          Idx := -1;
          for I := Low(FMercadoLivreItems) to High(FMercadoLivreItems) do
            if FMercadoLivreItems[I].ItemId = ItemIDSelecionado then
            begin
              Idx := I;
              Break;
            end;
          if Idx = -1 then
          begin
            ShowMessage('Nao foi possivel localizar os dados desse produto - atualize a lista e tente novamente.');
            Exit;
          end;
          GravarProdutoMercadoLivre(Qry, FMercadoLivreItems[Idx]);
        end;
      TMarketplaces.TikTokShop:
        begin
          Idx := -1;
          for I := Low(FTikTokItems) to High(FTikTokItems) do
            if FTikTokItems[I].Chave = ItemIDSelecionado then
            begin
              Idx := I;
              Break;
            end;
          if Idx = -1 then
          begin
            ShowMessage('Nao foi possivel localizar os dados desse produto - atualize a lista e tente novamente.');
            Exit;
          end;
          GravarProdutoTikTokShop(Qry, FTikTokItems[Idx]);
        end;
    end;
  finally
    Qry.Free;
  end;
  Log('Produto ' + ItemIDSelecionado + ' gravado com sucesso.');
  PreencherGrid;
end;
procedure TFrmOfertasMarketplace.CmdAtualizarTodosClick(Sender: TObject);
begin
  Screen.Cursor := crHourGlass;
  try
    GravarTodos;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmOfertasMarketplace.CmdAtualizarSelecionadoClick(Sender: TObject);
begin
  Screen.Cursor := crHourGlass;
  try
    GravarSelecionado;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmOfertasMarketplace.CmdVincularProdutoClick(Sender: TObject);
var
  ItemIDSelecionado: string;
  CodProdutoEscolhido: Integer;
  CodProdutosMarketplace, CodProdutoVinculadoAtual: Integer;
  EstoqueInfinito: Boolean;
  Qry: TFDQuery;
begin
  if (Grid.Row < 1) or (Grid.Row >= Grid.RowCount) or
     (Trim(Grid.Cells[COL_ITEMID, Grid.Row]) = '') then
  begin
    ShowMessage('Selecione um produto na lista primeiro.');
    Exit;
  end;
  ItemIDSelecionado := Grid.Cells[COL_ITEMID, Grid.Row];
  // A tela de selecao devolve so' o codigo escolhido (0 = cancelou) - quem
  // grava a ligacao na tabela e' aqui, nao a tela de selecao.
  CodProdutoEscolhido := TFrmVincularProduto.SelecionarProduto(FLoja);
  if CodProdutoEscolhido = 0 then
    Exit;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    CodProdutosMarketplace := BuscarCodigoExistente(Qry, ItemIDSelecionado,
      CodProdutoVinculadoAtual, EstoqueInfinito);
    if CodProdutosMarketplace = 0 then
    begin
      ShowMessage('Esse produto ainda nao foi gravado em PRODUTOS_MARKETPLACE. ' +
        'Clique em "Atualizar Todos" ou "Atualizar Selecionado" primeiro.');
      Exit;
    end;
    Qry.Close;
    Qry.SQL.Text :=
      'UPDATE PRODUTOS_MARKETPLACE SET CODPRODUTO = :CODPRODUTO ' +
      'WHERE CODPRODUTOS_MARKETPLACE = :COD';
    Qry.ParamByName('CODPRODUTO').AsInteger := CodProdutoEscolhido;
    Qry.ParamByName('COD').AsInteger := CodProdutosMarketplace;
    Qry.ExecSQL;
    Log('Produto ' + ItemIDSelecionado + ' vinculado ao produto fisico ' +
      IntToStr(CodProdutoEscolhido) + '.');
    // Sincroniza o estoque fisico ja na hora do vinculo, sem esperar o
    // usuario clicar em "Atualizar" de novo pra esse produto especifico.
    if not EstoqueInfinito then
    begin
      Qry.Close;
      Qry.SQL.Text := 'SELECT ESTOQUE FROM PRODUTOS_MARKETPLACE ' +
        'WHERE CODPRODUTOS_MARKETPLACE = :COD';
      Qry.ParamByName('COD').AsInteger := CodProdutosMarketplace;
      Qry.Open;
      if not Qry.IsEmpty then
        AtualizarEstoqueFisico(Qry, CodProdutoEscolhido, Qry.FieldByName('ESTOQUE').AsInteger);
      Qry.Close;
    end;
  finally
    Qry.Free;
  end;
  PreencherGrid;
end;
procedure TFrmOfertasMarketplace.CmdIncluirProdutoClick(Sender: TObject);
begin
  // O roteador decide sozinho qual tela abrir - direto se o marketplace so
  // tem um jeito de cadastrar (Shopee), ou perguntando ao usuario se tiver
  // mais de um (Amazon: oferta em ASIN existente x produto novo do zero).
  // Ver uModosCadastroProduto pra declarar os modos de cada marketplace.
  if uRoteadorIncluirProduto.AbrirTelaIncluirProduto(FLoja, FCodMarketplace, FAccountID,
       FToken, FDevClientId, FDevClientSecret, FSandbox) then
    // Busca de novo no marketplace (nao so' PreencherGrid) - o produto
    // recem cadastrado nao esta na lista FItems/FAmazonItems em memoria
    // ainda, precisa rebuscar pra ele aparecer na grid.
    BuscarOfertas;
end;
end.
