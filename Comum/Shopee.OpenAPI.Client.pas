// ============================================================================
// UNIT: Shopee.OpenAPI.Client
// OBJETIVO: Cliente standalone para autenticação OAuth e chamadas básicas à
//           Shopee Open API v2 (Partner Platform).
// REQUISITOS: Delphi 12.3+, System.Net.HttpClient, System.NetEncoding,
//             Indy (IdHMACSHA2, IdGlobal) - já vem de fábrica no Delphi.
// ============================================================================
//
// CONCEITOS IMPORTANTES:
//   - Partner ID / Partner Key: credenciais da SUA aplicação (obtidas no
//     Open Platform depois da aprovação), NUNCA mudam por vendedor.
//   - Toda chamada à API da Shopee (inclusive a de autorização) precisa de
//     uma ASSINATURA (sign) calculada com HMAC-SHA256, usando o Partner Key
//     como chave secreta. Isso é diferente da Amazon/WhatsApp, que usam só
//     um token fixo no header.
//   - Access Token / Refresh Token: um par por LOJA (shop_id) autorizada.
//     O Access Token expira (geralmente em 4h) e precisa ser renovado com
//     o Refresh Token (que dura bem mais, mas também expira eventualmente).
//   - Ambiente de testes ("Sandbox"): a Shopee libera um ambiente de teste
//     separado (test-stable) com Partner ID/Key próprios, diferente do de
//     produção. Use Sandbox=True até a Shopee liberar acesso de produção.
//
// FLUXO DE USO:
//   1. BuildAuthorizationURL -> abre no navegador do vendedor
//   2. Vendedor loga/autoriza, é redirecionado pra sua Redirect URI com
//      os parâmetros "code" e "shop_id" na query string
//   3. ExchangeCodeForTokens(code, shopId) -> retorna RefreshToken (guardar
//      por loja) e AccessToken (usar imediatamente)
//   4. Quando o AccessToken expirar: RefreshAccessToken(refreshToken, shopId)
//   5. TestConnection(accessToken, shopId) -> valida que está funcionando
// ============================================================================
unit Shopee.OpenAPI.Client;
interface
uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.NetEncoding,
  System.DateUtils,
  System.Hash,
  System.IOUtils,
  System.Math,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient,
  System.Net.Mime;
type
  TShopeeTokenInfo = record
    Success: Boolean;
    AccessToken: string;
    RefreshToken: string;
    ShopID: Int64;
    ExpireIn: Integer;        // segundos até expirar o AccessToken
    ObtainedAt: TDateTime;
    ErrorMessage: string;
    RawResponse: string;
  end;
  TShopeeLogEvent = procedure(const AMessage: string) of object;
  TShopeeItem = record
    ItemID: Int64;
    ItemName: string;
    ItemSKU: string;
    ItemStatus: string;
    OriginalPrice: Double;
    Stock: Integer;
    ModelID: Int64;      // 0 quando o item não tem variações
    CategoryID: Int64;
    CategoryName: string; // preenchido só quando disponível (nem toda chamada retorna)
    WeightKg: Double;
    ImageURL: string;     // primeira imagem da lista, se houver
    UpdateTime: TDateTime;
  end;
  TShopeeItemArray = TArray<TShopeeItem>;
  TShopeeOrder = record
    OrderSN: string;
    OrderStatus: string;
    CreateTime: TDateTime;
    TotalAmount: string;
    Currency: string;
  end;
  TShopeeOrderArray = TArray<TShopeeOrder>;

  // Item de dentro do detalhe completo de um pedido (get_order_detail,
  // item_list) - diferente de TShopeeItem (que e' o item do catalogo
  // geral, nao de um pedido especifico).
  TShopeeOrderItemDetail = record
    ItemID: string;               // so' usado pra localizar o produto interno via
                                    // PRODUTOS_MARKETPLACE - nao tem coluna dedicada
    ItemName: string;
    ItemSKU: string;
    OrderItemID: string;
    ModelID: string;
    ModelName: string;
    ModelSKU: string;
    ModelQuantityPurchased: Double;
    ModelOriginalPrice: Double;
    ModelDiscountedPrice: Double;
    PromotionGroupID: string;
    ProductLocationID: string;
  end;
  TShopeeOrderItemDetailArray = TArray<TShopeeOrderItemDetail>;

  // Detalhe completo de um pedido (get_order_detail) - usado pela baixa
  // no SAT (uBaixaPedidoSAT). Cobre os campos com coluna dedicada
  // confirmados no de-para do cliente (22/08/2026); os demais campos
  // (sem coluna dedicada, que viram OBS) sao lidos direto do
  // RawJSON pelo chamador.
  TShopeeOrderDetail = record
    OrderSN: string;
    OrderStatus: string;
    CreateTime: TDateTime;
    UpdateTime: TDateTime;
    TotalAmount: Double;
    BuyerUserID: string;
    BuyerUsername: string;
    BuyerCpfId: string;
    RecipientName: string;
    RecipientPhone: string;
    RecipientFullAddress: string; // full_address (ja vem pronto da Shopee)
    RecipientCity: string;
    RecipientDistrict: string;    // recipient_address.district (bairro, no Brasil)
    RecipientState: string;
    RecipientZipcode: string;
    RecipientCountry: string;
    ActualShippingFee: Double;
    ShippingCarrier: string;
    PickupDoneTime: TDateTime;
    Items: TShopeeOrderItemDetailArray;
    RawJSON: string; // resposta completa - usado pra extrair os campos "-> oe.obs"
  end;

  TShopeeOpenAPIClient = class
  private
    FPartnerID: Int64;
    FPartnerKey: string;
    FRedirectURI: string;
    FSandbox: Boolean;
    FHTTPClient: TNetHTTPClient;
    FOnLog: TShopeeLogEvent;
    procedure DoLog(const AMessage: string);
    function BaseURL: string;
    function CurrentTimestamp: Int64;
    function ComputeSign(const AApiPath: string; ATimestamp: Int64;
      const AAccessToken: string = ''; AShopID: Int64 = 0): string;
    function ParseTokenResponse(const AResponseStr: string): TShopeeTokenInfo;
    function ExecuteGet(const AApiPath, AQueryExtra, AAccessToken: string;
      AShopID: Int64; out AStatusCode: Integer): string;
    function ExecutePost(const AApiPath, ABodyJSON, AAccessToken: string;
      AShopID: Int64; out AStatusCode: Integer): string;
    // Extrai nome/sku/status/preço/estoque de um item retornado por
    // get_item_base_info, cobrindo tanto o formato atual da API v2
    // (price_info / stock_info_v2) quanto um fallback para variações mais
    // antigas do payload, já que a Shopee tem alterado esse formato entre
    // versões da API.
    procedure ParseItemJSON(const AItemObj: TJSONObject; var AItem: TShopeeItem);
  public
    constructor Create(APartnerID: Int64; const APartnerKey, ARedirectURI: string;
      ASandbox: Boolean = True);
    destructor Destroy; override;
    function BuildAuthorizationURL: string;
    function ExchangeCodeForTokens(const ACode: string; AShopID: Int64): TShopeeTokenInfo;
    function RefreshAccessToken(const ARefreshToken: string; AShopID: Int64): TShopeeTokenInfo;
    function TestConnection(const AAccessToken: string; AShopID: Int64;
      out AResponseJSON: string): Boolean;
    // --- Ofertas (produtos) ---
    // Lista os item_id da loja, cobrindo os 4 status principais (Ativo,
    // Violação, Sob Análise, Não publicado - igual às abas do painel da
    // Shopee). Itens excluídos (SELLER_DELETE/SHOPEE_DELETE) ficam de fora.
    function GetItemList(const AAccessToken: string; AShopID: Int64;
      out AItems: TShopeeItemArray; out AErrorMessage: string;
      AUpdateTimeFrom: Int64 = 0; AUpdateTimeTo: Int64 = 0;
      const AItemStatusFilter: string = ''): Boolean;
    // Busca um único item diretamente pelo item_id, sem passar pela
    // listagem (get_item_list) e portanto sem o filtro de status - funciona
    // com QUALQUER produto (ativo, inativo, não publicado, em análise etc.),
    // desde que o item_id pertença à loja autorizada (AShopID).
    function GetItemByID(const AAccessToken: string; AShopID, AItemID: Int64;
      out AItem: TShopeeItem; out AErrorMessage: string): Boolean;
    // --- Cadastro de produto (usado para montar CreateSimpleTestItem) ---
    // Busca a primeira categoria "folha" (sem subcategorias) retornada pela
    // Shopee - suficiente para cadastro de produto de teste, já que qualquer
    // categoria folha válida é aceita pelo add_item.
    function GetFirstLeafCategory(const AAccessToken: string; AShopID: Int64;
      out ACategoryID: Int64; out ACategoryName: string;
      out AErrorMessage: string): Boolean;
    // Busca o primeiro canal de logística HABILITADO para a loja - o
    // add_item exige pelo menos um canal de envio válido.
    function GetFirstEnabledLogisticsChannel(const AAccessToken: string;
      AShopID: Int64; out AChannelID: Int64; out AChannelName: string;
      out AErrorMessage: string): Boolean;
    // Envia uma imagem (upload multipart) e retorna o image_id gerado pela
    // Shopee - obrigatório para cadastrar qualquer produto.
    function UploadImage(const AAccessToken: string; AShopID: Int64;
      const AImageFilePath: string; out AImageID: string;
      out AErrorMessage: string): Boolean;
    // Cadastra um produto de ponta a ponta: sobe a imagem informada e chama
    // add_item. Categoria e marca podem ser informadas manualmente (uso em
    // produção, com os IDs reais do catálogo do vendedor) ou detectadas
    // automaticamente (ACategoryID=0 busca a primeira categoria "folha"
    // válida; ABrandID=0 usa "Sem marca" - prático para testes em Sandbox).
    // Canal de logística é sempre detectado automaticamente (primeiro
    // habilitado na loja).
    function CreateProduct(const AAccessToken: string; AShopID: Int64;
      const AItemName, ADescription, AImageFilePath: string; APrice: Double;
      AStock: Integer; AWeightKg: Double; ACategoryID: Int64; ABrandID: Int64;
      const ABrandName: string; out ANewItemID: Int64;
      out AErrorMessage: string): Boolean;
    // Atualiza o preço de um item (AModelID = 0 se o item não tem variações).
    function UpdatePrice(const AAccessToken: string; AShopID, AItemID, AModelID: Int64;
      ANewPrice: Double; out AErrorMessage: string): Boolean;
    // Atualiza o estoque de um item (AModelID = 0 se o item não tem variações).
    function UpdateStock(const AAccessToken: string; AShopID, AItemID, AModelID: Int64;
      ANewStock: Integer; out AErrorMessage: string): Boolean;
    // --- Pedidos (orders) ---
    // Lista os pedidos criados nos últimos ADiasAtras dias (padrão: 15, que é
    // o limite máximo aceito pela Shopee por chamada de get_order_list).
    function GetOrderList(const AAccessToken: string; AShopID: Int64;
      out AOrders: TShopeeOrderArray; out AErrorMessage: string;
      ADiasAtras: Integer = 15): Boolean;
    // --- Pagamento (Escrow) (adicionado) ---
    // So fica disponivel depois que o pedido e' despachado/concluido - a
    // Shopee ainda nao calculou o valor final antes disso. Devolve o JSON
    // bruto (ARawJSON) + um parse leve dos campos mais imediatos - o parse
    // completo (comissao, taxas, items[] com breakdown financeiro por item,
    // etc) fica pra quando a estrutura da tabela do lado do cliente estiver
    // definida.
    function GetEscrowDetail(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out AEscrowAmount, ABuyerTotalAmount: Double;
      out APaymentMethod, ARawJSON: string; out AErrorMessage: string): Boolean;
    // Detalhe completo de UM pedido (get_order_detail, sem limitar
    // response_optional_fields como o GetOrderList faz) - usado pela baixa
    // no SAT (uBaixaPedidoSAT), depois que o usuario ja escolheu o pedido
    // na grid. Devolve os campos com coluna dedicada ja parseados
    // (ADetalhe) - os demais campos (sem coluna dedicada, que viram OBS)
    // ficam disponiveis em ADetalhe.RawJSON pro chamador extrair.
    function GetOrderDetail(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out ADetalhe: TShopeeOrderDetail;
      out AErrorMessage: string): Boolean;
    // --- Acoes sobre pedidos (adicionado) ---
    function GetOrderItemIDs(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out AItemIDs: TArray<Int64>;
      out AModelIDs: TArray<Int64>; out AErrorMessage: string): Boolean;
    function GetShippingParameter(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out ARawJSON: string; out AErrorMessage: string): Boolean;
    function ShipOrder(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out AErrorMessage: string): Boolean;
    function CancelOrder(const AAccessToken: string; AShopID: Int64;
      const AOrderSN, ACancelReason: string; out AErrorMessage: string): Boolean;
    function HandleBuyerCancellation(const AAccessToken: string; AShopID: Int64;
      const AOrderSN, AOperation: string; out AErrorMessage: string): Boolean;
    // --- Etiqueta de Envio e Nota Fiscal (adicionado) ---
    // --- Etiqueta de Envio (Shipping Document) ---
    // Fluxo em 3 passos, porque a Shopee gera o PDF em segundo plano:
    //   1. CreateShippingDocument     -> pede pra gerar (busca package_number
    //      e tracking_number automaticamente antes de montar a chamada)
    //   2. GetShippingDocumentResult  -> pergunta se ja terminou (pode
    //      precisar chamar mais de uma vez, com um pequeno intervalo)
    //   3. DownloadShippingDocument   -> baixa o PDF pronto
    function GetOrderPackageInfo(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out APackageNumber, ATrackingNumber: string;
      out AErrorMessage: string): Boolean;
    function CreateShippingDocument(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out AErrorMessage: string): Boolean;
    function GetShippingDocumentResult(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out AStatus: string; out AErrorMessage: string): Boolean;
    function DownloadShippingDocument(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out APdfBytes: TBytes; out AErrorMessage: string): Boolean;
    // --- Nota Fiscal (Invoice - Brasil) ---
    function UploadInvoiceDoc(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; const APdfBytes: TBytes; out AErrorMessage: string): Boolean;
    function DownloadInvoiceDoc(const AAccessToken: string; AShopID: Int64;
      const AOrderSN: string; out APdfBytes: TBytes; out AErrorMessage: string): Boolean;
    property OnLog: TShopeeLogEvent read FOnLog write FOnLog;
  end;
function HMACSHA256Hex(const AKey, AMessage: string): string;
implementation
function HMACSHA256Hex(const AKey, AMessage: string): string;
begin
  // System.Hash.THashSHA2.GetHMAC(AData, AKey) - nota a ordem dos parâmetros:
  // primeiro os dados (a string base a assinar), depois a chave secreta.
  Result := LowerCase(THashSHA2.GetHMAC(AMessage, AKey, THashSHA2.TSHA2Version.SHA256));
end;
{ TShopeeOpenAPIClient }
constructor TShopeeOpenAPIClient.Create(APartnerID: Int64; const APartnerKey,
  ARedirectURI: string; ASandbox: Boolean);
begin
  inherited Create;
  FPartnerID := APartnerID;
  FPartnerKey := APartnerKey;
  FRedirectURI := ARedirectURI;
  FSandbox := ASandbox;
  FHTTPClient := TNetHTTPClient.Create(nil);
  FHTTPClient.ConnectionTimeout := 60000;
  FHTTPClient.ResponseTimeout := 60000;
end;
destructor TShopeeOpenAPIClient.Destroy;
begin
  FHTTPClient.Free;
  inherited;
end;
procedure TShopeeOpenAPIClient.DoLog(const AMessage: string);
begin
  if Assigned(FOnLog) then
    FOnLog(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' | ' + AMessage);
end;
function TShopeeOpenAPIClient.BaseURL: string;
begin
  if FSandbox then
    Result := 'https://openplatform.sandbox.test-stable.shopee.sg'
  else
    Result := 'https://partner.shopeemobile.com';
end;
function TShopeeOpenAPIClient.CurrentTimestamp: Int64;
begin
  // O valor já está em UTC (TTimeZone.Local.ToUniversalTime), então o segundo
  // parâmetro de DateTimeToUnix precisa ser True - passar False aqui fazia a
  // função converter de novo como se fosse hora local, deslocando o timestamp
  // pelo fuso horário (ex: -3h no Brasil) e derrubando a assinatura por
  // "Timestamp is expired" na Shopee.
  Result := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now), True);
end;
function TShopeeOpenAPIClient.ComputeSign(const AApiPath: string;
  ATimestamp: Int64; const AAccessToken: string; AShopID: Int64): string;
var
  BaseString: string;
begin
  // Fórmula da Shopee: partner_id + api_path + timestamp [+ access_token] [+ shop_id]
  // (access_token e shop_id só entram em chamadas já autorizadas)
  BaseString := IntToStr(FPartnerID) + AApiPath + IntToStr(ATimestamp);
  if AAccessToken <> '' then
    BaseString := BaseString + AAccessToken;
  if AShopID <> 0 then
    BaseString := BaseString + IntToStr(AShopID);
  Result := HMACSHA256Hex(FPartnerKey, BaseString);
end;
function TShopeeOpenAPIClient.BuildAuthorizationURL: string;
const
  API_PATH = '/api/v2/shop/auth_partner';
var
  Timestamp: Int64;
  Sign: string;
begin
  Timestamp := CurrentTimestamp;
  Sign := ComputeSign(API_PATH, Timestamp);
  Result := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&sign=' + Sign +
    '&redirect=' + TNetEncoding.URL.Encode(FRedirectURI);
  DoLog('URL de autorização gerada: ' + Result);
end;
function TShopeeOpenAPIClient.ParseTokenResponse(const AResponseStr: string): TShopeeTokenInfo;
var
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
  ErrorCode: string;
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
    // A Shopee retorna HTTP 200 mesmo em erro de negócio; o erro real vem
    // no campo "error" (string não-vazia quando algo deu errado).
    if Assigned(JSONObj.GetValue('error')) then
      ErrorCode := JSONObj.GetValue<string>('error')
    else
      ErrorCode := '';
    if ErrorCode <> '' then
    begin
      Result.ErrorMessage := ErrorCode;
      if Assigned(JSONObj.GetValue('message')) then
        Result.ErrorMessage := Result.ErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      DoLog('Erro retornado pela Shopee: ' + Result.ErrorMessage);
      Exit;
    end;
    if Assigned(JSONObj.GetValue('access_token')) then
      Result.AccessToken := JSONObj.GetValue<string>('access_token');
    if Assigned(JSONObj.GetValue('refresh_token')) then
      Result.RefreshToken := JSONObj.GetValue<string>('refresh_token');
    if Assigned(JSONObj.GetValue('expire_in')) then
      Result.ExpireIn := JSONObj.GetValue<Integer>('expire_in');
    if Assigned(JSONObj.GetValue('shop_id')) then
    begin
      Result.ShopID := JSONObj.GetValue<Int64>('shop_id');
      // Log de diagnostico: ja observamos esse campo divergir do shop_id
      // real (confirmado via redirect da Shopee) sem explicacao ainda
      // identificada. Registrar o valor bruto ajuda a investigar se
      // acontecer de novo.
      DoLog('DEBUG shop_id bruto na resposta do token exchange: ' +
        JSONObj.GetValue('shop_id').Value);
    end;
    if Result.AccessToken = '' then
    begin
      Result.ErrorMessage := 'access_token não veio na resposta';
      DoLog(Result.ErrorMessage + ': ' + AResponseStr);
      Exit;
    end;
    Result.Success := True;
    DoLog('Token obtido com sucesso (expira em ' + Result.ExpireIn.ToString + 's)');
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.ExchangeCodeForTokens(const ACode: string;
  AShopID: Int64): TShopeeTokenInfo;
const
  API_PATH = '/api/v2/auth/token/get';
var
  Timestamp: Int64;
  Sign, URL, BodyStr: string;
  BodyJSON: TJSONObject;
  RequestStream: TStringStream;
  Response: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Timestamp := CurrentTimestamp;
  Sign := ComputeSign(API_PATH, Timestamp);
  URL := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&sign=' + Sign;
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('code', ACode);
    // TJSONNumber.Create(Int64) constrói via string internamente para evitar
    // perda de precisao em ids grandes (shop_id/item_id da Shopee costumam
    // ter 15-17 digitos, alem do limite seguro de um Double).
    BodyJSON.AddPair('shop_id', TJSONNumber.Create(IntToStr(AShopID)));
    BodyJSON.AddPair('partner_id', TJSONNumber.Create(IntToStr(FPartnerID)));
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  DoLog('Trocando código de autorização por tokens...');
  RequestStream := TStringStream.Create(BodyStr, TEncoding.UTF8);
  try
    Headers := [TNameValuePair.Create('Content-Type', 'application/json')];
    try
      Response := FHTTPClient.Post(URL, RequestStream, nil, Headers);
      Result := ParseTokenResponse(Response.ContentAsString(TEncoding.UTF8));
    except
      on E: Exception do
      begin
        Result.Success := False;
        Result.ErrorMessage := E.Message;
        DoLog('Erro na requisição de token: ' + E.Message);
      end;
    end;
  finally
    RequestStream.Free;
  end;
end;
function TShopeeOpenAPIClient.RefreshAccessToken(const ARefreshToken: string;
  AShopID: Int64): TShopeeTokenInfo;
const
  API_PATH = '/api/v2/auth/access_token/get';
var
  Timestamp: Int64;
  Sign, URL, BodyStr: string;
  BodyJSON: TJSONObject;
  RequestStream: TStringStream;
  Response: IHTTPResponse;
  Headers: TNetHeaders;
begin
  Timestamp := CurrentTimestamp;
  Sign := ComputeSign(API_PATH, Timestamp);
  URL := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&sign=' + Sign;
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('refresh_token', ARefreshToken);
    BodyJSON.AddPair('shop_id', TJSONNumber.Create(IntToStr(AShopID)));
    BodyJSON.AddPair('partner_id', TJSONNumber.Create(IntToStr(FPartnerID)));
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  DoLog('Renovando access token a partir do refresh token...');
  RequestStream := TStringStream.Create(BodyStr, TEncoding.UTF8);
  try
    Headers := [TNameValuePair.Create('Content-Type', 'application/json')];
    try
      Response := FHTTPClient.Post(URL, RequestStream, nil, Headers);
      Result := ParseTokenResponse(Response.ContentAsString(TEncoding.UTF8));
    except
      on E: Exception do
      begin
        Result.Success := False;
        Result.ErrorMessage := E.Message;
        DoLog('Erro na requisição de refresh: ' + E.Message);
      end;
    end;
  finally
    RequestStream.Free;
  end;
end;
function TShopeeOpenAPIClient.TestConnection(const AAccessToken: string;
  AShopID: Int64; out AResponseJSON: string): Boolean;
const
  API_PATH = '/api/v2/shop/get_shop_info';
var
  Timestamp: Int64;
  Sign, URL: string;
  Response: IHTTPResponse;
begin
  Result := False;
  AResponseJSON := '';
  Timestamp := CurrentTimestamp;
  Sign := ComputeSign(API_PATH, Timestamp, AAccessToken, AShopID);
  URL := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&sign=' + Sign +
    '&shop_id=' + IntToStr(AShopID) +
    '&access_token=' + AAccessToken;
  try
    Response := FHTTPClient.Get(URL);
    AResponseJSON := Response.ContentAsString(TEncoding.UTF8);
    Result := Response.StatusCode < 400;
    if Result then
      DoLog('Teste de conexão OK: ' + AResponseJSON)
    else
      DoLog(Format('Teste de conexão falhou (HTTP %d): %s',
        [Response.StatusCode, AResponseJSON]));
  except
    on E: Exception do
    begin
      DoLog('Erro no teste de conexão: ' + E.Message);
      AResponseJSON := E.Message;
    end;
  end;
end;
function TShopeeOpenAPIClient.ExecuteGet(const AApiPath, AQueryExtra,
  AAccessToken: string; AShopID: Int64; out AStatusCode: Integer): string;
var
  Timestamp: Int64;
  Sign, URL: string;
  Response: IHTTPResponse;
begin
  Timestamp := CurrentTimestamp;
  Sign := ComputeSign(AApiPath, Timestamp, AAccessToken, AShopID);
  URL := BaseURL + AApiPath +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&sign=' + Sign +
    '&shop_id=' + IntToStr(AShopID) +
    '&access_token=' + AAccessToken;
  if AQueryExtra <> '' then
    URL := URL + '&' + AQueryExtra;
  try
    Response := FHTTPClient.Get(URL);
    AStatusCode := Response.StatusCode;
    Result := Response.ContentAsString(TEncoding.UTF8);
    if AStatusCode >= 400 then
      DoLog(Format('GET %s -> HTTP %d: %s', [AApiPath, AStatusCode, Result]));
  except
    on E: Exception do
    begin
      AStatusCode := 0;
      Result := '';
      DoLog('Erro em GET ' + AApiPath + ': ' + E.Message);
    end;
  end;
end;
function TShopeeOpenAPIClient.ExecutePost(const AApiPath, ABodyJSON,
  AAccessToken: string; AShopID: Int64; out AStatusCode: Integer): string;
var
  Timestamp: Int64;
  Sign, URL: string;
  Response: IHTTPResponse;
  RequestStream: TStringStream;
  Headers: TNetHeaders;
begin
  Timestamp := CurrentTimestamp;
  Sign := ComputeSign(AApiPath, Timestamp, AAccessToken, AShopID);
  URL := BaseURL + AApiPath +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&sign=' + Sign +
    '&shop_id=' + IntToStr(AShopID) +
    '&access_token=' + AAccessToken;
  RequestStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    Headers := [TNameValuePair.Create('Content-Type', 'application/json')];
    try
      Response := FHTTPClient.Post(URL, RequestStream, nil, Headers);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
      if AStatusCode >= 400 then
        DoLog(Format('POST %s -> HTTP %d: %s', [AApiPath, AStatusCode, Result]));
    except
      on E: Exception do
      begin
        AStatusCode := 0;
        Result := '';
        DoLog('Erro em POST ' + AApiPath + ': ' + E.Message);
      end;
    end;
  finally
    RequestStream.Free;
  end;
end;
procedure TShopeeOpenAPIClient.ParseItemJSON(const AItemObj: TJSONObject;
  var AItem: TShopeeItem);
var
  PriceInfoArr, ModelListArr, ImageURLArr: TJSONArray;
  PriceObj, StockV2Obj, SummaryObj, ModelObj, ImageObj: TJSONObject;
  OriginalPriceStr, WeightStr: string;
  StockValue: Integer;
  UpdateTimeUnix: Int64;
begin
  AItem.ItemID := AItemObj.GetValue<Int64>('item_id');
  if not AItemObj.TryGetValue<string>('item_name', AItem.ItemName) then
    AItem.ItemName := '';
  if not AItemObj.TryGetValue<string>('item_sku', AItem.ItemSKU) then
    AItem.ItemSKU := '';
  if not AItemObj.TryGetValue<string>('item_status', AItem.ItemStatus) then
    AItem.ItemStatus := '';
  AItem.ModelID := 0; // simplificação: itens sem variação (model_id=0)
  AItem.OriginalPrice := 0;
  AItem.Stock := 0;
  AItem.CategoryID := 0;
  AItem.CategoryName := '';
  AItem.WeightKg := 0;
  AItem.ImageURL := '';
  AItem.UpdateTime := 0;
  // --- Categoria ---
  if not AItemObj.TryGetValue<Int64>('category_id', AItem.CategoryID) then
    AItem.CategoryID := 0;
  // --- Peso ---
  // A Shopee retorna o peso como string (ex: "0.20"), em quilogramas.
  if AItemObj.TryGetValue<string>('weight', WeightStr) then
    AItem.WeightKg := StrToFloatDef(WeightStr, 0, TFormatSettings.Invariant);
  // --- Imagem ---
  // "image": { "image_url_list": ["https://...", ...], "image_id_list": [...] }
  if AItemObj.TryGetValue<TJSONObject>('image', ImageObj) and
     ImageObj.TryGetValue<TJSONArray>('image_url_list', ImageURLArr) and
     (ImageURLArr.Count > 0) then
    AItem.ImageURL := ImageURLArr.Items[0].Value;
  // --- Última atualização ---
  // "update_time" vem como timestamp Unix (segundos)
  if AItemObj.TryGetValue<Int64>('update_time', UpdateTimeUnix) then
    AItem.UpdateTime := UnixToDateTime(UpdateTimeUnix, False); // horário local
  // --- Preço ---
  // Formato atual (API v2): "price_info": [ { "currency": "...",
  // "original_price": 15.99, "current_price": 15.99, ... }, ... ]
  // Para item sem variação normalmente vem 1 elemento só; para item com
  // variação, cada elemento traz também "model_id" (não tratado aqui ainda).
  if AItemObj.TryGetValue<TJSONArray>('price_info', PriceInfoArr) and
     (PriceInfoArr.Count > 0) then
  begin
    PriceObj := PriceInfoArr.Items[0] as TJSONObject;
    if PriceObj.TryGetValue<string>('original_price', OriginalPriceStr) then
      AItem.OriginalPrice := StrToFloatDef(OriginalPriceStr, 0, TFormatSettings.Invariant)
    else if Assigned(PriceObj.GetValue('original_price')) then
      // alguns retornos trazem o preço como número, não string
      AItem.OriginalPrice := PriceObj.GetValue<Double>('original_price');
  end
  else
    DoLog(Format('DIAGNÓSTICO: item %d veio sem "price_info" no JSON (ou lista vazia) - ' +
      'preço ficará 0.00. Comum em itens não publicados/Inativos - a Shopee às vezes omite ' +
      'esse bloco até o produto ficar Ativo.', [AItem.ItemID]));
  // --- Estoque ---
  // Formato atual (API v2): "stock_info_v2": { "summary_info": {
  // "total_available_stock": N, "total_reserved_stock": N }, ... }
  if AItemObj.TryGetValue<TJSONObject>('stock_info_v2', StockV2Obj) then
  begin
    if StockV2Obj.TryGetValue<TJSONObject>('summary_info', SummaryObj) and
       SummaryObj.TryGetValue<Integer>('total_available_stock', StockValue) then
      AItem.Stock := StockValue;
  end
  // Fallback: formato mais antigo, "stock_info": { "stock": N } por model,
  // ou direto no item quando não há variação.
  else if AItemObj.TryGetValue<TJSONArray>('model', ModelListArr) and
          (ModelListArr.Count > 0) then
  begin
    ModelObj := ModelListArr.Items[0] as TJSONObject;
    if not ModelObj.TryGetValue<Integer>('stock', AItem.Stock) then
      AItem.Stock := 0;
  end
  else if not AItemObj.TryGetValue<Integer>('stock', AItem.Stock) then
  begin
    AItem.Stock := 0;
    DoLog(Format('DIAGNÓSTICO: item %d veio sem "stock_info_v2"/"model"/"stock" no JSON - ' +
      'estoque ficará 0. Comum em itens não publicados/Inativos.', [AItem.ItemID]));
  end;
end;
function TShopeeOpenAPIClient.GetItemByID(const AAccessToken: string;
  AShopID, AItemID: Int64; out AItem: TShopeeItem;
  out AErrorMessage: string): Boolean;
const
  PATH_INFO = '/api/v2/product/get_item_base_info';
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONResp: TJSONValue;
  RespObj, ResponseDataObj: TJSONObject;
  ItemArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  AItem.ItemID := 0;
  AItem.ItemName := '';
  AItem.ItemSKU := '';
  AItem.ItemStatus := '';
  AItem.OriginalPrice := 0;
  AItem.Stock := 0;
  AItem.ModelID := 0;
  DoLog(Format('Buscando item %d diretamente por ID (independente do status)...',
    [AItemID]));
  ResponseStr := ExecuteGet(PATH_INFO, 'item_id_list=' + IntToStr(AItemID),
    AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao buscar item %d: %s',
      [StatusCode, AItemID, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONResp is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada ao buscar item (não é JSON)';
      Exit;
    end;
    RespObj := TJSONObject(JSONResp);
    if Assigned(RespObj.GetValue('error')) and
       (RespObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := RespObj.GetValue<string>('error');
      if Assigned(RespObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
      DoLog('Erro ao buscar item: ' + AErrorMessage);
      Exit;
    end;
    if not RespObj.TryGetValue<TJSONObject>('response', ResponseDataObj) or
       not ResponseDataObj.TryGetValue<TJSONArray>('item_list', ItemArr) or
       (ItemArr.Count = 0) then
    begin
      AErrorMessage := Format('Item %d não encontrado na loja %d (verifique se o ' +
        'item_id pertence a essa loja e se o shop está autorizado).',
        [AItemID, AShopID]);
      Exit;
    end;
    ParseItemJSON(ItemArr.Items[0] as TJSONObject, AItem);
    Result := True;
    DoLog(Format('Item %d encontrado: "%s" | Status: %s | Preço: %.2f | Estoque: %d',
      [AItem.ItemID, AItem.ItemName, AItem.ItemStatus, AItem.OriginalPrice, AItem.Stock]));
  finally
    JSONResp.Free;
  end;
end;
function TShopeeOpenAPIClient.GetFirstLeafCategory(const AAccessToken: string;
  AShopID: Int64; out ACategoryID: Int64; out ACategoryName: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/product/get_category';
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONResp: TJSONValue;
  RespObj, ResponseDataObj, CatObj: TJSONObject;
  CatArr: TJSONArray;
  I: Integer;
  HasChildren: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  ACategoryID := 0;
  ACategoryName := '';
  DoLog('Buscando categoria de produto (get_category)...');
  ResponseStr := ExecuteGet(API_PATH, 'language=pt-br', AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao listar categorias: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONResp is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada ao listar categorias (não é JSON): ' + ResponseStr;
      Exit;
    end;
    RespObj := TJSONObject(JSONResp);
    if Assigned(RespObj.GetValue('error')) and (RespObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := RespObj.GetValue<string>('error');
      if Assigned(RespObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
      DoLog('Erro ao listar categorias: ' + AErrorMessage);
      Exit;
    end;
    if not RespObj.TryGetValue<TJSONObject>('response', ResponseDataObj) or
       not ResponseDataObj.TryGetValue<TJSONArray>('category_list', CatArr) then
    begin
      AErrorMessage := 'Resposta sem "category_list": ' + ResponseStr;
      Exit;
    end;
    for I := 0 to CatArr.Count - 1 do
    begin
      CatObj := CatArr.Items[I] as TJSONObject;
      if not CatObj.TryGetValue<Boolean>('has_children', HasChildren) then
        HasChildren := False;
      if not HasChildren then
      begin
        ACategoryID := CatObj.GetValue<Int64>('category_id');
        CatObj.TryGetValue<string>('category_name', ACategoryName);
        Result := True;
        DoLog(Format('Categoria selecionada: "%s" (ID %d)', [ACategoryName, ACategoryID]));
        Break;
      end;
    end;
    if not Result then
      AErrorMessage := 'Nenhuma categoria "folha" (sem subcategorias) encontrada na resposta.';
  finally
    JSONResp.Free;
  end;
end;
function TShopeeOpenAPIClient.GetFirstEnabledLogisticsChannel(
  const AAccessToken: string; AShopID: Int64; out AChannelID: Int64;
  out AChannelName: string; out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/logistics/get_channel_list';
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONResp: TJSONValue;
  RespObj, ResponseDataObj, ChanObj: TJSONObject;
  ChanArr: TJSONArray;
  I: Integer;
  Enabled: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  AChannelID := 0;
  AChannelName := '';
  DoLog('Buscando canal de logística habilitado (get_channel_list)...');
  ResponseStr := ExecuteGet(API_PATH, '', AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao listar canais de logística: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONResp is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada ao listar canais (não é JSON): ' + ResponseStr;
      Exit;
    end;
    RespObj := TJSONObject(JSONResp);
    if Assigned(RespObj.GetValue('error')) and (RespObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := RespObj.GetValue<string>('error');
      if Assigned(RespObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
      DoLog('Erro ao listar canais de logística: ' + AErrorMessage);
      Exit;
    end;
    if not RespObj.TryGetValue<TJSONObject>('response', ResponseDataObj) or
       not ResponseDataObj.TryGetValue<TJSONArray>('logistics_channel_list', ChanArr) then
    begin
      AErrorMessage := 'Resposta sem "logistics_channel_list": ' + ResponseStr;
      Exit;
    end;
    for I := 0 to ChanArr.Count - 1 do
    begin
      ChanObj := ChanArr.Items[I] as TJSONObject;
      if not ChanObj.TryGetValue<Boolean>('enabled', Enabled) then
        Enabled := False;
      if Enabled then
      begin
        AChannelID := ChanObj.GetValue<Int64>('logistics_channel_id');
        ChanObj.TryGetValue<string>('logistics_channel_name', AChannelName);
        Result := True;
        DoLog(Format('Canal de logística selecionado: "%s" (ID %d)', [AChannelName, AChannelID]));
        Break;
      end;
    end;
    if not Result then
      AErrorMessage := 'Nenhum canal de logística habilitado encontrado para essa loja.';
  finally
    JSONResp.Free;
  end;
end;
function TShopeeOpenAPIClient.UploadImage(const AAccessToken: string;
  AShopID: Int64; const AImageFilePath: string; out AImageID: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/media_space/upload_image';
  MAX_TENTATIVAS = 2;
var
  Timestamp: Int64;
  Sign, URL, ResponseStr: string;
  Response: IHTTPResponse;
  FormData: TMultipartFormData;
  StatusCode: Integer;
  JSONResp: TJSONValue;
  RespObj, ResponseDataObj, ImageInfoObj: TJSONObject;
  Tentativa: Integer;
  EnvioOK: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  AImageID := '';
  if not TFile.Exists(AImageFilePath) then
  begin
    AErrorMessage := 'Arquivo de imagem não encontrado: ' + AImageFilePath;
    Exit;
  end;
  EnvioOK := False;
  StatusCode := 0;
  ResponseStr := '';
  // Upload de imagem costuma ser a chamada mais sensível a lentidão da
  // Shopee (sobe um arquivo, não só um payload JSON pequeno) - em dias de
  // instabilidade da plataforma, um timeout pode ser só transitório. Por
  // isso tentamos até 2 vezes, recalculando timestamp/assinatura a cada
  // tentativa (a assinatura tem validade curta).
  for Tentativa := 1 to MAX_TENTATIVAS do
  begin
    if Tentativa > 1 then
      DoLog(Format('Timeout/erro no envio da imagem - tentativa %d de %d...',
        [Tentativa, MAX_TENTATIVAS]));
    Timestamp := CurrentTimestamp;
    Sign := ComputeSign(API_PATH, Timestamp, AAccessToken, AShopID);
    URL := BaseURL + API_PATH +
      '?partner_id=' + IntToStr(FPartnerID) +
      '&timestamp=' + IntToStr(Timestamp) +
      '&sign=' + Sign +
      '&shop_id=' + IntToStr(AShopID) +
      '&access_token=' + AAccessToken;
    DoLog(Format('Enviando imagem para a Shopee: %s (tentativa %d/%d)',
      [ExtractFileName(AImageFilePath), Tentativa, MAX_TENTATIVAS]));
    FormData := TMultipartFormData.Create;
    try
      FormData.AddFile('image', AImageFilePath);
      try
        Response := FHTTPClient.Post(URL, FormData);
        StatusCode := Response.StatusCode;
        ResponseStr := Response.ContentAsString(TEncoding.UTF8);
        EnvioOK := True;
      except
        on E: Exception do
        begin
          AErrorMessage := 'Erro ao enviar imagem: ' + E.Message;
          DoLog(AErrorMessage);
          // ETimeout e erros de conexão são candidatos a nova tentativa;
          // segue o loop. Se for a última tentativa, sai com o erro já
          // registrado em AErrorMessage.
        end;
      end;
    finally
      FormData.Free;
    end;
    if EnvioOK then
      Break;
  end;
  if not EnvioOK then
    Exit; // AErrorMessage já preenchido pela última tentativa
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao enviar imagem: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONResp is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada ao enviar imagem (não é JSON): ' + ResponseStr;
      Exit;
    end;
    RespObj := TJSONObject(JSONResp);
    if Assigned(RespObj.GetValue('error')) and (RespObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := RespObj.GetValue<string>('error');
      if Assigned(RespObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
      DoLog('Erro ao enviar imagem: ' + AErrorMessage);
      Exit;
    end;
    if not RespObj.TryGetValue<TJSONObject>('response', ResponseDataObj) then
    begin
      AErrorMessage := 'Resposta sem campo "response": ' + ResponseStr;
      Exit;
    end;
    if not ResponseDataObj.TryGetValue<TJSONObject>('image_info', ImageInfoObj) or
       not ImageInfoObj.TryGetValue<string>('image_id', AImageID) then
    begin
      AErrorMessage := 'Não foi possível localizar "image_id" na resposta: ' + ResponseStr;
      Exit;
    end;
    Result := True;
    DoLog('Imagem enviada com sucesso. image_id: ' + AImageID);
  finally
    JSONResp.Free;
  end;
end;
function TShopeeOpenAPIClient.CreateProduct(const AAccessToken: string;
  AShopID: Int64; const AItemName, ADescription, AImageFilePath: string;
  APrice: Double; AStock: Integer; AWeightKg: Double; ACategoryID: Int64;
  ABrandID: Int64; const ABrandName: string; out ANewItemID: Int64;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/product/add_item';
var
  CategoryID, LogisticsChannelID: Int64;
  CategoryName, LogisticsChannelName, ImageID, ResponseStr: string;
  BodyJSON, PriceInfoObj, StockInfoObj, SellerStockObj, ImageObj, LogisticObj,
    BrandObj: TJSONObject;
  PriceInfoArr, SellerStockArr, ImageIDArr, LogisticArr: TJSONArray;
  StatusCode: Integer;
  JSONResp: TJSONValue;
  RespObj, ResponseDataObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  ANewItemID := 0;
  DoLog('=== Iniciando cadastro de produto ===');
  // 1) Categoria - usa a informada manualmente, ou detecta automaticamente
  // (0 = auto) a primeira categoria "folha" válida - prático em Sandbox.
  if ACategoryID > 0 then
  begin
    CategoryID := ACategoryID;
    DoLog(Format('Usando categoria informada manualmente: ID %d', [CategoryID]));
  end
  else if not GetFirstLeafCategory(AAccessToken, AShopID, CategoryID, CategoryName, AErrorMessage) then
  begin
    AErrorMessage := 'Falha ao obter categoria: ' + AErrorMessage;
    Exit;
  end;
  // 2) Logística - pega o primeiro canal habilitado da loja
  if not GetFirstEnabledLogisticsChannel(AAccessToken, AShopID, LogisticsChannelID,
    LogisticsChannelName, AErrorMessage) then
  begin
    AErrorMessage := 'Falha ao obter canal de logística: ' + AErrorMessage;
    Exit;
  end;
  // 3) Imagem - obrigatória, sobe antes de montar o produto
  if not UploadImage(AAccessToken, AShopID, AImageFilePath, ImageID, AErrorMessage) then
  begin
    AErrorMessage := 'Falha ao enviar imagem: ' + AErrorMessage;
    Exit;
  end;
  // 4) Monta e envia o add_item
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('item_name', AItemName);
    BodyJSON.AddPair('description', ADescription);
    BodyJSON.AddPair('category_id', TJSONNumber.Create(CategoryID));
    BodyJSON.AddPair('weight', TJSONNumber.Create(AWeightKg));
    PriceInfoArr := TJSONArray.Create;
    PriceInfoObj := TJSONObject.Create;
    PriceInfoObj.AddPair('original_price', TJSONNumber.Create(APrice));
    PriceInfoArr.AddElement(PriceInfoObj);
    BodyJSON.AddPair('price_info', PriceInfoArr);
    StockInfoObj := TJSONObject.Create;
    SellerStockArr := TJSONArray.Create;
    SellerStockObj := TJSONObject.Create;
    // location_id vazio é rejeitado pelo add_item (diferente do
    // update_stock) - por isso a chave é omitida aqui.
    SellerStockObj.AddPair('stock', TJSONNumber.Create(AStock));
    SellerStockArr.AddElement(SellerStockObj);
    StockInfoObj.AddPair('seller_stock', SellerStockArr);
    BodyJSON.AddPair('stock_info_v2', StockInfoObj);
    ImageObj := TJSONObject.Create;
    ImageIDArr := TJSONArray.Create;
    ImageIDArr.Add(ImageID);
    ImageObj.AddPair('image_id_list', ImageIDArr);
    BodyJSON.AddPair('image', ImageObj);
    LogisticArr := TJSONArray.Create;
    LogisticObj := TJSONObject.Create;
    LogisticObj.AddPair('logistic_id', TJSONNumber.Create(LogisticsChannelID));
    LogisticObj.AddPair('enabled', TJSONBool.Create(True));
    LogisticArr.AddElement(LogisticObj);
    BodyJSON.AddPair('logistic_info', LogisticArr);
    // Marca - várias categorias exigem (product.error_invalid_brand se
    // omitido). ABrandID=0 + "No Brand" funciona na maioria das categorias;
    // em produção, informe o brand_id real cadastrado na loja quando a
    // categoria exigir uma marca específica.
    BrandObj := TJSONObject.Create;
    BrandObj.AddPair('brand_id', TJSONNumber.Create(ABrandID));
    BrandObj.AddPair('original_brand_name', ABrandName);
    BodyJSON.AddPair('brand', BrandObj);
    DoLog('Enviando add_item para a Shopee...');
    ResponseStr := ExecutePost(API_PATH, BodyJSON.ToJSON, AAccessToken, AShopID, StatusCode);
  finally
    BodyJSON.Free;
  end;
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao criar produto: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONResp is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada ao criar produto (não é JSON): ' + ResponseStr;
      Exit;
    end;
    RespObj := TJSONObject(JSONResp);
    if Assigned(RespObj.GetValue('error')) and (RespObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := RespObj.GetValue<string>('error');
      if Assigned(RespObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
      // request_id é necessário para abrir chamado de suporte com a Shopee
      // referenciando esta chamada específica.
      if Assigned(RespObj.GetValue('request_id')) then
        AErrorMessage := AErrorMessage + ' | request_id: ' + RespObj.GetValue<string>('request_id');
      DoLog('Erro ao criar produto: ' + AErrorMessage);
      Exit;
    end;
    if not RespObj.TryGetValue<TJSONObject>('response', ResponseDataObj) or
       not ResponseDataObj.TryGetValue<Int64>('item_id', ANewItemID) then
    begin
      AErrorMessage := 'Resposta sem "item_id": ' + ResponseStr;
      Exit;
    end;
    Result := True;
    DoLog(Format('Produto criado com sucesso! item_id: %d (status inicial normalmente NORMAL/Ativo)', [ANewItemID]));
  finally
    JSONResp.Free;
  end;
end;
function TShopeeOpenAPIClient.GetItemList(const AAccessToken: string; AShopID: Int64;
  out AItems: TShopeeItemArray; out AErrorMessage: string;
  AUpdateTimeFrom: Int64 = 0; AUpdateTimeTo: Int64 = 0;
  const AItemStatusFilter: string = ''): Boolean;
const
  PATH_LIST = '/api/v2/product/get_item_list';
  PATH_INFO = '/api/v2/product/get_item_base_info';
  // Tetos da propria Shopee: 50 itens por pagina na listagem e 50 ids por
  // chamada no get_item_base_info. Pedir mais devolve erro.
  PAGE_SIZE = 50;
  INFO_LOTE = 50;
  // Trava contra laco infinito (has_next_page que nunca zera). 200 x 50 =
  // 10.000 anuncios, muito acima do caso real.
  MAX_PAGINAS = 200;
var
  StatusCode: Integer;
  ResponseStr, QueryBase, QueryExtra, IDList: string;
  JSONValue, JSONResp: TJSONValue;
  JSONObj, RespObj, ResponseDataObj: TJSONObject;
  ItemArr: TJSONArray;
  I, J, Offset, Pagina, Base: Integer;
  TodosIDs: TArray<Int64>;
  TemProxima: Boolean;
begin
  Result := False;
  SetLength(AItems, 0);
  SetLength(TodosIDs, 0);
  AErrorMessage := '';
  // Filtros fixos da consulta, sem offset/page_size (esses mudam a cada pagina).
  // Se AItemStatusFilter vier vazio (uso padrao), usa os 4 status que cobrem
  // "todos os produtos cadastrados" (igual as abas Ativo/Violacao/Sob Analise/
  // Nao publicado do painel da Shopee): NORMAL, BANNED, REVIEWING e UNLIST.
  // SELLER_DELETE/SHOPEE_DELETE (itens excluidos) ficam de fora de proposito.
  QueryBase := '';
  if AItemStatusFilter <> '' then
    QueryBase := QueryBase + '&item_status=' + AItemStatusFilter
  else
    QueryBase := QueryBase +
      '&item_status=NORMAL&item_status=BANNED&item_status=REVIEWING&item_status=UNLIST';
  // {ATENCAO} update_time aqui e' a data da ULTIMA EDICAO DO ANUNCIO. Alterar
  // ESTOQUE ou PRECO por API NAO mexe nesse campo - confirmado em 14/10/2026:
  // um anuncio editado pela ultima vez em 31/07 continuou com update_time de
  // 31/07 depois de o F2 mudar estoque e preco no mesmo dia. Janela curta
  // demais aqui esconde produto ativo e em uso, sem erro nenhum.
  // A Shopee NAO limita o tamanho dessa janela (testado com 286 dias) -
  // diferente da busca de PEDIDOS, que trava em 15 dias.
  if AUpdateTimeFrom > 0 then
    QueryBase := QueryBase + '&update_time_from=' + IntToStr(AUpdateTimeFrom);
  if AUpdateTimeTo > 0 then
    QueryBase := QueryBase + '&update_time_to=' + IntToStr(AUpdateTimeTo);
  // 1) Lista os item_id da loja, pagina a pagina.
  Offset := 0;
  Pagina := 0;
  TemProxima := False;
  repeat
    Inc(Pagina);
    QueryExtra := 'offset=' + IntToStr(Offset) + '&page_size=' +
      IntToStr(PAGE_SIZE) + QueryBase;
    ResponseStr := ExecuteGet(PATH_LIST, QueryExtra, AAccessToken, AShopID, StatusCode);
    // {DIAGNOSTICO} resposta crua sempre no log - o ExecuteGet so registra
    // quando o HTTP e' 400 ou mais, e a Shopee responde 200 com lista vazia
    // tanto quando a loja nao tem item quanto quando o filtro nao casa. Sem
    // isso, "0 produtos" nao diz qual dos dois aconteceu.
    DoLog(Format('GetItemList pagina %d [%s]: HTTP %d %s',
      [Pagina, QueryExtra, StatusCode, ResponseStr]));
    if StatusCode >= 400 then
    begin
      AErrorMessage := Format('HTTP %d ao listar itens: %s', [StatusCode, ResponseStr]);
      DoLog(AErrorMessage);
      Exit;
    end;
    TemProxima := False;
    JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
    try
      if not (JSONValue is TJSONObject) then
      begin
        AErrorMessage := 'Resposta inesperada ao listar itens (nao e JSON)';
        Exit;
      end;
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and
         (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        DoLog('Erro ao listar itens: ' + AErrorMessage);
        Exit;
      end;
      // O array "item" vem dentro do objeto aninhado "response", nao na raiz.
      if not JSONObj.TryGetValue<TJSONObject>('response', RespObj) or
         not RespObj.TryGetValue<TJSONArray>('item', ItemArr) then
        Break; // sem itens nessa pagina - nao e' erro, so' acabou
      // Acrescenta ao que ja veio das paginas anteriores.
      Base := Length(TodosIDs);
      SetLength(TodosIDs, Base + ItemArr.Count);
      for I := 0 to ItemArr.Count - 1 do
        TodosIDs[Base + I] := ItemArr.Items[I].GetValue<Int64>('item_id');
      RespObj.TryGetValue<Boolean>('has_next_page', TemProxima);
    finally
      JSONValue.Free;
    end;
    Offset := Offset + PAGE_SIZE;
  until (not TemProxima) or (Pagina >= MAX_PAGINAS);
  if TemProxima and (Pagina >= MAX_PAGINAS) then
    DoLog(Format('Aviso: limite de %d paginas atingido - podem existir mais ' +
      'anuncios nao listados.', [MAX_PAGINAS]));
  if Length(TodosIDs) = 0 then
  begin
    Result := True;
    Exit;
  end;
  DoLog(Format('%d anuncio(s) listado(s) em %d pagina(s) - buscando detalhes.',
    [Length(TodosIDs), Pagina]));
  // 2) Traz nome/preco/estoque desses itens, em lotes de 50 (teto da Shopee).
  I := 0;
  while I < Length(TodosIDs) do
  begin
    IDList := '';
    J := I;
    while (J < Length(TodosIDs)) and (J - I < INFO_LOTE) do
    begin
      if IDList <> '' then
        IDList := IDList + ',';
      IDList := IDList + IntToStr(TodosIDs[J]);
      Inc(J);
    end;
    ResponseStr := ExecuteGet(PATH_INFO, 'item_id_list=' + IDList,
      AAccessToken, AShopID, StatusCode);
    if StatusCode >= 400 then
    begin
      AErrorMessage := Format('HTTP %d ao obter detalhes dos itens: %s',
        [StatusCode, ResponseStr]);
      DoLog(AErrorMessage);
      SetLength(AItems, 0);
      Exit;
    end;
    JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
    try
      if not (JSONResp is TJSONObject) then
      begin
        AErrorMessage := 'Resposta inesperada ao obter detalhes (nao e JSON)';
        SetLength(AItems, 0);
        Exit;
      end;
      RespObj := TJSONObject(JSONResp);
      if Assigned(RespObj.GetValue('error')) and
         (RespObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := RespObj.GetValue<string>('error');
        if Assigned(RespObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
        DoLog('Erro ao obter detalhes dos itens: ' + AErrorMessage);
        SetLength(AItems, 0);
        Exit;
      end;
      // Mesmo caso do passo 1: "item_list" vem dentro de "response".
      if RespObj.TryGetValue<TJSONObject>('response', ResponseDataObj) and
         ResponseDataObj.TryGetValue<TJSONArray>('item_list', ItemArr) then
      begin
        Base := Length(AItems);
        SetLength(AItems, Base + ItemArr.Count);
        for J := 0 to ItemArr.Count - 1 do
          ParseItemJSON(ItemArr.Items[J] as TJSONObject, AItems[Base + J]);
      end;
    finally
      JSONResp.Free;
    end;
    Inc(I, INFO_LOTE);
  end;
  Result := True;
end;
function TShopeeOpenAPIClient.UpdatePrice(const AAccessToken: string;
  AShopID, AItemID, AModelID: Int64; ANewPrice: Double;
  out AErrorMessage: string): Boolean;
const
  PATH = '/api/v2/product/update_price';
var
  BodyJSON, PriceItem: TJSONObject;
  PriceList: TJSONArray;
  StatusCode: Integer;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('item_id', TJSONNumber.Create(IntToStr(AItemID)));
    PriceList := TJSONArray.Create;
    PriceItem := TJSONObject.Create;
    if AModelID <> 0 then
      PriceItem.AddPair('model_id', TJSONNumber.Create(IntToStr(AModelID)));
    PriceItem.AddPair('original_price', TJSONNumber.Create(ANewPrice));
    PriceList.AddElement(PriceItem);
    BodyJSON.AddPair('price_list', PriceList);
    ResponseStr := ExecutePost(PATH, BodyJSON.ToJSON, AAccessToken, AShopID, StatusCode);
  finally
    BodyJSON.Free;
  end;
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        Exit;
      end;
    end;
    Result := True;
    DoLog(Format('Preço do item %d atualizado para %.2f', [AItemID, ANewPrice]));
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.UpdateStock(const AAccessToken: string;
  AShopID, AItemID, AModelID: Int64; ANewStock: Integer;
  out AErrorMessage: string): Boolean;
const
  PATH = '/api/v2/product/update_stock';
var
  BodyJSON, StockItem, SellerStockObj: TJSONObject;
  StockList, SellerStockArr: TJSONArray;
  StatusCode: Integer;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('item_id', TJSONNumber.Create(IntToStr(AItemID)));
    // A Shopee mudou o formato do update_stock: o estoque não vai mais como
    // um campo simples "normal_stock", e sim dentro de "seller_stock", uma
    // lista de { "location_id": "", "stock": N } - location_id pode ficar
    // vazio para sellers sem múltiplos armazéns (Warehouse Distribution não
    // habilitado). Sem esse campo, a API retorna
    // "invalid field seller_stock, value must Not Null".
    StockList := TJSONArray.Create;
    StockItem := TJSONObject.Create;
    if AModelID <> 0 then
      StockItem.AddPair('model_id', TJSONNumber.Create(IntToStr(AModelID)));
    SellerStockArr := TJSONArray.Create;
    SellerStockObj := TJSONObject.Create;
    SellerStockObj.AddPair('location_id', '');
    SellerStockObj.AddPair('stock', TJSONNumber.Create(ANewStock));
    SellerStockArr.AddElement(SellerStockObj);
    StockItem.AddPair('seller_stock', SellerStockArr);
    StockList.AddElement(StockItem);
    BodyJSON.AddPair('stock_list', StockList);
    ResponseStr := ExecutePost(PATH, BodyJSON.ToJSON, AAccessToken, AShopID, StatusCode);
  finally
    BodyJSON.Free;
  end;
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        Exit;
      end;
    end;
    Result := True;
    DoLog(Format('Estoque do item %d atualizado para %d', [AItemID, ANewStock]));
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.GetOrderList(const AAccessToken: string;
  AShopID: Int64; out AOrders: TShopeeOrderArray; out AErrorMessage: string;
  ADiasAtras: Integer): Boolean;
const
  PATH_LIST = '/api/v2/order/get_order_list';
  PATH_DETAIL = '/api/v2/order/get_order_detail';
  MAX_SN_POR_LOTE = 50; // limite da Shopee para order_sn_list no get_order_detail
var
  TimeFrom, TimeTo: Int64;
  ResponseStr: string;
  StatusCode: Integer;
  JSONValue, JSONResp: TJSONValue;
  JSONObj, RespObj, ResponseData, Item: TJSONObject;
  OrderListArr: TJSONArray;
  I, LoteInicio, LoteFim, J, TotalAcumulado: Integer;
  CreateTimeUnix: Int64;
  TodosOsSN: TArray<string>;
  SNListLote: string;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AOrders, 0);
  TimeTo := CurrentTimestamp;
  TimeFrom := TimeTo - (ADiasAtras * 86400);
  // 1) Busca a lista de order_sn no período
  ResponseStr := ExecuteGet(PATH_LIST,
    Format('time_range_field=create_time&time_from=%d&time_to=%d&page_size=100&response_optional_fields=order_status',
      [TimeFrom, TimeTo]),
    AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao listar pedidos: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta inesperada ao listar pedidos (não é JSON)';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and
       (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      DoLog('Erro ao listar pedidos: ' + AErrorMessage);
      Exit;
    end;
    if not JSONObj.TryGetValue<TJSONObject>('response', ResponseData) then
    begin
      // loja sem pedidos no periodo - nao e erro, so nao tem o que mostrar
      Result := True;
      Exit;
    end;
    if not ResponseData.TryGetValue<TJSONArray>('order_list', OrderListArr) or
       (OrderListArr.Count = 0) then
    begin
      Result := True;
      Exit;
    end;
    SetLength(TodosOsSN, OrderListArr.Count);
    for I := 0 to OrderListArr.Count - 1 do
      TodosOsSN[I] := (OrderListArr.Items[I] as TJSONObject).GetValue<string>('order_sn');
  finally
    JSONValue.Free;
  end;
  if Length(TodosOsSN) = 0 then
  begin
    Result := True;
    Exit;
  end;
  DoLog(Format('%d pedido(s) no período - buscando detalhes em lotes de até %d...',
    [Length(TodosOsSN), MAX_SN_POR_LOTE]));
  // 2) Traz os detalhes (status, data, valor total) em lotes de até 50 SNs
  // por chamada - limite documentado do get_order_detail. Sem essa
  // paginação, lojas com mais de 50 pedidos no período teriam pedidos
  // faltando ou a chamada falharia silenciosamente.
  TotalAcumulado := 0;
  LoteInicio := 0;
  while LoteInicio < Length(TodosOsSN) do
  begin
    LoteFim := Min(LoteInicio + MAX_SN_POR_LOTE, Length(TodosOsSN)) - 1;
    SNListLote := '';
    for J := LoteInicio to LoteFim do
    begin
      if SNListLote <> '' then
        SNListLote := SNListLote + ',';
      SNListLote := SNListLote + TodosOsSN[J];
    end;
    ResponseStr := ExecuteGet(PATH_DETAIL,
      'order_sn_list=' + SNListLote +
      '&response_optional_fields=order_status,create_time,total_amount,currency',
      AAccessToken, AShopID, StatusCode);
    if StatusCode >= 400 then
    begin
      AErrorMessage := Format('HTTP %d ao obter detalhes dos pedidos (lote %d-%d): %s',
        [StatusCode, LoteInicio + 1, LoteFim + 1, ResponseStr]);
      DoLog(AErrorMessage);
      Exit;
    end;
    JSONResp := TJSONObject.ParseJSONValue(ResponseStr);
    try
      if not (JSONResp is TJSONObject) then
      begin
        AErrorMessage := Format('Resposta inesperada ao obter detalhes dos pedidos (lote %d-%d, não é JSON)',
          [LoteInicio + 1, LoteFim + 1]);
        Exit;
      end;
      RespObj := TJSONObject(JSONResp);
      if Assigned(RespObj.GetValue('error')) and
         (RespObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := RespObj.GetValue<string>('error');
        if Assigned(RespObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + RespObj.GetValue<string>('message');
        DoLog(Format('Erro ao obter detalhes dos pedidos (lote %d-%d): %s',
          [LoteInicio + 1, LoteFim + 1, AErrorMessage]));
        Exit;
      end;
      if not RespObj.TryGetValue<TJSONObject>('response', ResponseData) or
         not ResponseData.TryGetValue<TJSONArray>('order_list', OrderListArr) then
      begin
        // este lote não trouxe pedidos (não é necessariamente erro) - segue
        // para o próximo lote em vez de abortar tudo
        Inc(LoteInicio, MAX_SN_POR_LOTE);
        Continue;
      end;
      SetLength(AOrders, TotalAcumulado + OrderListArr.Count);
      for I := 0 to OrderListArr.Count - 1 do
      begin
        Item := OrderListArr.Items[I] as TJSONObject;
        AOrders[TotalAcumulado].OrderSN := Item.GetValue<string>('order_sn');
        if not Item.TryGetValue<string>('order_status', AOrders[TotalAcumulado].OrderStatus) then
          AOrders[TotalAcumulado].OrderStatus := '';
        if Item.TryGetValue<Int64>('create_time', CreateTimeUnix) then
          AOrders[TotalAcumulado].CreateTime := UnixToDateTime(CreateTimeUnix, False)
        else
          AOrders[TotalAcumulado].CreateTime := 0;
        // total_amount pode vir como string ou como número dependendo da
        // versão/região da API - mesma situação já vista em original_price
        // no get_item_base_info - por isso tentamos os dois formatos.
        if not Item.TryGetValue<string>('total_amount', AOrders[TotalAcumulado].TotalAmount) then
        begin
          if Assigned(Item.GetValue('total_amount')) then
            AOrders[TotalAcumulado].TotalAmount := FormatFloat('0.00',
              Item.GetValue<Double>('total_amount'), TFormatSettings.Invariant)
          else
          begin
            AOrders[TotalAcumulado].TotalAmount := '';
            DoLog(Format('DIAGNÓSTICO: pedido %s veio sem "total_amount" no JSON.',
              [AOrders[TotalAcumulado].OrderSN]));
          end;
        end;
        if not Item.TryGetValue<string>('currency', AOrders[TotalAcumulado].Currency) then
          AOrders[TotalAcumulado].Currency := '';
        Inc(TotalAcumulado);
      end;
    finally
      JSONResp.Free;
    end;
    Inc(LoteInicio, MAX_SN_POR_LOTE);
  end;
  Result := True;
  DoLog(Format('%d pedido(s) encontrado(s) nos últimos %d dias.', [Length(AOrders), ADiasAtras]));
end;
// ============================================================================
// ACOES SOBRE PEDIDOS (adicionado)
// ============================================================================
function TShopeeOpenAPIClient.GetShippingParameter(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out ARawJSON: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/logistics/get_shipping_parameter';
var
  StatusCode: Integer;
  QueryExtra: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  ARawJSON := '';
  QueryExtra := 'order_sn=' + TNetEncoding.URL.Encode(AOrderSN);
  ARawJSON := ExecuteGet(API_PATH, QueryExtra, AAccessToken, AShopID, StatusCode);
  DoLog('get_shipping_parameter (' + AOrderSN + '): ' + ARawJSON);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao buscar parametros de envio: %s', [StatusCode, ARawJSON]);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ARawJSON);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta invalida ao buscar parametros de envio.';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      Exit;
    end;
    Result := True;
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.ShipOrder(const AAccessToken: string; AShopID: Int64;
  const AOrderSN: string; out AErrorMessage: string): Boolean;
var
  RawShippingParam: string;
  ShippingJSON: TJSONValue;
  ShippingObj, RespObj, InfoNeededObj, PickupObj, DropoffObj: TJSONObject;
  PickupArr, DropoffArr, NonIntArr, AddressListArr, BranchListArr: TJSONArray;
  BodyJSON, PickupBodyObj, DropoffBodyObj: TJSONObject;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
  AddressID, BranchID: Int64;
  FirstAddressObj, TimeSlotObj: TJSONObject;
  TimeSlotArr, FlagsArr: TJSONArray;
  PickupTimeID: string;
  J, K: Integer;
begin
  // A Shopee exige saber qual tipo de logistica esse pedido especifico usa
  // (pickup / dropoff / non_integrated) ANTES de despachar - por isso
  // consulta get_shipping_parameter primeiro, ao inves de so mandar
  // {"order_sn": ...} (que da o erro "select just one way to ship").
  Result := False;
  AErrorMessage := '';
  if not GetShippingParameter(AAccessToken, AShopID, AOrderSN, RawShippingParam, AErrorMessage) then
  begin
    AErrorMessage := 'Nao foi possivel obter os parametros de envio: ' + AErrorMessage;
    Exit;
  end;
  AddressID := 0;
  BranchID := 0;
  PickupTimeID := '';
  PickupArr := nil;
  DropoffArr := nil;
  NonIntArr := nil;
  ShippingJSON := TJSONObject.ParseJSONValue(RawShippingParam);
  try
    ShippingObj := ShippingJSON as TJSONObject;
    if not ShippingObj.TryGetValue<TJSONObject>('response', RespObj) then
    begin
      AErrorMessage := 'Resposta de get_shipping_parameter sem campo "response": ' + RawShippingParam;
      Exit;
    end;
    RespObj.TryGetValue<TJSONObject>('info_needed', InfoNeededObj);
    if Assigned(InfoNeededObj) then
    begin
      InfoNeededObj.TryGetValue<TJSONArray>('pickup', PickupArr);
      InfoNeededObj.TryGetValue<TJSONArray>('dropoff', DropoffArr);
      InfoNeededObj.TryGetValue<TJSONArray>('non_integrated', NonIntArr);
    end;
    BodyJSON := TJSONObject.Create;
    try
      BodyJSON.AddPair('order_sn', AOrderSN);
      if Assigned(PickupArr) and (PickupArr.Count > 0) then
      begin
        // Pega o primeiro endereco de retirada disponivel na propria
        // resposta do get_shipping_parameter (response.pickup.address_list),
        // e o horario de retirada marcado como "recommended" dentro do
        // time_slot_list desse endereco (se nao houver nenhum recomendado,
        // usa o primeiro da lista). A Shopee exige os DOIS campos juntos -
        // so o address_id sozinho da "Pickup time is out of range".
        DoLog('ShipOrder ' + AOrderSN + ': tipo PICKUP detectado.');
        if RespObj.TryGetValue<TJSONObject>('pickup', PickupObj) and
           PickupObj.TryGetValue<TJSONArray>('address_list', AddressListArr) and
           (AddressListArr.Count > 0) then
        begin
          FirstAddressObj := AddressListArr.Items[0] as TJSONObject;
          AddressID := FirstAddressObj.GetValue<Int64>('address_id');
          if FirstAddressObj.TryGetValue<TJSONArray>('time_slot_list', TimeSlotArr) and
             (TimeSlotArr.Count > 0) then
          begin
            // Procura o horario marcado como "recommended" primeiro
            for J := 0 to TimeSlotArr.Count - 1 do
            begin
              TimeSlotObj := TimeSlotArr.Items[J] as TJSONObject;
              if TimeSlotObj.TryGetValue<TJSONArray>('flags', FlagsArr) then
              begin
                for K := 0 to FlagsArr.Count - 1 do
                  if FlagsArr.Items[K].Value = 'recommended' then
                  begin
                    PickupTimeID := TimeSlotObj.GetValue<string>('pickup_time_id');
                    Break;
                  end;
              end;
              if PickupTimeID <> '' then
                Break;
            end;
            // Nenhum marcado como recomendado - usa o primeiro da lista
            if PickupTimeID = '' then
              PickupTimeID := (TimeSlotArr.Items[0] as TJSONObject).GetValue<string>('pickup_time_id');
          end;
        end;
        PickupBodyObj := TJSONObject.Create;
        if AddressID <> 0 then
          PickupBodyObj.AddPair('address_id', TJSONNumber.Create(AddressID));
        if PickupTimeID <> '' then
          PickupBodyObj.AddPair('pickup_time_id', PickupTimeID);
        BodyJSON.AddPair('pickup', PickupBodyObj);
      end
      else if Assigned(DropoffArr) and (DropoffArr.Count > 0) then
      begin
        // Pega o primeiro ponto de coleta disponivel na propria resposta
        // (response.dropoff.branch_list).
        DoLog('ShipOrder ' + AOrderSN + ': tipo DROPOFF detectado.');
        if RespObj.TryGetValue<TJSONObject>('dropoff', DropoffObj) and
           DropoffObj.TryGetValue<TJSONArray>('branch_list', BranchListArr) and
           (BranchListArr.Count > 0) then
          BranchID := (BranchListArr.Items[0] as TJSONObject).GetValue<Int64>('branch_id');
        DropoffBodyObj := TJSONObject.Create;
        if BranchID <> 0 then
          DropoffBodyObj.AddPair('branch_id', TJSONNumber.Create(BranchID));
        BodyJSON.AddPair('dropoff', DropoffBodyObj);
      end
      else
      begin
        // non_integrated (ou nenhuma info adicional exigida) - inclui o
        // campo mesmo vazio, como a Shopee exige.
        DoLog('ShipOrder ' + AOrderSN + ': tipo NON_INTEGRATED (ou sem info extra) detectado.');
        BodyJSON.AddPair('non_integrated', TJSONObject.Create);
      end;
      BodyStr := BodyJSON.ToJSON;
    finally
      BodyJSON.Free;
    end;
  finally
    ShippingJSON.Free;
  end;
  DoLog('ShipOrder body enviado: ' + BodyStr);
  ResponseStr := ExecutePost('/api/v2/logistics/ship_order', BodyStr, AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao despachar pedido: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and
         (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        DoLog('Erro ao despachar pedido ' + AOrderSN + ': ' + AErrorMessage);
        Exit;
      end;
    end;
    Result := True;
    DoLog('Pedido ' + AOrderSN + ' despachado com sucesso.');
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.GetOrderItemIDs(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out AItemIDs: TArray<Int64>;
  out AModelIDs: TArray<Int64>; out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/get_order_detail';
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONValue, RespValue: TJSONValue;
  JSONObj, RespObj: TJSONObject;
  OrderListArr, ItemListArr: TJSONArray;
  I: Integer;
  QueryExtra: string;
begin
  // {CONFIRMADO} (03/09/2026, sandbox) "response_optional_fields=item_list"
  // e' o nome certo do parametro nessa versao da API - validado debugando a
  // baixa de pedido no SAT, com os itens chegando corretamente. A duvida
  // antiga era so' sobre o nome do campo (a doc da Shopee ja alternou entre
  // "response_optional_fields" e "optional_fields"), e nome de parametro nao
  // muda entre sandbox e producao, entao esta resolvido pros dois.
  Result := False;
  AErrorMessage := '';
  SetLength(AItemIDs, 0);
  SetLength(AModelIDs, 0);
  QueryExtra := 'order_sn_list=' + TNetEncoding.URL.Encode(AOrderSN) +
    '&response_optional_fields=item_list';
  ResponseStr := ExecuteGet(API_PATH, QueryExtra, AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao buscar detalhes do pedido: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta invalida ao buscar detalhes do pedido.';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      Exit;
    end;
    if not (JSONObj.GetValue('response') is TJSONObject) then
    begin
      AErrorMessage := 'Resposta sem campo "response".';
      Exit;
    end;
    RespObj := JSONObj.GetValue('response') as TJSONObject;
    if not (RespObj.GetValue('order_list') is TJSONArray) then
    begin
      AErrorMessage := 'Pedido nao encontrado nos detalhes retornados.';
      Exit;
    end;
    OrderListArr := RespObj.GetValue('order_list') as TJSONArray;
    if OrderListArr.Count = 0 then
    begin
      AErrorMessage := 'Pedido nao encontrado (order_list vazio).';
      Exit;
    end;
    RespValue := OrderListArr.Items[0];
    if not (RespValue is TJSONObject) then
    begin
      AErrorMessage := 'Formato inesperado em order_list[0].';
      Exit;
    end;
    if not ((RespValue as TJSONObject).GetValue('item_list') is TJSONArray) then
    begin
      AErrorMessage := 'Pedido sem item_list na resposta - confirmar o parametro ' +
        'response_optional_fields usado na chamada.';
      Exit;
    end;
    ItemListArr := (RespValue as TJSONObject).GetValue('item_list') as TJSONArray;
    SetLength(AItemIDs, ItemListArr.Count);
    SetLength(AModelIDs, ItemListArr.Count);
    for I := 0 to ItemListArr.Count - 1 do
    begin
      AItemIDs[I] := (ItemListArr.Items[I] as TJSONObject).GetValue<Int64>('item_id');
      // model_id = 0 quando o item nao tem variacao - a Shopee aceita 0 nesse caso.
      if Assigned((ItemListArr.Items[I] as TJSONObject).GetValue('model_id')) then
        AModelIDs[I] := (ItemListArr.Items[I] as TJSONObject).GetValue<Int64>('model_id')
      else
        AModelIDs[I] := 0;
    end;
    Result := True;
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.CancelOrder(const AAccessToken: string; AShopID: Int64;
  const AOrderSN, ACancelReason: string; out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/cancel_order';
var
  BodyJSON: TJSONObject;
  ItemListArr: TJSONArray;
  ItemObj: TJSONObject;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
  ItemIDs, ModelIDs: TArray<Int64>;
  I: Integer;
begin
  // A Shopee exige a lista de itens do pedido no cancelamento (motivo
  // OUT_OF_STOCK) - busca isso automaticamente via get_order_detail antes
  // de montar o corpo da chamada.
  Result := False;
  AErrorMessage := '';
  if not GetOrderItemIDs(AAccessToken, AShopID, AOrderSN, ItemIDs, ModelIDs, AErrorMessage) then
  begin
    AErrorMessage := 'Nao foi possivel obter os itens do pedido para cancelar: ' + AErrorMessage;
    Exit;
  end;
  // Log de diagnostico - se der erro generico do servidor da Shopee, isso
  // ajuda a confirmar se o item_list que buscamos esta vazio/estranho (bug
  // nosso) ou se realmente enviamos algo valido e a Shopee que rejeitou
  // (mais provavel ser instabilidade do lado deles, ja documentada em
  // outros endpoints do sandbox).
  DoLog(Format('CancelOrder %s: %d item(ns) encontrado(s) via get_order_detail.',
    [AOrderSN, Length(ItemIDs)]));
  for I := Low(ItemIDs) to High(ItemIDs) do
    DoLog(Format('  item_id=%d model_id=%d', [ItemIDs[I], ModelIDs[I]]));
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('order_sn', AOrderSN);
    BodyJSON.AddPair('cancel_reason', ACancelReason);
    ItemListArr := TJSONArray.Create;
    for I := Low(ItemIDs) to High(ItemIDs) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('item_id', TJSONNumber.Create(ItemIDs[I]));
      ItemObj.AddPair('model_id', TJSONNumber.Create(ModelIDs[I]));
      ItemListArr.AddElement(ItemObj);
    end;
    BodyJSON.AddPair('item_list', ItemListArr);
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  DoLog('CancelOrder body enviado: ' + BodyStr);
  ResponseStr := ExecutePost(API_PATH, BodyStr, AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao cancelar pedido: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and
         (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        DoLog('Erro ao cancelar pedido ' + AOrderSN + ': ' + AErrorMessage);
        Exit;
      end;
    end;
    Result := True;
    DoLog('Pedido ' + AOrderSN + ' cancelado com sucesso.');
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.HandleBuyerCancellation(const AAccessToken: string;
  AShopID: Int64; const AOrderSN, AOperation: string; out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/handle_buyer_cancellation';
var
  BodyJSON: TJSONObject;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  // AOperation deve ser exatamente 'ACCEPT' (aprovar o cancelamento pedido
  // pelo comprador) ou 'REJECT' (recusar - ex: pedido ja foi despachado).
  Result := False;
  AErrorMessage := '';
  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('order_sn', AOrderSN);
    BodyJSON.AddPair('operation', AOperation);
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  ResponseStr := ExecutePost(API_PATH, BodyStr, AAccessToken, AShopID, StatusCode);
  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d ao processar cancelamento: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and
         (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        DoLog('Erro ao processar cancelamento do pedido ' + AOrderSN + ': ' + AErrorMessage);
        Exit;
      end;
    end;
    Result := True;
    DoLog('Cancelamento do pedido ' + AOrderSN + ' processado (' + AOperation + ').');
  finally
    JSONValue.Free;
  end;
end;
// ============================================================================
// ETIQUETA DE ENVIO E NOTA FISCAL (adicionado)
// ============================================================================
function FormatarErroHTTP(AStatusCode: Integer; const AResponseStr, AContexto: string): string;
begin
  if Trim(AResponseStr).StartsWith('<') then
    Result := Format('HTTP %d ao %s: Shopee indisponivel/em manutencao no momento ' +
      '(resposta veio como pagina HTML de manutencao, nao como dado esperado).',
      [AStatusCode, AContexto])
  else
    Result := Format('HTTP %d ao %s: %s', [AStatusCode, AContexto, AResponseStr]);
end;
// ============================================================================
// PAGAMENTO (ESCROW) (adicionado)
// ============================================================================
function TShopeeOpenAPIClient.GetEscrowDetail(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out AEscrowAmount, ABuyerTotalAmount: Double;
  out APaymentMethod, ARawJSON: string; out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/payment/get_escrow_detail';
var
  StatusCode: Integer;
  QueryExtra: string;
  JSONValue: TJSONValue;
  JSONObj, RespObj, OrderIncomeObj, BuyerPaymentInfoObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  ARawJSON := '';
  AEscrowAmount := 0;
  ABuyerTotalAmount := 0;
  APaymentMethod := '';
  QueryExtra := 'order_sn=' + TNetEncoding.URL.Encode(AOrderSN);
  ARawJSON := ExecuteGet(API_PATH, QueryExtra, AAccessToken, AShopID, StatusCode);
  // Log de diagnostico com a resposta bruta - importante pra confirmar a
  // estrutura real (nomes de campo podem diferir levemente do que a
  // documentacao/SDKs de terceiros mostram) antes de fazer um parse mais
  // completo, quando o de-para com o cliente estiver pronto.
  DoLog('GetEscrowDetail (' + AOrderSN + '): ' + ARawJSON);
  if StatusCode >= 400 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ARawJSON, 'buscar detalhes de pagamento');
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ARawJSON);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta invalida ao buscar detalhes de pagamento.';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      // Erro comum e esperado: pedido ainda nao despachado/concluido, a
      // Shopee ainda nao calculou o valor final - nao e' um bug nosso.
      Exit;
    end;
    if not JSONObj.TryGetValue<TJSONObject>('response', RespObj) then
    begin
      AErrorMessage := 'Resposta sem campo "response".';
      Exit;
    end;
    if RespObj.TryGetValue<TJSONObject>('order_income', OrderIncomeObj) then
    begin
      OrderIncomeObj.TryGetValue<Double>('escrow_amount', AEscrowAmount);
      OrderIncomeObj.TryGetValue<Double>('buyer_total_amount', ABuyerTotalAmount);
    end;
    if RespObj.TryGetValue<TJSONObject>('buyer_payment_info', BuyerPaymentInfoObj) then
      BuyerPaymentInfoObj.TryGetValue<string>('payment_method', APaymentMethod);
    Result := True;
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.GetOrderDetail(const AAccessToken: string; AShopID: Int64;
  const AOrderSN: string; out ADetalhe: TShopeeOrderDetail;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/get_order_detail';
  // Lista completa dos campos precisados pelo de-para do cliente
  // (22/08/2026) - bem mais ampla que a usada no GetOrderList (que so
  // pede o minimo pra listagem).
  CAMPOS = 'buyer_user_id,buyer_username,buyer_cpf_id,recipient_address,' +
    'estimated_shipping_fee,actual_shipping_fee,actual_shipping_fee_confirmed,' +
    'shipping_carrier,goods_to_declare,note,note_update_time,item_list,' +
    'pay_time,dropshipper,dropshipper_phone,split_up,buyer_cancel_reason,' +
    'cancel_by,cancel_reason,fulfillment_flag,pickup_done_time,' +
    'package_list,invoice_data,payment_method,create_time,update_time,' +
    'total_amount,order_status';
var
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj, RespObj, OrderObj, AddressObj, Item: TJSONObject;
  OrderListArr, ItemListArr: TJSONArray;
  CreateTimeUnix, UpdateTimeUnix, PickupTimeUnix: Int64;
  I: Integer;
begin
  Result := False;
  AErrorMessage := '';
  // {ATENCAO} NAO usar FillChar aqui - TShopeeOrderDetail tem campos
  // gerenciados (string, array dinamico); FillChar corromperia a
  // contagem de referencia deles. Como ADetalhe e' parametro "out", o
  // Delphi ja garante a inicializacao limpa (strings vazias, arrays nil)
  // automaticamente ao entrar na funcao.
  ADetalhe.OrderSN := AOrderSN;

  ADetalhe.RawJSON := ExecuteGet(API_PATH,
    'order_sn_list=' + TNetEncoding.URL.Encode(AOrderSN) + '&response_optional_fields=' + CAMPOS,
    AAccessToken, AShopID, StatusCode);

  DoLog('GetOrderDetail (' + AOrderSN + '): ' + ADetalhe.RawJSON);

  if StatusCode >= 400 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ADetalhe.RawJSON, 'buscar detalhe do pedido');
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ADetalhe.RawJSON);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta invalida ao buscar detalhe do pedido.';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      Exit;
    end;
    if not JSONObj.TryGetValue<TJSONObject>('response', RespObj) then
    begin
      AErrorMessage := 'Resposta sem campo "response".';
      Exit;
    end;
    if not RespObj.TryGetValue<TJSONArray>('order_list', OrderListArr) or
       (OrderListArr.Count = 0) then
    begin
      AErrorMessage := 'Pedido nao encontrado na resposta.';
      Exit;
    end;
    OrderObj := OrderListArr.Items[0] as TJSONObject;

    OrderObj.TryGetValue<string>('order_status', ADetalhe.OrderStatus);
    if OrderObj.TryGetValue<Int64>('create_time', CreateTimeUnix) then
      ADetalhe.CreateTime := UnixToDateTime(CreateTimeUnix, False);
    if OrderObj.TryGetValue<Int64>('update_time', UpdateTimeUnix) then
      ADetalhe.UpdateTime := UnixToDateTime(UpdateTimeUnix, False);
    // total_amount pode vir como string ou numero - mesma situacao ja
    // vista no GetOrderList/get_item_base_info.
    if not OrderObj.TryGetValue<Double>('total_amount', ADetalhe.TotalAmount) then
      ADetalhe.TotalAmount := 0;
    OrderObj.TryGetValue<string>('buyer_user_id', ADetalhe.BuyerUserID);
    OrderObj.TryGetValue<string>('buyer_username', ADetalhe.BuyerUsername);
    OrderObj.TryGetValue<string>('buyer_cpf_id', ADetalhe.BuyerCpfId);
    OrderObj.TryGetValue<Double>('actual_shipping_fee', ADetalhe.ActualShippingFee);
    OrderObj.TryGetValue<string>('shipping_carrier', ADetalhe.ShippingCarrier);
    if OrderObj.TryGetValue<Int64>('pickup_done_time', PickupTimeUnix) and (PickupTimeUnix > 0) then
      ADetalhe.PickupDoneTime := UnixToDateTime(PickupTimeUnix, False);

    if OrderObj.TryGetValue<TJSONObject>('recipient_address', AddressObj) then
    begin
      AddressObj.TryGetValue<string>('name', ADetalhe.RecipientName);
      AddressObj.TryGetValue<string>('phone', ADetalhe.RecipientPhone);
      AddressObj.TryGetValue<string>('full_address', ADetalhe.RecipientFullAddress);
      AddressObj.TryGetValue<string>('city', ADetalhe.RecipientCity);
      // {NAO CONFIRMADO} no Brasil o "district" deve ser o bairro - conferir
      // num pedido real. Leitura defensiva: fica vazio se nao vier.
      AddressObj.TryGetValue<string>('district', ADetalhe.RecipientDistrict);
      AddressObj.TryGetValue<string>('state', ADetalhe.RecipientState);
      AddressObj.TryGetValue<string>('zipcode', ADetalhe.RecipientZipcode);
      AddressObj.TryGetValue<string>('country', ADetalhe.RecipientCountry);
    end;

    if OrderObj.TryGetValue<TJSONArray>('item_list', ItemListArr) then
    begin
      SetLength(ADetalhe.Items, ItemListArr.Count);
      for I := 0 to ItemListArr.Count - 1 do
      begin
        Item := ItemListArr.Items[I] as TJSONObject;
        if not Item.TryGetValue<string>('item_id', ADetalhe.Items[I].ItemID) then
        begin
          // item_id pode vir como numero - tenta o fallback
          if Assigned(Item.GetValue('item_id')) then
            ADetalhe.Items[I].ItemID := Item.GetValue<Int64>('item_id').ToString;
        end;
        Item.TryGetValue<string>('item_name', ADetalhe.Items[I].ItemName);
        Item.TryGetValue<string>('item_sku', ADetalhe.Items[I].ItemSKU);
        if not Item.TryGetValue<string>('order_item_id', ADetalhe.Items[I].OrderItemID) then
          if Assigned(Item.GetValue('order_item_id')) then
            ADetalhe.Items[I].OrderItemID := Item.GetValue<Int64>('order_item_id').ToString;
        if not Item.TryGetValue<string>('model_id', ADetalhe.Items[I].ModelID) then
          if Assigned(Item.GetValue('model_id')) then
            ADetalhe.Items[I].ModelID := Item.GetValue<Int64>('model_id').ToString;
        Item.TryGetValue<string>('model_name', ADetalhe.Items[I].ModelName);
        Item.TryGetValue<string>('model_sku', ADetalhe.Items[I].ModelSKU);
        Item.TryGetValue<Double>('model_quantity_purchased', ADetalhe.Items[I].ModelQuantityPurchased);
        Item.TryGetValue<Double>('model_original_price', ADetalhe.Items[I].ModelOriginalPrice);
        Item.TryGetValue<Double>('model_discounted_price', ADetalhe.Items[I].ModelDiscountedPrice);
        Item.TryGetValue<string>('promotion_group_id', ADetalhe.Items[I].PromotionGroupID);
        Item.TryGetValue<string>('product_location_id', ADetalhe.Items[I].ProductLocationID);
      end;
    end;

    Result := True;
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.GetOrderPackageInfo(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out APackageNumber, ATrackingNumber: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/get_order_detail';
var
  ResponseStr: string;
  StatusCode: Integer;
  QueryExtra: string;
  JSONValue, OrderValue: TJSONValue;
  JSONObj, RespObj, OrderObj, PackageObj: TJSONObject;
  OrderListArr, PackageListArr: TJSONArray;
begin
  // Mesmo endpoint do GetOrderItemIDs (get_order_detail), so pedindo o
  // campo opcional "package_list" em vez de "item_list" - e' de onde vem o
  // package_number e o tracking_number que o create_shipping_document exige.
  Result := False;
  AErrorMessage := '';
  APackageNumber := '';
  ATrackingNumber := '';
  QueryExtra := 'order_sn_list=' + TNetEncoding.URL.Encode(AOrderSN) +
    '&response_optional_fields=package_list';
  ResponseStr := ExecuteGet(API_PATH, QueryExtra, AAccessToken, AShopID, StatusCode);
  DoLog('GetOrderPackageInfo (' + AOrderSN + '): ' + ResponseStr);
  if StatusCode >= 400 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar dados do pacote');
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta invalida ao buscar dados do pacote.';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      Exit;
    end;
    if not (JSONObj.GetValue('response') is TJSONObject) then
    begin
      AErrorMessage := 'Resposta sem campo "response".';
      Exit;
    end;
    RespObj := JSONObj.GetValue('response') as TJSONObject;
    if not (RespObj.GetValue('order_list') is TJSONArray) then
    begin
      AErrorMessage := 'Pedido nao encontrado nos detalhes retornados.';
      Exit;
    end;
    OrderListArr := RespObj.GetValue('order_list') as TJSONArray;
    if OrderListArr.Count = 0 then
    begin
      AErrorMessage := 'Pedido nao encontrado (order_list vazio).';
      Exit;
    end;
    OrderValue := OrderListArr.Items[0];
    if not (OrderValue is TJSONObject) then
    begin
      AErrorMessage := 'Formato inesperado em order_list[0].';
      Exit;
    end;
    OrderObj := OrderValue as TJSONObject;
    if not (OrderObj.GetValue('package_list') is TJSONArray) then
    begin
      AErrorMessage := 'Pedido sem package_list na resposta.';
      Exit;
    end;
    PackageListArr := OrderObj.GetValue('package_list') as TJSONArray;
    if PackageListArr.Count = 0 then
    begin
      AErrorMessage := 'package_list veio vazio - pedido pode nao ter pacote gerado ainda.';
      Exit;
    end;
    PackageObj := PackageListArr.Items[0] as TJSONObject;
    if Assigned(PackageObj.GetValue('package_number')) then
      APackageNumber := PackageObj.GetValue<string>('package_number');
    // tracking_number nem sempre vem preenchido nesse ponto (so' depois do
    // ship_order de fato gerar o rastreio) - fica vazio se nao houver.
    if Assigned(PackageObj.GetValue('tracking_number')) then
      ATrackingNumber := PackageObj.GetValue<string>('tracking_number');
    Result := APackageNumber <> '';
    if not Result then
      AErrorMessage := 'package_number nao encontrado na resposta.';
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.CreateShippingDocument(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/logistics/create_shipping_document';
var
  PackageNumber, TrackingNumber: string;
  BodyJSON, OrderObj: TJSONObject;
  OrderListArr: TJSONArray;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  if not GetOrderPackageInfo(AAccessToken, AShopID, AOrderSN, PackageNumber,
       TrackingNumber, AErrorMessage) then
  begin
    AErrorMessage := 'Nao foi possivel obter os dados do pacote: ' + AErrorMessage;
    Exit;
  end;
  BodyJSON := TJSONObject.Create;
  try
    OrderListArr := TJSONArray.Create;
    OrderObj := TJSONObject.Create;
    OrderObj.AddPair('order_sn', AOrderSN);
    OrderObj.AddPair('package_number', PackageNumber);
    if TrackingNumber <> '' then
      OrderObj.AddPair('tracking_number', TrackingNumber);
    // {ATENCAO} valor confirmado no Console de testes da Shopee pra essa
    // loja/pedido - pode variar conforme o canal de logistica usado por
    // outras lojas.
    OrderObj.AddPair('shipping_document_type', 'NORMAL_AIR_WAYBILL');
    OrderListArr.AddElement(OrderObj);
    BodyJSON.AddPair('order_list', OrderListArr);
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  DoLog('CreateShippingDocument body enviado: ' + BodyStr);
  ResponseStr := ExecutePost(API_PATH, BodyStr, AAccessToken, AShopID, StatusCode);
  DoLog('CreateShippingDocument resposta: ' + ResponseStr);
  if StatusCode >= 400 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'criar etiqueta');
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
      begin
        AErrorMessage := JSONObj.GetValue<string>('error');
        if Assigned(JSONObj.GetValue('message')) then
          AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
        Exit;
      end;
    end;
    Result := True;
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.GetShippingDocumentResult(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out AStatus: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/logistics/get_shipping_document_result';
var
  BodyJSON, OrderObj: TJSONObject;
  OrderListArr: TJSONArray;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj, RespObj: TJSONObject;
  RespListArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  AStatus := '';
  BodyJSON := TJSONObject.Create;
  try
    OrderListArr := TJSONArray.Create;
    OrderObj := TJSONObject.Create;
    OrderObj.AddPair('order_sn', AOrderSN);
    OrderListArr.AddElement(OrderObj);
    BodyJSON.AddPair('order_list', OrderListArr);
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  ResponseStr := ExecutePost(API_PATH, BodyStr, AAccessToken, AShopID, StatusCode);
  DoLog('GetShippingDocumentResult resposta: ' + ResponseStr);
  if StatusCode >= 400 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'consultar status da etiqueta');
    Exit;
  end;
  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONObject) then
    begin
      AErrorMessage := 'Resposta invalida ao consultar status da etiqueta.';
      Exit;
    end;
    JSONObj := TJSONObject(JSONValue);
    if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
    begin
      AErrorMessage := JSONObj.GetValue<string>('error');
      if Assigned(JSONObj.GetValue('message')) then
        AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
      Exit;
    end;
    if JSONObj.TryGetValue<TJSONObject>('response', RespObj) and
       RespObj.TryGetValue<TJSONArray>('result_list', RespListArr) and
       (RespListArr.Count > 0) then
      AStatus := (RespListArr.Items[0] as TJSONObject).GetValue<string>('status');
    Result := True;
  finally
    JSONValue.Free;
  end;
end;
function TShopeeOpenAPIClient.DownloadShippingDocument(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out APdfBytes: TBytes;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/logistics/download_shipping_document';
var
  BodyJSON, OrderObj: TJSONObject;
  OrderListArr: TJSONArray;
  BodyStr: string;
  Timestamp: Int64;
  Sign, URL: string;
  RequestStream: TStringStream;
  Response: IHTTPResponse;
  Headers: TNetHeaders;
begin
  // {ATENCAO} Esse endpoint devolve o PDF BINARIO direto (nao um JSON) -
  // por isso nao usa o ExecutePost compartilhado (que assume resposta em
  // texto/JSON) - monta a chamada manualmente aqui, reaproveitando o mesmo
  // padrao de assinatura (BaseURL/ComputeSign) que o resto da unit ja usa.
  Result := False;
  AErrorMessage := '';
  SetLength(APdfBytes, 0);
  BodyJSON := TJSONObject.Create;
  try
    OrderListArr := TJSONArray.Create;
    OrderObj := TJSONObject.Create;
    OrderObj.AddPair('order_sn', AOrderSN);
    OrderListArr.AddElement(OrderObj);
    BodyJSON.AddPair('order_list', OrderListArr);
    BodyJSON.AddPair('shipping_document_type', 'NORMAL_AIR_WAYBILL');
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  DoLog('DownloadShippingDocument body enviado: ' + BodyStr);
  Timestamp := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now));
  Sign := ComputeSign(API_PATH, Timestamp, AAccessToken, AShopID);
  URL := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&access_token=' + AAccessToken +
    '&shop_id=' + IntToStr(AShopID) +
    '&sign=' + Sign;
  RequestStream := TStringStream.Create(BodyStr, TEncoding.UTF8);
  try
    Headers := [TNetHeader.Create('Content-Type', 'application/json')];
    try
      Response := FHTTPClient.Post(URL, RequestStream, nil, Headers);
      if Response.StatusCode >= 400 then
      begin
        AErrorMessage := FormatarErroHTTP(Response.StatusCode,
          Response.ContentAsString(TEncoding.UTF8), 'baixar etiqueta');
        DoLog(AErrorMessage);
        Exit;
      end;
      // Se a Shopee devolveu JSON em vez de PDF, e' porque deu erro (o PDF
      // binario nao comeca com "{") - loga pra facilitar o diagnostico.
      if (Response.ContentStream.Size > 0) and (Response.ContentAsString(TEncoding.UTF8).StartsWith('{')) then
      begin
        AErrorMessage := 'A Shopee devolveu um erro em vez do PDF: ' +
          Response.ContentAsString(TEncoding.UTF8);
        DoLog(AErrorMessage);
        Exit;
      end;
      Response.ContentStream.Position := 0;
      SetLength(APdfBytes, Response.ContentStream.Size);
      Response.ContentStream.ReadBuffer(APdfBytes[0], Response.ContentStream.Size);
      Result := True;
      DoLog(Format('DownloadShippingDocument: %d bytes recebidos.', [Length(APdfBytes)]));
    except
      on E: Exception do
      begin
        AErrorMessage := 'Erro na requisicao de download da etiqueta: ' + E.Message;
        DoLog(AErrorMessage);
      end;
    end;
  finally
    RequestStream.Free;
  end;
end;
function TShopeeOpenAPIClient.DownloadInvoiceDoc(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; out APdfBytes: TBytes;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/download_invoice_doc';
var
  QueryExtra: string;
  Timestamp: Int64;
  Sign, URL: string;
  Response: IHTTPResponse;
begin
  // Assim como o de etiqueta, devolve o PDF binario direto - GET simples
  // (nao precisa de corpo), mas ainda assim nao passa pelo ExecuteGet
  // compartilhado (que so trata resposta texto).
  Result := False;
  AErrorMessage := '';
  SetLength(APdfBytes, 0);
  QueryExtra := 'order_sn=' + TNetEncoding.URL.Encode(AOrderSN);
  Timestamp := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now));
  Sign := ComputeSign(API_PATH, Timestamp, AAccessToken, AShopID);
  URL := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&access_token=' + AAccessToken +
    '&shop_id=' + IntToStr(AShopID) +
    '&sign=' + Sign +
    '&' + QueryExtra;
  try
    Response := FHTTPClient.Get(URL);
    if Response.StatusCode >= 400 then
    begin
      AErrorMessage := FormatarErroHTTP(Response.StatusCode,
        Response.ContentAsString(TEncoding.UTF8), 'baixar nota fiscal');
      DoLog(AErrorMessage);
      Exit;
    end;
    if (Response.ContentStream.Size > 0) and (Response.ContentAsString(TEncoding.UTF8).StartsWith('{')) then
    begin
      AErrorMessage := 'A Shopee devolveu um erro em vez do PDF: ' +
        Response.ContentAsString(TEncoding.UTF8);
      DoLog(AErrorMessage);
      Exit;
    end;
    Response.ContentStream.Position := 0;
    SetLength(APdfBytes, Response.ContentStream.Size);
    Response.ContentStream.ReadBuffer(APdfBytes[0], Response.ContentStream.Size);
    Result := True;
    DoLog(Format('DownloadInvoiceDoc: %d bytes recebidos.', [Length(APdfBytes)]));
  except
    on E: Exception do
    begin
      AErrorMessage := 'Erro na requisicao de download da nota fiscal: ' + E.Message;
      DoLog(AErrorMessage);
    end;
  end;
end;
function TShopeeOpenAPIClient.UploadInvoiceDoc(const AAccessToken: string;
  AShopID: Int64; const AOrderSN: string; const APdfBytes: TBytes;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/api/v2/order/upload_invoice_doc';
var
  Timestamp: Int64;
  Sign, URL: string;
  MultipartData: TMultipartFormData;
  Response: IHTTPResponse;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  // {ATENCAO MAIOR AQUI} Esse e' o metodo com menos certeza de formato -
  // upload de arquivo na Shopee normalmente e' multipart/form-data (mesmo
  // padrao do upload de imagem de produto que ja funciona nessa unit), mas
  // NAO TESTAMOS AINDA contra o endpoint real de nota fiscal. Se der erro
  // de parametro/formato, o log abaixo mostra a resposta bruta da Shopee -
  // me manda que ajustamos junto.
  Result := False;
  AErrorMessage := '';
  Timestamp := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now));
  Sign := ComputeSign(API_PATH, Timestamp, AAccessToken, AShopID);
  URL := BaseURL + API_PATH +
    '?partner_id=' + IntToStr(FPartnerID) +
    '&timestamp=' + IntToStr(Timestamp) +
    '&access_token=' + AAccessToken +
    '&shop_id=' + IntToStr(AShopID) +
    '&sign=' + Sign;
  MultipartData := TMultipartFormData.Create;
  try
    MultipartData.AddField('order_sn', AOrderSN);
    MultipartData.AddStream('invoice', TBytesStream.Create(APdfBytes),
      'nota_fiscal_' + AOrderSN + '.pdf', 'application/pdf');
    DoLog('UploadInvoiceDoc: enviando ' + IntToStr(Length(APdfBytes)) +
      ' bytes para o pedido ' + AOrderSN);
    Response := FHTTPClient.Post(URL, MultipartData);
    ResponseStr := Response.ContentAsString(TEncoding.UTF8);
    if Trim(ResponseStr).StartsWith('<') then
      DoLog('UploadInvoiceDoc resposta: Shopee indisponivel/em manutencao (pagina HTML recebida).')
    else
      DoLog('UploadInvoiceDoc resposta: ' + ResponseStr);
    if Response.StatusCode >= 400 then
    begin
      AErrorMessage := FormatarErroHTTP(Response.StatusCode, ResponseStr, 'enviar nota fiscal');
      Exit;
    end;
    JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
    try
      if JSONValue is TJSONObject then
      begin
        JSONObj := TJSONObject(JSONValue);
        if Assigned(JSONObj.GetValue('error')) and (JSONObj.GetValue<string>('error') <> '') then
        begin
          AErrorMessage := JSONObj.GetValue<string>('error');
          if Assigned(JSONObj.GetValue('message')) then
            AErrorMessage := AErrorMessage + ': ' + JSONObj.GetValue<string>('message');
          Exit;
        end;
      end;
      Result := True;
    finally
      JSONValue.Free;
    end;
  finally
    MultipartData.Free;
  end;
end;
end.
