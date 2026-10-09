// ============================================================================
// UNIT: uFrmCadastrarProdutoMarketplace
// OBJETIVO: Tela (aberta pelo botao "Incluir Produto" da tela de Ofertas)
// pra cadastrar um produto novo na loja virtual.
//
// SHOPEE: cadastro completo (nome, descricao, imagem, preco, estoque, peso,
// categoria/marca) via add_item - cria o produto do ZERO.
//
// AMAZON: cria uma OFERTA em cima de um ASIN que JA EXISTE no catalogo da
// Amazon (nao cria produto novo do zero - isso exigiria a Product Type
// Definitions API pra descobrir os atributos obrigatorios por categoria,
// bem mais complexo). So pede SKU (novo, escolhido pelo vendedor), ASIN (do
// produto ja existente), Preco e Estoque.
//
// Os campos NAO puxam dados do produto fisico - os campos sao diferentes
// entre os marketplaces (principalmente fotos, no caso da Shopee).
//
// Ao ter sucesso, grava a oferta nova em PRODUTOS_MARKETPLACE - SEM vinculo
// com produto fisico ainda (CODPRODUTO fica em branco, igual toda oferta
// nova que vem do "Buscar Ofertas"). O vinculo continua sendo feito depois,
// separadamente, pelo botao "Vincular Produto" que ja existe na tela de
// Ofertas - mantem o mesmo padrao modular que ja vinhamos usando.
//
// Magalu ainda nao tem CreateProduct/oferta implementado.
// ============================================================================
unit uFrmCadastrarProdutoMarketplace;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.StrUtils, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Buttons,
  Data.DB, FireDAC.Comp.Client, DMZ, uMarketplace, Shopee.OpenAPI.Client,
  Amazon.SPAPI.Client;
const
  FLoja = 1; // mesmo padrao ja usado no resto do projeto
type
  TFrmCadastrarProdutoMarketplace = class(TForm)
    pnlTopo: TPanel;
    lblTitulo: TLabel;
    lblNome: TLabel;
    edtNome: TEdit;
    lblDescricao: TLabel;
    mmDescricao: TMemo;
    lblImagem: TLabel;
    edtImagem: TEdit;
    CmdProcurarImagem: TBitBtn;
    lblPreco: TLabel;
    edtPreco: TEdit;
    lblEstoque: TLabel;
    edtEstoque: TEdit;
    lblPeso: TLabel;
    edtPeso: TEdit;
    lblCategoriaID: TLabel;
    edtCategoriaID: TEdit;
    lblBrandID: TLabel;
    edtBrandID: TEdit;
    lblBrandName: TLabel;
    edtBrandName: TEdit;
    lblSku: TLabel;
    edtSku: TEdit;
    lblAsin: TLabel;
    edtAsin: TEdit;
    CmdCadastrar: TBitBtn;
    CmdFechar: TBitBtn;
    MemoLog: TMemo;
    OpenDialogImagem: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure CmdProcurarImagemClick(Sender: TObject);
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
    // Sinaliza pra quem abriu a tela (uFrmOfertasMarketplace) que pelo
    // menos um produto foi cadastrado com sucesso - assim quem chamou sabe
    // se vale a pena atualizar a grid de ofertas ao fechar esta tela.
    FCadastrouAlgo: Boolean;
    // Preenche os campos de exemplo e ajusta a visibilidade dos campos
    // conforme o marketplace - chamado explicitamente pelo AbrirParaLoja,
    // DEPOIS que FCodMarketplace/FAccountID/etc ja foram atribuidos (o
    // FormCreate roda ainda dentro do TForm.Create, antes dessas
    // atribuicoes, entao nao pode depender delas).
    procedure Inicializar;
    procedure Log(const AMsg: string);
    function ParseValorDecimal(const ATexto: string; out AValor: Double): Boolean;
    procedure AtualizarVisibilidadeCampos;
    function ValidarCamposShopee(out AErro: string): Boolean;
    function ValidarCamposAmazon(out AErro: string): Boolean;
    procedure CadastrarShopee;
    procedure CadastrarAmazon;
    procedure GravarProdutoMarketplace(const ACodProdutoNoMarketplace, ANome: string;
      const AEstoque: Integer; const APreco: Double);
  public
    // CadastrouAlgo = True se pelo menos um produto foi cadastrado com
    // sucesso durante a sessao dessa tela.
    // AASINSugerido (opcional): pre-preenche o campo ASIN (Amazon) - usado
    // quando a tela e' aberta a partir de uma busca no catalogo (ver
    // uFrmCadastrarProdutoAmazonNovo, botao "Usar ASIN selecionado"),
    // pra o usuario nao ter que copiar/colar o ASIN manualmente.
    class function AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
      const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
      const ASandbox: Boolean; const AASINSugerido: string = ''): Boolean;
  end;
implementation
{$R *.dfm}
{ TFrmCadastrarProdutoMarketplace }
class function TFrmCadastrarProdutoMarketplace.AbrirParaLoja(const ALoja, ACodMarketplace: Integer;
  const AAccountID, AToken: string; const ADevClientId, ADevClientSecret: string;
  const ASandbox: Boolean; const AASINSugerido: string): Boolean;
var
  Frm: TFrmCadastrarProdutoMarketplace;
begin
  Frm := TFrmCadastrarProdutoMarketplace.Create(Application);
  try
    Frm.FLoja := ALoja;
    Frm.FCodMarketplace := ACodMarketplace;
    Frm.FAccountID := AAccountID;
    Frm.FToken := AToken;
    Frm.FDevClientId := ADevClientId;
    Frm.FDevClientSecret := ADevClientSecret;
    Frm.FSandbox := ASandbox;
    Frm.FCadastrouAlgo := False;
    Frm.lblTitulo.Caption := 'Incluir Produto - ' + NomeMarketplace(TMarketplaces(ACodMarketplace));
    // So agora, com todos os campos ja atribuidos, e' seguro montar a tela
    // (visibilidade de campos, valores de exemplo, checagem de marketplace
    // suportado). Ver comentario no Inicializar.
    Frm.Inicializar;
    if AASINSugerido <> '' then
      Frm.edtAsin.Text := AASINSugerido;
    Frm.ShowModal;
    Result := Frm.FCadastrouAlgo;
  finally
    Frm.Free;
  end;
end;
procedure TFrmCadastrarProdutoMarketplace.FormCreate(Sender: TObject);
begin
  // ATENCAO: este evento roda DENTRO do TForm.Create (chamado la' no
  // AbrirParaLoja), ou seja, ANTES de FCodMarketplace/FAccountID/etc serem
  // atribuidos pelo chamador. Por isso nao pode ter nenhuma logica aqui que
  // dependa desses campos - toda essa logica fica em Inicializar, chamado
  // explicitamente pelo AbrirParaLoja depois das atribuicoes. Esse era
  // exatamente o bug: a tela cadastrava a visibilidade dos campos e exibia
  // a mensagem de "marketplace nao suportado" com base no valor padrao
  // (0) de FCodMarketplace, antes do valor real ser atribuido.
end;
procedure TFrmCadastrarProdutoMarketplace.Inicializar;
begin
  // Valores de exemplo pra facilitar o preenchimento (mesmo padrao do
  // projeto isolado) - o usuario so precisa trocar o que for diferente.
  edtNome.Text := Format('Produto %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]);
  mmDescricao.Text := 'Descreva o produto aqui (mínimo 25 caracteres exigido pela Shopee).';
  edtPreco.Text := '10,00';
  edtEstoque.Text := '5';
  edtPeso.Text := '0,20';
  // 0 = detectar automaticamente (o CreateProduct ja trata isso).
  edtCategoriaID.Text := '0';
  edtBrandID.Text := '0';
  edtBrandName.Text := 'No Brand';
  edtSku.Text := Format('SKU-%s', [FormatDateTime('yyyymmddhhnnss', Now)]);
  edtAsin.Clear;
  AtualizarVisibilidadeCampos;
  if not (TMarketplaces(FCodMarketplace) in [TMarketplaces.Shopee, TMarketplaces.Amazon]) then
    Log('Cadastro de produto ainda nao disponivel para este marketplace.');
end;
procedure TFrmCadastrarProdutoMarketplace.AtualizarVisibilidadeCampos;
var
  EhShopee: Boolean;
begin
  EhShopee := TMarketplaces(FCodMarketplace) = TMarketplaces.Shopee;
  // Campos exclusivos da Shopee (cadastro completo, produto novo do zero).
  lblNome.Visible := EhShopee;
  edtNome.Visible := EhShopee;
  lblDescricao.Visible := EhShopee;
  mmDescricao.Visible := EhShopee;
  lblImagem.Visible := EhShopee;
  edtImagem.Visible := EhShopee;
  CmdProcurarImagem.Visible := EhShopee;
  lblPeso.Visible := EhShopee;
  edtPeso.Visible := EhShopee;
  lblCategoriaID.Visible := EhShopee;
  edtCategoriaID.Visible := EhShopee;
  lblBrandID.Visible := EhShopee;
  edtBrandID.Visible := EhShopee;
  lblBrandName.Visible := EhShopee;
  edtBrandName.Visible := EhShopee;
  // Campos exclusivos da Amazon (oferta em cima de ASIN ja existente).
  lblSku.Visible := not EhShopee;
  edtSku.Visible := not EhShopee;
  lblAsin.Visible := not EhShopee;
  edtAsin.Visible := not EhShopee;
  // Preco/Estoque sao compartilhados pelos dois - sempre visiveis.
end;
procedure TFrmCadastrarProdutoMarketplace.Log(const AMsg: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' - ' + AMsg);
end;
function TFrmCadastrarProdutoMarketplace.ParseValorDecimal(const ATexto: string;
  out AValor: Double): Boolean;
var
  FS: TFormatSettings;
  TextoNormalizado: string;
begin
  // Aceita tanto virgula quanto ponto como separador decimal, e usa um
  // TFormatSettings proprio (ponto fixo) em vez do FormatSettings global -
  // assim nao depende da config regional do Windows da maquina onde o
  // programa roda. A config regional do Brasil normalmente usa virgula
  // como separador decimal - o codigo antigo trocava ',' por '.' no texto
  // mas depois chamava StrToFloatDef "cru" (usando o FormatSettings global,
  // que esperava virgula), entao sempre falhava e caia no valor padrao 0.
  FS := TFormatSettings.Invariant;
  TextoNormalizado := StringReplace(Trim(ATexto), ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(TextoNormalizado, AValor, FS);
end;
procedure TFrmCadastrarProdutoMarketplace.CmdProcurarImagemClick(Sender: TObject);
begin
  OpenDialogImagem.Filter := 'Imagens (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png';
  if OpenDialogImagem.Execute then
    edtImagem.Text := OpenDialogImagem.FileName;
end;
function TFrmCadastrarProdutoMarketplace.ValidarCamposShopee(out AErro: string): Boolean;
var
  ValorTeste: Double;
begin
  Result := False;
  if Trim(edtNome.Text) = '' then
  begin
    AErro := 'Informe o nome do produto.';
    Exit;
  end;
  // Exigencia real da Shopee - confirmada no projeto isolado.
  if Length(Trim(mmDescricao.Text)) < 25 then
  begin
    AErro := 'A descrição precisa ter pelo menos 25 caracteres (exigência da Shopee).';
    Exit;
  end;
  if Trim(edtImagem.Text) = '' then
  begin
    AErro := 'Selecione uma imagem - a Shopee exige pelo menos uma foto pra cadastrar o produto.';
    Exit;
  end;
  if not FileExists(edtImagem.Text) then
  begin
    AErro := 'O arquivo de imagem selecionado nao foi encontrado: ' + edtImagem.Text;
    Exit;
  end;
  if not ParseValorDecimal(edtPreco.Text, ValorTeste) or (ValorTeste <= 0) then
  begin
    AErro := 'Informe um preco valido (maior que zero).';
    Exit;
  end;
  if StrToIntDef(edtEstoque.Text, -1) < 0 then
  begin
    AErro := 'Informe um estoque valido (0 ou maior).';
    Exit;
  end;
  if not ParseValorDecimal(edtPeso.Text, ValorTeste) or (ValorTeste <= 0) then
  begin
    AErro := 'Informe um peso valido em kg (maior que zero, ex: 0,20).';
    Exit;
  end;
  Result := True;
end;
function TFrmCadastrarProdutoMarketplace.ValidarCamposAmazon(out AErro: string): Boolean;
var
  ValorTeste: Double;
begin
  Result := False;
  if Trim(edtSku.Text) = '' then
  begin
    AErro := 'Informe o SKU (identificador que voce vai usar pra esse produto).';
    Exit;
  end;
  // ASIN sempre tem exatamente 10 caracteres alfanumericos.
  if Length(Trim(edtAsin.Text)) <> 10 then
  begin
    AErro := 'Informe um ASIN valido (10 caracteres) - o produto precisa ja existir no catalogo da Amazon.';
    Exit;
  end;
  if not ParseValorDecimal(edtPreco.Text, ValorTeste) or (ValorTeste <= 0) then
  begin
    AErro := 'Informe um preco valido (maior que zero).';
    Exit;
  end;
  if StrToIntDef(edtEstoque.Text, -1) < 0 then
  begin
    AErro := 'Informe um estoque valido (0 ou maior).';
    Exit;
  end;
  Result := True;
end;
procedure TFrmCadastrarProdutoMarketplace.CmdCadastrarClick(Sender: TObject);
begin
  case TMarketplaces(FCodMarketplace) of
    TMarketplaces.Shopee: CadastrarShopee;
    TMarketplaces.Amazon: CadastrarAmazon;
  else
    ShowMessage('Cadastro de produto ainda nao disponivel para este marketplace.');
  end;
end;
procedure TFrmCadastrarProdutoMarketplace.CadastrarShopee;
var
  Erro: string;
  Cliente: TShopeeOpenAPIClient;
  NovoItemID: Int64;
  Preco: Double;
  Estoque: Integer;
  Peso: Double;
  CategoriaID, BrandID: Int64;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Shopee nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  if not ValidarCamposShopee(Erro) then
  begin
    ShowMessage(Erro);
    Exit;
  end;
  // Reaproveita ParseValorDecimal (mesma logica ja validada em
  // ValidarCamposShopee) - AQUI ja sabemos que os dois campos sao validos,
  // pois a validacao ja passou; se por algum motivo falhar mesmo assim,
  // cai nos defaults de seguranca (0 e 0,1) so por precaucao.
  if not ParseValorDecimal(edtPreco.Text, Preco) then
    Preco := 0;
  Estoque := StrToIntDef(edtEstoque.Text, 0);
  if not ParseValorDecimal(edtPeso.Text, Peso) then
    Peso := 0.1;
  CategoriaID := StrToInt64Def(edtCategoriaID.Text, 0);
  BrandID := StrToInt64Def(edtBrandID.Text, 0);
  Screen.Cursor := crHourGlass;
  try
    Log('Cadastrando produto "' + edtNome.Text + '" na Shopee' +
      IfThen(FSandbox, ' (Sandbox)', '') + '...');
    Cliente := TShopeeOpenAPIClient.Create(StrToInt64Def(FDevClientId, 0),
      FDevClientSecret, '', FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.CreateProduct(FToken, StrToInt64Def(FAccountID, 0),
           Trim(edtNome.Text), mmDescricao.Text, edtImagem.Text, Preco, Estoque,
           Peso, CategoriaID, BrandID, Trim(edtBrandName.Text), NovoItemID, Erro) then
      begin
        Log('Falha ao cadastrar produto: ' + Erro);
        ShowMessage('Falha ao cadastrar produto: ' + Erro);
        Exit;
      end;
      Log('Produto cadastrado com sucesso! Item ID: ' + IntToStr(NovoItemID));
    finally
      Cliente.Free;
    end;
    // Grava a oferta nova em PRODUTOS_MARKETPLACE - sem vinculo com produto
    // fisico ainda (mesmo padrao de toda oferta nova vinda do "Buscar
    // Ofertas"). O vinculo e' feito depois, separadamente, pelo botao
    // "Vincular Produto" ja existente na tela de Ofertas.
    GravarProdutoMarketplace(IntToStr(NovoItemID), Trim(edtNome.Text), Estoque, Preco);
    FCadastrouAlgo := True;
    if MessageDlg('Produto cadastrado com sucesso!' + sLineBreak +
         'Deseja cadastrar outro produto agora?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      // Limpa os campos pra um cadastro novo, mantendo categoria/marca (o
      // usuario provavelmente vai cadastrar varios produtos parecidos em
      // sequencia).
      edtNome.Clear;
      mmDescricao.Clear;
      edtImagem.Clear;
      edtPreco.Clear;
      edtEstoque.Clear;
      edtNome.SetFocus;
    end
    else
      ModalResult := mrOk;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmCadastrarProdutoMarketplace.CadastrarAmazon;
var
  Erro, RespostaJSON: string;
  Cliente: TAmazonSPAPIClient;
  Preco: Double;
  Estoque: Integer;
begin
  if (FDevClientId = '') or (FDevClientSecret = '') then
  begin
    Log('Credenciais de desenvolvedor da Amazon nao cadastradas para esta ' +
      'loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA na tabela Lojas).');
    Exit;
  end;
  if not ValidarCamposAmazon(Erro) then
  begin
    ShowMessage(Erro);
    Exit;
  end;
  if not ParseValorDecimal(edtPreco.Text, Preco) then
    Preco := 0;
  Estoque := StrToIntDef(edtEstoque.Text, 0);
  Screen.Cursor := crHourGlass;
  try
    Log('Criando oferta para o ASIN ' + Trim(edtAsin.Text) + ' na Amazon' +
      IfThen(FSandbox, ' (Sandbox)', '') + '...');
    Cliente := TAmazonSPAPIClient.Create(FDevClientId, FDevClientSecret, '',
      uMarketplace.AMAZON_MARKETPLACE_ID_BRASIL, FSandbox);
    Cliente.OnLog := Log;
    try
      if not Cliente.CreateOfferForExistingASIN(FToken, FAccountID, Trim(edtSku.Text),
           Trim(edtAsin.Text), Preco, Estoque, RespostaJSON, Erro) then
      begin
        Log('Falha ao criar oferta: ' + Erro);
        ShowMessage('Falha ao criar oferta: ' + Erro);
        Exit;
      end;
      Log('Oferta criada/enviada com sucesso! SKU: ' + Trim(edtSku.Text));
    finally
      Cliente.Free;
    end;
    // {ATENCAO} A Amazon processa a submissao de forma assincrona - pode
    // levar alguns minutos pra aparecer no "Buscar Ofertas". O nome do
    // produto aqui e' desconhecido no momento do cadastro (vem do catalogo
    // da Amazon, nao foi digitado) - fica em branco ate o proximo "Buscar
    // Ofertas"/"Atualizar" trazer o nome real.
    GravarProdutoMarketplace(Trim(edtSku.Text), '', Estoque, Preco);
    FCadastrouAlgo := True;
    if MessageDlg('Oferta enviada para processamento na Amazon!' + sLineBreak +
         'Pode levar alguns minutos para aparecer disponivel para venda.' + sLineBreak +
         'Deseja cadastrar outra oferta agora?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      edtSku.Text := Format('SKU-%s', [FormatDateTime('yyyymmddhhnnss', Now)]);
      edtAsin.Clear;
      edtPreco.Clear;
      edtEstoque.Clear;
      edtAsin.SetFocus;
    end
    else
      ModalResult := mrOk;
  finally
    Screen.Cursor := crDefault;
  end;
end;
procedure TFrmCadastrarProdutoMarketplace.GravarProdutoMarketplace(
  const ACodProdutoNoMarketplace, ANome: string; const AEstoque: Integer;
  const APreco: Double);
var
  Qry: TFDQuery;
  NovoCodigo: Integer;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DZ.ZDatabase;
    // {TODO} Placeholder de geracao de codigo - se existir um GEN_ID proprio
    // pra essa tabela no banco, trocar por:
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
procedure TFrmCadastrarProdutoMarketplace.CmdFecharClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;
end.
