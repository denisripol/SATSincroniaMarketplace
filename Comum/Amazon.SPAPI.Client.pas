// ============================================================================
// UNIT: Amazon.SPAPI.Client
// OBJETIVO: Cliente standalone para autenticação OAuth/LWA e chamadas básicas
//           à Amazon Selling Partner API (SP-API).
// REQUISITOS: Delphi 12.3+, System.Net.HttpClient, System.NetEncoding
// ============================================================================
//
// CONCEITOS IMPORTANTES:
//   - Client ID / Client Secret (LWA): identificam SUA aplicação, obtidos no
//     Solution Provider Portal. Não mudam por vendedor (seller).
//   - Application ID: identificador do app no Solution Provider Portal, usado
//     apenas para montar a URL de autorização (diferente do Client ID).
//   - Diferente da Shopee, a Amazon NÃO usa assinatura HMAC nas chamadas de
//     dados - só um Access Token (Bearer-like) no header "x-amz-access-token".
//   - Access Token / Refresh Token: um par por vendedor autorizado. O mesmo
//     método RefreshAccessToken serve tanto para um refresh_token de produção
//     (vendedor real) quanto para o refresh_token de um "Sandbox Application"
//     (self-authorization, gerado direto no Solution Provider Portal sem
//     precisar de nenhum vendedor - útil para testar antes da autorização
//     real).
//   - Região: fixado em NA (América do Norte), que inclui o marketplace do
//     Brasil segundo a classificação da própria Amazon.
//
// FLUXO DE USO (vendedor real, produção):
//   1. BuildAuthorizationURL -> abre no navegador do vendedor
//   2. Vendedor loga/autoriza, é redirecionado pra sua Redirect URI com os
//      parâmetros "spapi_oauth_code", "selling_partner_id" e "state"
//   3. ExchangeCodeForTokens(spapi_oauth_code) -> retorna RefreshToken
//      (guardar) e AccessToken (usar imediatamente)
//   4. Quando o AccessToken expirar: RefreshAccessToken(refreshTokenAtual)
//
// FLUXO DE USO (Sandbox Application / self-authorization):
//   1. Gere o refresh_token direto no Solution Provider Portal (sem
//      navegador, sem vendedor)
//   2. RefreshAccessToken(refreshTokenSandbox) -> pronto para testar
// ============================================================================

unit Amazon.SPAPI.Client;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.JSON,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient,
  System.Hash,
  System.DateUtils;

type
  TAmazonTokenInfo = record
    Success: Boolean;
    AccessToken: string;
    RefreshToken: string;
    ExpiresIn: Integer;      // segundos até expirar o AccessToken
    ObtainedAt: TDateTime;
    ErrorMessage: string;
    RawResponse: string;
  end;

  TAmazonLogEvent = procedure(const AMessage: string) of object;

  TAmazonOrder = record
    AmazonOrderId: string;
    OrderStatus: string;
    PurchaseDate: string;
    CurrencyCode: string;
    TotalAmount: string;
  end;

  TAmazonOrderArray = TArray<TAmazonOrder>;

  // Um item de pedido (OrderItem) da Amazon - usado tanto pro
  // confirmShipment (Despachar) quanto pela baixa no SAT (campos de
  // preco/frete/ASIN adicionados em 24/08 pra isso).
  TAmazonOrderItem = record
    OrderItemId: string;
    SellerSKU: string;
    Title: string;
    QuantityOrdered: Integer;
    ASIN: string;                 // usado pra localizar PRODUTOS_MARKETPLACE
    ItemPriceAmount: Double;      // ItemPrice.Amount - valor TOTAL da linha (nao unitario)
    ShippingPrice: Double;
    ConditionId: string;
  end;
  TAmazonOrderItemArray = TArray<TAmazonOrderItem>;

  // Detalhe completo de um pedido (getOrder, sem os filtros que o
  // GetOrders da tela de listagem usa) - usado pela baixa no SAT
  // (uBaixaPedidoSAT). Cobre os campos com coluna dedicada confirmados
  // no de-para do cliente (mapeamento por analogia com a Shopee,
  // proposto em 24/08 - Amazon nao teve de-para formalmente respondido
  // ainda, mas a Orders API v0 e' publica/estavel, entao a confianca e'
  // alta). Os demais campos (sem coluna dedicada, que viram OBS) ficam
  // disponiveis em RawJSON pro chamador extrair.
  TAmazonOrderDetail = record
    AmazonOrderId: string;
    OrderStatus: string;
    PurchaseDate: TDateTime;
    LastUpdateDate: TDateTime;
    TotalAmount: Double;
    BuyerName: string;
    BuyerEmail: string;
    ShippingName: string;
    ShippingPhone: string;
    ShippingAddressLine: string; // AddressLine1+2+3 concatenados
    ShippingCity: string;
    ShippingDistrict: string;    // ShippingAddress.District (bairro) - {NAO
                                 // CONFIRMADO} se a Amazon BR preenche;
                                 // fica vazio quando nao vem
    ShippingState: string;
    ShippingPostalCode: string;
    ShippingCountryCode: string;
    RawJSON: string; // resposta completa - usado pra extrair os campos "-> oe.obs"
  end;

  TAmazonListingItem = record
    SKU: string;
    ASIN: string;
    ItemName: string;
    // Status vem como array na resposta da Amazon (ex: ["BUYABLE"]) - guarda
    // so o primeiro/principal aqui, como string simples.
    Status: string;
    Price: Double;
    Currency: string;
    Stock: Integer;
    // summaries[0].lastUpdatedDate, em hora local. 0 = a Amazon nao mandou.
    LastUpdated: TDateTime;
  end;
  TAmazonListingItemArray = TArray<TAmazonListingItem>;

  // Um productType candidato devolvido pela busca por palavra-chave
  // (Product Type Definitions API) - ex: nome "OFFICE_PRODUCTS".
  TAmazonProductTypeInfo = record
    Name: string;
    DisplayName: string; // pode vir vazio - nem toda resposta traz isso
  end;
  TAmazonProductTypeInfoArray = TArray<TAmazonProductTypeInfo>;

  // Um item de resultado da busca no catalogo geral da Amazon (Catalog
  // Items API) - usado pra checar se um produto parecido ja existe antes
  // de cadastrar do zero (ver uFrmCadastrarProdutoAmazonNovo, botao
  // "Buscar no Catalogo").
  TAmazonCatalogItem = record
    ASIN: string;
    Titulo: string;
    Marca: string;
    ImagemURL: string; // pode vir vazio se o item nao tiver imagem principal
  end;
  TAmazonCatalogItemArray = TArray<TAmazonCatalogItem>;

  TAmazonSPAPIClient = class
  private
    FClientID: string;
    FClientSecret: string;
    FRedirectURI: string;
    FMarketplaceID: string;
    FSandbox: Boolean;
    FHTTPClient: TNetHTTPClient;
    FOnLog: TAmazonLogEvent;

    procedure DoLog(const AMessage: string);
    function BaseURL: string;
    function ParseTokenResponse(const AResponseStr: string): TAmazonTokenInfo;
    function ExecuteTokenRequest(const ABodyFormEncoded: string): TAmazonTokenInfo;
    function ExecuteGet(const AApiPath, AQueryExtra, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePost(const AApiPath, AQueryExtra, ABodyJSON, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePatch(const AApiPath, AQueryExtra, ABodyJSON, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePut(const AApiPath, AQueryExtra, ABodyJSON, AAccessToken: string;
      out AStatusCode: Integer): string;
  public
    constructor Create(const AClientID, AClientSecret, ARedirectURI,
      AMarketplaceID: string; ASandbox: Boolean = True);
    destructor Destroy; override;

    // --- Autenticação ---
    // Monta a URL de autorização para apps ainda em rascunho/beta no Seller
    // Central. AApplicationID vem do Solution Provider Portal (não é o
    // Client ID). Depois que o app for publicado na Appstore, o vendedor
    // pode autorizar direto por lá, sem precisar desta URL manual.
    function BuildAuthorizationURL(const AApplicationID, AState: string): string;

    // Troca o spapi_oauth_code (recebido no redirect após autorização real
    // de um vendedor) pelos tokens.
    function ExchangeCodeForTokens(const ASpapiOAuthCode: string): TAmazonTokenInfo;

    // Gera um novo Access Token a partir de um Refresh Token já guardado.
    // Serve tanto para refresh_token de produção quanto de Sandbox Application.
    function RefreshAccessToken(const ARefreshToken: string): TAmazonTokenInfo;

    // Teste leve de conexão: lista as marketplaces que o vendedor participa.
    function TestConnection(const AAccessToken: string; out AResponseJSON: string): Boolean;

    // --- Pedidos (Orders API v0) ---
    function GetOrders(const AAccessToken, ACreatedAfter: string;
      out AOrders: TAmazonOrderArray; out AErrorMessage: string): Boolean;

    // Busca os itens (orderItemId, SKU, quantidade) de um pedido especifico -
    // necessario pra montar o "orderItems" do ConfirmShipment (Despachar),
    // que exige orderItemId de verdade, nao SKU.
    function GetOrderItems(const AAccessToken, AAmazonOrderId: string;
      out AItems: TAmazonOrderItemArray; out AErrorMessage: string): Boolean;

    // Detalhe completo de UM pedido (getOrder, sem os filtros do GetOrders
    // usado na tela de listagem) - usado pela baixa no SAT
    // (uBaixaPedidoSAT). Devolve os campos com coluna dedicada ja
    // parseados (ADetalhe) - os demais campos (sem coluna dedicada, que
    // viram OBS) ficam disponiveis em ADetalhe.RawJSON pro chamador
    // extrair.
    function GetOrderDetail(const AAccessToken, AAmazonOrderId: string;
      out ADetalhe: TAmazonOrderDetail; out AErrorMessage: string): Boolean;

    // --- Financeiro (Finances API) ---
    // {ATENCAO} A API v0 (listFinancialEventsByOrderId) esta sendo
    // DESATIVADA pela Amazon com prazo 28/08/2026 - por isso implementado
    // direto na v2024-06-19 (listTransactions), que e' o caminho oficial
    // pra frente. Precisa da role "Finance and Accounting" aprovada pra
    // Amazon devolver dado de verdade (mesma situacao da Nota Fiscal -
    // codigo pronto, aguardando aprovacao). Devolve o valor liquido
    // somado (repasse real, ja com taxas/comissao descontadas) + o JSON
    // bruto, caso precise detalhar mais no futuro.
    function GetOrderNetAmount(const AAccessToken, AAmazonOrderId: string;
      APostedAfter: TDateTime; out ANetAmount: Double; out ARawJSON: string;
      out AErrorMessage: string): Boolean;

    // "Despachar" - confirma o envio de um pedido MFN (self-ship). Path
    // real e' POST /orders/v0/orders/{orderId}/shipmentConfirmation
    // (confirmado no schema oficial - amzn/selling-partner-api-models).
    // ACarrierCode precisa bater com a lista de codigos aceitos pela
    // Amazon (ex: "CORREIOS", "UPS", "FEDEX") ou "Other" + ACarrierName
    // preenchido. AShipDate em UTC (TDateTime local e' convertido aqui).
    function ConfirmShipment(const AAccessToken, AAmazonOrderId, ACarrierCode,
      ACarrierName, ATrackingNumber: string; AShipDate: TDateTime;
      const AItems: TAmazonOrderItemArray;
      out AErrorMessage: string): Boolean;

    // "Enviar Nota Fiscal" - envia o XML da NF-e ja emitida (fora da
    // Amazon, no seu proprio sistema fiscal) pra Amazon, via Delivery by
    // Amazon API v2022-07-01. {ATENCAO} Essa API esta em "Restricted
    // Availability" - exige a role "Tax Invoicing (Restricted)" aprovada
    // pela Amazon pro app, sem isso vai dar 403 mesmo com o codigo certo.
    // programType fixo em "SelfShip" (pedido MFN, vendedor despacha
    // direto) - se o pedido for Easy Ship/FBA, o programType seria outro.
    function SubmitDeliveryInvoice(const AAccessToken, AAmazonOrderId: string;
      const AXmlBytes: TBytes; out AErrorMessage: string): Boolean;

    // Consulta o status de uma nota fiscal ja enviada - nao ha' documento
    // pra "baixar" de volta da Amazon (quem gera o XML e' o proprio
    // vendedor), entao esse metodo serve pro botao "Baixar Nota Fiscal"
    // mostrar o status em vez de salvar um arquivo.
    function GetDeliveryInvoiceStatus(const AAccessToken, AAmazonOrderId: string;
      out AStatus: string; out AErrorMessage: string): Boolean;

    // --- Precificação (Product Pricing API v2022-05-01) ---
    function GetCompetitiveSummary(const AAccessToken, AAsin: string;
      out AResponseJSON: string; out AErrorMessage: string): Boolean;

    // --- Ofertas (Listings Items API v2021-08-01) ---
    function GetListingsItem(const AAccessToken, ASellerID, ASku: string;
      out AResponseJSON: string; out AErrorMessage: string): Boolean;
    // Lista TODOS os listings/ofertas do vendedor (searchListingsItems) -
    // sem passar "identifiers", a Amazon devolve tudo, paginado. Percorre a
    // paginacao inteira (pageToken/nextToken), entao o retorno e' o catalogo
    // completo, nao a primeira pagina: com pageSize maximo de 20, um vendedor
    // com 300 ofertas custa 15 chamadas.
    function SearchListingsItems(const AAccessToken, ASellerID: string;
      out AItems: TAmazonListingItemArray; out AErrorMessage: string): Boolean;

    // {LEGADO - EVITAR} generico demais: manda "value" como texto solto,
    // o que so funciona pra atributos de texto simples - NAO funciona pra
    // fulfillment_availability (estoque), que precisa de
    // fulfillment_channel_code+quantity, nem tem o productType real do
    // item (fica fixo em 'PRODUCT', quase sempre errado). Nunca foi
    // chamado por nenhuma tela. Pra atualizar estoque, use
    // UpdateStockQuantity abaixo.
    function PatchListingsItemAttribute(const AAccessToken, ASellerID, ASku,
      AAttributeName, AAttributeValue: string;
      out AResponseJSON: string; out AErrorMessage: string): Boolean;

    // Atualiza o ESTOQUE (fulfillment_availability, canal DEFAULT) de um
    // SKU que ja tem oferta ativa na Amazon - descobre sozinho o
    // productType real do item (GetListingsItem) antes de montar o PATCH,
    // pra nao repetir o erro do metodo legado acima. Usar isso no F2
    // (Enviar Dados) pra sincronizar estoque fisico -> Amazon.
    function UpdateStockQuantity(const AAccessToken, ASellerID, ASku: string;
      AQuantity: Integer; out AResponseJSON: string; out AErrorMessage: string): Boolean;

    // Atualiza o PRECO (purchasable_offer) de um SKU que ja tem oferta ativa.
    // Mesmo caminho do estoque: descobre o productType real antes de montar o
    // PATCH. Usar no F2 junto com o UpdateStockQuantity.
    // {ATENCAO} a Amazon tem preco minimo e maximo por oferta. Preco fora dessa
    // faixa e' aceito na chamada mas pode SUPRIMIR o anuncio - a oferta some da
    // venda sem erro aparente. Se isso acontecer, conferir os limites no Seller
    // Central antes de suspeitar da integracao.
    function UpdateSalePrice(const AAccessToken, ASellerID, ASku: string;
      ANovoPreco: Double; out AResponseJSON: string;
      out AErrorMessage: string): Boolean;

    // Cria uma OFERTA em cima de um ASIN que JA EXISTE no catalogo da
    // Amazon (nao cria produto novo do zero - isso exigiria a Product Type
    // Definitions API pra descobrir os atributos obrigatorios por
    // categoria, bem mais complexo). Usa productType "PRODUCT" +
    // requirements "LISTING_OFFER_ONLY", o caminho oficialmente
    // documentado pela Amazon pra esse caso mais simples.
    function CreateOfferForExistingASIN(const AAccessToken, ASellerID, ASku,
      AASIN: string; APrice: Double; AQuantity: Integer;
      out AResponseJSON: string; out AErrorMessage: string): Boolean;

    // --- Product Type Definitions API (2020-09-01) - cadastro de produto
    // NOVO do zero (sem ASIN existente) ---

    // Busca os productType candidatos pra uma palavra-chave (nome do
    // produto, categoria etc) - primeiro passo pra descobrir em qual
    // "categoria" da Amazon o produto novo se encaixa. Ex: "clipe de
    // papel" pode devolver "OFFICE_PRODUCTS".
    function SearchProductTypes(const AAccessToken, AKeywords: string;
      out AProductTypes: TAmazonProductTypeInfoArray;
      out AErrorMessage: string): Boolean;

    // Busca no CATALOGO GERAL da Amazon (Catalog Items API 2022-04-01) por
    // palavra-chave - serve pra checar se um produto parecido ja existe
    // (de qualquer vendedor) ANTES de cadastrar do zero. Se achar um ASIN
    // que bate, e' bem mais simples usar CreateOfferForExistingASIN em vez
    // de passar por todo o cadastro completo (que exige GTIN/isencao).
    function SearchCatalogItems(const AAccessToken, AKeywords: string;
      out AItems: TAmazonCatalogItemArray;
      out AErrorMessage: string): Boolean;

    // Baixa o JSON Schema completo de um productType especifico - fluxo em
    // 2 passos: 1) pega o "link" do schema via getDefinitionsProductType
    // (SP-API, autenticado), 2) baixa o schema de fato desse link (URL
    // publica, hospedada fora da SP-API, SEM token). O schema e' um JSON
    // Schema (draft) - use "required" e "properties" no nivel raiz pra
    // saber quais atributos sao obrigatorios pra esse productType.
    function GetProductTypeSchema(const AAccessToken, AProductType,
      ASellerID: string; out ASchemaJSON: string;
      out AErrorMessage: string): Boolean;

    // Cria um produto NOVO do zero (ainda sem ASIN) - AAttributesJSON e' o
    // conteudo (objeto JSON cru, como string) que vai dentro da chave
    // "attributes" do payload, montado pelo chamador de acordo com o
    // schema do productType escolhido (ver GetProductTypeSchema). Manda
    // "requirements": "LISTING" explicito (listagem completa, nao so
    // oferta) - diferente do CreateOfferForExistingASIN que usa
    // "LISTING_OFFER_ONLY". AIssuesJSON devolve o array bruto de "issues"
    // que a Amazon manda de volta (avisos/erros por atributo) mesmo em
    // caso de sucesso parcial - use pra mostrar ao usuario o que falta
    // corrigir.
    function CreateNewProduct(const AAccessToken, ASellerID, ASku,
      AProductType, AAttributesJSON: string;
      out AResponseJSON, AIssuesJSON: string;
      out AErrorMessage: string): Boolean;

    property OnLog: TAmazonLogEvent read FOnLog write FOnLog;
    property MarketplaceID: string read FMarketplaceID write FMarketplaceID;
  end;

function NovoState: string;

implementation

const
  LWA_TOKEN_URL = 'https://api.amazon.com/auth/o2/token';

function NovoState: string;
begin
  Result := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
end;

// {FIX} Converte um TDateTime local pra UTC usando a API do Windows
// (GetTimeZoneInformation) em vez de TTimeZone (System.SysUtils) - o
// TTimeZone estava dando "Undeclared identifier" nesse projeto (motivo
// exato desconhecido, mas essa alternativa via Winapi.Windows e' 100%
// confiavel em qualquer configuracao, ja que o projeto e' Windows/VCL).
function LocalParaUTC(const ALocal: TDateTime): TDateTime;
var
  TZI: TTimeZoneInformation;
  BiasMinutos: Integer;
begin
  case GetTimeZoneInformation(TZI) of
    TIME_ZONE_ID_STANDARD: BiasMinutos := TZI.Bias + TZI.StandardBias;
    TIME_ZONE_ID_DAYLIGHT: BiasMinutos := TZI.Bias + TZI.DaylightBias;
  else
    BiasMinutos := TZI.Bias;
  end;
  // Bias e' "minutos a somar ao horario local pra chegar em UTC"
  // (ex: Brasil UTC-3 -> Bias = +180).
  Result := ALocal + (BiasMinutos / 1440);
end;

{ TAmazonSPAPIClient }

constructor TAmazonSPAPIClient.Create(const AClientID, AClientSecret,
  ARedirectURI, AMarketplaceID: string; ASandbox: Boolean);
begin
  inherited Create;
  FClientID := AClientID;
  FClientSecret := AClientSecret;
  FRedirectURI := ARedirectURI;
  FMarketplaceID := AMarketplaceID;
  FSandbox := ASandbox;

  FHTTPClient := TNetHTTPClient.Create(nil);
  FHTTPClient.ConnectionTimeout := 30000;
  FHTTPClient.ResponseTimeout := 30000;
end;

destructor TAmazonSPAPIClient.Destroy;
begin
  FHTTPClient.Free;
  inherited;
end;

procedure TAmazonSPAPIClient.DoLog(const AMessage: string);
begin
  if Assigned(FOnLog) then
    FOnLog(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' | ' + AMessage);
end;

function TAmazonSPAPIClient.BaseURL: string;
begin
  // Regiao fixada em NA (America do Norte) - inclui o marketplace do Brasil
  // segundo a classificacao da propria Amazon.
  if FSandbox then
    Result := 'https://sandbox.sellingpartnerapi-na.amazon.com'
  else
    Result := 'https://sellingpartnerapi-na.amazon.com';
end;

function TAmazonSPAPIClient.BuildAuthorizationURL(const AApplicationID,
  AState: string): string;
begin
  Result := 'https://sellercentral.amazon.com/apps/authorize/consent' +
    '?application_id=' + TNetEncoding.URL.Encode(AApplicationID) +
    '&state=' + TNetEncoding.URL.Encode(AState) +
    '&version=beta';

  DoLog('URL de autorização gerada: ' + Result);
end;

function TAmazonSPAPIClient.ParseTokenResponse(const AResponseStr: string): TAmazonTokenInfo;
var
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result.Success := False;
  Result.ObtainedAt := Now;
  Result.RawResponse := AResponseStr;

  JSONValue := TJSONObject.ParseJSONValue(AResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      Result.ErrorMessage := 'Resposta inesperada (não é JSON)';
      Exit;
    end;

    JSONObj := TJSONObject(JSONValue);

    if Assigned(JSONObj.GetValue('error')) then
    begin
      Result.ErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('error_description')) then
        Result.ErrorMessage := Result.ErrorMessage + ': ' +
          JSONObj.GetValue<string>('error_description');
      DoLog('Erro ao obter/renovar token: ' + Result.ErrorMessage);
      Exit;
    end;

    if Assigned(JSONObj.GetValue('access_token')) then
      Result.AccessToken := JSONObj.GetValue<string>('access_token');
    if Assigned(JSONObj.GetValue('refresh_token')) then
      Result.RefreshToken := JSONObj.GetValue<string>('refresh_token');
    if Assigned(JSONObj.GetValue('expires_in')) then
      Result.ExpiresIn := JSONObj.GetValue<Integer>('expires_in');

    if Result.AccessToken = '' then
    begin
      Result.ErrorMessage := 'access_token não veio na resposta: ' + AResponseStr;
      DoLog(Result.ErrorMessage);
      Exit;
    end;

    Result.Success := True;
    DoLog('Token obtido com sucesso (expira em ' + Result.ExpiresIn.ToString + 's).');
  finally
    JSONValue.Free;
  end;
end;

function TAmazonSPAPIClient.ExecuteTokenRequest(const ABodyFormEncoded: string): TAmazonTokenInfo;
var
  Response: IHTTPResponse;
  RequestStream: TStringStream;
begin
  Result.Success := False;
  Result.ObtainedAt := Now;

  RequestStream := TStringStream.Create(ABodyFormEncoded, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Post(LWA_TOKEN_URL, RequestStream, nil,
        [TNetHeader.Create('Content-Type', 'application/x-www-form-urlencoded')]);
      Result := ParseTokenResponse(Response.ContentAsString(TEncoding.UTF8));
    except
      on E: Exception do
      begin
        Result.ErrorMessage := E.Message;
        DoLog('Erro na requisição de token: ' + E.Message);
      end;
    end;
  finally
    RequestStream.Free;
  end;
end;

function TAmazonSPAPIClient.ExchangeCodeForTokens(const ASpapiOAuthCode: string): TAmazonTokenInfo;
var
  Body: string;
begin
  DoLog('Trocando spapi_oauth_code por tokens...');

  Body := 'grant_type=authorization_code' +
    '&code=' + TNetEncoding.URL.Encode(ASpapiOAuthCode) +
    '&client_id=' + TNetEncoding.URL.Encode(FClientID) +
    '&client_secret=' + TNetEncoding.URL.Encode(FClientSecret) +
    '&redirect_uri=' + TNetEncoding.URL.Encode(FRedirectURI);

  Result := ExecuteTokenRequest(Body);
end;

function TAmazonSPAPIClient.RefreshAccessToken(const ARefreshToken: string): TAmazonTokenInfo;
var
  Body: string;
begin
  DoLog('Renovando access token a partir do refresh token...');

  Body := 'grant_type=refresh_token' +
    '&refresh_token=' + TNetEncoding.URL.Encode(ARefreshToken) +
    '&client_id=' + TNetEncoding.URL.Encode(FClientID) +
    '&client_secret=' + TNetEncoding.URL.Encode(FClientSecret);

  Result := ExecuteTokenRequest(Body);
end;

function TAmazonSPAPIClient.ExecuteGet(const AApiPath, AQueryExtra,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  URL: string;
  Response: IHTTPResponse;
begin
  URL := BaseURL + AApiPath;
  if AQueryExtra <> '' then
    URL := URL + '?' + AQueryExtra;

  try
    Response := FHTTPClient.Get(URL, nil,
      [TNetHeader.Create('x-amz-access-token', AAccessToken),
       TNetHeader.Create('Content-Type', 'application/json')]);
    AStatusCode := Response.StatusCode;
    Result := Response.ContentAsString(TEncoding.UTF8);
    // {SUPORTE} A Amazon exige o x-amzn-RequestId em qualquer chamado de
    // suporte sobre uma chamada de API especifica - loga sempre (sucesso
    // ou erro) pra ficar facil de copiar quando precisar abrir chamado.
    DoLog('x-amzn-RequestId: ' + Response.HeaderValue['x-amzn-RequestId']);
  except
    on E: Exception do
    begin
      AStatusCode := 0;
      Result := '';
      DoLog('Erro na chamada GET ' + AApiPath + ': ' + E.Message);
    end;
  end;
end;

function TAmazonSPAPIClient.ExecutePost(const AApiPath, AQueryExtra, ABodyJSON,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  URL: string;
  Response: IHTTPResponse;
  BodyStream: TStringStream;
begin
  URL := BaseURL + AApiPath;
  if AQueryExtra <> '' then
    URL := URL + '?' + AQueryExtra;

  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Post(URL, BodyStream, nil,
        [TNetHeader.Create('x-amz-access-token', AAccessToken),
         TNetHeader.Create('Content-Type', 'application/json')]);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
      DoLog('x-amzn-RequestId: ' + Response.HeaderValue['x-amzn-RequestId']);
    except
      on E: Exception do
      begin
        AStatusCode := 0;
        Result := '';
        DoLog('Erro na chamada POST ' + AApiPath + ': ' + E.Message);
      end;
    end;
  finally
    BodyStream.Free;
  end;
end;

function TAmazonSPAPIClient.ExecutePatch(const AApiPath, AQueryExtra, ABodyJSON,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  URL: string;
  Response: IHTTPResponse;
  BodyStream: TStringStream;
begin
  URL := BaseURL + AApiPath;
  if AQueryExtra <> '' then
    URL := URL + '?' + AQueryExtra;

  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Patch(URL, BodyStream, nil,
        [TNetHeader.Create('x-amz-access-token', AAccessToken),
         TNetHeader.Create('Content-Type', 'application/json')]);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
      DoLog('x-amzn-RequestId: ' + Response.HeaderValue['x-amzn-RequestId']);
    except
      on E: Exception do
      begin
        AStatusCode := 0;
        Result := '';
        DoLog('Erro na chamada PATCH ' + AApiPath + ': ' + E.Message);
      end;
    end;
  finally
    BodyStream.Free;
  end;
end;

function TAmazonSPAPIClient.ExecutePut(const AApiPath, AQueryExtra, ABodyJSON,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  URL: string;
  Response: IHTTPResponse;
  BodyStream: TStringStream;
begin
  URL := BaseURL + AApiPath;
  if AQueryExtra <> '' then
    URL := URL + '?' + AQueryExtra;
  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Put(URL, BodyStream, nil,
        [TNetHeader.Create('x-amz-access-token', AAccessToken),
         TNetHeader.Create('Content-Type', 'application/json')]);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
      DoLog('x-amzn-RequestId: ' + Response.HeaderValue['x-amzn-RequestId']);
    except
      on E: Exception do
      begin
        AStatusCode := 0;
        Result := '';
        DoLog('Erro na chamada PUT ' + AApiPath + ': ' + E.Message);
      end;
    end;
  finally
    BodyStream.Free;
  end;
end;

function TAmazonSPAPIClient.TestConnection(const AAccessToken: string;
  out AResponseJSON: string): Boolean;
var
  StatusCode: Integer;
begin
  AResponseJSON := ExecuteGet('/sellers/v1/marketplaceParticipations', '',
    AAccessToken, StatusCode);

  Result := StatusCode = 200;
  if Result then
    DoLog('Teste de conexão OK.')
  else
    DoLog(Format('Teste de conexão falhou (HTTP %d): %s', [StatusCode, AResponseJSON]));
end;

function TAmazonSPAPIClient.GetOrders(const AAccessToken, ACreatedAfter: string;
  out AOrders: TAmazonOrderArray; out AErrorMessage: string): Boolean;
const
  API_PATH = '/orders/v0/orders';
  // {SANDBOX} A Amazon documenta que o sandbox e' "estatico" - so devolve
  // resposta se voce mandar EXATAMENTE esses valores (nao aceita
  // parametros reais, mesmo que validos em producao). O MarketplaceId
  // fixo e' dos EUA (ATVPDKIKX0DER), nao tem equivalente Brasil pro
  // sandbox. Confirmado em teste real 24/08 via curl.
  SANDBOX_CREATED_AFTER = 'TEST_CASE_200';
  SANDBOX_MARKETPLACE_ID = 'ATVPDKIKX0DER';
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONRoot, JSONPayload, Order, OrderTotal: TJSONObject;
  JSONOrders: TJSONArray;
  I: Integer;
  MarketplaceIdUsado, CreatedAfterUsado: string;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AOrders, 0);

  if FSandbox then
  begin
    MarketplaceIdUsado := SANDBOX_MARKETPLACE_ID;
    CreatedAfterUsado := SANDBOX_CREATED_AFTER;
    DoLog('Sandbox ativo - usando valores fixos de teste da Amazon ' +
      '(CreatedAfter=TEST_CASE_200, MarketplaceIds=ATVPDKIKX0DER) em vez ' +
      'dos parametros reais - o pedido que aparecer na tela e um pedido ' +
      'de EXEMPLO fixo da Amazon, nao um pedido de verdade da loja.');
  end
  else
  begin
    MarketplaceIdUsado := FMarketplaceID;
    CreatedAfterUsado := ACreatedAfter;
  end;

  ResponseStr := ExecuteGet(API_PATH,
    'MarketplaceIds=' + MarketplaceIdUsado + '&CreatedAfter=' +
    TNetEncoding.URL.Encode(CreatedAfterUsado), AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  try
    if not Assigned(JSONRoot) then
    begin
      AErrorMessage := 'Resposta não é um JSON válido';
      Exit;
    end;

    JSONPayload := JSONRoot.GetValue('payload') as TJSONObject;
    if not Assigned(JSONPayload) then
    begin
      Result := True; // sem payload, mas sem erro
      Exit;
    end;

    JSONOrders := JSONPayload.GetValue('Orders') as TJSONArray;
    if not Assigned(JSONOrders) then
    begin
      Result := True;
      Exit;
    end;

    SetLength(AOrders, JSONOrders.Count);
    for I := 0 to JSONOrders.Count - 1 do
    begin
      Order := JSONOrders.Items[I] as TJSONObject;
      AOrders[I].AmazonOrderId := Order.GetValue<string>('AmazonOrderId');
      AOrders[I].OrderStatus := Order.GetValue<string>('OrderStatus');
      AOrders[I].PurchaseDate := Order.GetValue<string>('PurchaseDate');

      OrderTotal := Order.GetValue('OrderTotal') as TJSONObject;
      if Assigned(OrderTotal) then
      begin
        AOrders[I].CurrencyCode := OrderTotal.GetValue<string>('CurrencyCode');
        AOrders[I].TotalAmount := OrderTotal.GetValue<string>('Amount');
      end;
    end;

    Result := True;
    DoLog(Format('%d pedido(s) encontrado(s).', [Length(AOrders)]));
  finally
    JSONRoot.Free;
  end;
end;

// Traduz um AmazonOrderId real pro "ID magico" que o SANDBOX ESTATICO da
// Amazon exige nas operacoes que recebem orderId no path.
//
// Confirmado em 26/08/2026 por duas fontes:
//   1. Resposta do suporte de desenvolvedores da SP-API (caso aberto sobre
//      o erro "InvalidInput - Could not match input arguments"): cada
//      operacao do sandbox estatico tem seu proprio bloco
//      x-amzn-api-sandbox no modelo Swagger, e a saida de uma operacao NAO
//      serve de entrada pra outra - ou seja, os AmazonOrderId que o
//      getOrders devolve no sandbox (902-1845936-5435065 etc) NAO valem
//      pra getOrderItems/getOrder.
//   2. O proprio ordersV0.json (repositorio oficial amzn/
//      selling-partner-api-models): em getOrder e getOrderBuyerInfo o
//      bloco x-amzn-api-sandbox usa orderId = "TEST_CASE_200".
//
// Em PRODUCAO nao muda nada - devolve o ID real recebido.
function OrderIdParaSandbox(const AAmazonOrderId: string;
  const ASandbox: Boolean): string;
begin
  if ASandbox then
    Result := 'TEST_CASE_200'
  else
    Result := AAmazonOrderId;
end;

function TAmazonSPAPIClient.GetOrderItems(const AAccessToken, AAmazonOrderId: string;
  out AItems: TAmazonOrderItemArray; out AErrorMessage: string): Boolean;
var
  ApiPath, ResponseStr: string;
  StatusCode: Integer;
  JSONRoot, JSONPayload, ItemObj: TJSONObject;
  JSONItems: TJSONArray;
  I: Integer;
  ItemPriceObj, ShippingPriceObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AItems, 0);

  // Idem GetOrderDetail: no sandbox vai o ID magico, nao o AmazonOrderId
  // que o getOrders devolveu (era exatamente essa a causa do erro
  // "InvalidInput - Could not match input arguments").
  ApiPath := '/orders/v0/orders/' +
    TNetEncoding.URL.Encode(OrderIdParaSandbox(AAmazonOrderId, FSandbox)) + '/orderItems';
  if FSandbox then
    DoLog('Sandbox: consultando os itens do pedido de exemplo TEST_CASE_200 ' +
      'em vez de ' + AAmazonOrderId + '.');
  ResponseStr := ExecuteGet(ApiPath, '', AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  try
    if not Assigned(JSONRoot) then
    begin
      AErrorMessage := 'Resposta não é um JSON válido';
      Exit;
    end;

    JSONPayload := JSONRoot.GetValue('payload') as TJSONObject;
    if not Assigned(JSONPayload) then
    begin
      Result := True;
      Exit;
    end;

    JSONItems := JSONPayload.GetValue('OrderItems') as TJSONArray;
    if not Assigned(JSONItems) then
    begin
      Result := True;
      Exit;
    end;

    SetLength(AItems, JSONItems.Count);
    for I := 0 to JSONItems.Count - 1 do
    begin
      ItemObj := JSONItems.Items[I] as TJSONObject;
      AItems[I].OrderItemId := ItemObj.GetValue<string>('OrderItemId');
      if Assigned(ItemObj.GetValue('SellerSKU')) then
        AItems[I].SellerSKU := ItemObj.GetValue<string>('SellerSKU');
      if Assigned(ItemObj.GetValue('Title')) then
        AItems[I].Title := ItemObj.GetValue<string>('Title');
      if Assigned(ItemObj.GetValue('QuantityOrdered')) then
        AItems[I].QuantityOrdered := ItemObj.GetValue<Integer>('QuantityOrdered');
      if Assigned(ItemObj.GetValue('ASIN')) then
        AItems[I].ASIN := ItemObj.GetValue<string>('ASIN');
      if Assigned(ItemObj.GetValue('ConditionId')) then
        AItems[I].ConditionId := ItemObj.GetValue<string>('ConditionId');
      if ItemObj.TryGetValue<TJSONObject>('ItemPrice', ItemPriceObj) then
        ItemPriceObj.TryGetValue<Double>('Amount', AItems[I].ItemPriceAmount);
      if ItemObj.TryGetValue<TJSONObject>('ShippingPrice', ShippingPriceObj) then
        ShippingPriceObj.TryGetValue<Double>('Amount', AItems[I].ShippingPrice);
    end;

    Result := True;
    DoLog(Format('%d item(ns) encontrado(s) no pedido %s.', [Length(AItems), AAmazonOrderId]));
  finally
    JSONRoot.Free;
  end;
end;

function TAmazonSPAPIClient.GetOrderDetail(const AAccessToken, AAmazonOrderId: string;
  out ADetalhe: TAmazonOrderDetail; out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  StatusCode: Integer;
  JSONRoot, JSONPayload, BuyerInfoObj, AddressObj, OrderTotalObj: TJSONObject;
  AddressLine1, AddressLine2, AddressLine3: string;
  Linhas: TArray<string>;
  I, N: Integer;
begin
  Result := False;
  AErrorMessage := '';
  ADetalhe.AmazonOrderId := AAmazonOrderId;

  // No sandbox, o path precisa do ID magico - ver OrderIdParaSandbox.
  ApiPath := '/orders/v0/orders/' +
    TNetEncoding.URL.Encode(OrderIdParaSandbox(AAmazonOrderId, FSandbox));
  if FSandbox then
    DoLog('Sandbox: consultando o pedido de exemplo TEST_CASE_200 em vez de ' +
      AAmazonOrderId + ' (o sandbox estatico so responde ao ID magico).');
  ADetalhe.RawJSON := ExecuteGet(ApiPath, '', AAccessToken, StatusCode);

  DoLog('GetOrderDetail (' + AAmazonOrderId + '): ' + ADetalhe.RawJSON);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ADetalhe.RawJSON]);
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ADetalhe.RawJSON) as TJSONObject;
  try
    if not Assigned(JSONRoot) then
    begin
      AErrorMessage := 'Resposta não é um JSON válido';
      Exit;
    end;

    JSONPayload := JSONRoot.GetValue('payload') as TJSONObject;
    if not Assigned(JSONPayload) then
    begin
      AErrorMessage := 'Resposta sem campo "payload" - pedido nao encontrado.';
      Exit;
    end;

    JSONPayload.TryGetValue<string>('OrderStatus', ADetalhe.OrderStatus);
    if Assigned(JSONPayload.GetValue('PurchaseDate')) then
      ADetalhe.PurchaseDate := ISO8601ToDate(JSONPayload.GetValue<string>('PurchaseDate'), False);
    if Assigned(JSONPayload.GetValue('LastUpdateDate')) then
      ADetalhe.LastUpdateDate := ISO8601ToDate(JSONPayload.GetValue<string>('LastUpdateDate'), False);

    if JSONPayload.TryGetValue<TJSONObject>('OrderTotal', OrderTotalObj) then
      OrderTotalObj.TryGetValue<Double>('Amount', ADetalhe.TotalAmount);

    // {ATENCAO} BuyerInfo so vem preenchido se o app tiver a role
    // restrita de PII aprovada pela Amazon (mesma role que a Nota
    // Fiscal precisa) - sem ela, esses campos ficam vazios mesmo com o
    // pedido existindo.
    if JSONPayload.TryGetValue<TJSONObject>('BuyerInfo', BuyerInfoObj) then
    begin
      BuyerInfoObj.TryGetValue<string>('BuyerName', ADetalhe.BuyerName);
      BuyerInfoObj.TryGetValue<string>('BuyerEmail', ADetalhe.BuyerEmail);
    end;

    if JSONPayload.TryGetValue<TJSONObject>('ShippingAddress', AddressObj) then
    begin
      AddressObj.TryGetValue<string>('Name', ADetalhe.ShippingName);
      AddressObj.TryGetValue<string>('Phone', ADetalhe.ShippingPhone);
      AddressObj.TryGetValue<string>('City', ADetalhe.ShippingCity);
      AddressObj.TryGetValue<string>('District', ADetalhe.ShippingDistrict);
      AddressObj.TryGetValue<string>('StateOrRegion', ADetalhe.ShippingState);
      AddressObj.TryGetValue<string>('PostalCode', ADetalhe.ShippingPostalCode);
      AddressObj.TryGetValue<string>('CountryCode', ADetalhe.ShippingCountryCode);

      // AddressLine1/2/3 concatenados num so campo (mesmo espirito do
      // full_address ja pronto que a Shopee devolve).
      AddressLine1 := '';
      AddressLine2 := '';
      AddressLine3 := '';
      AddressObj.TryGetValue<string>('AddressLine1', AddressLine1);
      AddressObj.TryGetValue<string>('AddressLine2', AddressLine2);
      AddressObj.TryGetValue<string>('AddressLine3', AddressLine3);
      SetLength(Linhas, 0);
      N := 0;
      SetLength(Linhas, 3);
      if AddressLine1 <> '' then begin Linhas[N] := AddressLine1; Inc(N); end;
      if AddressLine2 <> '' then begin Linhas[N] := AddressLine2; Inc(N); end;
      if AddressLine3 <> '' then begin Linhas[N] := AddressLine3; Inc(N); end;
      SetLength(Linhas, N);
      ADetalhe.ShippingAddressLine := '';
      for I := 0 to High(Linhas) do
      begin
        if I > 0 then
          ADetalhe.ShippingAddressLine := ADetalhe.ShippingAddressLine + ', ';
        ADetalhe.ShippingAddressLine := ADetalhe.ShippingAddressLine + Linhas[I];
      end;
    end;

    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TAmazonSPAPIClient.GetOrderNetAmount(const AAccessToken, AAmazonOrderId: string;
  APostedAfter: TDateTime; out ANetAmount: Double; out ARawJSON: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/finances/2024-06-19/transactions';
var
  StatusCode: Integer;
  Query: string;
  JSONRoot, JSONPayload, TransObj, TotalAmountObj: TJSONObject;
  JSONTransactions: TJSONArray;
  I: Integer;
  ValorTransacao: Double;
begin
  Result := False;
  AErrorMessage := '';
  ANetAmount := 0;

  // {ATENCAO} postedAfter e' obrigatorio e o intervalo max e' 180 dias -
  // usa a data de compra do pedido como inicio (deve ser mais que
  // suficiente pra pegar todos os eventos financeiros desse pedido) e
  // "agora" como fim.
  Query := 'postedAfter=' + TNetEncoding.URL.Encode(
    FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', LocalParaUTC(APostedAfter))) +
    '&postedBefore=' + TNetEncoding.URL.Encode(
    FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', LocalParaUTC(Now))) +
    '&relatedIdentifierName=ORDER_ID&relatedIdentifierValue=' +
    TNetEncoding.URL.Encode(AAmazonOrderId);

  ARawJSON := ExecuteGet(API_PATH, Query, AAccessToken, StatusCode);

  DoLog('GetOrderNetAmount (' + AAmazonOrderId + '): ' + ARawJSON);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ARawJSON]);
    if StatusCode = 403 then
      AErrorMessage := AErrorMessage + ' - (HTTP 403 aqui costuma significar que a role ' +
        '"Finance and Accounting" ainda nao foi aprovada pela Amazon pro app)';
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ARawJSON) as TJSONObject;
  try
    if not Assigned(JSONRoot) then
    begin
      AErrorMessage := 'Resposta não é um JSON válido';
      Exit;
    end;

    JSONPayload := JSONRoot.GetValue('payload') as TJSONObject;
    if not Assigned(JSONPayload) then
    begin
      Result := True; // sem payload = sem transacao ainda pra esse pedido, mas sem erro
      Exit;
    end;

    JSONTransactions := JSONPayload.GetValue('transactions') as TJSONArray;
    if not Assigned(JSONTransactions) then
    begin
      Result := True;
      Exit;
    end;

    // {ATENCAO} nomes de campo abaixo (transactions/totalAmount/
    // currencyAmount) sao o melhor palpite baseado na documentacao
    // (camelCase, diferente do PascalCase da v0) - ainda NAO confirmado
    // contra uma resposta real, ja que depende da role aprovada. totalAmount
    // ja vem com sinal (taxa negativa, venda positiva), entao somar todas
    // as transacoes do pedido da' o valor liquido direto, sem precisar
    // decompor a arvore de "breakdowns".
    for I := 0 to JSONTransactions.Count - 1 do
    begin
      TransObj := JSONTransactions.Items[I] as TJSONObject;
      if TransObj.TryGetValue<TJSONObject>('totalAmount', TotalAmountObj) then
        if TotalAmountObj.TryGetValue<Double>('currencyAmount', ValorTransacao) then
          ANetAmount := ANetAmount + ValorTransacao;
    end;

    Result := True;
    DoLog(Format('%d transacao(oes) financeira(s) encontrada(s) pro pedido %s - valor liquido: %.2f',
      [JSONTransactions.Count, AAmazonOrderId, ANetAmount]));
  finally
    JSONRoot.Free;
  end;
end;

function TAmazonSPAPIClient.ConfirmShipment(const AAccessToken, AAmazonOrderId, ACarrierCode,
  ACarrierName, ATrackingNumber: string; AShipDate: TDateTime;
  const AItems: TAmazonOrderItemArray; out AErrorMessage: string): Boolean;
var
  ApiPath, BodyStr, ResponseStr: string;
  StatusCode: Integer;
  Root, PackageDetail, ItemObj: TJSONObject;
  ItemsArr: TJSONArray;
  I: Integer;
begin
  Result := False;
  AErrorMessage := '';

  if Length(AItems) = 0 then
  begin
    AErrorMessage := 'Nenhum item informado - busque os itens do pedido (GetOrderItems) antes.';
    Exit;
  end;

  ItemsArr := TJSONArray.Create;
  for I := 0 to High(AItems) do
  begin
    ItemObj := TJSONObject.Create;
    ItemObj.AddPair('orderItemId', AItems[I].OrderItemId);
    ItemObj.AddPair('quantity', TJSONNumber.Create(AItems[I].QuantityOrdered));
    ItemsArr.AddElement(ItemObj);
  end;

  PackageDetail := TJSONObject.Create;
  // {ATENCAO} packageReferenceId - documentacao oficial diz que aceita
  // string, mas ha' relatos de desenvolvedores (issue #5094 do repo de
  // modelos da Amazon) de que só valores NUMERICOS POSITIVOS funcionam de
  // fato - por isso usa '1' fixo (unico pacote por pedido, cenario mais
  // comum) em vez de gerar algo alfanumerico.
  PackageDetail.AddPair('packageReferenceId', '1');
  PackageDetail.AddPair('carrierCode', ACarrierCode);
  if SameText(ACarrierCode, 'Other') and (ACarrierName <> '') then
    PackageDetail.AddPair('carrierName', ACarrierName);
  PackageDetail.AddPair('trackingNumber', ATrackingNumber);
  // shipDate em UTC, formato ISO 8601 (Amazon exige isso explicitamente).
  PackageDetail.AddPair('shipDate', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',
    LocalParaUTC(AShipDate)));
  PackageDetail.AddPair('orderItems', ItemsArr);

  Root := TJSONObject.Create;
  try
    Root.AddPair('marketplaceId', FMarketplaceID);
    Root.AddPair('packageDetail', PackageDetail);
    BodyStr := Root.ToJSON;
  finally
    Root.Free;
  end;

  DoLog('ConfirmShipment body enviado (pedido ' + AAmazonOrderId + '): ' + BodyStr);

  ApiPath := '/orders/v0/orders/' + TNetEncoding.URL.Encode(AAmazonOrderId) + '/shipmentConfirmation';
  ResponseStr := ExecutePost(ApiPath, '', BodyStr, AAccessToken, StatusCode);

  DoLog('ConfirmShipment resposta: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  // Sucesso e' 204 (sem corpo) segundo a doc oficial.
  if (StatusCode <> 204) and (StatusCode <> 200) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Pedido ' + AAmazonOrderId + ' despachado com sucesso (rastreio: ' +
    ATrackingNumber + ').');
end;

function TAmazonSPAPIClient.SubmitDeliveryInvoice(const AAccessToken, AAmazonOrderId: string;
  const AXmlBytes: TBytes; out AErrorMessage: string): Boolean;
var
  ApiPath, BodyStr, ResponseStr, InvoiceContentB64, MD5Base64: string;
  StatusCode: Integer;
  Root: TJSONObject;
  MD5Digest: TBytes;
  MD5Hash: THashMD5;
begin
  Result := False;
  AErrorMessage := '';

  if Length(AXmlBytes) = 0 then
  begin
    AErrorMessage := 'Arquivo XML vazio.';
    Exit;
  end;

  // Base64 do conteudo do XML - remove quebras de linha que o
  // TNetEncoding.Base64 insere por padrao (Amazon espera uma unica linha).
  InvoiceContentB64 := TNetEncoding.Base64.EncodeBytesToString(AXmlBytes);
  InvoiceContentB64 := StringReplace(InvoiceContentB64, sLineBreak, '', [rfReplaceAll]);
  InvoiceContentB64 := StringReplace(InvoiceContentB64, #13, '', [rfReplaceAll]);
  InvoiceContentB64 := StringReplace(InvoiceContentB64, #10, '', [rfReplaceAll]);

  // MD5 dos bytes originais (nao do base64!), tambem em base64 - e' o
  // "contentMD5Value" que a Amazon usa pra verificar integridade.
  // {FIX} THashMD5.GetHashBytes nao tem overload pra TBytes nessa versao
  // do RTL - usa o padrao de instancia (Create + Update + HashAsBytes),
  // que aceita TBytes direto.
  MD5Hash := THashMD5.Create;
  MD5Hash.Update(AXmlBytes);
  MD5Digest := MD5Hash.HashAsBytes;
  MD5Base64 := TNetEncoding.Base64.EncodeBytesToString(MD5Digest);
  MD5Base64 := StringReplace(MD5Base64, sLineBreak, '', [rfReplaceAll]);
  MD5Base64 := StringReplace(MD5Base64, #13, '', [rfReplaceAll]);
  MD5Base64 := StringReplace(MD5Base64, #10, '', [rfReplaceAll]);

  Root := TJSONObject.Create;
  try
    Root.AddPair('invoiceContent', InvoiceContentB64);
    Root.AddPair('contentMD5Value', MD5Base64);
    Root.AddPair('invoiceType', 'Outbound');
    // {ATENCAO} "SelfShip" e' pra pedido MFN onde o proprio vendedor
    // despacha (nosso caso ate agora) - se um pedido usar Easy Ship, seria
    // "EasyShip" em vez disso (ver doc oficial - Delivery by Amazon API).
    Root.AddPair('programType', 'SelfShip');
    Root.AddPair('marketplaceId', FMarketplaceID);
    BodyStr := Root.ToJSON;
  finally
    Root.Free;
  end;

  DoLog('SubmitDeliveryInvoice body enviado (pedido ' + AAmazonOrderId + ', ' +
    Length(AXmlBytes).ToString + ' bytes de XML)');

  ApiPath := '/delivery/2022-07-01/invoice';
  ResponseStr := ExecutePost(ApiPath, 'orderId=' + TNetEncoding.URL.Encode(AAmazonOrderId),
    BodyStr, AAccessToken, StatusCode);

  DoLog('SubmitDeliveryInvoice resposta: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if (StatusCode <> 200) and (StatusCode <> 202) and (StatusCode <> 204) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    if StatusCode = 403 then
      AErrorMessage := AErrorMessage + ' - (HTTP 403 aqui costuma significar que a role ' +
        '"Tax Invoicing (Restricted)" ainda nao foi aprovada pela Amazon pro app)';
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Nota fiscal enviada com sucesso para o pedido ' + AAmazonOrderId + '.');
end;

function TAmazonSPAPIClient.GetDeliveryInvoiceStatus(const AAccessToken, AAmazonOrderId: string;
  out AStatus: string; out AErrorMessage: string): Boolean;
var
  ApiPath, ResponseStr: string;
  StatusCode: Integer;
  JSONRoot: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  AStatus := '';

  ApiPath := '/delivery/2022-07-01/invoice/status';
  ResponseStr := ExecuteGet(ApiPath,
    'marketplaceId=' + FMarketplaceID + '&programType=SelfShip&orderId=' +
    TNetEncoding.URL.Encode(AAmazonOrderId) + '&invoiceType=Outbound',
    AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    if StatusCode = 403 then
      AErrorMessage := AErrorMessage + ' - (HTTP 403 aqui costuma significar que a role ' +
        '"Tax Invoicing (Restricted)" ainda nao foi aprovada pela Amazon pro app)';
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  try
    // {ATENCAO} nome exato do campo de status na resposta nao confirmado
    // contra a API real - se "invoiceStatus" nao existir, cai no fallback
    // de mostrar a resposta crua (o log completo ja mostra de qualquer jeito).
    if Assigned(JSONRoot) and Assigned(JSONRoot.GetValue('invoiceStatus')) then
      AStatus := JSONRoot.GetValue<string>('invoiceStatus')
    else
      AStatus := ResponseStr;
    Result := True;
  finally
    if Assigned(JSONRoot) then
      JSONRoot.Free;
  end;
end;

function TAmazonSPAPIClient.GetCompetitiveSummary(const AAccessToken, AAsin: string;
  out AResponseJSON: string; out AErrorMessage: string): Boolean;
const
  API_PATH = '/batches/products/pricing/2022-05-01/items/competitiveSummary';
var
  Root, Req: TJSONObject;
  Requests, IncludedData: TJSONArray;
  BodyJSON: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  IncludedData := TJSONArray.Create;
  IncludedData.Add('featuredBuyingOptions');
  IncludedData.Add('referencePrices');
  IncludedData.Add('lowestPricedOffers');

  Req := TJSONObject.Create;
  Req.AddPair('asin', AAsin);
  Req.AddPair('marketplaceId', FMarketplaceID);
  Req.AddPair('includedData', IncludedData);
  Req.AddPair('uri', '/products/pricing/2022-05-01/items/competitiveSummary');
  Req.AddPair('method', 'GET');

  Requests := TJSONArray.Create;
  Requests.AddElement(Req);

  Root := TJSONObject.Create;
  Root.AddPair('requests', Requests);
  try
    BodyJSON := Root.ToJSON;
  finally
    Root.Free;
  end;

  AResponseJSON := ExecutePost(API_PATH, '', BodyJSON, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Competitive summary obtido para ASIN ' + AAsin);
end;

function TAmazonSPAPIClient.GetListingsItem(const AAccessToken, ASellerID, ASku: string;
  out AResponseJSON: string; out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  ApiPath := '/listings/2021-08-01/items/' + ASellerID + '/' +
    TNetEncoding.URL.Encode(ASku);

  AResponseJSON := ExecuteGet(ApiPath,
    'marketplaceIds=' + FMarketplaceID +
    '&includedData=summaries,attributes,issues,offers,fulfillmentAvailability',
    AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Oferta/listing obtido para SKU ' + ASku);
end;

function TAmazonSPAPIClient.SearchListingsItems(const AAccessToken, ASellerID: string;
  out AItems: TAmazonListingItemArray; out AErrorMessage: string): Boolean;
const
  API_PATH_BASE = '/listings/2021-08-01/items/';
  // 20 e' o teto que a propria Amazon aceita nessa API - pedir mais devolve
  // erro. Entao paginar nao e' otimizacao, e' obrigatorio pra quem tem
  // catalogo maior que isso.
  PAGE_SIZE = 20;
  // Trava contra laco infinito (nextToken que nunca zera ou que se repete).
  // 500 x 20 = 10.000 ofertas, bem acima do caso real - se alguem bater
  // nisso, o log avisa em vez de listar errado calado.
  MAX_PAGINAS = 500;
var
  ApiPath, QueryBase, Query, ResponseJSON, NextToken, TokenAnterior: string;
  DataTxt: string;
  DataAlt: TDateTime;
  StatusCode, Pagina, Base, I: Integer;
  JSONValue: TJSONValue;
  JSONObj, ItemObj, SummaryObj, PriceObj, FulfillObj, PagObj: TJSONObject;
  ItemsArr, SummariesArr, OffersArr, FulfillArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AItems, 0);
  ApiPath := API_PATH_BASE + ASellerID;
  QueryBase := 'marketplaceIds=' + FMarketplaceID +
    '&includedData=summaries,attributes,offers,fulfillmentAvailability' +
    '&pageSize=' + IntToStr(PAGE_SIZE);
  NextToken := '';
  Pagina := 0;
  repeat
    Inc(Pagina);
    Query := QueryBase;
    // O nextToken vem em base64 e pode conter '+' - sem encodar, o '+' chega
    // como espaco do outro lado e a Amazon responde token invalido.
    if NextToken <> '' then
      Query := Query + '&pageToken=' + TNetEncoding.URL.Encode(NextToken);
    ResponseJSON := ExecuteGet(ApiPath, Query, AAccessToken, StatusCode);
    // Log de diagnostico com a resposta bruta - a estrutura de offers/
    // fulfillmentAvailability pode variar (nem todo item tem preco/estoque
    // preenchido, por exemplo) - ajuda a confirmar/ajustar o parse abaixo
    // com dados reais.
    DoLog(Format('searchListingsItems (pagina %d): %s', [Pagina, ResponseJSON]));
    if StatusCode <> 200 then
    begin
      // Falha no meio da paginacao devolve ERRO, nao lista parcial: uma lista
      // curta e silenciosa e' pior que um erro visivel, porque parece que o
      // vendedor simplesmente nao tem mais ofertas.
      AErrorMessage := Format('HTTP %d na pagina %d: %s',
        [StatusCode, Pagina, ResponseJSON]);
      DoLog(AErrorMessage);
      SetLength(AItems, 0);
      Exit;
    end;
    TokenAnterior := NextToken;
    NextToken := '';
    JSONValue := TJSONObject.ParseJSONValue(ResponseJSON);
    try
      if not (JSONValue is TJSONObject) then
      begin
        AErrorMessage := Format('Resposta invalida ao listar ofertas (pagina %d).',
          [Pagina]);
        SetLength(AItems, 0);
        Exit;
      end;
      JSONObj := TJSONObject(JSONValue);
      if not JSONObj.TryGetValue<TJSONArray>('items', ItemsArr) then
      begin
        // Sem itens nessa pagina nao e' erro: na primeira, quer dizer
        // vendedor sem ofertas; numa seguinte, fim da lista.
        Result := True;
        Exit;
      end;
      // ACRESCENTA ao que ja veio das paginas anteriores. O SetLength direto
      // no Count da pagina era o bug: cada pagina jogava fora a anterior.
      Base := Length(AItems);
      SetLength(AItems, Base + ItemsArr.Count);
      for I := 0 to ItemsArr.Count - 1 do
      begin
        ItemObj := ItemsArr.Items[I] as TJSONObject;
        AItems[Base + I].SKU := ItemObj.GetValue<string>('sku');
        AItems[Base + I].ASIN := '';
        AItems[Base + I].ItemName := '';
        AItems[Base + I].Status := '';
        AItems[Base + I].Price := 0;
        AItems[Base + I].Currency := '';
        AItems[Base + I].Stock := 0;
        AItems[Base + I].LastUpdated := 0;
        // {ATENCAO} SummariesArr zerado a cada volta de proposito: o
        // TryGetValue nao limpa a variavel quando falha, e como ela e' local
        // da funcao (nao do laco), um item sem "summaries" herdaria nome,
        // ASIN e status do item anterior.
        SummariesArr := nil;
        if ItemObj.TryGetValue<TJSONArray>('summaries', SummariesArr) and
           (SummariesArr.Count > 0) then
        begin
          SummaryObj := SummariesArr.Items[0] as TJSONObject;
          SummaryObj.TryGetValue<string>('itemName', AItems[Base + I].ItemName);
          SummaryObj.TryGetValue<string>('asin', AItems[Base + I].ASIN);
          // Status vem como array (ex: ["BUYABLE"]) dentro de summaries -
          // pega o primeiro valor como representativo.
          if Assigned(SummaryObj.GetValue('status')) and
             (SummaryObj.GetValue('status') is TJSONArray) and
             (TJSONArray(SummaryObj.GetValue('status')).Count > 0) then
            AItems[Base + I].Status :=
              TJSONArray(SummaryObj.GetValue('status')).Items[0].Value;
          // Data da ultima alteracao do anuncio, ISO 8601 em UTC
          // (ex: 2026-10-14T18:22:05.123Z) - convertida para hora local.
          DataTxt := '';
          if SummaryObj.TryGetValue<string>('lastUpdatedDate', DataTxt) and
             TryISO8601ToDate(DataTxt, DataAlt, False) then
            AItems[Base + I].LastUpdated := DataAlt;
        end;
        if ItemObj.TryGetValue<TJSONArray>('offers', OffersArr) and
           (OffersArr.Count > 0) then
        begin
          if (OffersArr.Items[0] as TJSONObject).TryGetValue<TJSONObject>('price', PriceObj) then
          begin
            PriceObj.TryGetValue<Double>('amount', AItems[Base + I].Price);
            PriceObj.TryGetValue<string>('currencyCode', AItems[Base + I].Currency);
          end;
        end;
        if ItemObj.TryGetValue<TJSONArray>('fulfillmentAvailability', FulfillArr) and
           (FulfillArr.Count > 0) then
        begin
          FulfillObj := FulfillArr.Items[0] as TJSONObject;
          FulfillObj.TryGetValue<Integer>('quantity', AItems[Base + I].Stock);
        end;
      end;
      // pagination.nextToken ausente ou vazio = acabou.
      if JSONObj.TryGetValue<TJSONObject>('pagination', PagObj) then
        PagObj.TryGetValue<string>('nextToken', NextToken);
    finally
      JSONValue.Free;
    end;
    if (NextToken <> '') and (NextToken = TokenAnterior) then
    begin
      DoLog(Format('Aviso: nextToken repetido na pagina %d - paginacao'
        + ' interrompida pra nao entrar em laco.', [Pagina]));
      Break;
    end;
    if (NextToken <> '') and (Pagina >= MAX_PAGINAS) then
    begin
      DoLog(Format('Aviso: limite de %d paginas atingido - podem existir mais'
        + ' ofertas nao listadas.', [MAX_PAGINAS]));
      Break;
    end;
  until NextToken = '';
  Result := True;
  DoLog(Format('%d oferta(s) encontrada(s) em %d pagina(s).',
    [Length(AItems), Pagina]));
end;

function TAmazonSPAPIClient.PatchListingsItemAttribute(const AAccessToken, ASellerID,
  ASku, AAttributeName, AAttributeValue: string;
  out AResponseJSON: string; out AErrorMessage: string): Boolean;
var
  ApiPath, BodyJSON: string;
  Root, Patch, ValueObj: TJSONObject;
  Patches, Values: TJSONArray;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  // NOTA: o atributo real para alterar preço/estoque depende do Product Type
  // Definitions schema do produto específico - o schema real só é obtido com
  // uma conta de vendedor autorizada (no sandbox o link do schema é fictício).
  ValueObj := TJSONObject.Create;
  ValueObj.AddPair('value', AAttributeValue);

  Values := TJSONArray.Create;
  Values.AddElement(ValueObj);

  Patch := TJSONObject.Create;
  Patch.AddPair('op', 'replace');
  Patch.AddPair('path', '/attributes/' + AAttributeName);
  Patch.AddPair('value', Values);

  Patches := TJSONArray.Create;
  Patches.AddElement(Patch);

  Root := TJSONObject.Create;
  Root.AddPair('productType', 'PRODUCT');
  Root.AddPair('patches', Patches);
  try
    BodyJSON := Root.ToJSON;
  finally
    Root.Free;
  end;

  ApiPath := '/listings/2021-08-01/items/' + ASellerID + '/' +
    TNetEncoding.URL.Encode(ASku);

  AResponseJSON := ExecutePatch(ApiPath,
    'marketplaceIds=' + FMarketplaceID + '&includedData=identifiers,issues',
    BodyJSON, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Atributo "' + AAttributeName + '" atualizado para SKU ' + ASku);
end;

function TAmazonSPAPIClient.UpdateStockQuantity(const AAccessToken, ASellerID, ASku: string;
  AQuantity: Integer; out AResponseJSON: string; out AErrorMessage: string): Boolean;
var
  ItemJSON, ApiPath, BodyStr, ProductType, Severity: string;
  ItemValue, JSONValue: TJSONValue;
  ItemObj, SummaryObj, JSONObj, IssueObj, Root, Patch, FulfillObj: TJSONObject;
  SummariesArr, IssuesArr, Patches, PatchValueArr: TJSONArray;
  StatusCode, I: Integer;
  TemIssueDeErro: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  AResponseJSON := '';
  TemIssueDeErro := False;

  // Passo 1: descobre o productType REAL do SKU - obrigatorio no corpo do
  // PATCH. Usar um valor fixo generico (como o metodo legado
  // PatchListingsItemAttribute fazia, com 'PRODUCT') e' quase sempre
  // errado - ja vimos isso na pratica (era, por exemplo, "DRINKING_CUP").
  if not GetListingsItem(AAccessToken, ASellerID, ASku, ItemJSON, AErrorMessage) then
  begin
    AErrorMessage := 'Nao foi possivel obter dados do SKU ' + ASku + ' antes de ' +
      'atualizar o estoque: ' + AErrorMessage;
    Exit;
  end;

  ProductType := '';
  ItemValue := TJSONObject.ParseJSONValue(ItemJSON);
  try
    if ItemValue is TJSONObject then
    begin
      ItemObj := TJSONObject(ItemValue);
      if ItemObj.TryGetValue<TJSONArray>('summaries', SummariesArr) and (SummariesArr.Count > 0) then
      begin
        SummaryObj := SummariesArr.Items[0] as TJSONObject;
        SummaryObj.TryGetValue<string>('productType', ProductType);
      end;
    end;
  finally
    ItemValue.Free;
  end;

  if ProductType = '' then
  begin
    AErrorMessage := 'Nao foi possivel descobrir o productType do SKU ' + ASku +
      ' (resposta da Amazon nao trouxe "summaries[0].productType") - sem isso ' +
      'nao da pra montar o PATCH corretamente.';
    DoLog(AErrorMessage);
    Exit;
  end;

  // Passo 2: monta o PATCH com o formato REAL de fulfillment_availability
  // (fulfillment_channel_code + quantity - NAO um "value" de texto solto).
  FulfillObj := TJSONObject.Create;
  FulfillObj.AddPair('fulfillment_channel_code', 'DEFAULT');
  FulfillObj.AddPair('quantity', TJSONNumber.Create(AQuantity));
  FulfillObj.AddPair('marketplace_id', FMarketplaceID);

  PatchValueArr := TJSONArray.Create;
  PatchValueArr.AddElement(FulfillObj);

  Patch := TJSONObject.Create;
  Patch.AddPair('op', 'replace');
  Patch.AddPair('path', '/attributes/fulfillment_availability');
  Patch.AddPair('value', PatchValueArr);

  Patches := TJSONArray.Create;
  Patches.AddElement(Patch);

  Root := TJSONObject.Create;
  try
    Root.AddPair('productType', ProductType);
    Root.AddPair('patches', Patches);
    BodyStr := Root.ToJSON;
  finally
    Root.Free;
  end;

  DoLog('UpdateStockQuantity body enviado (SKU ' + ASku + ', productType ' + ProductType +
    '): ' + BodyStr);

  ApiPath := '/listings/2021-08-01/items/' + ASellerID + '/' + TNetEncoding.URL.Encode(ASku);

  // {ATENCAO} SEM "includedData" de proposito - esse parametro extra foi
  // exatamente o que causava o erro generico "InvalidInput / cannot be
  // parsed" no PUT de CreateNewProduct (ver historico) - nao arrisca
  // repetir o mesmo problema aqui no PATCH.
  AResponseJSON := ExecutePatch(ApiPath, 'marketplaceIds=' + FMarketplaceID,
    BodyStr, AAccessToken, StatusCode);

  DoLog('UpdateStockQuantity resposta: ' + AResponseJSON);

  if (StatusCode <> 200) and (StatusCode <> 202) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;

  // Mesmo com HTTP 200/202, confere "issues" de severidade ERROR - mesmo
  // padrao ja usado em CreateOfferForExistingASIN/CreateNewProduct.
  JSONValue := TJSONObject.ParseJSONValue(AResponseJSON);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if JSONObj.TryGetValue<TJSONArray>('issues', IssuesArr) then
        for I := 0 to IssuesArr.Count - 1 do
        begin
          IssueObj := IssuesArr.Items[I] as TJSONObject;
          Severity := '';
          IssueObj.TryGetValue<string>('severity', Severity);
          if SameText(Severity, 'ERROR') then
            TemIssueDeErro := True;
        end;
    end;
  finally
    if Assigned(JSONValue) then
      JSONValue.Free;
  end;

  if TemIssueDeErro then
  begin
    AErrorMessage := 'Amazon devolveu issue(s) de severidade ERROR: ' + AResponseJSON;
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Estoque atualizado com sucesso - SKU ' + ASku + ' -> ' + AQuantity.ToString + ' unidade(s).');
end;

function TAmazonSPAPIClient.UpdateSalePrice(const AAccessToken, ASellerID, ASku: string;
  ANovoPreco: Double; out AResponseJSON: string; out AErrorMessage: string): Boolean;
var
  ItemJSON, ApiPath, BodyStr, ProductType, Severity: string;
  ItemValue, JSONValue: TJSONValue;
  ItemObj, SummaryObj, JSONObj, IssueObj, Root, Patch: TJSONObject;
  PrecoObj, ScheduleObj, OfferObj: TJSONObject;
  SummariesArr, IssuesArr, Patches, PatchValueArr, ScheduleArr, OurPriceArr: TJSONArray;
  StatusCode, I: Integer;
  TemIssueDeErro: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  AResponseJSON := '';
  TemIssueDeErro := False;
  if ANovoPreco <= 0 then
  begin
    AErrorMessage := 'Preco invalido (zero ou negativo) - nada enviado.';
    Exit;
  end;
  // Passo 1: descobre o productType REAL do SKU, obrigatorio no corpo do PATCH.
  // {NOTA} esse bloco e' igual ao do UpdateStockQuantity de proposito: preferi
  // repetir a 'deteccao' a mexer num metodo que ja esta em producao. Se um dia
  // precisar ajustar, lembre que sao DOIS lugares.
  if not GetListingsItem(AAccessToken, ASellerID, ASku, ItemJSON, AErrorMessage) then
  begin
    AErrorMessage := 'Nao foi possivel obter dados do SKU ' + ASku +
      ' antes de atualizar o preco: ' + AErrorMessage;
    Exit;
  end;
  ProductType := '';
  ItemValue := TJSONObject.ParseJSONValue(ItemJSON);
  try
    if ItemValue is TJSONObject then
    begin
      ItemObj := TJSONObject(ItemValue);
      if ItemObj.TryGetValue<TJSONArray>('summaries', SummariesArr) and
         (SummariesArr.Count > 0) then
      begin
        SummaryObj := SummariesArr.Items[0] as TJSONObject;
        SummaryObj.TryGetValue<string>('productType', ProductType);
      end;
    end;
  finally
    ItemValue.Free;
  end;
  if ProductType = '' then
  begin
    AErrorMessage := 'Nao foi possivel descobrir o productType do SKU ' + ASku +
      ' - sem isso nao da pra montar o PATCH de preco.';
    DoLog(AErrorMessage);
    Exit;
  end;
  // Passo 2: monta o purchasable_offer. Mesmo formato usado no cadastro de
  // produto novo, inclusive o "audience".
  // {ATENCAO} sem "audience":"ALL" a Amazon responde 200/202 sem erro nenhum e
  // a oferta fica incompleta, SUMINDO da venda ate alguem editar na mao no
  // Seller Central. Isso ja' nos custou um diagnostico inteiro - nao remover.
  ScheduleObj := TJSONObject.Create;
  ScheduleObj.AddPair('value_with_tax', TJSONNumber.Create(ANovoPreco));
  ScheduleArr := TJSONArray.Create;
  ScheduleArr.AddElement(ScheduleObj);
  PrecoObj := TJSONObject.Create;
  PrecoObj.AddPair('schedule', ScheduleArr);
  OurPriceArr := TJSONArray.Create;
  OurPriceArr.AddElement(PrecoObj);
  OfferObj := TJSONObject.Create;
  OfferObj.AddPair('currency', 'BRL');
  OfferObj.AddPair('audience', 'ALL');
  OfferObj.AddPair('our_price', OurPriceArr);
  OfferObj.AddPair('marketplace_id', FMarketplaceID);
  PatchValueArr := TJSONArray.Create;
  PatchValueArr.AddElement(OfferObj);
  Patch := TJSONObject.Create;
  Patch.AddPair('op', 'replace');
  Patch.AddPair('path', '/attributes/purchasable_offer');
  Patch.AddPair('value', PatchValueArr);
  Patches := TJSONArray.Create;
  Patches.AddElement(Patch);
  Root := TJSONObject.Create;
  try
    Root.AddPair('productType', ProductType);
    Root.AddPair('patches', Patches);
    BodyStr := Root.ToJSON;
  finally
    Root.Free;
  end;
  DoLog('UpdateSalePrice body enviado (SKU ' + ASku + ', productType ' +
    ProductType + '): ' + BodyStr);
  ApiPath := '/listings/2021-08-01/items/' + ASellerID + '/' +
    TNetEncoding.URL.Encode(ASku);
  AResponseJSON := ExecutePatch(ApiPath, 'marketplaceIds=' + FMarketplaceID,
    BodyStr, AAccessToken, StatusCode);
  DoLog('UpdateSalePrice resposta: ' + AResponseJSON);
  if (StatusCode <> 200) and (StatusCode <> 202) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;
  // HTTP 200/202 nao garante sucesso: a Amazon devolve "issues" com severidade.
  JSONValue := TJSONObject.ParseJSONValue(AResponseJSON);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if JSONObj.TryGetValue<TJSONArray>('issues', IssuesArr) then
        for I := 0 to IssuesArr.Count - 1 do
        begin
          IssueObj := IssuesArr.Items[I] as TJSONObject;
          Severity := '';
          IssueObj.TryGetValue<string>('severity', Severity);
          if SameText(Severity, 'ERROR') then
            TemIssueDeErro := True;
        end;
    end;
  finally
    if Assigned(JSONValue) then
      JSONValue.Free;
  end;
  if TemIssueDeErro then
  begin
    AErrorMessage := 'A Amazon aceitou a chamada mas devolveu erro no conteudo: ' +
      AResponseJSON;
    DoLog(AErrorMessage);
    Exit;
  end;
  Result := True;
end;

function TAmazonSPAPIClient.CreateOfferForExistingASIN(const AAccessToken, ASellerID,
  ASku, AASIN: string; APrice: Double; AQuantity: Integer;
  out AResponseJSON: string; out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  StatusCode: Integer;
  BodyJSON, AttrObj, AsinObj, CondObj, FulfillObj, OfferObj, PriceObj,
    ScheduleObj: TJSONObject;
  AsinArr, CondArr, FulfillArr, OfferArr, ScheduleArr, OurPriceArr: TJSONArray;
  BodyStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  AResponseJSON := '';
  // {ATENCAO} Montado com base no padrao documentado oficialmente pela
  // Amazon pra oferta-apenas em cima de ASIN existente (productType
  // "PRODUCT" + requirements "LISTING_OFFER_ONLY") - nao testado ainda
  // contra a API real. Log da resposta bruta abaixo ajuda a ajustar rapido
  // se algum campo vier com nome/formato diferente do esperado.
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('productType', 'PRODUCT');
    BodyJSON.AddPair('requirements', 'LISTING_OFFER_ONLY');
    AttrObj := TJSONObject.Create;
    // merchant_suggested_asin - informa que esse SKU corresponde a um ASIN
    // que ja existe no catalogo.
    AsinArr := TJSONArray.Create;
    AsinObj := TJSONObject.Create;
    AsinObj.AddPair('value', AASIN);
    AsinObj.AddPair('marketplace_id', FMarketplaceID);
    AsinArr.AddElement(AsinObj);
    AttrObj.AddPair('merchant_suggested_asin', AsinArr);
    // condition_type - "new_new" = produto novo (mais comum).
    CondArr := TJSONArray.Create;
    CondObj := TJSONObject.Create;
    CondObj.AddPair('value', 'new_new');
    CondObj.AddPair('marketplace_id', FMarketplaceID);
    CondArr.AddElement(CondObj);
    AttrObj.AddPair('condition_type', CondArr);
    // fulfillment_availability - estoque (canal DEFAULT = o proprio
    // vendedor cuida do envio, nao FBA).
    FulfillArr := TJSONArray.Create;
    FulfillObj := TJSONObject.Create;
    FulfillObj.AddPair('fulfillment_channel_code', 'DEFAULT');
    FulfillObj.AddPair('quantity', TJSONNumber.Create(AQuantity));
    FulfillArr.AddElement(FulfillObj);
    AttrObj.AddPair('fulfillment_availability', FulfillArr);
    // purchasable_offer - preco de venda.
    ScheduleObj := TJSONObject.Create;
    ScheduleObj.AddPair('value_with_tax', TJSONNumber.Create(APrice));
    ScheduleArr := TJSONArray.Create;
    ScheduleArr.AddElement(ScheduleObj);
    PriceObj := TJSONObject.Create;
    PriceObj.AddPair('schedule', ScheduleArr);
    OfferObj := TJSONObject.Create;
    OfferObj.AddPair('currency', 'BRL');
    // {FIX} Sem "audience" a Amazon aceita o PUT (HTTP 200/202, sem erro),
    // mas o purchasable_offer fica incompleto e a oferta nao aparece pra
    // venda ("Oferta nao encontrada" no Seller Central) ate alguem editar
    // manualmente e o painel preencher esse campo. Confirmado comparando
    // com o JSON de uma oferta ja funcional (TESTE-CLIPE-001), que tem
    // "audience":"ALL" nesse mesmo nivel.
    OfferObj.AddPair('audience', 'ALL');
    OurPriceArr := TJSONArray.Create;
    OurPriceArr.AddElement(PriceObj);
    OfferObj.AddPair('our_price', OurPriceArr);
    OfferObj.AddPair('marketplace_id', FMarketplaceID);
    OfferArr := TJSONArray.Create;
    OfferArr.AddElement(OfferObj);
    AttrObj.AddPair('purchasable_offer', OfferArr);
    BodyJSON.AddPair('attributes', AttrObj);
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  DoLog('CreateOfferForExistingASIN body enviado: ' + BodyStr);
  ApiPath := '/listings/2021-08-01/items/' + ASellerID + '/' +
    TNetEncoding.URL.Encode(ASku);
  AResponseJSON := ExecutePut(ApiPath, 'marketplaceIds=' + FMarketplaceID,
    BodyStr, AAccessToken, StatusCode);
  DoLog('CreateOfferForExistingASIN resposta: ' + AResponseJSON);
  if (StatusCode <> 200) and (StatusCode <> 202) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;
  // Mesmo com HTTP 200/202, a Amazon pode devolver "issues" (avisos ou
  // erros) dentro da resposta - confere se tem algum "ERROR" antes de
  // considerar sucesso de verdade.
  JSONValue := TJSONObject.ParseJSONValue(AResponseJSON);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('status')) and
         (JSONObj.GetValue<string>('status') = 'INVALID') then
      begin
        AErrorMessage := 'Amazon rejeitou a submissao (status INVALID): ' + AResponseJSON;
        Exit;
      end;
    end;
    Result := True;
    DoLog('Oferta criada/enviada para processamento (SKU ' + ASku + ').');
  finally
    JSONValue.Free;
  end;
end;

function TAmazonSPAPIClient.SearchProductTypes(const AAccessToken, AKeywords: string;
  out AProductTypes: TAmazonProductTypeInfoArray; out AErrorMessage: string): Boolean;
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
  TypesArr: TJSONArray;
  I: Integer;
  ItemObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AProductTypes, 0);

  ResponseStr := ExecuteGet('/definitions/2020-09-01/productTypes',
    'keywords=' + TNetEncoding.URL.Encode(AKeywords) +
    '&marketplaceIds=' + FMarketplaceID, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada (nao e JSON): ' + ResponseStr;
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if not JSONObj.TryGetValue<TJSONArray>('productTypes', TypesArr) then
    begin
      // Nenhum productType encontrado pra essa palavra-chave - nao e' erro,
      // so devolve array vazio pro chamador tentar outra palavra-chave.
      Result := True;
      DoLog('Nenhum productType encontrado para "' + AKeywords + '".');
      Exit;
    end;

    SetLength(AProductTypes, TypesArr.Count);
    for I := 0 to TypesArr.Count - 1 do
    begin
      ItemObj := TypesArr.Items[I] as TJSONObject;
      ItemObj.TryGetValue<string>('name', AProductTypes[I].Name);
      // "displayName" nem sempre vem na resposta - deixa vazio se nao vier.
      ItemObj.TryGetValue<string>('displayName', AProductTypes[I].DisplayName);
    end;

    Result := True;
    DoLog(Format('%d productType(s) encontrado(s) para "%s".',
      [Length(AProductTypes), AKeywords]));
  finally
    JSONValue.Free;
  end;
end;

function TAmazonSPAPIClient.SearchCatalogItems(const AAccessToken, AKeywords: string;
  out AItems: TAmazonCatalogItemArray; out AErrorMessage: string): Boolean;
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj, ItemObj, SummaryObj, ImagesEntryObj: TJSONObject;
  ItemsArr, SummariesArr, ImagesArr, ImagesEntryArr: TJSONArray;
  I, J, K: Integer;
  Variant: string;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AItems, 0);

  ResponseStr := ExecuteGet('/catalog/2022-04-01/items',
    'keywords=' + TNetEncoding.URL.Encode(AKeywords) +
    '&marketplaceIds=' + FMarketplaceID +
    '&includedData=summaries,images&pageSize=10', AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada (nao e JSON): ' + ResponseStr;
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if not JSONObj.TryGetValue<TJSONArray>('items', ItemsArr) then
    begin
      // Nenhum resultado - nao e' erro, so devolve array vazio.
      Result := True;
      DoLog('Nenhum produto encontrado no catalogo para "' + AKeywords + '".');
      Exit;
    end;

    SetLength(AItems, ItemsArr.Count);
    for I := 0 to ItemsArr.Count - 1 do
    begin
      ItemObj := ItemsArr.Items[I] as TJSONObject;
      ItemObj.TryGetValue<string>('asin', AItems[I].ASIN);
      // "summaries" e' um array (1 por marketplace/idioma) - pega o
      // primeiro que tiver itemName preenchido.
      if ItemObj.TryGetValue<TJSONArray>('summaries', SummariesArr) then
        for J := 0 to SummariesArr.Count - 1 do
        begin
          SummaryObj := SummariesArr.Items[J] as TJSONObject;
          if AItems[I].Titulo = '' then
            SummaryObj.TryGetValue<string>('itemName', AItems[I].Titulo);
          if AItems[I].Marca = '' then
            SummaryObj.TryGetValue<string>('brand', AItems[I].Marca);
        end;
      // "images" e' um array por marketplace, cada um com um array de
      // variantes (MAIN, PT01 etc) - pega a variante MAIN da primeira
      // entrada que tiver.
      if ItemObj.TryGetValue<TJSONArray>('images', ImagesArr) then
        for J := 0 to ImagesArr.Count - 1 do
        begin
          ImagesEntryObj := ImagesArr.Items[J] as TJSONObject;
          if ImagesEntryObj.TryGetValue<TJSONArray>('images', ImagesEntryArr) then
            for K := 0 to ImagesEntryArr.Count - 1 do
            begin
              Variant := '';
              (ImagesEntryArr.Items[K] as TJSONObject).TryGetValue<string>('variant', Variant);
              if SameText(Variant, 'MAIN') and (AItems[I].ImagemURL = '') then
                (ImagesEntryArr.Items[K] as TJSONObject).TryGetValue<string>('link', AItems[I].ImagemURL);
            end;
        end;
    end;

    Result := True;
    DoLog(Format('%d produto(s) encontrado(s) no catalogo para "%s".',
      [Length(AItems), AKeywords]));
  finally
    JSONValue.Free;
  end;
end;

function TAmazonSPAPIClient.GetProductTypeSchema(const AAccessToken, AProductType,
  ASellerID: string; out ASchemaJSON: string; out AErrorMessage: string): Boolean;
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj, SchemaObj, LinkObj: TJSONObject;
  SchemaLinkURL: string;
  Response: IHTTPResponse;
begin
  Result := False;
  AErrorMessage := '';
  ASchemaJSON := '';

  // Passo 1: pega o "link" do schema (chamada autenticada na SP-API).
  ResponseStr := ExecuteGet('/definitions/2020-09-01/productTypes/' +
    TNetEncoding.URL.Encode(AProductType),
    'marketplaceIds=' + FMarketplaceID + '&sellerId=' + ASellerID +
    '&requirements=LISTING', AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d ao buscar definicao do productType "%s": %s',
      [StatusCode, AProductType, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada (nao e JSON): ' + ResponseStr;
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if not JSONObj.TryGetValue<TJSONObject>('schema', SchemaObj) or
       not SchemaObj.TryGetValue<TJSONObject>('link', LinkObj) or
       not LinkObj.TryGetValue<string>('resource', SchemaLinkURL) then
    begin
      AErrorMessage := 'Resposta nao trouxe schema.link.resource: ' + ResponseStr;
      DoLog(AErrorMessage);
      Exit;
    end;
  finally
    JSONValue.Free;
  end;

  // Passo 2: baixa o schema de fato - e' uma URL publica fora da SP-API,
  // NAO manda o x-amz-access-token aqui (a URL ja vem assinada/temporaria).
  DoLog('Baixando schema do productType "' + AProductType + '" de: ' + SchemaLinkURL);
  try
    Response := FHTTPClient.Get(SchemaLinkURL);
    if Response.StatusCode <> 200 then
    begin
      AErrorMessage := Format('HTTP %d ao baixar o schema de %s',
        [Response.StatusCode, SchemaLinkURL]);
      DoLog(AErrorMessage);
      Exit;
    end;
    ASchemaJSON := Response.ContentAsString(TEncoding.UTF8);
  except
    on E: Exception do
    begin
      AErrorMessage := 'Erro ao baixar o schema: ' + E.Message;
      DoLog(AErrorMessage);
      Exit;
    end;
  end;

  Result := True;
  DoLog('Schema do productType "' + AProductType + '" baixado com sucesso ' +
    '(' + Length(ASchemaJSON).ToString + ' bytes).');
end;

function TAmazonSPAPIClient.CreateNewProduct(const AAccessToken, ASellerID, ASku,
  AProductType, AAttributesJSON: string; out AResponseJSON, AIssuesJSON: string;
  out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  StatusCode: Integer;
  BodyJSON: TJSONObject;
  AttrValue: TJSONValue;
  BodyStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
  IssuesArr: TJSONArray;
  I: Integer;
  IssueObj: TJSONObject;
  Severity: string;
  TemIssueDeErro: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  AResponseJSON := '';
  AIssuesJSON := '';
  TemIssueDeErro := False;

  AttrValue := TJSONObject.ParseJSONValue(AAttributesJSON);
  if not (AttrValue is TJSONObject) then
  begin
    AttrValue.Free;
    AErrorMessage := 'AAttributesJSON invalido (nao e um objeto JSON): ' + AAttributesJSON;
    DoLog(AErrorMessage);
    Exit;
  end;

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('productType', AProductType);
    // {FIX} A documentacao oficial da Amazon SEMPRE inclui "requirements":
    // "LISTING" explicito nos exemplos, mesmo dizendo que e' o valor
    // default - a omissao pode ter contribuido pro erro generico
    // "InvalidInput / cannot be parsed" que a gente tomou testando sem
    // esse campo. Manda explicito pra eliminar essa ambiguidade.
    BodyJSON.AddPair('requirements', 'LISTING');
    BodyJSON.AddPair('attributes', AttrValue);
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free; // libera tambem o AttrValue (foi anexado como pair)
  end;

  DoLog('CreateNewProduct body enviado: ' + BodyStr);
  ApiPath := '/listings/2021-08-01/items/' + ASellerID + '/' +
    TNetEncoding.URL.Encode(ASku);
  // {FIX} O PUT de CreateOfferForExistingASIN (ja validado contra a API
  // real) usa SO "marketplaceIds" - sem "includedData". A gente estava
  // mandando "includedData" a mais aqui, o que pode ser rejeitado como
  // parametro invalido ANTES da Amazon sequer olhar o corpo da
  // requisicao, explicando o erro generico "InvalidInput / cannot be
  // parsed" que nao mudava nem apos corrigir varias vezes o JSON de
  // atributos.
  AResponseJSON := ExecutePut(ApiPath, 'marketplaceIds=' + FMarketplaceID,
    BodyStr, AAccessToken, StatusCode);
  DoLog('CreateNewProduct resposta: ' + AResponseJSON);

  if (StatusCode <> 200) and (StatusCode <> 202) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(AResponseJSON);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('status')) and
         (JSONObj.GetValue<string>('status') = 'INVALID') then
      begin
        AErrorMessage := 'Amazon rejeitou a submissao (status INVALID): ' + AResponseJSON;
        Exit;
      end;
      // "issues" pode vir mesmo com status diferente de INVALID (avisos,
      // ou erros em atributos especificos que nao invalidam a submissao
      // inteira) - devolve pro chamador mostrar/decidir o que corrigir.
      if JSONObj.TryGetValue<TJSONArray>('issues', IssuesArr) then
      begin
        AIssuesJSON := IssuesArr.ToJSON;
        for I := 0 to IssuesArr.Count - 1 do
        begin
          IssueObj := IssuesArr.Items[I] as TJSONObject;
          Severity := '';
          IssueObj.TryGetValue<string>('severity', Severity);
          if SameText(Severity, 'ERROR') then
            TemIssueDeErro := True;
        end;
      end;
    end;

    if TemIssueDeErro then
    begin
      AErrorMessage := 'Amazon devolveu issue(s) de severidade ERROR: ' + AIssuesJSON;
      DoLog(AErrorMessage);
      Exit;
    end;

    Result := True;
    DoLog('Produto novo criado/enviado para processamento (SKU ' + ASku + ', productType ' +
      AProductType + ').');
  finally
    JSONValue.Free;
  end;
end;

end.
