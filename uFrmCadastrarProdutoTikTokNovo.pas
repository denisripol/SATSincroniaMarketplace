// ============================================================================
// UNIT: uFrmCadastrarProdutoTikTokNovo
// OBJETIVO: Tela do modo "produto completo" (mcpProdutoCompleto) do TikTok
// Shop - cadastrar um produto do zero na loja.
//
// Mesma estrutura em 2 passos ja usada nas telas da Amazon e do Mercado
// Livre, porque o problema e' o mesmo: descobrir a categoria, descobrir os
// atributos obrigatorios daquela categoria, e so' entao publicar.
//   Passo 1: titulo -> o TikTok recomenda a categoria (so' categoria FOLHA
//            aceita produto - a lista marca quais servem).
//   Passo 2: dados comerciais + atributos revisaveis em JSON -> publica.
//
// QUATRO COISAS DO TIKTOK QUE NAO EXISTEM NAS OUTRAS TELAS - vale ler antes
// de mexer aqui:
//
//   1. IMAGEM E' ARQUIVO, NAO URL. O TikTok nao aceita link publico: cada
//      imagem tem que ser enviada e vira um "uri" interno. Por isso o memo
//      pede CAMINHO DE ARQUIVO local, e o Publicar sobe uma por uma antes
//      de criar o produto. Na Shopee e no ML e' URL.
//
//   2. MARCA E' OBRIGATORIAMENTE UM ID. Nao existe marca em texto livre - e'
//      preciso escolher da lista que o proprio TikTok devolve.
//
//   3. O SKU JA NASCE COM ESTOQUE NUM DEPOSITO. Nao ha "estoque solto": o
//      corpo do produto leva warehouse_id + quantidade. A tela busca o
//      deposito de venda sozinha, igual o F2 faz.
//
//   4. PESO E' OBRIGATORIO. O TikTok recusa produto sem package_weight.
//
// {IMPORTANTE} ao gravar em PRODUTOS_MARKETPLACE, a chave e'
// "product_id|sku_id" - a MESMA usada na tela de Ofertas, no F2 de estoque e
// no lookup da baixa de pedido. Gravar so' o product_id quebraria os tres.
//
// {ATENCAO} Escrito a partir da documentacao publica da Partner API, sem app
// real pra exercitar - mesma ressalva do resto da integracao do TikTok.
// ============================================================================
unit uFrmCadastrarProdutoTikTokNovo;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.Variants, System.Classes, System.StrUtils, System.IOUtils,
  System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Data.DB, FireDAC.Comp.Client,
  DMZ, uMarketplace, TikTokShop.OpenAPI.Client;

type
  TFrmCadastrarProdutoTikTokNovo = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    // --- Passo 1: categoria ---
    lblBuscaCategoria: TLabel;
    edtBuscaCategoria: TEdit;
    CmdPreverCategoria: TBitBtn;
    lstCategorias: TListBox;
    CmdProximoPasso1: TBitBtn;
    // --- Passo 2: dados do produto ---
    lblCategoriaSelecionada: TLabel;
    lblSku: TLabel;
    edtSku: TEdit;
    lblNome: TLabel;
    edtNome: TEdit;
    lblMarca: TLabel;
    edtBuscaMarca: TEdit;
    CmdBuscarMarca: TBitBtn;
    cbMarca: TComboBox;
    lblPreco: TLabel;
    edtPreco: TEdit;
    lblEstoque: TLabel;
    edtEstoque: TEdit;
    lblPeso: TLabel;
    edtPeso: TEdit;
    lblDimensoes: TLabel;
    edtComprimento: TEdit;
    edtLargura: TEdit;
    edtAltura: TEdit;
    lblImagens: TLabel;
    mmImagens: TMemo;
    lblDescricao: TLabel;
    mmDescricao: TMemo;
    CmdMontarJSON: TBitBtn;
    CmdVerAtributos: TBitBtn;
    lblAtributosJSON: TLabel;
    mmAtributosJSON: TMemo;
    CmdVoltar: TBitBtn;
    CmdCadastrar: TBitBtn;
    // --- Compartilhado ---
    CmdFechar: TBitBtn;
    MemoLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure CmdPreverCategoriaClick(Sender: TObject);
    procedure CmdProximoPasso1Click(Sender: TObject);
    procedure CmdBuscarMarcaClick(Sender: TObject);
    procedure CmdMontarJSONClick(Sender: TObject);
    procedure CmdVerAtributosClick(Sender: TObject);
    procedure CmdVoltarClick(Sender: TObject);
    procedure CmdCadastrarClick(Sender: TObject);
    procedure CmdFecharClick(Sender: TObject);
  private
    FLoja: Integer;
    FCodMarketplace: Integer;
    FAccountID: string;   // "shop_id|shop_cipher" - ver uMarketplace
    FShopCipher: string;
    FToken: string;
    FDevClientId: string;
    FDevClientSecret: string;
    FSandbox: Boolean;
    FCadastrouAlgo: Boolean;
    FCategorias: TTikTokShopCategoriaSugeridaArray;
    FCategoryIdEscolhida: string;
    FCategoryNomeEscolhida: string;
    FAtributosCategoria: TTikTokShopAtributoArray;
    FAtributosRawJSON: string;
    FMarcas: TTikTokShopMarcaArray;
    procedure Log(const AMsg: string);
    function ParseValorDecimal(const ATexto: string; out AValor: Double): Boolean;
    // So chamado explicitamente pelo AbrirParaLoja, DEPOIS que os campos ja
    // foram atribuidos - o FormCreate roda dentro do TForm.Create, antes
    // disso (mesmo cuidado das outras telas de cadastro do projeto).
    procedure Inicializar;
    procedure MostrarPasso(const APasso: Integer);
    procedure MontarJSON;
    function MontarBodyProduto(const AImagensUri: TArray<string>;
      const AWarehouseId: string; out ABodyJSON, AErro: string): Boolean;
    function EnviarImagens(ACliente: TTikTokShopOpenAPIClient;
      out AUris: TArray<string>; out AErro: string): Boolean;
    procedure GravarProdutoMarketplace(const AProductId, ASkuId, ANome: string;
      const AEstoque: Integer; const APreco: Double);
  public
    class function AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
      const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
      const ASandbox: Boolean): Boolean;
  end;

implementation

{$R *.dfm}

class function TFrmCadastrarProdutoTikTokNovo.AbrirParaLoja(
  const ALoja, ACodMarketplace: Integer; const AAccountID, AToken: string;
  const ADevClientId, ADevClientSecret: string; const ASandbox: Boolean): Boolean;
var
  Frm: TFrmCadastrarProdutoTikTokNovo;
begin
  Frm := TFrmCadastrarProdutoTikTokNovo.Create(Application);
  try
    Frm.FLoja := ALoja;
    Frm.FCodMarketplace := ACodMarketplace;
    Frm.FAccountID := AAccountID;
    Frm.FToken := AToken;
    Frm.FDevClientId := ADevClientId;
    Frm.FDevClientSecret := ADevClientSecret;
    Frm.FSandbox := ASandbox;
    Frm.FCadastrouAlgo := False;
    Frm.Inicializar;
    Frm.ShowModal;
    Result := Frm.FCadastrouAlgo;
  finally
    Frm.Free;
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.FormCreate(Sender: TObject);
begin
  MemoLog.Clear;
end;

procedure TFrmCadastrarProdutoTikTokNovo.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;

function TFrmCadastrarProdutoTikTokNovo.ParseValorDecimal(const ATexto: string;
  out AValor: Double): Boolean;
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

procedure TFrmCadastrarProdutoTikTokNovo.Inicializar;
var
  ShopId: string;
begin
  lblTitulo.Caption := 'Incluir Produto Novo - TikTok Shop';
  edtBuscaCategoria.Clear;
  lstCategorias.Clear;
  SetLength(FCategorias, 0);
  FCategoryIdEscolhida := '';
  FCategoryNomeEscolhida := '';
  SetLength(FAtributosCategoria, 0);
  FAtributosRawJSON := '';
  SetLength(FMarcas, 0);
  cbMarca.Items.Clear;
  edtSku.Text := '';
  edtNome.Text := '';
  edtPreco.Text := '';
  edtEstoque.Text := '';
  edtPeso.Text := '1';
    edtComprimento.Text := '10';
    edtLargura.Text := '10';
    edtAltura.Text := '10';
  mmImagens.Clear;
  mmDescricao.Clear;
  mmAtributosJSON.Clear;

  // O TikTok identifica a loja pelo shop_cipher, guardado junto com o
  // shop_id no mesmo campo (ver uMarketplace).
  SepararShopIdECipherTikTok(FAccountID, ShopId, FShopCipher);

  MostrarPasso(1);
  if FShopCipher = '' then
    Log('ATENCAO: vinculo do TikTok incompleto (falta o shop_cipher). ' +
      'Desconecte e conecte a loja novamente no SATLojas antes de cadastrar.')
  else
    Log('Pronto. Digite o titulo do produto pra o TikTok sugerir a categoria.');
end;

procedure TFrmCadastrarProdutoTikTokNovo.MostrarPasso(const APasso: Integer);
begin
  // Passo 1 - categoria.
  lblBuscaCategoria.Visible := APasso = 1;
  edtBuscaCategoria.Visible := APasso = 1;
  CmdPreverCategoria.Visible := APasso = 1;
  lstCategorias.Visible := APasso = 1;
  CmdProximoPasso1.Visible := APasso = 1;
  // Passo 2 - dados do produto.
  lblCategoriaSelecionada.Visible := APasso = 2;
  lblSku.Visible := APasso = 2;
  edtSku.Visible := APasso = 2;
  lblNome.Visible := APasso = 2;
  edtNome.Visible := APasso = 2;
  lblMarca.Visible := APasso = 2;
  edtBuscaMarca.Visible := APasso = 2;
  CmdBuscarMarca.Visible := APasso = 2;
  cbMarca.Visible := APasso = 2;
  lblPreco.Visible := APasso = 2;
  edtPreco.Visible := APasso = 2;
  lblEstoque.Visible := APasso = 2;
  edtEstoque.Visible := APasso = 2;
  lblPeso.Visible := APasso = 2;
  edtPeso.Visible := APasso = 2;
  lblDimensoes.Visible := APasso = 2;
  edtComprimento.Visible := APasso = 2;
  edtLargura.Visible := APasso = 2;
  edtAltura.Visible := APasso = 2;
  lblImagens.Visible := APasso = 2;
  mmImagens.Visible := APasso = 2;
  lblDescricao.Visible := APasso = 2;
  mmDescricao.Visible := APasso = 2;
  CmdMontarJSON.Visible := APasso = 2;
  CmdVerAtributos.Visible := APasso = 2;
  lblAtributosJSON.Visible := APasso = 2;
  mmAtributosJSON.Visible := APasso = 2;
  CmdVoltar.Visible := APasso = 2;
  CmdCadastrar.Visible := APasso = 2;
  // CmdFechar e MemoLog ficam sempre visiveis (declarados assim no dfm).
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdPreverCategoriaClick(Sender: TObject);
var
  Cliente: TTikTokShopOpenAPIClient;
  ErroMsg, Linha: string;
  I: Integer;
begin
  if Trim(edtBuscaCategoria.Text) = '' then
  begin
    ShowMessage('Digite o titulo do produto primeiro.');
    Exit;
  end;
  if FShopCipher = '' then
  begin
    ShowMessage('Vinculo do TikTok incompleto: falta o shop_cipher. Desconecte e ' +
      'conecte a loja novamente no SATLojas.');
    Exit;
  end;

  lstCategorias.Clear;
  SetLength(FCategorias, 0);

  Screen.Cursor := crHourGlass;
  try
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.RecommendCategory(FToken, FShopCipher,
           Trim(edtBuscaCategoria.Text), FCategorias, ErroMsg) then
      begin
        Log('Falha ao sugerir a categoria: ' + ErroMsg);
        ShowMessage('Falha ao sugerir a categoria: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;

    if Length(FCategorias) = 0 then
    begin
      Log('O TikTok nao sugeriu nenhuma categoria pra esse titulo.');
      ShowMessage('O TikTok nao sugeriu nenhuma categoria. Tente um titulo mais ' +
        'descritivo (marca + tipo de produto).');
      Exit;
    end;

    for I := Low(FCategorias) to High(FCategorias) do
    begin
      Linha := FCategorias[I].Nome + '  (' + FCategorias[I].Id + ')';
      // So' categoria-folha aceita produto - marca as demais pra o usuario
      // nao perder tempo escolhendo uma que vai ser recusada.
      if not FCategorias[I].EhFolha then
        Linha := Linha + '   [nao e categoria final - nao aceita produto]';
      lstCategorias.Items.Add(Linha);
    end;
    Log(Format('%d categoria(s) sugerida(s).', [Length(FCategorias)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdProximoPasso1Click(Sender: TObject);
var
  Cliente: TTikTokShopOpenAPIClient;
  ErroMsg: string;
  Idx: Integer;
begin
  Idx := lstCategorias.ItemIndex;
  if (Idx < 0) or (Idx > High(FCategorias)) then
  begin
    ShowMessage('Escolha uma categoria na lista primeiro.');
    Exit;
  end;
  if not FCategorias[Idx].EhFolha then
  begin
    ShowMessage('Essa nao e uma categoria final. O TikTok so aceita produto na ' +
      'ultima categoria da arvore - escolha uma que nao esteja marcada como ' +
      '"nao aceita produto".');
    Exit;
  end;

  FCategoryIdEscolhida := FCategorias[Idx].Id;
  FCategoryNomeEscolhida := FCategorias[Idx].Nome;
  SetLength(FAtributosCategoria, 0);
  FAtributosRawJSON := '';

  Screen.Cursor := crHourGlass;
  try
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      // Falhar aqui NAO trava o fluxo: da pra publicar sem atributo opcional,
      // e o proprio POST recusa se faltar algum obrigatorio - com mensagem
      // melhor do que qualquer chute nosso.
      if not Cliente.GetCategoryAttributes(FToken, FShopCipher, FCategoryIdEscolhida,
           FAtributosCategoria, FAtributosRawJSON, ErroMsg) then
        Log('Aviso: nao foi possivel carregar os atributos da categoria (' +
          ErroMsg + ') - seguindo sem eles.');
    finally
      Cliente.Free;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  lblCategoriaSelecionada.Caption := 'Categoria: ' + FCategoryNomeEscolhida +
    '  (' + FCategoryIdEscolhida + ')';
  if Trim(edtNome.Text) = '' then
    edtNome.Text := Trim(edtBuscaCategoria.Text);
  MontarJSON;
  MostrarPasso(2);
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdBuscarMarcaClick(Sender: TObject);
var
  Cliente: TTikTokShopOpenAPIClient;
  ErroMsg: string;
  I: Integer;
begin
  Screen.Cursor := crHourGlass;
  try
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.GetBrands(FToken, FShopCipher, Trim(edtBuscaMarca.Text),
           FMarcas, ErroMsg) then
      begin
        Log('Falha ao listar as marcas: ' + ErroMsg);
        ShowMessage('Falha ao listar as marcas: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;

    cbMarca.Items.Clear;
    for I := Low(FMarcas) to High(FMarcas) do
      cbMarca.Items.Add(FMarcas[I].Nome);
    if cbMarca.Items.Count > 0 then
      cbMarca.ItemIndex := 0;
    Log(Format('%d marca(s) carregada(s).', [Length(FMarcas)]));
    if Length(FMarcas) = 0 then
      ShowMessage('Nenhuma marca encontrada com esse texto. O TikTok exige uma ' +
        'marca da lista dele - tente outro termo, ou cadastre a marca pelo ' +
        'Seller Center antes.');
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.MontarJSON;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  // Monta um esqueleto com os atributos OBRIGATORIOS da categoria, com valor
  // em branco pra o usuario preencher. Mesma ideia do JSON revisavel das
  // telas da Amazon e do Mercado Livre: o usuario ve e corrige antes de
  // publicar, em vez de descobrir o que faltou pelo erro da API.
  Arr := TJSONArray.Create;
  try
    for I := Low(FAtributosCategoria) to High(FAtributosCategoria) do
    begin
      if not FAtributosCategoria[I].Obrigatorio then
        Continue;
      Obj := TJSONObject.Create;
      Obj.AddPair('id', FAtributosCategoria[I].Id);
      // O TikTok aceita value_id (quando o atributo tem lista fechada) ou
      // value_name (texto livre). Deixa os dois em branco - o usuario apaga
      // o que nao usar.
      Obj.AddPair('name', FAtributosCategoria[I].Nome);
      Obj.AddPair('value_id', '');
      Obj.AddPair('value_name', '');
      Arr.AddElement(Obj);
    end;
    mmAtributosJSON.Lines.Text := Arr.Format(2);
  finally
    Arr.Free;
  end;
  if mmAtributosJSON.Lines.Text = '[]' then
    Log('Essa categoria nao declarou atributo obrigatorio.')
  else
    Log('Atributos obrigatorios montados - preencha os valores antes de publicar.');
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdMontarJSONClick(Sender: TObject);
begin
  if FCategoryIdEscolhida = '' then
  begin
    ShowMessage('Escolha a categoria primeiro.');
    Exit;
  end;
  MontarJSON;
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdVerAtributosClick(Sender: TObject);
var
  Caminho: string;
begin
  if Trim(FAtributosRawJSON) = '' then
  begin
    ShowMessage('Nenhum atributo carregado ainda - escolha a categoria primeiro.');
    Exit;
  end;
  // Mesmo padrao do "Ver Atributos" das outras telas: grava num .json
  // temporario e abre no editor padrao do Windows.
  Caminho := TPath.Combine(TPath.GetTempPath,
    'tiktok_atributos_' + FCategoryIdEscolhida + '.json');
  try
    TFile.WriteAllText(Caminho, FAtributosRawJSON, TEncoding.UTF8);
    ShellExecute(0, 'open', PChar(Caminho), nil, nil, SW_SHOWNORMAL);
    Log('Atributos da categoria salvos em: ' + Caminho);
  except
    on E: Exception do
      Log('Nao foi possivel abrir o arquivo de atributos: ' + E.Message);
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdVoltarClick(Sender: TObject);
begin
  MostrarPasso(1);
end;

function TFrmCadastrarProdutoTikTokNovo.EnviarImagens(
  ACliente: TTikTokShopOpenAPIClient; out AUris: TArray<string>;
  out AErro: string): Boolean;
var
  I, Total: Integer;
  Caminho, Uri: string;
begin
  Result := False;
  AErro := '';
  SetLength(AUris, mmImagens.Lines.Count);
  Total := 0;

  // {ATENCAO} uma chamada por imagem. Se a terceira falhar, as duas primeiras
  // JA subiram - nao da pra desfazer, mas tambem nao custa nada: imagem
  // orfa no TikTok nao vira produto nem aparece pra ninguem.
  for I := 0 to mmImagens.Lines.Count - 1 do
  begin
    Caminho := Trim(mmImagens.Lines[I]);
    if Caminho = '' then
      Continue;
    if not ACliente.UploadProductImage(FToken, Caminho, Uri, AErro) then
    begin
      AErro := 'Falha ao enviar a imagem "' + ExtractFileName(Caminho) + '": ' + AErro;
      Exit;
    end;
    AUris[Total] := Uri;
    Inc(Total);
    Log(Format('  Imagem %d/%d enviada: %s', [Total, mmImagens.Lines.Count,
      ExtractFileName(Caminho)]));
  end;

  SetLength(AUris, Total);
  if Total = 0 then
  begin
    AErro := 'Informe pelo menos uma imagem - o TikTok nao publica produto sem imagem.';
    Exit;
  end;
  Result := True;
end;

function TFrmCadastrarProdutoTikTokNovo.MontarBodyProduto(
  const AImagensUri: TArray<string>; const AWarehouseId: string;
  out ABodyJSON, AErro: string): Boolean;
var
  Body, PrecoObj, PesoObj, DimObj, SkuObj, EstoqueObj, ImgObj: TJSONObject;
  ImgsArr, SkusArr, EstoqueArr: TJSONArray;
  AttrsValor: TJSONValue;
  Preco, Peso, Comprimento, Largura, Altura: Double;
  Estoque, I: Integer;
begin
  Result := False;
  ABodyJSON := '';
  AErro := '';

  if Trim(edtNome.Text) = '' then
  begin
    AErro := 'Informe o titulo do produto.';
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
  if not ParseValorDecimal(edtPeso.Text, Peso) or (Peso <= 0) then
  begin
    AErro := 'Peso invalido - o TikTok recusa produto sem peso da embalagem.';
    Exit;
  end;
  if not ParseValorDecimal(edtComprimento.Text, Comprimento) or (Comprimento <= 0) then
  begin
    AErro := 'Comprimento invalido - o TikTok exige as tres dimensoes maiores que zero.';
    Exit;
  end;
  if not ParseValorDecimal(edtLargura.Text, Largura) or (Largura <= 0) then
  begin
    AErro := 'Largura invalida - o TikTok exige as tres dimensoes maiores que zero.';
    Exit;
  end;
  if not ParseValorDecimal(edtAltura.Text, Altura) or (Altura <= 0) then
  begin
    AErro := 'Altura invalida - o TikTok exige as tres dimensoes maiores que zero.';
    Exit;
  end;

  // O array de atributos vem do memo, ja revisado pelo usuario.
  AttrsValor := TJSONObject.ParseJSONValue(Trim(mmAtributosJSON.Lines.Text));
  if not Assigned(AttrsValor) or not (AttrsValor is TJSONArray) then
  begin
    if Assigned(AttrsValor) then
      AttrsValor.Free;
    AErro := 'O JSON de atributos esta invalido - precisa ser uma lista [ ... ].';
    Exit;
  end;

  Body := TJSONObject.Create;
  try
    // save_mode LISTING = publica de verdade. "AS_DRAFT" deixaria em rascunho
    // no Seller Center, o que nao serve pro fluxo do SAT.
    Body.AddPair('save_mode', 'LISTING');
    Body.AddPair('title', Trim(edtNome.Text));
    // {ATENCAO} a descricao do TikTok e' HTML, nao texto plano (diferente do
    // Mercado Livre, que recusa HTML). Embrulha em <p> quando o usuario
    // digitou texto simples.
    if Trim(mmDescricao.Lines.Text) <> '' then
      Body.AddPair('description', '<p>' +
        StringReplace(Trim(mmDescricao.Lines.Text), sLineBreak, '</p><p>',
          [rfReplaceAll]) + '</p>');
    Body.AddPair('category_id', FCategoryIdEscolhida);

    if (cbMarca.ItemIndex >= 0) and (cbMarca.ItemIndex <= High(FMarcas)) then
      Body.AddPair('brand_id', FMarcas[cbMarca.ItemIndex].Id);

    ImgsArr := TJSONArray.Create;
    for I := Low(AImagensUri) to High(AImagensUri) do
    begin
      ImgObj := TJSONObject.Create;
      ImgObj.AddPair('uri', AImagensUri[I]);
      ImgsArr.AddElement(ImgObj);
    end;
    Body.AddPair('main_images', ImgsArr);

    PesoObj := TJSONObject.Create;
    // {ATENCAO} valores monetarios e de peso vao como STRING no TikTok.
    PesoObj.AddPair('value', FormatFloat('0.###', Peso, TFormatSettings.Invariant));
    PesoObj.AddPair('unit', 'KILOGRAM');
    Body.AddPair('package_weight', PesoObj);

    // {ATENCAO} package_dimensions e' OBRIGATORIO. Nao enviar nao equivale a
    // omitir: o TikTok assume zero e recusa com o code 12052116 ("all package
    // dimensions must be positive numeric values"). Vao como STRING, igual
    // peso e preco.
    DimObj := TJSONObject.Create;
    DimObj.AddPair('length', FormatFloat('0.###', Comprimento, TFormatSettings.Invariant));
    DimObj.AddPair('width', FormatFloat('0.###', Largura, TFormatSettings.Invariant));
    DimObj.AddPair('height', FormatFloat('0.###', Altura, TFormatSettings.Invariant));
    DimObj.AddPair('unit', 'CENTIMETER');
    Body.AddPair('package_dimensions', DimObj);

    // Um SKU so'. Produto com variacao precisaria de varios, cada um com seu
    // sales_attributes - fica pra quando o cliente precisar.
    PrecoObj := TJSONObject.Create;
    PrecoObj.AddPair('amount', FormatFloat('0.00', Preco, TFormatSettings.Invariant));
    PrecoObj.AddPair('currency', 'BRL');

    EstoqueObj := TJSONObject.Create;
    EstoqueObj.AddPair('warehouse_id', AWarehouseId);
    EstoqueObj.AddPair('quantity', TJSONNumber.Create(Estoque));
    EstoqueArr := TJSONArray.Create;
    EstoqueArr.AddElement(EstoqueObj);

    SkuObj := TJSONObject.Create;
    if Trim(edtSku.Text) <> '' then
      SkuObj.AddPair('seller_sku', Trim(edtSku.Text));
    SkuObj.AddPair('price', PrecoObj);
    SkuObj.AddPair('inventory', EstoqueArr);

    SkusArr := TJSONArray.Create;
    SkusArr.AddElement(SkuObj);
    Body.AddPair('skus', SkusArr);

    // Toma posse do array de atributos (o Body passa a ser o dono).
    Body.AddPair('product_attributes', AttrsValor);

    ABodyJSON := Body.ToJSON;
    Result := True;
  finally
    Body.Free; // libera tambem os filhos, inclusive AttrsValor
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdCadastrarClick(Sender: TObject);
var
  Cliente: TTikTokShopOpenAPIClient;
  Depositos: TTikTokShopWarehouseArray;
  ImagensUri: TArray<string>;
  BodyJSON, ErroMsg, ProductId, SkuId, RespostaJSON, WarehouseId: string;
  Preco: Double;
  Estoque, I: Integer;
begin
  if FCategoryIdEscolhida = '' then
  begin
    ShowMessage('Escolha a categoria primeiro.');
    Exit;
  end;
  if cbMarca.ItemIndex < 0 then
    if MessageDlg('Nenhuma marca escolhida. O TikTok costuma EXIGIR marca para ' +
         'publicar, e a maioria das categorias recusa produto sem ela. ' +
         'Continuar mesmo assim?', mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;

  ParseValorDecimal(edtPreco.Text, Preco);
  Estoque := StrToIntDef(Trim(edtEstoque.Text), 0);

  Screen.Cursor := crHourGlass;
  try
    Cliente := TTikTokShopOpenAPIClient.Create(FDevClientId, FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      // 1) Deposito: o SKU nasce com estoque num deposito especifico. Mesma
      // logica do F2 - primeiro deposito de venda, caindo pro primeiro da
      // lista se nenhum vier marcado.
      WarehouseId := '';
      if Cliente.GetWarehouses(FToken, FShopCipher, Depositos, ErroMsg) then
      begin
        for I := Low(Depositos) to High(Depositos) do
          if SameText(Depositos[I].Tipo, 'SALES_WAREHOUSE') then
          begin
            WarehouseId := Depositos[I].Id;
            Break;
          end;
        if (WarehouseId = '') and (Length(Depositos) > 0) then
          WarehouseId := Depositos[0].Id;
      end
      else
        Log('Falha ao listar depositos: ' + ErroMsg);
      if WarehouseId = '' then
      begin
        ShowMessage('Nao foi possivel identificar o deposito da loja no TikTok - ' +
          'sem ele nao da para criar o produto com estoque.');
        Exit;
      end;
      Log('Deposito: ' + WarehouseId);

      // 2) Imagens - precisam existir ANTES do produto.
      Log('Enviando imagens...');
      if not EnviarImagens(Cliente, ImagensUri, ErroMsg) then
      begin
        Log(ErroMsg);
        ShowMessage(ErroMsg);
        Exit;
      end;

      // 3) Corpo do produto.
      if not MontarBodyProduto(ImagensUri, WarehouseId, BodyJSON, ErroMsg) then
      begin
        Log('Nao foi possivel montar o produto: ' + ErroMsg);
        ShowMessage(ErroMsg);
        Exit;
      end;

      // 4) Cria.
      if not Cliente.CreateProduct(FToken, FShopCipher, BodyJSON, ProductId, SkuId,
           RespostaJSON, ErroMsg) then
      begin
        Log('Falha ao publicar o produto: ' + ErroMsg);
        ShowMessage('Falha ao publicar o produto:' + sLineBreak + ErroMsg +
          sLineBreak + sLineBreak + 'O TikTok costuma apontar o campo exato no ' +
          'corpo do erro - confira o log. Atributo obrigatorio em branco e ' +
          'marca ausente sao as causas mais comuns.');
        Exit;
      end;

      Log('Produto publicado com sucesso: ' + ProductId + ' / SKU ' + SkuId);
    finally
      Cliente.Free;
    end;

    GravarProdutoMarketplace(ProductId, SkuId, Trim(edtNome.Text), Estoque, Preco);
    FCadastrouAlgo := True;
    ShowMessage('Produto publicado no TikTok Shop!' + sLineBreak +
      'ID do produto: ' + ProductId + sLineBreak +
      'O TikTok ainda vai revisar o anuncio antes de ele ficar visivel.');
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.GravarProdutoMarketplace(
  const AProductId, ASkuId, ANome: string; const AEstoque: Integer;
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
    // {IMPORTANTE} a chave e' "product_id|sku_id" - a MESMA usada na tela de
    // Ofertas, no F2 de estoque e no lookup da baixa de pedido.
    Qry.ParamByName('CODPRODUTONOMARKETPLACE').AsString :=
      MontarChaveProdutoTikTok(AProductId, ASkuId);
    Qry.ParamByName('DESCRICAO').AsString := ANome;
    Qry.ParamByName('ESTOQUE').AsInteger := AEstoque;
    Qry.ParamByName('PRECO').AsFloat := APreco;
    Qry.ParamByName('DATAULTIMAALTERACAO').AsDateTime := Now;
    Qry.ParamByName('LOJA').AsInteger := FLoja;
    Qry.ExecSQL;
    Log('Registro gravado em PRODUTOS_MARKETPLACE (marcado para sincronizar ' +
      'estoque; falta vincular ao produto fisico na tela de Ofertas).');
  finally
    Qry.Free;
  end;
end;

procedure TFrmCadastrarProdutoTikTokNovo.CmdFecharClick(Sender: TObject);
begin
  Close;
end;

end.
