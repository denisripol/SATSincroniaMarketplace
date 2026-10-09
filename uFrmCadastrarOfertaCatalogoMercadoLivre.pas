// ============================================================================
// UNIT: uFrmCadastrarOfertaCatalogoMercadoLivre
// OBJETIVO: Tela do modo "oferta simples" (mcpOfertaSimples) do Mercado
// Livre - publicar uma oferta EM CIMA de um produto que JA existe no
// catalogo do ML, em vez de cadastrar um produto novo do zero.
//
// E' o equivalente ao "oferta sobre ASIN existente" da Amazon, mas com API
// propria - por isso tela dedicada, e nao a uFrmCadastrarProdutoMarketplace
// generica (que so' sabe fazer o fluxo da Amazon).
//
// FLUXO EM 2 PASSOS:
//   Passo 1: usuario digita o nome/modelo do produto e a tela busca no
//   catalogo (SearchCatalogProducts -> GET /products/search). A lista mostra
//   nome + os primeiros atributos, que e' o que diferencia dois produtos
//   parecidos (ex: mesma capa de celular em cores/modelos diferentes).
//
//   Passo 2: escolhido o produto, so' sobram os dados COMERCIAIS - preco,
//   estoque, condicao, tipo de anuncio, garantia e SKU. Titulo, categoria,
//   atributos, ficha tecnica e imagens saem do proprio produto de catalogo,
//   entao NAO existem nesta tela (essa e' justamente a vantagem do modo).
//
// DIFERENCAS EM RELACAO A uFrmCadastrarProdutoMercadoLivreNovo:
//   1. O corpo do POST /items leva "catalog_product_id" + "catalog_listing":
//      true, e NAO leva title/category_id/attributes/pictures - mandar esses
//      campos junto e' o erro mais comum aqui, porque o ML recusa ou ignora.
//   2. Nao existe chamada de descricao (SetItemDescription): a descricao da
//      oferta de catalogo e' a do proprio produto do catalogo.
//   3. A checagem de listing_type_id so' roda quando o produto de catalogo
//      devolve category_id - nem todo dominio devolve, e nesse caso a tela
//      segue e deixa o proprio POST recusar (com mensagem mais especifica).
//
// {ATENCAO} O Mercado Livre nao deixa o MESMO vendedor ter duas ofertas no
// mesmo produto de catalogo - a segunda tentativa volta com erro da propria
// API, que a tela mostra cru no log e na mensagem.
//
// Ao ter sucesso, grava em PRODUTOS_MARKETPLACE - SEM vinculo com produto
// fisico ainda, mesmo padrao do resto do projeto.
// ============================================================================
unit uFrmCadastrarOfertaCatalogoMercadoLivre;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.Variants, System.Classes, System.StrUtils, System.IOUtils,
  System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Data.DB, FireDAC.Comp.Client,
  DMZ, uMarketplace, MercadoLivre.OpenAPI.Client;

type
  TFrmCadastrarOfertaCatalogoMercadoLivre = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    // --- Passo 1: busca no catalogo ---
    lblBuscaCatalogo: TLabel;
    edtBuscaCatalogo: TEdit;
    CmdBuscarCatalogo: TBitBtn;
    lstProdutos: TListBox;
    CmdProximoPasso1: TBitBtn;
    // --- Passo 2: dados comerciais da oferta ---
    lblProdutoSelecionado: TLabel;
    lblSku: TLabel;
    edtSku: TEdit;
    lblCondicao: TLabel;
    cbCondicao: TComboBox;
    lblTipoAnuncio: TLabel;
    cbTipoAnuncio: TComboBox;
    lblGarantia: TLabel;
    edtGarantia: TEdit;
    lblPreco: TLabel;
    edtPreco: TEdit;
    lblEstoque: TLabel;
    edtEstoque: TEdit;
    CmdVerFichaProduto: TBitBtn;
    CmdVoltar: TBitBtn;
    CmdPublicar: TBitBtn;
    // --- Compartilhado ---
    CmdFechar: TBitBtn;
    MemoLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure CmdBuscarCatalogoClick(Sender: TObject);
    procedure CmdProximoPasso1Click(Sender: TObject);
    procedure CmdVerFichaProdutoClick(Sender: TObject);
    procedure CmdVoltarClick(Sender: TObject);
    procedure CmdPublicarClick(Sender: TObject);
    procedure CmdFecharClick(Sender: TObject);
  private
    FLoja: Integer;
    FCodMarketplace: Integer;
    FAccountID: string;   // seller/user id no Mercado Livre
    FToken: string;
    FDevClientId: string;
    FDevClientSecret: string;
    FSandbox: Boolean;
    FCadastrouAlgo: Boolean;
    // Resultado da ultima busca no catalogo (passo 1) - o indice selecionado
    // em lstProdutos indexa este array.
    FProdutos: TMercadoLivreProdutoCatalogoArray;
    // Produto escolhido no passo 1 + a ficha crua dele (pro "Ver Ficha").
    FProdutoEscolhido: TMercadoLivreProdutoCatalogo;
    FFichaRawJSON: string;
    procedure Log(const AMsg: string);
    function ParseValorDecimal(const ATexto: string; out AValor: Double): Boolean;
    // So chamado explicitamente pelo AbrirParaLoja, DEPOIS que os campos ja
    // foram atribuidos - o FormCreate roda dentro do TForm.Create, antes
    // disso (mesmo cuidado das outras telas de cadastro do projeto).
    procedure Inicializar;
    procedure MostrarPasso(const APasso: Integer);
    function MontarBodyOferta(out ABodyJSON, AErro: string): Boolean;
    procedure GravarProdutoMarketplace(const ACodProdutoNoMarketplace, ANome: string;
      const AEstoque: Integer; const APreco: Double);
  public
    class function AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
      const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
      const ASandbox: Boolean): Boolean;
  end;

implementation

{$R *.dfm}

class function TFrmCadastrarOfertaCatalogoMercadoLivre.AbrirParaLoja(
  const ALoja, ACodMarketplace: Integer; const AAccountID, AToken: string;
  const ADevClientId, ADevClientSecret: string; const ASandbox: Boolean): Boolean;
var
  Frm: TFrmCadastrarOfertaCatalogoMercadoLivre;
begin
  Frm := TFrmCadastrarOfertaCatalogoMercadoLivre.Create(Application);
  try
    Frm.FLoja := ALoja;
    Frm.FCodMarketplace := ACodMarketplace;
    Frm.FAccountID := AAccountID;
    Frm.FToken := AToken;
    Frm.FDevClientId := ADevClientId;
    Frm.FDevClientSecret := ADevClientSecret;
    Frm.FSandbox := ASandbox;
    Frm.FCadastrouAlgo := False;
    // So agora, com todos os campos ja atribuidos, e' seguro montar a tela.
    Frm.Inicializar;
    Frm.ShowModal;
    Result := Frm.FCadastrouAlgo;
  finally
    Frm.Free;
  end;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.FormCreate(Sender: TObject);
begin
  MemoLog.Clear;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;

function TFrmCadastrarOfertaCatalogoMercadoLivre.ParseValorDecimal(
  const ATexto: string; out AValor: Double): Boolean;
var
  FS: TFormatSettings;
  TextoNormalizado: string;
begin
  // Mesma logica ja validada nas outras telas de cadastro - aceita virgula
  // ou ponto, com TFormatSettings proprio pra nao depender da config
  // regional da maquina.
  FS := TFormatSettings.Invariant;
  TextoNormalizado := StringReplace(Trim(ATexto), ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(TextoNormalizado, AValor, FS);
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.Inicializar;
begin
  lblTitulo.Caption := 'Incluir Oferta em Produto do Catalogo - Mercado Livre';
  edtBuscaCatalogo.Clear;
  lstProdutos.Clear;
  SetLength(FProdutos, 0);
  FProdutoEscolhido := Default(TMercadoLivreProdutoCatalogo);
  FFichaRawJSON := '';

  // Mesma lista da tela de produto novo. A condicao aceita por categoria
  // pode variar, mas em oferta de catalogo o normal e' "new".
  cbCondicao.Items.Clear;
  cbCondicao.Items.Add('new');
  cbCondicao.Items.Add('used');
  cbCondicao.ItemIndex := 0;

  // {ATENCAO} disponibilidade depende da CONTA e da CATEGORIA - antes de
  // publicar, a tela consulta CheckListingTypeAvailable quando o produto de
  // catalogo trouxe category_id.
  cbTipoAnuncio.Items.Clear;
  cbTipoAnuncio.Items.Add('gold_special');
  cbTipoAnuncio.Items.Add('gold_pro');
  cbTipoAnuncio.Items.Add('free');
  cbTipoAnuncio.ItemIndex := 0;

  edtSku.Text := '';
  edtGarantia.Text := '';
  edtPreco.Text := '';
  edtEstoque.Text := '';

  MostrarPasso(1);
  Log('Pronto. Digite o nome/modelo do produto pra buscar no catalogo do Mercado Livre.');
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.MostrarPasso(const APasso: Integer);
begin
  // Passo 1 - busca no catalogo.
  lblBuscaCatalogo.Visible := APasso = 1;
  edtBuscaCatalogo.Visible := APasso = 1;
  CmdBuscarCatalogo.Visible := APasso = 1;
  lstProdutos.Visible := APasso = 1;
  CmdProximoPasso1.Visible := APasso = 1;
  // Passo 2 - dados comerciais da oferta.
  lblProdutoSelecionado.Visible := APasso = 2;
  lblSku.Visible := APasso = 2;
  edtSku.Visible := APasso = 2;
  lblCondicao.Visible := APasso = 2;
  cbCondicao.Visible := APasso = 2;
  lblTipoAnuncio.Visible := APasso = 2;
  cbTipoAnuncio.Visible := APasso = 2;
  lblGarantia.Visible := APasso = 2;
  edtGarantia.Visible := APasso = 2;
  lblPreco.Visible := APasso = 2;
  edtPreco.Visible := APasso = 2;
  lblEstoque.Visible := APasso = 2;
  edtEstoque.Visible := APasso = 2;
  CmdVerFichaProduto.Visible := APasso = 2;
  CmdVoltar.Visible := APasso = 2;
  CmdPublicar.Visible := APasso = 2;
  // CmdFechar e MemoLog ficam sempre visiveis (declarados assim no dfm).
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.CmdBuscarCatalogoClick(
  Sender: TObject);
var
  Cliente: TMercadoLivreOpenAPIClient;
  ErroMsg, Linha: string;
  I: Integer;
begin
  if Trim(edtBuscaCatalogo.Text) = '' then
  begin
    ShowMessage('Digite o nome/modelo do produto pra buscar no catalogo.');
    Exit;
  end;

  lstProdutos.Clear;
  SetLength(FProdutos, 0);

  Screen.Cursor := crHourGlass;
  try
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      '', FSandbox);
    Cliente.OnLog := Log;
    try
      // Limite 20: o suficiente pra achar o produto certo sem virar uma
      // lista impossivel de ler (o /products/search ordena por relevancia).
      if not Cliente.SearchCatalogProducts(FToken, 'MLB',
           Trim(edtBuscaCatalogo.Text), 20, FProdutos, ErroMsg) then
      begin
        Log('Falha ao buscar no catalogo: ' + ErroMsg);
        ShowMessage('Falha ao buscar no catalogo: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;

    if Length(FProdutos) = 0 then
    begin
      Log('Nenhum produto de catalogo encontrado pra esse texto.');
      ShowMessage('Nenhum produto encontrado no catalogo do Mercado Livre.' +
        sLineBreak + sLineBreak + 'Tente com marca + modelo (ex: "Samsung Galaxy A15 ' +
        '128GB"). Se o produto realmente nao existir no catalogo, use "Produto novo" ' +
        'em vez desta opcao.');
      Exit;
    end;

    for I := Low(FProdutos) to High(FProdutos) do
    begin
      Linha := FProdutos[I].Nome;
      if FProdutos[I].Resumo <> '' then
        Linha := Linha + '  [' + FProdutos[I].Resumo + ']';
      Linha := Linha + '  (' + FProdutos[I].ProductId + ')';
      lstProdutos.Items.Add(Linha);
    end;
    Log(Format('%d produto(s) de catalogo listado(s).', [Length(FProdutos)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.CmdProximoPasso1Click(
  Sender: TObject);
var
  Cliente: TMercadoLivreOpenAPIClient;
  ErroMsg: string;
  Detalhe: TMercadoLivreProdutoCatalogo;
begin
  if (lstProdutos.ItemIndex < 0) or (lstProdutos.ItemIndex > High(FProdutos)) then
  begin
    ShowMessage('Escolha um produto na lista primeiro.');
    Exit;
  end;

  FProdutoEscolhido := FProdutos[lstProdutos.ItemIndex];
  FFichaRawJSON := '';

  // Busca a ficha completa: o /products/search devolve uma versao resumida,
  // e e' no detalhe que costuma vir o category_id usado na checagem do tipo
  // de anuncio. Falhar aqui NAO trava o fluxo - so' perde a checagem.
  Screen.Cursor := crHourGlass;
  try
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      '', FSandbox);
    Cliente.OnLog := Log;
    try
      if Cliente.GetCatalogProduct(FToken, FProdutoEscolhido.ProductId, Detalhe,
           FFichaRawJSON, ErroMsg) then
        FProdutoEscolhido := Detalhe
      else
        Log('Aviso: nao foi possivel carregar a ficha completa do produto (' +
          ErroMsg + ') - seguindo com os dados da busca.');
    finally
      Cliente.Free;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  if not SameText(FProdutoEscolhido.Status, 'active') and
     (FProdutoEscolhido.Status <> '') then
    if MessageDlg('Este produto de catalogo esta com status "' +
         FProdutoEscolhido.Status + '" (o normal pra publicar e "active"). ' +
         'O Mercado Livre provavelmente vai recusar a oferta. Continuar mesmo assim?',
         mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;

  lblProdutoSelecionado.Caption := 'Produto: ' + FProdutoEscolhido.Nome +
    '  (' + FProdutoEscolhido.ProductId + ')';
  Log('Produto de catalogo escolhido: ' + FProdutoEscolhido.ProductId +
    ' - ' + FProdutoEscolhido.Nome);
  if FProdutoEscolhido.CategoryId = '' then
    Log('Aviso: este produto nao devolveu category_id - a checagem do tipo de ' +
      'anuncio sera pulada e quem valida sera o proprio POST de publicacao.');

  MostrarPasso(2);
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.CmdVerFichaProdutoClick(
  Sender: TObject);
var
  Caminho: string;
begin
  if Trim(FFichaRawJSON) = '' then
  begin
    ShowMessage('A ficha completa deste produto nao foi carregada - escolha o ' +
      'produto de novo no passo anterior.');
    Exit;
  end;
  // Mesmo padrao do "Ver Atributos da Categoria" das outras telas: grava num
  // .json temporario e abre no editor padrao do Windows.
  Caminho := TPath.Combine(TPath.GetTempPath,
    'mercadolivre_catalogo_' + FProdutoEscolhido.ProductId + '.json');
  try
    TFile.WriteAllText(Caminho, FFichaRawJSON, TEncoding.UTF8);
    ShellExecute(0, 'open', PChar(Caminho), nil, nil, SW_SHOWNORMAL);
    Log('Ficha do produto salva em: ' + Caminho);
  except
    on E: Exception do
      Log('Nao foi possivel abrir o arquivo da ficha: ' + E.Message);
  end;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.CmdVoltarClick(Sender: TObject);
begin
  MostrarPasso(1);
end;

function TFrmCadastrarOfertaCatalogoMercadoLivre.MontarBodyOferta(
  out ABodyJSON, AErro: string): Boolean;
var
  Body: TJSONObject;
  Preco: Double;
  Estoque: Integer;
begin
  Result := False;
  ABodyJSON := '';
  AErro := '';

  if FProdutoEscolhido.ProductId = '' then
  begin
    AErro := 'Nenhum produto de catalogo escolhido.';
    Exit;
  end;
  if not ParseValorDecimal(edtPreco.Text, Preco) or (Preco <= 0) then
  begin
    AErro := 'Preco invalido.';
    Exit;
  end;
  if not TryStrToInt(Trim(edtEstoque.Text), Estoque) or (Estoque < 0) then
  begin
    AErro := 'Estoque invalido.';
    Exit;
  end;
  if cbTipoAnuncio.ItemIndex < 0 then
  begin
    AErro := 'Escolha o tipo de anuncio.';
    Exit;
  end;
  if cbCondicao.ItemIndex < 0 then
  begin
    AErro := 'Escolha a condicao do produto.';
    Exit;
  end;

  Body := TJSONObject.Create;
  try
    // {IMPORTANTE} o par catalog_product_id + catalog_listing=true e' o que
    // transforma isso numa oferta de catalogo. NAO mandar title,
    // category_id, attributes nem pictures junto - tudo isso vem do proprio
    // produto de catalogo, e mandar duplicado e' motivo de recusa.
    Body.AddPair('catalog_product_id', FProdutoEscolhido.ProductId);
    Body.AddPair('catalog_listing', TJSONBool.Create(True));
    Body.AddPair('price', TJSONNumber.Create(Preco));
    Body.AddPair('currency_id', 'BRL');
    Body.AddPair('available_quantity', TJSONNumber.Create(Estoque));
    Body.AddPair('buying_mode', 'buy_it_now');
    Body.AddPair('listing_type_id', cbTipoAnuncio.Text);
    Body.AddPair('condition', cbCondicao.Text);
    // seller_custom_field e' onde o Mercado Livre guarda o SKU do vendedor.
    if Trim(edtSku.Text) <> '' then
      Body.AddPair('seller_custom_field', Trim(edtSku.Text));
    // {NOTA} "warranty" e' o campo simples, mesmo usado na tela de produto
    // novo. O ML tambem aceita garantia estruturada em sale_terms
    // (WARRANTY_TYPE + WARRANTY_TIME) - se um dia a conta exigir esse
    // formato, e' aqui que muda.
    if Trim(edtGarantia.Text) <> '' then
      Body.AddPair('warranty', Trim(edtGarantia.Text));

    ABodyJSON := Body.ToJSON;
    Result := True;
  finally
    Body.Free;
  end;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.CmdPublicarClick(Sender: TObject);
var
  Cliente: TMercadoLivreOpenAPIClient;
  BodyJSON, ErroMsg, ItemId, RespostaJSON, Causa: string;
  Disponivel: Boolean;
  Preco: Double;
  Estoque: Integer;
begin
  if not MontarBodyOferta(BodyJSON, ErroMsg) then
  begin
    Log('Nao foi possivel montar a oferta: ' + ErroMsg);
    ShowMessage(ErroMsg);
    Exit;
  end;

  ParseValorDecimal(edtPreco.Text, Preco);
  Estoque := StrToIntDef(Trim(edtEstoque.Text), 0);

  Screen.Cursor := crHourGlass;
  try
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      '', FSandbox);
    Cliente.OnLog := Log;
    try
      // So' da' pra conferir o tipo de anuncio quando sabemos a categoria -
      // nem todo produto de catalogo devolve category_id (ver LerProdutoCatalogo).
      if FProdutoEscolhido.CategoryId <> '' then
      begin
        if Cliente.CheckListingTypeAvailable(FToken, FAccountID, cbTipoAnuncio.Text,
             FProdutoEscolhido.CategoryId, Disponivel, Causa, ErroMsg) then
        begin
          if not Disponivel then
          begin
            Log('Tipo de anuncio "' + cbTipoAnuncio.Text + '" nao disponivel: ' + Causa);
            ShowMessage('O tipo de anuncio "' + cbTipoAnuncio.Text +
              '" nao esta disponivel para esta conta/categoria.' + sLineBreak +
              sLineBreak + 'Motivo informado pelo Mercado Livre: ' + Causa +
              sLineBreak + sLineBreak + 'Escolha outro tipo e tente de novo.');
            Exit;
          end;
        end
        else
          // Nao trava o fluxo: se a consulta falhar, segue e deixa o proprio
          // POST /items recusar (com mensagem mais especifica).
          Log('Aviso: nao foi possivel conferir o tipo de anuncio antes de ' +
            'publicar (' + ErroMsg + ') - seguindo mesmo assim.');
      end;

      if not Cliente.CreateItem(FToken, BodyJSON, ItemId, RespostaJSON, ErroMsg) then
      begin
        Log('Falha ao publicar a oferta: ' + ErroMsg);
        ShowMessage('Falha ao publicar a oferta:' + sLineBreak + ErroMsg +
          sLineBreak + sLineBreak + 'Causas comuns aqui: voce ja tem uma oferta ' +
          'nesse mesmo produto de catalogo, o produto nao aceita oferta nova, ou ' +
          'o tipo de anuncio nao esta liberado. O Mercado Livre costuma apontar o ' +
          'motivo exato no corpo do erro - confira o log.');
        Exit;
      end;

      Log('Oferta publicada com sucesso: ' + ItemId);
    finally
      Cliente.Free;
    end;

    // Grava com o NOME DO CATALOGO: numa oferta de catalogo o titulo do
    // anuncio e' o do proprio produto, entao e' esse o texto que o usuario
    // vai reconhecer depois na tela de Ofertas e no vinculo com o fisico.
    GravarProdutoMarketplace(ItemId, FProdutoEscolhido.Nome, Estoque, Preco);
    FCadastrouAlgo := True;
    ShowMessage('Oferta publicada no Mercado Livre!' + sLineBreak +
      'ID do anuncio: ' + ItemId);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.GravarProdutoMarketplace(
  const ACodProdutoNoMarketplace, ANome: string; const AEstoque: Integer;
  const APreco: Double);
var
  Qry: TFDQuery;
  NovoCodigo: Integer;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    Qry.SQL.Text :=
      'SELECT COALESCE(MAX(CODPRODUTOS_MARKETPLACE), 0) + 1 AS PROXIMO ' +
      'FROM PRODUTOS_MARKETPLACE';
    Qry.Open;
    NovoCodigo := Qry.FieldByName('PROXIMO').AsInteger;
    Qry.Close;
    Qry.SQL.Text :=
      'INSERT INTO PRODUTOS_MARKETPLACE ' +
      '(CODPRODUTOS_MARKETPLACE, CODPRODUTO, CODMARKETPLACE, ' +
      'CODPRODUTONOMARKETPLACE, DISPONIBILIZARMARKETPLACE, ' +
      // {DECISAO DO CLIENTE - 07/09/2026} ATUALIZAR_ESTOQUE_MARKETPLACE ja
      // nasce 'S': e o campo que o F2 le pra saber o que sincronizar, e nada
      // no sistema o marcava (nem codigo, nem gatilho) - o F2 so sabe limpar
      // pra 'N' depois de enviar. Mesmo criterio da tela de Ofertas.
      'ATUALIZARMARKETPLACE, EXCLUIDO, ATUALIZAR_ESTOQUE_MARKETPLACE, ' +
      'DESCRICAO, ESTOQUE, PRECO, ' +
      'DATAULTIMAALTERACAO, LOJA) ' +
      'VALUES (:CODPRODUTOS_MARKETPLACE, NULL, :CODMARKETPLACE, ' +
      ':CODPRODUTONOMARKETPLACE, ''N'', ''N'', ''N'', ''S'', :DESCRICAO, ' +
      ':ESTOQUE, :PRECO, :DATAULTIMAALTERACAO, :LOJA)';
    Qry.ParamByName('CODPRODUTOS_MARKETPLACE').AsInteger := NovoCodigo;
    Qry.ParamByName('CODMARKETPLACE').AsInteger := FCodMarketplace;
    // {IMPORTANTE} grava o ItemId (MLB...) do ANUNCIO, nao o id do produto
    // de catalogo - e' a mesma chave usada em
    // uFrmOfertasMarketplace.GravarProdutoMercadoLivre, no F2 de estoque e
    // no lookup da baixa de pedido. Gravar o catalog_product_id aqui
    // quebraria os tres.
    Qry.ParamByName('CODPRODUTONOMARKETPLACE').AsString := ACodProdutoNoMarketplace;
    Qry.ParamByName('DESCRICAO').AsString := ANome;
    Qry.ParamByName('ESTOQUE').AsInteger := AEstoque;
    Qry.ParamByName('PRECO').AsFloat := APreco;
    Qry.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    Qry.ParamByName('LOJA').AsInteger := FLoja;
    Qry.ExecSQL;
    Log('Registro gravado em PRODUTOS_MARKETPLACE (sem vinculo com produto fisico ainda).');
  finally
    Qry.Free;
  end;
end;

procedure TFrmCadastrarOfertaCatalogoMercadoLivre.CmdFecharClick(Sender: TObject);
begin
  Close;
end;

end.
