// ============================================================================
// UNIT: uFrmCadastrarProdutoMercadoLivreNovo
// OBJETIVO: Tela pra publicar um anuncio NOVO no Mercado Livre - mesmo
// papel da uFrmCadastrarProdutoAmazonNovo, so' que pro fluxo do ML.
//
// FLUXO EM 2 PASSOS (mesmo padrao da tela da Amazon):
//   Passo 1: usuario digita o titulo/descricao curta do produto (ex:
//   "clipe de papel niquelado 50mm"), a tela chama o PREDITOR DE CATEGORIA
//   (PredictCategory / domain_discovery) e lista as categorias candidatas.
//
//   Passo 2: ao escolher a categoria, a tela baixa os atributos daquela
//   categoria (GetCategoryAttributes) e monta automaticamente o JSON do
//   array "attributes" com:
//     - o que o proprio preditor ja deduziu do texto (BRAND/MODEL/LINE com
//       value_id pronto - aproveitado direto, e' a parte mais confiavel);
//     - um esqueleto {"id":"X","value_name":""} pra cada atributo marcado
//       como obrigatorio que o preditor nao preencheu.
//   O usuario revisa/edita esse JSON no memo antes de publicar. O botao
//   "Ver Atributos da Categoria" abre a lista completa (arquivo .json
//   temporario) pra conferir formato e valores aceitos de cada atributo.
//
// DIFERENCAS IMPORTANTES EM RELACAO A AMAZON (valem pra quem for dar
// manutencao):
//   1. NAO precisa de GTIN/EAN nem isencao pra publicar - o vendedor
//      publica com o proprio ID de anuncio (MLB...). Aquela parede de
//      "ASIN generico restrito" que travou o teste na Amazon nao existe aqui.
//   2. A DESCRICAO nao vai no corpo da criacao - e' uma segunda chamada
//      (SetItemDescription), so' com TEXTO PLANO. Por isso o cadastro aqui
//      sao 2 chamadas, e a descricao falhar NAO desfaz o anuncio (que ja
//      foi criado) - a tela avisa e segue.
//   3. listing_type_id (tipo de anuncio) afeta CUSTO DE VENDA e exposicao,
//      e a disponibilidade depende da conta + categoria. Por isso a tela
//      consulta (CheckListingTypeAvailable) antes de publicar e mostra o
//      motivo quando o tipo escolhido nao esta liberado.
//
// {LIMITACAO CONHECIDA} Variacoes (cor/tamanho como itens separados dentro
// do mesmo anuncio) NAO sao suportadas aqui - o payload muda de forma
// (array "variations" com attribute_combinations, e o estoque/preco passa
// pra dentro de cada variacao). Mesma decisao ja tomada na tela da Amazon:
// primeira versao cobre o produto simples. Atributos marcados com
// allow_variations continuam podendo ser preenchidos como atributo normal
// do anuncio - o que nao da' pra fazer e' publicar VARIAS combinacoes.
//
// {ATENCAO} Imagens precisam ser URLs PUBLICAS (o Mercado Livre baixa a
// imagem da URL que voce informar) - nao ha upload de arquivo local pela
// API, mesmo caso da Amazon.
//
// Ao ter sucesso, grava o anuncio em PRODUTOS_MARKETPLACE - SEM vinculo
// com produto fisico ainda, mesmo padrao do resto do projeto.
// ============================================================================
unit uFrmCadastrarProdutoMercadoLivreNovo;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.Variants, System.Classes, System.StrUtils, System.IOUtils,
  System.JSON, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons, Data.DB, FireDAC.Comp.Client,
  DMZ, uMarketplace, MercadoLivre.OpenAPI.Client;

type
  TFrmCadastrarProdutoMercadoLivreNovo = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    // --- Passo 1: preditor de categoria ---
    lblBuscaCategoria: TLabel;
    edtBuscaCategoria: TEdit;
    CmdPreverCategoria: TBitBtn;
    lstCategorias: TListBox;
    CmdProximoPasso1: TBitBtn;
    // --- Passo 2: campos do anuncio + JSON de atributos ---
    lblCategoriaSelecionada: TLabel;
    lblSku: TLabel;
    edtSku: TEdit;
    lblNome: TLabel;
    edtNome: TEdit;
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
    procedure CmdMontarJSONClick(Sender: TObject);
    procedure CmdVerAtributosClick(Sender: TObject);
    procedure CmdVoltarClick(Sender: TObject);
    procedure CmdCadastrarClick(Sender: TObject);
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
    // Resultado da ultima previsao de categoria (passo 1) - o indice
    // selecionado em lstCategorias indexa este array.
    FCategorias: TMercadoLivreCategoriaSugeridaArray;
    // Categoria escolhida no passo 1.
    FCategoryIdEscolhida: string;
    FCategoryNomeEscolhida: string;
    // Atributos que o preditor ja deduziu pra categoria escolhida (JSON
    // cru do array "attributes" da sugestao) - aproveitado no MontarJSON.
    FAtributosPreditosJSON: string;
    // Atributos da categoria escolhida + o JSON cru (pro "Ver Atributos").
    FAtributosCategoria: TMercadoLivreAtributoArray;
    FAtributosRawJSON: string;
    procedure Log(const AMsg: string);
    function ParseValorDecimal(const ATexto: string; out AValor: Double): Boolean;
    // So chamado explicitamente pelo AbrirParaLoja, DEPOIS que os campos
    // ja foram atribuidos - o FormCreate roda dentro do TForm.Create,
    // antes disso (mesmo cuidado que corrigiu o bug original na
    // uFrmCadastrarProdutoMarketplace).
    procedure Inicializar;
    procedure MostrarPasso(const APasso: Integer);
    procedure MontarJSON;
    // Monta o corpo completo do POST /items a partir dos campos da tela +
    // do JSON de atributos revisado pelo usuario.
    function MontarBodyAnuncio(out ABodyJSON, AErro: string): Boolean;
    procedure GravarProdutoMarketplace(const ACodProdutoNoMarketplace, ANome: string;
      const AEstoque: Integer; const APreco: Double);
  public
    class function AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
      const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
      const ASandbox: Boolean): Boolean;
  end;

implementation

{$R *.dfm}

class function TFrmCadastrarProdutoMercadoLivreNovo.AbrirParaLoja(
  const ALoja, ACodMarketplace: Integer; const AAccountID, AToken: string;
  const ADevClientId, ADevClientSecret: string; const ASandbox: Boolean): Boolean;
var
  Frm: TFrmCadastrarProdutoMercadoLivreNovo;
begin
  Frm := TFrmCadastrarProdutoMercadoLivreNovo.Create(Application);
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

procedure TFrmCadastrarProdutoMercadoLivreNovo.FormCreate(Sender: TObject);
begin
  // Vazio de proposito: toda a montagem depende de FLoja/FCodMarketplace/
  // FToken etc, que ainda NAO foram atribuidos quando o OnCreate dispara.
  // Ver Inicializar, chamado pelo AbrirParaLoja.
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;

function TFrmCadastrarProdutoMercadoLivreNovo.ParseValorDecimal(const ATexto: string;
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

procedure TFrmCadastrarProdutoMercadoLivreNovo.Inicializar;
begin
  lblTitulo.Caption := 'Incluir Produto Novo - Mercado Livre';
  edtBuscaCategoria.Clear;
  lstCategorias.Clear;
  SetLength(FCategorias, 0);
  FCategoryIdEscolhida := '';
  FCategoryNomeEscolhida := '';
  FAtributosPreditosJSON := '';
  SetLength(FAtributosCategoria, 0);
  FAtributosRawJSON := '';

  // Valores aceitos em "condition" - os dois usados no dia a dia. A lista
  // exata permitida varia por categoria (o atributo ITEM_CONDITION do
  // GET /categories/{id}/attributes diz quais valem), por isso o botao
  // "Ver Atributos da Categoria" e' o lugar de conferir em caso de recusa.
  cbCondicao.Items.Clear;
  cbCondicao.Items.Add('new');
  cbCondicao.Items.Add('used');
  cbCondicao.ItemIndex := 0;

  // Tipos de anuncio mais comuns no Brasil. {ATENCAO} a disponibilidade
  // depende da CONTA e da CATEGORIA - antes de publicar, a tela consulta
  // CheckListingTypeAvailable e mostra o motivo quando nao esta liberado
  // (ex: "free" costuma ser bloqueado pra quem ja tem historico de vendas).
  cbTipoAnuncio.Items.Clear;
  cbTipoAnuncio.Items.Add('gold_special');
  cbTipoAnuncio.Items.Add('gold_pro');
  cbTipoAnuncio.Items.Add('free');
  cbTipoAnuncio.ItemIndex := 0;

  edtGarantia.Text := '';
  mmImagens.Clear;
  mmDescricao.Clear;
  mmAtributosJSON.Clear;

  MostrarPasso(1);
  Log('Pronto. Digite o titulo do produto pra o Mercado Livre sugerir a categoria.');
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.MostrarPasso(const APasso: Integer);
begin
  // Passo 1 - preditor de categoria.
  lblBuscaCategoria.Visible := APasso = 1;
  edtBuscaCategoria.Visible := APasso = 1;
  CmdPreverCategoria.Visible := APasso = 1;
  lstCategorias.Visible := APasso = 1;
  CmdProximoPasso1.Visible := APasso = 1;
  // Passo 2 - campos do anuncio + JSON de atributos.
  lblCategoriaSelecionada.Visible := APasso = 2;
  lblSku.Visible := APasso = 2;
  edtSku.Visible := APasso = 2;
  lblNome.Visible := APasso = 2;
  edtNome.Visible := APasso = 2;
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

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdPreverCategoriaClick(Sender: TObject);
var
  Cliente: TMercadoLivreOpenAPIClient;
  ErroMsg: string;
  I: Integer;
begin
  if Trim(edtBuscaCategoria.Text) = '' then
  begin
    ShowMessage('Digite o titulo/descricao do produto pra buscar a categoria.');
    Exit;
  end;

  lstCategorias.Clear;
  SetLength(FCategorias, 0);

  Screen.Cursor := crHourGlass;
  try
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      '', FSandbox);
    Cliente.OnLog := Log;
    try
      // limit=3: recomendacao da propria doc, pra dar opcoes ao vendedor
      // igual a experiencia do site.
      if not Cliente.PredictCategory(FToken, 'MLB', Trim(edtBuscaCategoria.Text), 3,
           FCategorias, ErroMsg) then
      begin
        Log('Erro ao prever categoria: ' + ErroMsg);
        ShowMessage('Erro ao prever categoria: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;

    if Length(FCategorias) = 0 then
    begin
      Log('Nenhuma categoria sugerida - tente um texto mais especifico ' +
        '(ex: incluir marca e tipo do produto).');
      Exit;
    end;

    for I := Low(FCategorias) to High(FCategorias) do
      lstCategorias.Items.Add(FCategorias[I].CategoryName + '  [' +
        FCategorias[I].CategoryId + ']  -  ' + FCategorias[I].DomainName);
    lstCategorias.ItemIndex := 0;
    Log(Format('%d categoria(s) sugerida(s). Escolha uma e clique em Continuar.',
      [Length(FCategorias)]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdProximoPasso1Click(Sender: TObject);
var
  Cliente: TMercadoLivreOpenAPIClient;
  ErroMsg: string;
  Idx: Integer;
begin
  Idx := lstCategorias.ItemIndex;
  if (Idx < 0) or (Idx > High(FCategorias)) then
  begin
    ShowMessage('Selecione uma categoria na lista primeiro.');
    Exit;
  end;

  FCategoryIdEscolhida := FCategorias[Idx].CategoryId;
  FCategoryNomeEscolhida := FCategorias[Idx].CategoryName;
  FAtributosPreditosJSON := FCategorias[Idx].AtributosPreditosJSON;

  Screen.Cursor := crHourGlass;
  try
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.GetCategoryAttributes(FToken, FCategoryIdEscolhida,
           FAtributosCategoria, FAtributosRawJSON, ErroMsg) then
      begin
        Log('Erro ao buscar atributos da categoria: ' + ErroMsg);
        ShowMessage('Erro ao buscar atributos da categoria: ' + ErroMsg);
        Exit;
      end;
    finally
      Cliente.Free;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  lblCategoriaSelecionada.Caption := 'Categoria: ' + FCategoryNomeEscolhida +
    ' (' + FCategoryIdEscolhida + ')';
  // Aproveita o texto da busca como titulo inicial - normalmente e' quase
  // o titulo final mesmo.
  if Trim(edtNome.Text) = '' then
    edtNome.Text := Trim(edtBuscaCategoria.Text);
  // SKU sugerido no mesmo formato ja usado na tela da Amazon.
  if Trim(edtSku.Text) = '' then
    edtSku.Text := 'SKU-' + FormatDateTime('yyyymmddhhnnss', Now);

  MostrarPasso(2);
  MontarJSON;
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.MontarJSON;
var
  AttrsArr, PreditosArr: TJSONArray;
  AttrObj: TJSONObject;
  Raiz: TJSONValue;
  I, J, QtdObrig, QtdPreditos: Integer;
  JaPreenchidos: TArray<string>;
  Achou: Boolean;
  IdPredito: string;
begin
  AttrsArr := TJSONArray.Create;
  try
    SetLength(JaPreenchidos, 0);
    QtdPreditos := 0;

    // 1) Aproveita o que o preditor ja deduziu (BRAND/MODEL/LINE com
    // value_id pronto). Essa e' a parte mais confiavel do JSON - veio do
    // proprio Mercado Livre analisando o texto que voce digitou.
    if Trim(FAtributosPreditosJSON) <> '' then
    begin
      Raiz := TJSONObject.ParseJSONValue(FAtributosPreditosJSON);
      if Assigned(Raiz) then
      try
        if Raiz is TJSONArray then
        begin
          PreditosArr := TJSONArray(Raiz);
          for I := 0 to PreditosArr.Count - 1 do
            if PreditosArr.Items[I] is TJSONObject then
            begin
              IdPredito := '';
              TJSONObject(PreditosArr.Items[I]).TryGetValue<string>('id', IdPredito);
              if IdPredito = '' then
                Continue;
              // Clona pelo texto - evita mexer no dono do objeto original.
              AttrsArr.AddElement(TJSONObject.ParseJSONValue(
                PreditosArr.Items[I].ToJSON) as TJSONObject);
              SetLength(JaPreenchidos, Length(JaPreenchidos) + 1);
              JaPreenchidos[High(JaPreenchidos)] := IdPredito;
              Inc(QtdPreditos);
            end;
        end;
      finally
        Raiz.Free;
      end;
    end;

    // 2) Esqueleto pros atributos OBRIGATORIOS que o preditor nao cobriu.
    // Usa value_name (texto livre) porque e' o unico formato que serve pra
    // qualquer value_type; quando o atributo for do tipo lista, o usuario
    // deve trocar por um dos valores aceitos (ver "Ver Atributos da
    // Categoria") - de preferencia usando "value_id", que e' o formato que
    // o Mercado Livre casa com mais precisao.
    QtdObrig := 0;
    for I := Low(FAtributosCategoria) to High(FAtributosCategoria) do
    begin
      if not FAtributosCategoria[I].Obrigatorio then
        Continue;
      Achou := False;
      for J := Low(JaPreenchidos) to High(JaPreenchidos) do
        if SameText(JaPreenchidos[J], FAtributosCategoria[I].Id) then
        begin
          Achou := True;
          Break;
        end;
      if Achou then
        Continue;

      AttrObj := TJSONObject.Create;
      AttrObj.AddPair('id', FAtributosCategoria[I].Id);
      AttrObj.AddPair('value_name', '');
      AttrsArr.AddElement(AttrObj);
      Inc(QtdObrig);
      Log('  Atributo obrigatorio a preencher: ' + FAtributosCategoria[I].Id +
        ' (' + FAtributosCategoria[I].Nome + ') - tipo ' +
        FAtributosCategoria[I].ValueType);
    end;

    mmAtributosJSON.Lines.Text := AttrsArr.Format(2);
  finally
    AttrsArr.Free;
  end;

  Log(Format('JSON de atributos montado: %d ja preenchido(s) pelo preditor, ' +
    '%d obrigatorio(s) esperando valor.', [QtdPreditos, QtdObrig]));
  if QtdObrig > 0 then
    Log('Preencha os value_name vazios antes de publicar - o Mercado Livre ' +
      'recusa o anuncio com atributo obrigatorio em branco.');
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdMontarJSONClick(Sender: TObject);
begin
  if FCategoryIdEscolhida = '' then
  begin
    ShowMessage('Escolha a categoria primeiro.');
    Exit;
  end;
  MontarJSON;
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdVerAtributosClick(Sender: TObject);
var
  Caminho: string;
begin
  if Trim(FAtributosRawJSON) = '' then
  begin
    ShowMessage('Nenhum atributo carregado ainda - escolha a categoria primeiro.');
    Exit;
  end;
  // Mesmo padrao do "Ver Schema Completo" da tela da Amazon: grava num
  // .json temporario e abre no editor padrao do Windows.
  Caminho := TPath.Combine(TPath.GetTempPath,
    'mercadolivre_atributos_' + FCategoryIdEscolhida + '.json');
  try
    TFile.WriteAllText(Caminho, FAtributosRawJSON, TEncoding.UTF8);
    ShellExecute(0, 'open', PChar(Caminho), nil, nil, SW_SHOWNORMAL);
    Log('Atributos da categoria salvos em: ' + Caminho);
  except
    on E: Exception do
      Log('Nao foi possivel abrir o arquivo de atributos: ' + E.Message);
  end;
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdVoltarClick(Sender: TObject);
begin
  MostrarPasso(1);
end;

function TFrmCadastrarProdutoMercadoLivreNovo.MontarBodyAnuncio(
  out ABodyJSON, AErro: string): Boolean;
var
  Body, PicObj: TJSONObject;
  PicsArr: TJSONArray;
  AttrsValor: TJSONValue;
  Preco: Double;
  Estoque, I: Integer;
  Linha: string;
begin
  Result := False;
  ABodyJSON := '';
  AErro := '';

  if Trim(edtNome.Text) = '' then
  begin
    AErro := 'Informe o titulo do anuncio.';
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
    Body.AddPair('title', Trim(edtNome.Text));
    Body.AddPair('category_id', FCategoryIdEscolhida);
    Body.AddPair('price', TJSONNumber.Create(Preco));
    Body.AddPair('currency_id', 'BRL');
    Body.AddPair('available_quantity', TJSONNumber.Create(Estoque));
    Body.AddPair('buying_mode', 'buy_it_now');
    Body.AddPair('listing_type_id', cbTipoAnuncio.Text);
    Body.AddPair('condition', cbCondicao.Text);
    // seller_custom_field e' onde o Mercado Livre guarda o SKU do vendedor.
    if Trim(edtSku.Text) <> '' then
      Body.AddPair('seller_custom_field', Trim(edtSku.Text));
    if Trim(edtGarantia.Text) <> '' then
      Body.AddPair('warranty', Trim(edtGarantia.Text));

    // Imagens: uma URL publica por linha do memo.
    PicsArr := TJSONArray.Create;
    for I := 0 to mmImagens.Lines.Count - 1 do
    begin
      Linha := Trim(mmImagens.Lines[I]);
      if Linha = '' then
        Continue;
      PicObj := TJSONObject.Create;
      PicObj.AddPair('source', Linha);
      PicsArr.AddElement(PicObj);
    end;
    Body.AddPair('pictures', PicsArr);

    // Toma posse do array de atributos (o Body passa a ser o dono).
    Body.AddPair('attributes', AttrsValor);

    ABodyJSON := Body.ToJSON;
    Result := True;
  finally
    Body.Free; // libera tambem PicsArr e AttrsValor, ja que sao filhos
  end;
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdCadastrarClick(Sender: TObject);
var
  Cliente: TMercadoLivreOpenAPIClient;
  BodyJSON, ErroMsg, ItemId, RespostaJSON, Causa: string;
  Disponivel: Boolean;
  Preco: Double;
  Estoque: Integer;
begin
  if FCategoryIdEscolhida = '' then
  begin
    ShowMessage('Escolha a categoria primeiro.');
    Exit;
  end;

  if not MontarBodyAnuncio(BodyJSON, ErroMsg) then
  begin
    Log('Nao foi possivel montar o anuncio: ' + ErroMsg);
    ShowMessage(ErroMsg);
    Exit;
  end;

  if mmImagens.Lines.Count = 0 then
    if MessageDlg('Nenhuma imagem informada. O Mercado Livre aceita publicar ' +
         'sem imagem, mas o anuncio fica com qualidade baixa e pouca ' +
         'visibilidade. Publicar mesmo assim?', mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;

  ParseValorDecimal(edtPreco.Text, Preco);
  Estoque := StrToIntDef(Trim(edtEstoque.Text), 0);

  Screen.Cursor := crHourGlass;
  try
    Cliente := TMercadoLivreOpenAPIClient.Create(FDevClientId, FDevClientSecret,
      '', FSandbox);
    Cliente.OnLog := Log;
    try
      // Confere o tipo de anuncio ANTES de publicar - erro de
      // listing_type_id e' um dos motivos mais comuns de recusa, e aqui o
      // proprio Mercado Livre devolve o motivo em texto.
      if Cliente.CheckListingTypeAvailable(FToken, FAccountID, cbTipoAnuncio.Text,
           FCategoryIdEscolhida, Disponivel, Causa, ErroMsg) then
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

      if not Cliente.CreateItem(FToken, BodyJSON, ItemId, RespostaJSON, ErroMsg) then
      begin
        Log('Falha ao publicar o anuncio: ' + ErroMsg);
        ShowMessage('Falha ao publicar o anuncio:' + sLineBreak + ErroMsg +
          sLineBreak + sLineBreak + 'O Mercado Livre costuma apontar o campo ' +
          'exato no corpo do erro - confira o log.');
        Exit;
      end;

      Log('Anuncio publicado com sucesso: ' + ItemId);

      // Descricao: chamada SEPARADA, feita depois de o item existir. Se
      // falhar, o anuncio JA foi criado - nao da' pra desfazer, entao so'
      // avisa (o usuario pode preencher a descricao pelo painel do ML).
      if Trim(mmDescricao.Lines.Text) <> '' then
        if not Cliente.SetItemDescription(FToken, ItemId,
             Trim(mmDescricao.Lines.Text), ErroMsg) then
          Log('Aviso: o anuncio ' + ItemId + ' foi criado, mas a descricao nao ' +
            'foi gravada (' + ErroMsg + ') - preencha pelo painel do Mercado Livre.');
    finally
      Cliente.Free;
    end;

    GravarProdutoMarketplace(ItemId, Trim(edtNome.Text), Estoque, Preco);
    FCadastrouAlgo := True;
    ShowMessage('Anuncio publicado no Mercado Livre!' + sLineBreak +
      'ID do anuncio: ' + ItemId);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TFrmCadastrarProdutoMercadoLivreNovo.GravarProdutoMarketplace(
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
    // {IMPORTANTE} grava o ItemId (MLB...), que e' a MESMA chave usada em
    // uFrmOfertasMarketplace.GravarProdutoMercadoLivre e no lookup da baixa
    // de pedido (uBaixaPedidoSAT) - se mudar aqui, quebra os dois.
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

procedure TFrmCadastrarProdutoMercadoLivreNovo.CmdFecharClick(Sender: TObject);
begin
  Close;
end;

end.
