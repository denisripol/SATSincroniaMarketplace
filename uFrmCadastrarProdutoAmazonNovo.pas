// ============================================================================
// UNIT: uFrmCadastrarProdutoAmazonNovo
// OBJETIVO: Tela pra cadastrar um produto NOVO do zero na Amazon (sem ASIN
// existente) - usa a Product Type Definitions API pra descobrir a
// "categoria" (productType) e os atributos obrigatorios, diferente da
// uFrmCadastrarProdutoMarketplace (que so cria oferta em cima de ASIN ja
// existente, ou faz cadastro completo direto pra Shopee).
//
// FLUXO EM 2 PASSOS:
//   Passo 1: usuario digita uma palavra-chave (ex: "clipe de papel"), a
//   tela busca os productType candidatos (SearchProductTypes) e lista pra
//   escolha.
//
//   Passo 2: ao escolher um productType, a tela baixa o schema completo
//   (GetProductTypeSchema) e extrai a lista de atributos obrigatorios
//   ("required" no nivel raiz do schema). Monta automaticamente um JSON
//   de atributos com os campos mais comuns (item_name, bullet_point,
//   condition_type, fulfillment_availability, purchasable_offer - estes
//   ultimos tres no MESMO formato ja validado em
//   Amazon.SPAPI.Client.CreateOfferForExistingASIN, incluindo o campo
//   "audience" que faltava la e fazia a oferta ficar incompleta) e um
//   ESQUELETO (chute de formato simples {"value":"", "marketplace_id":
//   ...}) pros demais atributos obrigatorios que a tela nao sabe montar
//   sozinha. O usuario revisa/edita esse JSON no memo antes de cadastrar -
//   principalmente atributos compostos (imagens, GTIN/EAN, dimensoes),
//   que quase certamente precisam de ajuste manual. O botao "Ver Schema
//   Completo" abre o schema baixado (arquivo .json temporario) pra
//   conferencia do formato exato exigido por cada atributo.
//
// Ao ter sucesso, grava a oferta nova em PRODUTOS_MARKETPLACE - SEM
// vinculo com produto fisico ainda, mesmo padrao usado no resto do
// projeto (uFrmCadastrarProdutoMarketplace, "Buscar Ofertas").
//
// {ATENCAO - LIMITACAO CONHECIDA} A extracao de atributos obrigatorios
// (ExtrairAtributosObrigatorios) so le o array "required" no nivel raiz
// do schema. O JSON Schema da Amazon tambem usa blocos "allOf" com regras
// condicionais (if/then) pra exigir atributos SO em certas situacoes -
// ex: "merchant_shipping_group" so e' obrigatorio quando
// fulfillment_channel_code = "DEFAULT" (ja tratado abaixo, adicionado
// incondicionalmente porque e' sempre o nosso caso). Se aparecer de novo
// o erro generico "HTTP 400 InvalidInput / cannot be parsed" MESMO com
// todo o "required" simples preenchido, o schema completo (botao "Ver
// Schema Completo") deve ser revisado atras de blocos "allOf" que citem
// os atributos que a gente esta mandando - normalmente e' isso.
// ============================================================================
unit uFrmCadastrarProdutoAmazonNovo;
interface
uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.Variants, System.Classes, System.StrUtils, System.IOUtils,
  System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Data.DB, FireDAC.Comp.Client,
  DMZ, uMarketplace, Amazon.SPAPI.Client, uFrmCadastrarProdutoMarketplace;
type
  TFrmCadastrarProdutoAmazonNovo = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    // --- Passo 1: busca da categoria (productType) ---
    lblKeywords: TLabel;
    edtKeywords: TEdit;
    CmdBuscarProductType: TBitBtn;
    lstProductTypes: TListBox;
    CmdProximoPasso1: TBitBtn;
    // --- Passo 1 (alternativa): checar se o produto ja existe no
    // catalogo antes de cadastrar do zero (evita GTIN/isencao). ---
    lblOuBuscarCatalogo: TLabel;
    edtBuscaCatalogo: TEdit;
    CmdBuscarCatalogo: TBitBtn;
    lstResultadosCatalogo: TListBox;
    CmdUsarASINExistente: TBitBtn;
    // --- Passo 2: campos comuns + JSON de atributos ---
    lblProductTypeSelecionado: TLabel;
    lblSku: TLabel;
    edtSku: TEdit;
    lblNome: TLabel;
    edtNome: TEdit;
    lblBulletPoints: TLabel;
    mmBulletPoints: TMemo;
    lblMarca: TLabel;
    edtMarca: TEdit;
    lblPaisOrigem: TLabel;
    edtPaisOrigem: TEdit;
    lblDescricao: TLabel;
    mmDescricao: TMemo;
    lblCodigoBarras: TLabel;
    cbTipoCodigoBarras: TComboBox;
    edtCodigoBarras: TEdit;
    lblPreco: TLabel;
    edtPreco: TEdit;
    lblEstoque: TLabel;
    edtEstoque: TEdit;
    CmdMontarJSON: TBitBtn;
    CmdVerSchema: TBitBtn;
    lblAtributosJSON: TLabel;
    mmAtributosJSON: TMemo;
    CmdVoltar: TBitBtn;
    CmdCadastrar: TBitBtn;
    // --- Compartilhado ---
    CmdFechar: TBitBtn;
    MemoLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure CmdBuscarProductTypeClick(Sender: TObject);
    procedure CmdProximoPasso1Click(Sender: TObject);
    procedure CmdBuscarCatalogoClick(Sender: TObject);
    procedure CmdUsarASINExistenteClick(Sender: TObject);
    procedure CmdMontarJSONClick(Sender: TObject);
    procedure CmdVerSchemaClick(Sender: TObject);
    procedure CmdVoltarClick(Sender: TObject);
    procedure CmdCadastrarClick(Sender: TObject);
    procedure CmdFecharClick(Sender: TObject);
  private
    FLoja: Integer;
    FCodMarketplace: Integer;
    FAccountID: string;
    FToken: string;
    FDevClientId: string;
    FDevClientSecret: string;
    FSandbox: Boolean;
    // Sinaliza pra quem abriu a tela que pelo menos um produto foi
    // cadastrado com sucesso - mesmo padrao da uFrmCadastrarProdutoMarketplace.
    FCadastrouAlgo: Boolean;
    // Resultado da ultima busca de productType (passo 1) - o indice
    // selecionado em lstProductTypes indexa este array.
    FProductTypes: TAmazonProductTypeInfoArray;
    // Resultado da ultima busca no catalogo geral da Amazon (Catalog Items
    // API) - o indice selecionado em lstResultadosCatalogo indexa este
    // array.
    FCatalogItems: TAmazonCatalogItemArray;
    // productType escolhido no passo 1, usado no passo 2 e no cadastro final.
    FProductTypeEscolhido: string;
    // Schema JSON baixado pro productType escolhido (guardado inteiro pra
    // permitir "Ver Schema Completo" sem baixar de novo).
    FSchemaJSON: string;
    // Lista de nomes de atributos que o schema marcou como obrigatorios
    // ("required" no nivel raiz) - usada pra montar o esqueleto do JSON.
    FAtributosObrigatorios: TArray<string>;
    procedure Log(const AMsg: string);
    function ParseValorDecimal(const ATexto: string; out AValor: Double): Boolean;
    // So chamado explicitamente pelo AbrirParaLoja, DEPOIS que
    // FLoja/FCodMarketplace/FAccountID/etc ja foram atribuidos - o
    // FormCreate roda ainda dentro do TForm.Create, antes dessas
    // atribuicoes (mesmo cuidado que corrigiu o bug na
    // uFrmCadastrarProdutoMarketplace).
    procedure Inicializar;
    procedure MostrarPasso(const APasso: Integer);
    procedure ExtrairAtributosObrigatorios;
    procedure MontarJSON;
    // Le o schema (FSchemaJSON) e monta um array de 1 item com todos os
    // sub-campos obrigatorios de AAttrName preenchidos com um palpite
    // razoavel (primeiro valor do enum quando existir, 0/false/"" pro
    // resto) - generico, funciona pra QUALQUER atributo de QUALQUER
    // categoria, sem precisar de codigo especifico por atributo.
    function MontarEsqueletoAtributo(const ASchemaRoot: TJSONObject;
      const AAttrName: string): TJSONArray;
    // Le AIssuesJSON (devolvido por CreateNewProduct), pega os
    // "attributeNames" de issues ERROR que ainda nao estao no JSON atual,
    // e adiciona um esqueleto (via MontarEsqueletoAtributo) pra cada um -
    // fluxo iterativo: tenta, a Amazon aponta o que falta, a tela ja
    // prepara os campos, usuario so revisa/preenche os valores reais.
    procedure AdicionarAtributosFaltantes(const AIssuesJSON: string);
    procedure GravarProdutoMarketplace(const ACodProdutoNoMarketplace, ANome: string;
      const AEstoque: Integer; const APreco: Double);
  public
    // CadastrouAlgo = True se pelo menos um produto foi cadastrado com
    // sucesso durante a sessao dessa tela.
    class function AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
      const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
      const ASandbox: Boolean): Boolean;
  end;
implementation
{$R *.dfm}
{ TFrmCadastrarProdutoAmazonNovo }
class function TFrmCadastrarProdutoAmazonNovo.AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
  const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
  const ASandbox: Boolean): Boolean;
var
  Frm: TFrmCadastrarProdutoAmazonNovo;
begin
  Frm := TFrmCadastrarProdutoAmazonNovo.Create(Application);
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
procedure TFrmCadastrarProdutoAmazonNovo.FormCreate(Sender: TObject);
begin
  // ATENCAO: nao colocar aqui nenhuma logica que dependa de
  // FAccountID/FToken/etc - eles ainda nao foram atribuidos nesse momento
  // (ver comentario em Inicializar e no AbrirParaLoja).
end;
procedure TFrmCadastrarProdutoAmazonNovo.Inicializar;
begin
  lblTitulo.Caption := 'Incluir Produto Novo - Amazon (sem ASIN)';
  edtKeywords.Clear;
  lstProductTypes.Clear;
  edtBuscaCatalogo.Clear;
  lstResultadosCatalogo.Clear;
  SetLength(FCatalogItems, 0);
  FProductTypeEscolhido := '';
  FSchemaJSON := '';
  SetLength(FAtributosObrigatorios, 0);
  MostrarPasso(1);
  Log('Pronto. Busque a categoria (productType) do produto na Amazon pra comecar.');
end;
procedure TFrmCadastrarProdutoAmazonNovo.MostrarPasso(const APasso: Integer);
begin
  // Passo 1 - busca de categoria.
  lblKeywords.Visible := APasso = 1;
  edtKeywords.Visible := APasso = 1;
  CmdBuscarProductType.Visible := APasso = 1;
  lstProductTypes.Visible := APasso = 1;
  CmdProximoPasso1.Visible := APasso = 1;
  lblOuBuscarCatalogo.Visible := APasso = 1;
  edtBuscaCatalogo.Visible := APasso = 1;
  CmdBuscarCatalogo.Visible := APasso = 1;
  lstResultadosCatalogo.Visible := APasso = 1;
  CmdUsarASINExistente.Visible := APasso = 1;
  // Passo 2 - campos comuns + JSON de atributos.
  lblProductTypeSelecionado.Visible := APasso = 2;
  lblSku.Visible := APasso = 2;
  edtSku.Visible := APasso = 2;
  lblNome.Visible := APasso = 2;
  edtNome.Visible := APasso = 2;
  lblBulletPoints.Visible := APasso = 2;
  mmBulletPoints.Visible := APasso = 2;
  lblMarca.Visible := APasso = 2;
  edtMarca.Visible := APasso = 2;
  lblPaisOrigem.Visible := APasso = 2;
  edtPaisOrigem.Visible := APasso = 2;
  lblDescricao.Visible := APasso = 2;
  mmDescricao.Visible := APasso = 2;
  lblCodigoBarras.Visible := APasso = 2;
  cbTipoCodigoBarras.Visible := APasso = 2;
  edtCodigoBarras.Visible := APasso = 2;
  lblPreco.Visible := APasso = 2;
  edtPreco.Visible := APasso = 2;
  lblEstoque.Visible := APasso = 2;
  edtEstoque.Visible := APasso = 2;
  CmdMontarJSON.Visible := APasso = 2;
  CmdVerSchema.Visible := APasso = 2;
  lblAtributosJSON.Visible := APasso = 2;
  mmAtributosJSON.Visible := APasso = 2;
  CmdVoltar.Visible := APasso = 2;
  CmdCadastrar.Visible := APasso = 2;
  // CmdFechar e MemoLog ficam sempre visiveis (declarados assim no dfm).
end;
procedure TFrmCadastrarProdutoAmazonNovo.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;
function TFrmCadastrarProdutoAmazonNovo.ParseValorDecimal(const ATexto: string;
  out AValor: Double): Boolean;
var
  FS: TFormatSettings;
  TextoNormalizado: string;
begin
  // Mesma logica ja validada na uFrmCadastrarProdutoMarketplace - aceita
  // virgula ou ponto, usa TFormatSettings proprio (ponto fixo) pra nao
  // depender da config regional da maquina.
  FS := TFormatSettings.Invariant;
  TextoNormalizado := StringReplace(Trim(ATexto), ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(TextoNormalizado, AValor, FS);
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdBuscarProductTypeClick(Sender: TObject);
var
  Cliente: TAmazonSPAPIClient;
  Erro: string;
  I: Integer;
  Descricao: string;
begin
  if Trim(edtKeywords.Text) = '' then
  begin
    ShowMessage('Digite uma palavra-chave pra buscar a categoria (ex: "clipe de papel").');
    Exit;
  end;
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Amazon nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    lstProductTypes.Clear;
    Log('Buscando categorias para "' + Trim(edtKeywords.Text) + '"...');
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.SearchProductTypes(FToken, Trim(edtKeywords.Text), FProductTypes, Erro) then
      begin
        Log('Falha ao buscar categorias: ' + Erro);
        ShowMessage('Falha ao buscar categorias: ' + Erro);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    if Length(FProductTypes) = 0 then
    begin
      Log('Nenhuma categoria encontrada para essa palavra-chave. Tente outro termo.');
      Exit;
    end;
    for I := 0 to High(FProductTypes) do
    begin
      Descricao := FProductTypes[I].Name;
      if FProductTypes[I].DisplayName <> '' then
        Descricao := Descricao + ' - ' + FProductTypes[I].DisplayName;
      lstProductTypes.Items.Add(Descricao);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdProximoPasso1Click(Sender: TObject);
var
  Cliente: TAmazonSPAPIClient;
  Erro: string;
begin
  if lstProductTypes.ItemIndex < 0 then
  begin
    ShowMessage('Selecione uma categoria na lista antes de continuar.');
    Exit;
  end;
  FProductTypeEscolhido := FProductTypes[lstProductTypes.ItemIndex].Name;
  Screen.Cursor := crHourGlass;
  try
    Log('Baixando schema do productType "' + FProductTypeEscolhido + '"...');
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.GetProductTypeSchema(FToken, FProductTypeEscolhido, FAccountID,
           FSchemaJSON, Erro) then
      begin
        Log('Falha ao baixar schema: ' + Erro);
        ShowMessage('Falha ao baixar schema: ' + Erro);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    ExtrairAtributosObrigatorios;
    lblProductTypeSelecionado.Caption := 'Categoria selecionada: ' + FProductTypeEscolhido;
    edtSku.Text := Format('SKU-%s', [FormatDateTime('yyyymmddhhnnss', Now)]);
    edtNome.Clear;
    mmBulletPoints.Clear;
    edtMarca.Clear;
    edtPaisOrigem.Text := 'BR';
    mmDescricao.Clear;
    cbTipoCodigoBarras.ItemIndex := 0;
    edtCodigoBarras.Clear;
    edtPreco.Text := '10,00';
    edtEstoque.Text := '5';
    MontarJSON;
    MostrarPasso(2);
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdBuscarCatalogoClick(Sender: TObject);
var
  Cliente: TAmazonSPAPIClient;
  Erro, Descricao: string;
  I: Integer;
begin
  if Trim(edtBuscaCatalogo.Text) = '' then
  begin
    ShowMessage('Digite uma palavra-chave pra buscar no catalogo da Amazon.');
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    lstResultadosCatalogo.Clear;
    SetLength(FCatalogItems, 0);
    Log('Buscando "' + Trim(edtBuscaCatalogo.Text) + '" no catalogo geral da Amazon...');
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.SearchCatalogItems(FToken, Trim(edtBuscaCatalogo.Text), FCatalogItems, Erro) then
      begin
        Log('Falha ao buscar no catalogo: ' + Erro);
        ShowMessage('Falha ao buscar no catalogo: ' + Erro);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
    if Length(FCatalogItems) = 0 then
    begin
      Log('Nenhum produto parecido encontrado no catalogo - pode seguir com o cadastro do zero.');
      Exit;
    end;
    for I := 0 to High(FCatalogItems) do
    begin
      Descricao := FCatalogItems[I].ASIN + ' - ' + FCatalogItems[I].Titulo;
      if FCatalogItems[I].Marca <> '' then
        Descricao := Descricao + ' (' + FCatalogItems[I].Marca + ')';
      lstResultadosCatalogo.Items.Add(Descricao);
    end;
    Log(Format('%d produto(s) parecido(s) encontrado(s) no catalogo - se algum bater, ' +
      'selecione e clique em "Usar ASIN selecionado" (bem mais simples, sem precisar de ' +
      'codigo de barras).', [Length(FCatalogItems)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdUsarASINExistenteClick(Sender: TObject);
var
  ASINEscolhido: string;
begin
  if lstResultadosCatalogo.ItemIndex < 0 then
  begin
    ShowMessage('Selecione um produto na lista de resultados do catalogo primeiro.');
    Exit;
  end;
  ASINEscolhido := FCatalogItems[lstResultadosCatalogo.ItemIndex].ASIN;
  if MessageDlg('Fechar esse cadastro do zero e abrir a tela "Produto ja existe" ja com o ASIN ' +
       ASINEscolhido + ' preenchido?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if TFrmCadastrarProdutoMarketplace.AbrirParaLoja(FLoja, FCodMarketplace, FAccountID, FToken,
       FDevClientId, FDevClientSecret, FSandbox, ASINEscolhido) then
    FCadastrouAlgo := True;
  // Fecha esta tela - o cadastro (se aconteceu) ja foi feito na outra tela.
  ModalResult := mrCancel;
end;
procedure TFrmCadastrarProdutoAmazonNovo.ExtrairAtributosObrigatorios;
var
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
  RequiredArr: TJSONArray;
  I: Integer;
  ListaTexto: string;
begin
  SetLength(FAtributosObrigatorios, 0);
  JSONValue := TJSONObject.ParseJSONValue(FSchemaJSON);
  try
    if not (JSONValue is TJSONObject) then
    begin
      Log('AVISO: o schema baixado nao e um JSON valido - nao foi possivel ' +
        'extrair os atributos obrigatorios automaticamente.');
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if not JSONObj.TryGetValue<TJSONArray>('required', RequiredArr) then
    begin
      Log('AVISO: o schema nao trouxe uma lista "required" no nivel raiz - ' +
        'use "Ver Schema Completo" pra conferir a estrutura real desse productType.');
      Exit;
    end;
    SetLength(FAtributosObrigatorios, RequiredArr.Count);
    ListaTexto := '';
    for I := 0 to RequiredArr.Count - 1 do
    begin
      FAtributosObrigatorios[I] := RequiredArr.Items[I].Value;
      if ListaTexto <> '' then
        ListaTexto := ListaTexto + ', ';
      ListaTexto := ListaTexto + FAtributosObrigatorios[I];
    end;
    Log(Format('%d atributo(s) obrigatorio(s) segundo o schema: %s',
      [Length(FAtributosObrigatorios), ListaTexto]));
  finally
    JSONValue.Free;
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.MontarJSON;
const
  // language_tag exigido pela Amazon em atributos de texto localizado
  // (item_name, bullet_point, product_description, brand em algumas
  // categorias) - SEM esse campo a Amazon devolve HTTP 400 generico
  // "Request has missing or invalid parameters and cannot be parsed"
  // (confirmado comparando com a documentacao oficial: o exemplo la' tem
  // "language_tag" em item_name e a gente nao tinha).
  LANGUAGE_TAG_BR = 'pt_BR';
var
  Root, ItemNameVal, BulletVal, CondVal, FulfillVal, OfferVal, PriceVal,
    ScheduleVal, SkeletonVal, BrandVal, CountryVal, DescVal, ShippingVal,
    BarcodeVal: TJSONObject;
  ItemNameArr, BulletArr, CondArr, FulfillArr, OfferArr, ScheduleArr,
    OurPriceArr, SkeletonArr, BrandArr, CountryArr, DescArr, ShippingArr,
    BarcodeArr: TJSONArray;
  Linha: string;
  I: Integer;
  Preco: Double;
  Estoque: Integer;
  Atrib: string;
  JaCoberto: Boolean;
  TemMarca, TemPaisOrigem, TemDescricao, TemCodigoBarras, TemBrowseNode: Boolean;
begin
  if not ParseValorDecimal(edtPreco.Text, Preco) then
    Preco := 0;
  Estoque := StrToIntDef(edtEstoque.Text, 0);
  TemMarca := Trim(edtMarca.Text) <> '';
  TemPaisOrigem := Trim(edtPaisOrigem.Text) <> '';
  TemDescricao := Trim(mmDescricao.Text) <> '';
  TemCodigoBarras := Trim(edtCodigoBarras.Text) <> '';
  TemBrowseNode := False;
  Root := TJSONObject.Create;
  try
    // item_name - "language_tag" e' obrigatorio junto com value/marketplace_id.
    ItemNameArr := TJSONArray.Create;
    ItemNameVal := TJSONObject.Create;
    ItemNameVal.AddPair('value', Trim(edtNome.Text));
    ItemNameVal.AddPair('language_tag', LANGUAGE_TAG_BR);
    ItemNameVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
    ItemNameArr.AddElement(ItemNameVal);
    Root.AddPair('item_name', ItemNameArr);
    // bullet_point - um item de array por linha nao-vazia do memo, tambem
    // com language_tag.
    BulletArr := TJSONArray.Create;
    for I := 0 to mmBulletPoints.Lines.Count - 1 do
    begin
      Linha := Trim(mmBulletPoints.Lines[I]);
      if Linha <> '' then
      begin
        BulletVal := TJSONObject.Create;
        BulletVal.AddPair('value', Linha);
        BulletVal.AddPair('language_tag', LANGUAGE_TAG_BR);
        BulletVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
        BulletArr.AddElement(BulletVal);
      end;
    end;
    if BulletArr.Count > 0 then
      Root.AddPair('bullet_point', BulletArr)
    else
      BulletArr.Free;
    // brand - campo novo (Marca), so entra se preenchido.
    if TemMarca then
    begin
      BrandArr := TJSONArray.Create;
      BrandVal := TJSONObject.Create;
      BrandVal.AddPair('value', Trim(edtMarca.Text));
      BrandVal.AddPair('language_tag', LANGUAGE_TAG_BR);
      BrandVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
      BrandArr.AddElement(BrandVal);
      Root.AddPair('brand', BrandArr);
    end;
    // country_of_origin - campo novo (Pais de Origem), so entra se
    // preenchido - NAO leva language_tag (e' um codigo, nao texto livre).
    if TemPaisOrigem then
    begin
      CountryArr := TJSONArray.Create;
      CountryVal := TJSONObject.Create;
      CountryVal.AddPair('value', Trim(edtPaisOrigem.Text));
      CountryVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
      CountryArr.AddElement(CountryVal);
      Root.AddPair('country_of_origin', CountryArr);
    end;
    // product_description - campo novo (Descricao), so entra se preenchido.
    if TemDescricao then
    begin
      DescArr := TJSONArray.Create;
      DescVal := TJSONObject.Create;
      DescVal.AddPair('value', Trim(mmDescricao.Text));
      DescVal.AddPair('language_tag', LANGUAGE_TAG_BR);
      DescVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
      DescArr.AddElement(DescVal);
      Root.AddPair('product_description', DescArr);
    end;
    // externally_assigned_product_identifier - campo novo (Codigo de
    // Barras), so entra se preenchido. "type" tem que ser exatamente
    // "ean"/"gtin"/"upc" (minusculo) - por isso o combo ja da os valores
    // certos em vez de deixar o usuario digitar.
    if TemCodigoBarras then
    begin
      BarcodeArr := TJSONArray.Create;
      BarcodeVal := TJSONObject.Create;
      BarcodeVal.AddPair('type', LowerCase(Trim(cbTipoCodigoBarras.Text)));
      BarcodeVal.AddPair('value', Trim(edtCodigoBarras.Text));
      BarcodeVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
      BarcodeArr.AddElement(BarcodeVal);
      Root.AddPair('externally_assigned_product_identifier', BarcodeArr);
    end;
    // condition_type - "new_new" = produto novo (mesmo padrao ja usado em
    // CreateOfferForExistingASIN).
    CondArr := TJSONArray.Create;
    CondVal := TJSONObject.Create;
    CondVal.AddPair('value', 'new_new');
    CondVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
    CondArr.AddElement(CondVal);
    Root.AddPair('condition_type', CondArr);
    // fulfillment_availability - estoque (canal DEFAULT = vendedor cuida
    // do envio, nao FBA).
    FulfillArr := TJSONArray.Create;
    FulfillVal := TJSONObject.Create;
    FulfillVal.AddPair('fulfillment_channel_code', 'DEFAULT');
    FulfillVal.AddPair('quantity', TJSONNumber.Create(Estoque));
    FulfillArr.AddElement(FulfillVal);
    Root.AddPair('fulfillment_availability', FulfillArr);
    // merchant_shipping_group - {ATENCAO} atributo obrigatorio CONDICIONAL
    // (regra "allOf" no schema, nao aparece na lista "required" simples
    // que a gente le em ExtrairAtributosObrigatorios) sempre que
    // fulfillment_channel_code = "DEFAULT" (autoatendimento pelo
    // vendedor, nao FBA) - como e' sempre o nosso caso aqui, adiciona
    // incondicionalmente. O valor "legacy-template-id" e' o modelo de
    // envio padrao da Amazon - se a conta tiver modelos de envio
    // proprios configurados, o schema baixado (Ver Schema Completo) vai
    // listar outros valores validos no enum de
    // "merchant_shipping_group.items.properties.value.enum".
    ShippingArr := TJSONArray.Create;
    ShippingVal := TJSONObject.Create;
    ShippingVal.AddPair('value', 'legacy-template-id');
    ShippingVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
    ShippingArr.AddElement(ShippingVal);
    Root.AddPair('merchant_shipping_group', ShippingArr);
    // purchasable_offer - preco de venda. Inclui "audience" - sem esse
    // campo a Amazon aceita o PUT mas a oferta fica incompleta e nao
    // aparece pra venda (bug ja corrigido no CreateOfferForExistingASIN).
    ScheduleVal := TJSONObject.Create;
    ScheduleVal.AddPair('value_with_tax', TJSONNumber.Create(Preco));
    ScheduleArr := TJSONArray.Create;
    ScheduleArr.AddElement(ScheduleVal);
    PriceVal := TJSONObject.Create;
    PriceVal.AddPair('schedule', ScheduleArr);
    OfferVal := TJSONObject.Create;
    OfferVal.AddPair('currency', 'BRL');
    OfferVal.AddPair('audience', 'ALL');
    OurPriceArr := TJSONArray.Create;
    OurPriceArr.AddElement(PriceVal);
    OfferVal.AddPair('our_price', OurPriceArr);
    OfferVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
    OfferArr := TJSONArray.Create;
    OfferArr.AddElement(OfferVal);
    Root.AddPair('purchasable_offer', OfferArr);
    // Esqueleto pros demais atributos que o SCHEMA marcou como
    // obrigatorios e que a tela ainda nao sabe montar sozinha - ATENCAO:
    // o formato "[{"value":"", "marketplace_id":...}]" e' um CHUTE
    // (funciona pra atributos simples de texto/numero, mas NAO funciona
    // pra atributos compostos como imagens, GTIN/EAN, dimensoes etc -
    // esses precisam de ajuste manual aqui no JSON antes de cadastrar;
    // use "Ver Schema Completo" pra conferir o formato exato exigido).
    for Atrib in FAtributosObrigatorios do
    begin
      JaCoberto := SameText(Atrib, 'item_name') or SameText(Atrib, 'bullet_point') or
        SameText(Atrib, 'condition_type') or SameText(Atrib, 'fulfillment_availability') or
        SameText(Atrib, 'purchasable_offer') or SameText(Atrib, 'merchant_shipping_group') or
        (SameText(Atrib, 'brand') and TemMarca) or
        (SameText(Atrib, 'country_of_origin') and TemPaisOrigem) or
        (SameText(Atrib, 'product_description') and TemDescricao) or
        (SameText(Atrib, 'externally_assigned_product_identifier') and TemCodigoBarras);
      if not JaCoberto then
      begin
        if SameText(Atrib, 'supplier_declared_dg_hz_regulation') then
        begin
          // "not_applicable" e' o valor mais comum pra declarar "isso NAO
          // e' produto perigoso/regulado" - funciona pra maioria das
          // categorias, mas ALGUMAS usam um enum diferente. Confira em
          // "Ver Schema Completo" se a categoria escolhida aceita esse
          // valor antes de cadastrar.
          SkeletonArr := TJSONArray.Create;
          SkeletonVal := TJSONObject.Create;
          SkeletonVal.AddPair('value', 'not_applicable');
          SkeletonVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
          SkeletonArr.AddElement(SkeletonVal);
          Root.AddPair(Atrib, SkeletonArr);
        end
        else
        begin
          if SameText(Atrib, 'recommended_browse_nodes') then
            TemBrowseNode := True;
          SkeletonArr := TJSONArray.Create;
          SkeletonVal := TJSONObject.Create;
          SkeletonVal.AddPair('value', '');
          SkeletonVal.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
          SkeletonArr.AddElement(SkeletonVal);
          Root.AddPair(Atrib, SkeletonArr);
        end;
      end;
    end;
    mmAtributosJSON.Text := Root.ToJSON;
  finally
    Root.Free;
  end;
  Log('JSON de atributos (re)montado. Revise os campos com "" antes de cadastrar ' +
    '- "Ver Schema Completo" mostra o formato exato exigido por cada atributo.');
  if TemBrowseNode then
    Log('ATENCAO: "recommended_browse_nodes" precisa de um ID de categoria (browse node) ' +
      'valido da Amazon - ficou vazio no esqueleto porque nao da pra adivinhar. Pesquise o ' +
      'browse node certo pra essa categoria (Seller Central ou documentacao da Amazon) e ' +
      'edite manualmente no JSON antes de cadastrar.');
  if not TemCodigoBarras then
    Log('ATENCAO: nenhum codigo de barras informado - a Amazon vai exigir OU o codigo de ' +
      'barras (EAN/UPC/GTIN, campo "Codigo de Barras" acima) OU um ASIN existente ' +
      '("merchant_suggested_asin", so use se for exatamente o mesmo produto) OU isencao de ' +
      'GTIN aprovada pra marca. Sem nenhum desses, o cadastro vai falhar nessa exigencia.');
end;
function TFrmCadastrarProdutoAmazonNovo.MontarEsqueletoAtributo(
  const ASchemaRoot: TJSONObject; const AAttrName: string): TJSONArray;
var
  Props, AttrDef, ItemsDef, ItemProps, SubPropDef: TJSONObject;
  RequiredArr, EnumArr: TJSONArray;
  ItemObj: TJSONObject;
  I: Integer;
  SubPropName, SubPropType: string;
begin
  Result := TJSONArray.Create;
  ItemObj := TJSONObject.Create;
  Result.AddElement(ItemObj);
  ItemObj.AddPair('marketplace_id', uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
  // Sem "properties.<AAttrName>.items.properties/required" no schema, fica
  // so' com marketplace_id mesmo - melhor que nada, mas provavelmente vai
  // precisar de ajuste manual (atributo com estrutura fora do padrao).
  if not ASchemaRoot.TryGetValue<TJSONObject>('properties', Props) then Exit;
  if not Props.TryGetValue<TJSONObject>(AAttrName, AttrDef) then Exit;
  if not AttrDef.TryGetValue<TJSONObject>('items', ItemsDef) then Exit;
  if not ItemsDef.TryGetValue<TJSONObject>('properties', ItemProps) then Exit;
  if not ItemsDef.TryGetValue<TJSONArray>('required', RequiredArr) then Exit;
  for I := 0 to RequiredArr.Count - 1 do
  begin
    SubPropName := RequiredArr.Items[I].Value;
    if SameText(SubPropName, 'marketplace_id') then
      Continue; // ja adicionado acima
    if SameText(SubPropName, 'language_tag') then
    begin
      ItemObj.AddPair(SubPropName, 'pt_BR');
      Continue;
    end;
    if not ItemProps.TryGetValue<TJSONObject>(SubPropName, SubPropDef) then
      Continue;
    SubPropType := '';
    SubPropDef.TryGetValue<string>('type', SubPropType);
    if SubPropDef.TryGetValue<TJSONArray>('enum', EnumArr) and (EnumArr.Count > 0) then
      // {ATENCAO} primeiro valor do enum como PALPITE - revisar se e' o
      // certo pro produto (ex: "color" pode vir com "Beige" so por ser o
      // primeiro da lista, sem ter nada a ver com o produto real).
      ItemObj.AddPair(SubPropName, EnumArr.Items[0].Value)
    else if SameText(SubPropType, 'number') then
      ItemObj.AddPair(SubPropName, TJSONNumber.Create(0))
    else if SameText(SubPropType, 'boolean') then
      ItemObj.AddPair(SubPropName, TJSONBool.Create(False))
    else
      ItemObj.AddPair(SubPropName, '');
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.AdicionarAtributosFaltantes(const AIssuesJSON: string);
var
  IssuesVal, RootVal, SchemaVal: TJSONValue;
  IssuesArr, AttrNamesArr, NovoArr: TJSONArray;
  IssueObj, RootObj, SchemaRoot, PropsSchema, AttrDefSchema: TJSONObject;
  I, J: Integer;
  Severity, AttrName, Titulo: string;
  NomesAdicionados: TStringList;
begin
  IssuesVal := TJSONObject.ParseJSONValue(AIssuesJSON);
  if not (IssuesVal is TJSONArray) then
  begin
    FreeAndNil(IssuesVal);
    Exit;
  end;
  IssuesArr := TJSONArray(IssuesVal);
  RootVal := TJSONObject.ParseJSONValue(mmAtributosJSON.Text);
  if not (RootVal is TJSONObject) then
  begin
    IssuesVal.Free;
    FreeAndNil(RootVal);
    Exit;
  end;
  RootObj := TJSONObject(RootVal);
  SchemaVal := TJSONObject.ParseJSONValue(FSchemaJSON);
  if SchemaVal is TJSONObject then
    SchemaRoot := TJSONObject(SchemaVal)
  else
    SchemaRoot := nil;
  NomesAdicionados := TStringList.Create;
  try
    for I := 0 to IssuesArr.Count - 1 do
    begin
      IssueObj := IssuesArr.Items[I] as TJSONObject;
      Severity := '';
      IssueObj.TryGetValue<string>('severity', Severity);
      if not SameText(Severity, 'ERROR') then
        Continue;
      if not IssueObj.TryGetValue<TJSONArray>('attributeNames', AttrNamesArr) then
        Continue;
      for J := 0 to AttrNamesArr.Count - 1 do
      begin
        AttrName := AttrNamesArr.Items[J].Value;
        if Assigned(RootObj.GetValue(AttrName)) then
          Continue; // ja existe no JSON atual, nao mexe (pode ser erro de VALOR, nao de ausencia)
        if NomesAdicionados.IndexOf(AttrName) >= 0 then
          Continue; // ja tratado nesse mesmo loop (issue duplicada)
        if Assigned(SchemaRoot) then
          NovoArr := MontarEsqueletoAtributo(SchemaRoot, AttrName)
        else
        begin
          NovoArr := TJSONArray.Create;
          NovoArr.AddElement(TJSONObject.Create);
          TJSONObject(NovoArr.Items[0]).AddPair('value', '');
          TJSONObject(NovoArr.Items[0]).AddPair('marketplace_id',
            uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL);
        end;
        RootObj.AddPair(AttrName, NovoArr);
        NomesAdicionados.Add(AttrName);
        Titulo := AttrName;
        if Assigned(SchemaRoot) and SchemaRoot.TryGetValue<TJSONObject>('properties', PropsSchema) and
           PropsSchema.TryGetValue<TJSONObject>(AttrName, AttrDefSchema) then
          AttrDefSchema.TryGetValue<string>('title', Titulo);
        Log('Adicionado esqueleto para "' + AttrName + '" (' + Titulo +
          ') - revise/preencha o valor real antes de cadastrar de novo.');
        if SameText(AttrName, 'externally_assigned_product_identifier') or
           SameText(AttrName, 'merchant_suggested_asin') then
          Log('ATENCAO "' + AttrName + '": a Amazon so precisa de UM dos dois - ' +
            '"externally_assigned_product_identifier" (codigo de barras EAN/UPC/GTIN real do ' +
            'produto) OU "merchant_suggested_asin" (se ja existir um ASIN parecido). Sem ' +
            'nenhum codigo de barras de verdade, a alternativa e pedir isencao de GTIN pra marca ' +
            'no Seller Central (Brand Registry) - sem isso, o cadastro vai continuar falhando ' +
            'pra esse atributo mesmo com o esqueleto preenchido.');
      end;
    end;
    if NomesAdicionados.Count > 0 then
    begin
      mmAtributosJSON.Text := RootObj.ToJSON;
      ShowMessage(Format('%d atributo(s) apontado(s) pela Amazon como faltando foram ' +
        'adicionados automaticamente ao JSON (com valor de exemplo do enum quando existia). ' +
        'Role o log acima pra ver a lista com os nomes em portugues, revise/preencha os valores ' +
        'reais no JSON e clique em "Cadastrar Produto" de novo.', [NomesAdicionados.Count]));
    end;
  finally
    NomesAdicionados.Free;
    RootObj.Free;
    IssuesVal.Free;
    if Assigned(SchemaVal) then
      SchemaVal.Free;
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdMontarJSONClick(Sender: TObject);
begin
  if mmAtributosJSON.Text <> '' then
    if MessageDlg('Isso vai substituir o JSON atual (inclusive edicoes manuais) ' +
         'pelo esqueleto gerado a partir dos campos acima. Continuar?',
         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  MontarJSON;
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdVerSchemaClick(Sender: TObject);
var
  ArquivoTemp: string;
begin
  if FSchemaJSON = '' then
  begin
    ShowMessage('Nenhum schema carregado ainda - volte ao passo 1 e escolha uma categoria.');
    Exit;
  end;
  ArquivoTemp := TPath.Combine(TPath.GetTempPath,
    'amazon_schema_' + FProductTypeEscolhido + '.json');
  TFile.WriteAllText(ArquivoTemp, FSchemaJSON, TEncoding.UTF8);
  Log('Schema completo salvo em: ' + ArquivoTemp);
  ShellExecute(0, 'open', PChar(ArquivoTemp), nil, nil, SW_SHOWNORMAL);
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdVoltarClick(Sender: TObject);
begin
  MostrarPasso(1);
end;
procedure TFrmCadastrarProdutoAmazonNovo.CmdCadastrarClick(Sender: TObject);
var
  Cliente: TAmazonSPAPIClient;
  Erro, RespostaJSON, IssuesJSON: string;
  Preco: Double;
  Estoque: Integer;
  TesteJSON: TJSONValue;
begin
  if Trim(edtSku.Text) = '' then
  begin
    ShowMessage('Informe o SKU do produto.');
    Exit;
  end;
  if Trim(edtNome.Text) = '' then
  begin
    ShowMessage('Informe o nome do produto.');
    Exit;
  end;
  if not ParseValorDecimal(edtPreco.Text, Preco) or (Preco <= 0) then
  begin
    ShowMessage('Informe um preco valido (maior que zero).');
    Exit;
  end;
  Estoque := StrToIntDef(edtEstoque.Text, -1);
  if Estoque < 0 then
  begin
    ShowMessage('Informe um estoque valido (0 ou maior).');
    Exit;
  end;
  // Valida que o JSON no memo ainda e' um JSON valido antes de gastar uma
  // chamada de API - o usuario pode ter editado o texto na mao.
  TesteJSON := TJSONObject.ParseJSONValue(mmAtributosJSON.Text);
  if not Assigned(TesteJSON) or not (TesteJSON is TJSONObject) then
  begin
    FreeAndNil(TesteJSON);
    ShowMessage('O JSON de atributos esta invalido - revise a sintaxe (chaves, ' +
      'colchetes e virgulas) antes de cadastrar.');
    Exit;
  end;
  TesteJSON.Free;
  Screen.Cursor := crHourGlass;
  try
    Log('Cadastrando produto novo "' + Trim(edtNome.Text) + '" (productType ' +
      FProductTypeEscolhido + ') na Amazon' + IfThen(FSandbox, ' (Sandbox)', '') + '...');
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.CreateNewProduct(FToken, FAccountID, Trim(edtSku.Text),
           FProductTypeEscolhido, mmAtributosJSON.Text, RespostaJSON, IssuesJSON, Erro) then
      begin
        Log('Falha ao cadastrar produto novo: ' + Erro);
        if IssuesJSON <> '' then
        begin
          // Fluxo iterativo: a Amazon aponta o que falta (issues), a tela
          // ja prepara o esqueleto de cada atributo faltante no JSON -
          // usuario so revisa/preenche os valores reais e tenta de novo.
          AdicionarAtributosFaltantes(IssuesJSON)
        end
        else
          ShowMessage('Falha ao cadastrar produto novo: ' + Erro + sLineBreak +
            'Revise o JSON de atributos e tente novamente.');
        Exit;
      end;
      Log('Produto novo criado/enviado com sucesso! SKU: ' + Trim(edtSku.Text));
      if IssuesJSON <> '' then
        Log('Issues retornadas pela Amazon (revise se sao so avisos): ' + IssuesJSON);
    finally
      Cliente.Free;
    end;
    // {ATENCAO} Mesmo padrao do CreateOfferForExistingASIN: a Amazon
    // processa de forma assincrona, pode levar alguns minutos pra
    // aparecer disponivel de fato.
    GravarProdutoMarketplace(Trim(edtSku.Text), Trim(edtNome.Text), Estoque, Preco);
    FCadastrouAlgo := True;
    if MessageDlg('Produto novo enviado para processamento na Amazon!' + sLineBreak +
         'Pode levar alguns minutos para aparecer disponivel para venda.' + sLineBreak +
         'Deseja cadastrar outro produto agora?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      MostrarPasso(1);
      edtKeywords.Clear;
      lstProductTypes.Clear;
    end
    else
      ModalResult := mrOk;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmCadastrarProdutoAmazonNovo.GravarProdutoMarketplace(
  const ACodProdutoNoMarketplace, ANome: string; const AEstoque: Integer;
  const APreco: Double);
var
  Qry: TFDQuery;
  NovoCodigo: Integer;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // {TODO} Placeholder de geracao de codigo - se existir um GEN_ID
    // proprio pra essa tabela no banco, trocar por:
    // SELECT GEN_ID(GEN_NOME_AQUI, 1) FROM RDB$DATABASE
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
procedure TFrmCadastrarProdutoAmazonNovo.CmdFecharClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;
end.
