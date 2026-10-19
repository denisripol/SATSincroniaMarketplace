// ============================================================================
// UNIT: Magalu.OpenAPI.Client
// OBJETIVO: Cliente standalone para autenticação OAuth 2.0 e chamadas
//           básicas às APIs do Magalu Marketplace.
// REQUISITOS: Delphi 12.3+, System.Net.HttpClient, System.NetEncoding
// ============================================================================
//
// CONCEITOS IMPORTANTES:
//   - Client ID / Client Secret: gerados via IDM CLI (idm client create),
//     identificam SUA aplicação, não mudam por vendedor (seller).
//   - Diferente da Amazon/Shopee, o fluxo do Magalu é OAuth 2.0 "clássico"
//     (Authorization Code), sem assinatura HMAC e sem PKCE.
//   - Access Token / Refresh Token: um par por seller autorizado. O Access
//     Token expira (geralmente em 7200s = 2h). O Refresh Token dura até
//     6 meses, mas SÓ PODE SER USADO UMA VEZ - cada renovação gera um novo
//     refresh_token que precisa substituir o anterior no seu armazenamento.
//   - Tenant ID: identifica QUAL conta/visão de dados está sendo acessada
//     (um mesmo login pode ter mais de um tenant - ex: comprador vs seller).
//     É necessário em praticamente toda chamada de dados via header
//     "x-tenant-id".
//
// FLUXO DE USO:
//   1. BuildAuthorizationURL -> abre no navegador do seller
//   2. Seller loga/autoriza, é redirecionado pra sua Redirect URI com os
//      parâmetros "code" e "state" na query string
//   3. ExchangeCodeForTokens(code) -> retorna RefreshToken (guardar) e
//      AccessToken (usar imediatamente)
//   4. Quando o AccessToken expirar: RefreshAccessToken(refreshTokenAtual)
//      -> IMPORTANTE: guarde o NOVO refresh_token retornado, o antigo é
//      invalidado após o uso
//
// ATENÇÃO - ENDPOINTS DE DADOS:
//   GetOrders, GetSkuInfo, UpdatePrice e UpdateStock foram corrigidos com
//   base na documentação oficial atual (developers.magalu.com/docs/apis) -
//   confirmamos path E metodo HTTP certos (os endpoints de
//   Estoque/Preco usam PATCH, nao PUT, e o SKU vai na URL, nao no corpo).
//   AINDA ASSIM nao foram testados contra trafego real (formato exato do
//   corpo da resposta/requisicao pode ter detalhes que so aparecem na
//   pratica) - assim que tivermos o primeiro vendedor autorizado,
//   validamos de ponta a ponta. GetSellerTenantId continua com o path
//   antigo (/account/v1/whoami/tenants), baseado num tutorial mais
//   antigo (ambiente alpha) - esse ja foi validado e funciona.
// ============================================================================

unit Magalu.OpenAPI.Client;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.NetEncoding,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient,
  System.DateUtils;

type
  TMagaluTokenInfo = record
    Success: Boolean;
    AccessToken: string;
    RefreshToken: string;
    Scope: string;
    ExpiresIn: Integer;      // segundos até expirar o AccessToken
    ObtainedAt: TDateTime;
    ErrorMessage: string;
    RawResponse: string;
  end;

  TMagaluLogEvent = procedure(const AMessage: string) of object;

  TMagaluOrder = record
    IdOrder: string;
    Status: string;
    OrderDate: string;
    TotalAmount: string;
  end;

  TMagaluOrderArray = TArray<TMagaluOrder>;

  // {ATENCAO} Estrutura NAO confirmada - item dentro de uma entrega
  // (confirmado que items[].info.sku e items[].quantity existem, pelo
  // exemplo real do sandbox de CRIACAO de pedido - o resto (descricao,
  // preco) e' estimativa, ja que a resposta de CONSULTA nunca foi vista
  // de verdade).
  TMagaluDeliveryItem = record
    Sku: string;
    Quantity: Double;
    Description: string;
    Price: Double;
  end;
  TMagaluDeliveryItemArray = TArray<TMagaluDeliveryItem>;

  // {ATENCAO} Estrutura NAO confirmada contra API real ainda - o Magalu
  // trata "pedido" (order) e "entrega" (delivery) como recursos
  // separados, e o Despachar usa o ID da ENTREGA, nao do pedido. A
  // resposta de GET /seller/v1/deliveries pode vir num wrapper diferente
  // do que assumimos aqui (ver GetDeliveries) - so' vamos confirmar com
  // uma conta de vendedor real.
  TMagaluDelivery = record
    Id: string;
    OrderId: string;
    Status: string;
    Items: TMagaluDeliveryItemArray;
  end;
  TMagaluDeliveryArray = TArray<TMagaluDelivery>;

  // {ATENCAO} Estrutura 100% ESTIMATIVA - montada por analogia com o
  // de-para proposto (planilha enviada ao cliente em 22/08, nunca
  // respondida pra Magalu) e o exemplo de sandbox de CRIACAO de pedido.
  // NENHUM campo aqui foi confirmado contra uma resposta real de GET de
  // pedido - so' vamos saber se bate quando tivermos uma loja Magalu
  // aprovada pra testar.
  TMagaluOrderDetail = record
    IdOrder: string;
    Status: string;
    OrderDate: TDateTime;
    TotalAmount: Double;
    BuyerName: string;
    BuyerDocument: string; // CPF/CNPJ
    BuyerEmail: string;
    BuyerPhone: string;
    ShippingStreet: string;
    ShippingNumber: string;
    ShippingComplement: string;
    ShippingNeighborhood: string;
    ShippingCity: string;
    ShippingState: string;
    ShippingZipCode: string;
    PaymentMethod: string;
    RawJSON: string;
  end;

  // {ATENCAO} Campos NAO confirmados contra a API real - o GetSkuInfo
  // (unitario) sempre devolveu JSON cru sem parsing nenhum, entao nunca
  // tivemos confirmacao dos nomes de campo de um SKU. Usa os mesmos nomes
  // ja "chutados" em UpdatePrice/UpdateStock (listPrice/salePrice/quantity)
  // por consistencia, com fallbacks pros nomes mais genericos tambem.
  TMagaluOffer = record
    Sku: string;
    Description: string;
    Price: Double;
    Stock: Integer;
    Status: string;
    // Data da ultima alteracao do SKU, em hora local. 0 = nao veio.
    // {NAO CONFIRMADO} nome do campo ainda nao visto numa resposta real.
    LastUpdated: TDateTime;
  end;
  TMagaluOfferArray = TArray<TMagaluOffer>;

  TMagaluOpenAPIClient = class
  private
    FClientID: string;
    FClientSecret: string;
    FRedirectURI: string;
    FScopes: string;
    FSandbox: Boolean;
    FHTTPClient: TNetHTTPClient;
    FOnLog: TMagaluLogEvent;

    procedure DoLog(const AMessage: string);
    function BaseURL: string;
    function ExecuteTokenRequest(const ABodyJSON: string): TMagaluTokenInfo;
    function ExecuteGet(const AApiPath, ATenantID, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePut(const AApiPath, ABodyJSON, ATenantID, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePatch(const AApiPath, ABodyJSON, ATenantID, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePost(const AApiPath, ABodyJSON, ATenantID, AAccessToken: string;
      out AStatusCode: Integer): string;
  public
    constructor Create(const AClientID, AClientSecret, ARedirectURI, AScopes: string;
      ASandbox: Boolean = False);
    destructor Destroy; override;

    // Monta a URL de consentimento pra abrir no navegador do seller.
    // AState deve ser um valor aleatório único (ex: GUID) gerado por você,
    // guardado temporariamente, e conferido quando o redirect voltar.
    function BuildAuthorizationURL(const AState: string): string;

    // Troca o código de autorização (recebido no redirect) pelos tokens.
    function ExchangeCodeForTokens(const ACode: string): TMagaluTokenInfo;

    // Gera um novo Access Token a partir de um Refresh Token já guardado.
    // ATENÇÃO: o refresh_token retornado aqui é NOVO - substitua o antigo.
    function RefreshAccessToken(const ARefreshToken: string): TMagaluTokenInfo;

    // Obtém o Tenant ID do tipo "seller" associado ao token (necessário em
    // toda chamada de dados via header x-tenant-id). ENDPOINT A CONFIRMAR.
    function GetSellerTenantId(const AAccessToken: string;
      out ATenantID, AErrorMessage: string): Boolean;

    // --- Pedidos (endpoint a confirmar - ver nota no topo do arquivo) ---
    function GetOrders(const AAccessToken, ATenantID: string;
      out AOrders: TMagaluOrderArray; out AErrorMessage: string): Boolean;

    // Detalhe completo de UM pedido - usado pela baixa no SAT
    // (uBaixaPedidoSAT). {ATENCAO} path e TODOS os campos sao estimativa
    // - ver comentarios na implementacao e no tipo TMagaluOrderDetail.
    function GetOrderDetail(const AAccessToken, ATenantID, AOrderId: string;
      out ADetalhe: TMagaluOrderDetail; out AErrorMessage: string): Boolean;

    // --- Entregas (Deliveries) - CONFIRMADO na doc oficial que o path
    // de despacho existe (/seller/v1/deliveries/:id/shippings), mas NAO
    // temos confirmacao do formato de resposta do GET nem do corpo
    // exigido pelo POST de despacho - ver comentarios em cada metodo.

    // Busca as entregas de um pedido - {ATENCAO} nome do parametro de
    // filtro (aqui um chute: "order_id") e o formato da resposta (aqui um
    // chute: array na raiz OU dentro de "results"/"data"/"deliveries")
    // NAO confirmados contra a API real.
    function GetDeliveries(const AAccessToken, ATenantID, AOrderId: string;
      out ADeliveries: TMagaluDeliveryArray; out AErrorMessage: string): Boolean;

    // "Despachar" - marca uma entrega como enviada. Path CONFIRMADO
    // (POST /seller/v1/deliveries/:id/shippings, doc oficial: "Marcar
    // entrega enviada"). {ATENCAO} corpo da requisicao NAO documentado -
    // manda vazio por padrao; se ATrackingNumber for informado, tenta
    // incluir num campo chutado "tracking_code" (revisar se der erro).
    function MarkDeliveryShipped(const AAccessToken, ATenantID, ADeliveryId,
      ATrackingNumber: string; out AErrorMessage: string): Boolean;

    // --- Ofertas / Portfolio (endpoint a confirmar) ---
    function GetSkuInfo(const AAccessToken, ATenantID, ASku: string;
      out AResponseJSON: string; out AErrorMessage: string): Boolean;

    // Lista todos os SKUs do vendedor (F3 - Receber Ofertas). Path
    // CONFIRMADO na doc oficial (release notes: "Consulta de SKUs de
    // forma individual ou em lista" + mesmo padrao do GetSkuInfo, so' sem
    // o SKU no final). {ATENCAO} nomes de campo da resposta NAO
    // confirmados - ver comentarios no TMagaluOffer e na implementacao.
    function GetSkus(const AAccessToken, ATenantID: string;
      out AOffers: TMagaluOfferArray; out AErrorMessage: string): Boolean;

    function UpdatePrice(const AAccessToken, ATenantID, ASku: string;
      ANovoPreco: Double; out AErrorMessage: string): Boolean;

    function UpdateStock(const AAccessToken, ATenantID, ASku: string;
      ANovoEstoque: Integer; out AErrorMessage: string): Boolean;

    property OnLog: TMagaluLogEvent read FOnLog write FOnLog;
  end;

function NovoState: string;

implementation

function NovoState: string;
begin
  Result := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
end;

{ TMagaluOpenAPIClient }

constructor TMagaluOpenAPIClient.Create(const AClientID, AClientSecret,
  ARedirectURI, AScopes: string; ASandbox: Boolean);
begin
  inherited Create;
  FClientID := AClientID;
  FClientSecret := AClientSecret;
  FRedirectURI := ARedirectURI;
  FScopes := AScopes;
  FSandbox := ASandbox;

  FHTTPClient := TNetHTTPClient.Create(nil);
  FHTTPClient.ConnectionTimeout := 30000;
  FHTTPClient.ResponseTimeout := 30000;
end;

destructor TMagaluOpenAPIClient.Destroy;
begin
  FHTTPClient.Free;
  inherited;
end;

procedure TMagaluOpenAPIClient.DoLog(const AMessage: string);
begin
  if Assigned(FOnLog) then
    FOnLog(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' | ' + AMessage);
end;

function TMagaluOpenAPIClient.BaseURL: string;
begin
  // O audience de sandbox (api-sandbox.magalu.com) precisa estar habilitado
  // no client via "idm client update --audience" para funcionar - ver nota
  // no topo do arquivo sobre incerteza dos paths de dados.
  if FSandbox then
    Result := 'https://api-sandbox.magalu.com'
  else
    Result := 'https://api.magalu.com';
end;

function TMagaluOpenAPIClient.BuildAuthorizationURL(const AState: string): string;
begin
  Result := 'https://id.magalu.com/login' +
    '?client_id=' + TNetEncoding.URL.Encode(FClientID) +
    '&redirect_uri=' + TNetEncoding.URL.Encode(FRedirectURI) +
    '&scope=' + TNetEncoding.URL.Encode(FScopes) +
    '&response_type=code' +
    '&choose_tenants=true' +
    '&state=' + TNetEncoding.URL.Encode(AState);

  DoLog('URL de autorização gerada: ' + Result);
end;

function TMagaluOpenAPIClient.ExecuteTokenRequest(const ABodyJSON: string): TMagaluTokenInfo;
var
  Response: IHTTPResponse;
  RequestStream: TStringStream;
  Headers: TNetHeaders;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONObj: TJSONObject;
begin
  Result.Success := False;
  Result.ObtainedAt := Now;

  RequestStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    Headers := [TNameValuePair.Create('Content-Type', 'application/json')];
    try
      Response := FHTTPClient.Post('https://id.magalu.com/oauth/token',
        RequestStream, nil, Headers);
      ResponseStr := Response.ContentAsString(TEncoding.UTF8);
      Result.RawResponse := ResponseStr;

      if Response.StatusCode >= 400 then
      begin
        Result.ErrorMessage := Format('HTTP %d: %s', [Response.StatusCode, ResponseStr]);
        DoLog('Erro ao obter/renovar token: ' + Result.ErrorMessage);
        Exit;
      end;

      JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
      try
        if not (JSONValue is TJSONObject) then
        begin
          Result.ErrorMessage := 'Resposta inesperada (não é JSON)';
          Exit;
        end;

        JSONObj := TJSONObject(JSONValue);
        if Assigned(JSONObj.GetValue('access_token')) then
          Result.AccessToken := JSONObj.GetValue<string>('access_token');
        if Assigned(JSONObj.GetValue('refresh_token')) then
          Result.RefreshToken := JSONObj.GetValue<string>('refresh_token');
        if Assigned(JSONObj.GetValue('scope')) then
          Result.Scope := JSONObj.GetValue<string>('scope');
        if Assigned(JSONObj.GetValue('expires_in')) then
          Result.ExpiresIn := JSONObj.GetValue<Integer>('expires_in');

        if Result.AccessToken = '' then
        begin
          Result.ErrorMessage := 'access_token não veio na resposta: ' + ResponseStr;
          DoLog(Result.ErrorMessage);
          Exit;
        end;

        Result.Success := True;
        DoLog('Token obtido com sucesso (expira em ' + Result.ExpiresIn.ToString +
          's, escopos: ' + Result.Scope + ')');
      finally
        JSONValue.Free;
      end;
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

function TMagaluOpenAPIClient.ExchangeCodeForTokens(const ACode: string): TMagaluTokenInfo;
var
  BodyJSON: TJSONObject;
begin
  DoLog('Trocando código de autorização por tokens...');

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('client_id', FClientID);
    BodyJSON.AddPair('client_secret', FClientSecret);
    BodyJSON.AddPair('redirect_uri', FRedirectURI);
    BodyJSON.AddPair('code', ACode);
    BodyJSON.AddPair('grant_type', 'authorization_code');

    Result := ExecuteTokenRequest(BodyJSON.ToJSON);
  finally
    BodyJSON.Free;
  end;
end;

function TMagaluOpenAPIClient.RefreshAccessToken(const ARefreshToken: string): TMagaluTokenInfo;
var
  BodyJSON: TJSONObject;
begin
  DoLog('Renovando access token a partir do refresh token...');

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('client_id', FClientID);
    BodyJSON.AddPair('client_secret', FClientSecret);
    BodyJSON.AddPair('refresh_token', ARefreshToken);
    BodyJSON.AddPair('grant_type', 'refresh_token');

    Result := ExecuteTokenRequest(BodyJSON.ToJSON);

    // ATENÇÃO: se este método falhar com erro 400/415 (formato não aceito),
    // a documentação mais antiga do Magalu (Acelera) mostra esse mesmo
    // endpoint recebendo application/x-www-form-urlencoded em vez de JSON
    // para o refresh especificamente. Se acontecer, é só avisar que ajusto
    // este método pra usar form-urlencoded em vez de JSON aqui.
  finally
    BodyJSON.Free;
  end;
end;

function TMagaluOpenAPIClient.ExecuteGet(const AApiPath, ATenantID,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  Headers: TNetHeaders;
begin
  try
    Headers := [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken),
                TNetHeader.Create('Content-Type', 'application/json')];

    // So inclui o header x-tenant-id se tiver valor - um header com valor
    // vazio faz o TNetHTTPClient (WinINet) estourar ENetHTTPRequestException
    // "Error adding header: (12150)".
    if ATenantID <> '' then
      Headers := Headers + [TNetHeader.Create('x-tenant-id', ATenantID)];

    // {NOVO} Loga a URL completa (sem o token) ANTES de disparar a
    // chamada - facilita muito diagnosticar confusao sandbox x producao,
    // ja que antes so aparecia o path relativo.
    DoLog('GET ' + BaseURL + AApiPath + ' (tenant: ' + ATenantID + ', sandbox: ' +
      BoolToStr(FSandbox, True) + ')');

    Response := FHTTPClient.Get(BaseURL + AApiPath, nil, Headers);
    AStatusCode := Response.StatusCode;
    Result := Response.ContentAsString(TEncoding.UTF8);
  except
    on E: Exception do
    begin
      AStatusCode := 0;
      Result := '';
      DoLog('Erro na chamada GET ' + AApiPath + ': ' + E.Message);
    end;
  end;
end;

function TMagaluOpenAPIClient.ExecutePut(const AApiPath, ABodyJSON, ATenantID,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  BodyStream: TStringStream;
  Headers: TNetHeaders;
begin
  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Headers := [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken),
                  TNetHeader.Create('Content-Type', 'application/json')];

      if ATenantID <> '' then
        Headers := Headers + [TNetHeader.Create('x-tenant-id', ATenantID)];

      DoLog('PUT ' + BaseURL + AApiPath + ' (tenant: ' + ATenantID + ', sandbox: ' +
        BoolToStr(FSandbox, True) + ')');

      Response := FHTTPClient.Put(BaseURL + AApiPath, BodyStream, nil, Headers);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
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

function TMagaluOpenAPIClient.ExecutePatch(const AApiPath, ABodyJSON, ATenantID,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  BodyStream: TStringStream;
  Headers: TNetHeaders;
begin
  // {NOVO} Os endpoints reais de Estoque/Preco do Magalu usam PATCH, nao
  // PUT (confirmado na documentacao oficial - developers.magalu.com) - o
  // TNetHTTPClient.Put que a gente usava batia num 404/405 mesmo com o
  // path certo.
  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Headers := [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken),
                  TNetHeader.Create('Content-Type', 'application/json')];

      if ATenantID <> '' then
        Headers := Headers + [TNetHeader.Create('x-tenant-id', ATenantID)];

      DoLog('PATCH ' + BaseURL + AApiPath + ' (tenant: ' + ATenantID + ', sandbox: ' +
        BoolToStr(FSandbox, True) + ')');

      Response := FHTTPClient.Patch(BaseURL + AApiPath, BodyStream, nil, Headers);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
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

function TMagaluOpenAPIClient.ExecutePost(const AApiPath, ABodyJSON, ATenantID,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  BodyStream: TStringStream;
  Headers: TNetHeaders;
begin
  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Headers := [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken),
                  TNetHeader.Create('Content-Type', 'application/json')];

      if ATenantID <> '' then
        Headers := Headers + [TNetHeader.Create('x-tenant-id', ATenantID)];

      DoLog('POST ' + BaseURL + AApiPath + ' (tenant: ' + ATenantID + ', sandbox: ' +
        BoolToStr(FSandbox, True) + ')');

      Response := FHTTPClient.Post(BaseURL + AApiPath, BodyStream, nil, Headers);
      AStatusCode := Response.StatusCode;
      Result := Response.ContentAsString(TEncoding.UTF8);
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

function TMagaluOpenAPIClient.GetSellerTenantId(const AAccessToken: string;
  out ATenantID, AErrorMessage: string): Boolean;
const
  // ENDPOINT A CONFIRMAR: baseado em um tutorial oficial mais antigo
  // (ambiente alpha), que usava GET .../account/v1/whoami/tenants e
  // filtrava pelo tenant cujo tipo/nome contém "SELLER".
  API_PATH = '/account/v1/whoami/tenants';
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONArr: TJSONArray;
  Item: TJSONObject;
  I: Integer;
  TenantType, TenantId: string;
begin
  Result := False;
  AErrorMessage := '';
  ATenantID := '';

  ResponseStr := ExecuteGet(API_PATH, '', AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not (JSONValue is TJSONArray) then
    begin
      AErrorMessage := 'Formato de resposta não reconhecido: ' + ResponseStr;
      DoLog(AErrorMessage);
      Exit;
    end;

    JSONArr := TJSONArray(JSONValue);
    for I := 0 to JSONArr.Count - 1 do
    begin
      Item := JSONArr.Items[I] as TJSONObject;
      TenantType := '';
      TenantId := '';
      Item.TryGetValue<string>('type', TenantType);
      if not Item.TryGetValue<string>('id', TenantId) then
        Item.TryGetValue<string>('uuid', TenantId);

      if Pos('SELLER', UpperCase(TenantType)) > 0 then
      begin
        ATenantID := TenantId;
        Break;
      end;
    end;

    if ATenantID = '' then
    begin
      AErrorMessage := 'Nenhum tenant do tipo SELLER encontrado na resposta: ' + ResponseStr;
      DoLog(AErrorMessage);
      Exit;
    end;

    Result := True;
    DoLog('Tenant ID (seller) obtido: ' + ATenantID);
  finally
    JSONValue.Free;
  end;
end;

function TMagaluOpenAPIClient.GetOrders(const AAccessToken, ATenantID: string;
  out AOrders: TMagaluOrderArray; out AErrorMessage: string): Boolean;
const
  // {FIX} CONFIRMADO na documentacao oficial (developers.magalu.com/docs/
  // apis/orders/ref/seller-v-1-get-order-list): faltava o prefixo
  // "/seller" - o path antigo "/v1/orders" devolvia HTTP 404
  // "resource_not_found".
  API_PATH = '/seller/v1/orders';
var
  StatusCode: Integer;
  ResponseStr: string;
  JSONValue: TJSONValue;
  JSONArr: TJSONArray;
  JSONObj, Item: TJSONObject;
  I: Integer;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AOrders, 0);

  ResponseStr := ExecuteGet(API_PATH, ATenantID, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    // A resposta pode vir como array direto ou como objeto com uma
    // propriedade de lista (ex.: "results"/"items") - tentamos os dois.
    if JSONValue is TJSONArray then
      JSONArr := TJSONArray(JSONValue)
    else if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if not JSONObj.TryGetValue<TJSONArray>('results', JSONArr) then
        if not JSONObj.TryGetValue<TJSONArray>('items', JSONArr) then
        begin
          AErrorMessage := 'Formato de resposta não reconhecido: ' + ResponseStr;
          DoLog(AErrorMessage);
          Exit;
        end;
    end
    else
    begin
      AErrorMessage := 'Resposta não é um JSON válido';
      Exit;
    end;

    SetLength(AOrders, JSONArr.Count);
    for I := 0 to JSONArr.Count - 1 do
    begin
      Item := JSONArr.Items[I] as TJSONObject;

      if not Item.TryGetValue<string>('id', AOrders[I].IdOrder) then
        Item.TryGetValue<string>('orderId', AOrders[I].IdOrder);

      Item.TryGetValue<string>('status', AOrders[I].Status);

      if not Item.TryGetValue<string>('orderDate', AOrders[I].OrderDate) then
        Item.TryGetValue<string>('createdAt', AOrders[I].OrderDate);

      Item.TryGetValue<string>('total', AOrders[I].TotalAmount);
    end;

    Result := True;
    DoLog(Format('%d pedido(s) encontrado(s).', [Length(AOrders)]));
  finally
    JSONValue.Free;
  end;
end;

function TMagaluOpenAPIClient.GetDeliveries(const AAccessToken, ATenantID, AOrderId: string;
  out ADeliveries: TMagaluDeliveryArray; out AErrorMessage: string): Boolean;
const
  API_PATH = '/seller/v1/deliveries';
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj, Item, ItemObj, InfoObj: TJSONObject;
  JSONArr, ItemsArr: TJSONArray;
  I, J: Integer;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(ADeliveries, 0);

  // {ATENCAO} nome do parametro de filtro ("order_id") e' um chute -
  // baseado na convencao mais comum de REST, nao confirmado na doc.
  ResponseStr := ExecuteGet(API_PATH + '?order_id=' + TNetEncoding.URL.Encode(AOrderId),
    ATenantID, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    // {ATENCAO} formato de resposta chutado - tenta as 3 formas mais
    // comuns: array na raiz, ou envelopado em "results"/"data".
    JSONArr := nil;
    if JSONValue is TJSONArray then
      JSONArr := TJSONArray(JSONValue)
    else if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if not JSONObj.TryGetValue<TJSONArray>('results', JSONArr) then
        if not JSONObj.TryGetValue<TJSONArray>('data', JSONArr) then
          JSONObj.TryGetValue<TJSONArray>('deliveries', JSONArr);
    end;

    if not Assigned(JSONArr) then
    begin
      AErrorMessage := 'Nao foi possivel identificar o array de entregas na resposta - ' +
        'formato inesperado (ver log da resposta crua acima).';
      DoLog(AErrorMessage);
      Exit;
    end;

    SetLength(ADeliveries, JSONArr.Count);
    for I := 0 to JSONArr.Count - 1 do
    begin
      Item := JSONArr.Items[I] as TJSONObject;
      Item.TryGetValue<string>('id', ADeliveries[I].Id);
      if not Item.TryGetValue<string>('order_id', ADeliveries[I].OrderId) then
        Item.TryGetValue<string>('orderId', ADeliveries[I].OrderId);
      Item.TryGetValue<string>('status', ADeliveries[I].Status);

      // {CONFIRMADO parcialmente} items[].info.sku e items[].quantity
      // batem com o exemplo real do sandbox de CRIACAO de pedido
      // (POST /v1/samples/orders) - o resto (descricao/preco) e' chute.
      if Item.TryGetValue<TJSONArray>('items', ItemsArr) then
      begin
        SetLength(ADeliveries[I].Items, ItemsArr.Count);
        for J := 0 to ItemsArr.Count - 1 do
        begin
          ItemObj := ItemsArr.Items[J] as TJSONObject;
          if ItemObj.TryGetValue<TJSONObject>('info', InfoObj) then
          begin
            InfoObj.TryGetValue<string>('sku', ADeliveries[I].Items[J].Sku);
            if not InfoObj.TryGetValue<string>('description', ADeliveries[I].Items[J].Description) then
              InfoObj.TryGetValue<string>('name', ADeliveries[I].Items[J].Description);
          end;
          ItemObj.TryGetValue<Double>('quantity', ADeliveries[I].Items[J].Quantity);
          ItemObj.TryGetValue<Double>('price', ADeliveries[I].Items[J].Price);
        end;
      end;
    end;

    Result := True;
    DoLog(Format('%d entrega(s) encontrada(s) para o pedido %s.', [Length(ADeliveries), AOrderId]));
  finally
    JSONValue.Free;
  end;
end;

function TMagaluOpenAPIClient.GetOrderDetail(const AAccessToken, ATenantID, AOrderId: string;
  out ADetalhe: TMagaluOrderDetail; out AErrorMessage: string): Boolean;
const
  // {ATENCAO} path NAO confirmado - segue o mesmo padrao ja confirmado
  // pra SKU (plural pra listar, singular+id pra consultar 1) e Entregas
  // (plural /deliveries, singular+id pra Despachar) - por analogia,
  // GET /seller/v1/orders/{id} deveria devolver 1 pedido. Nunca testado.
  API_PATH_BASE = '/seller/v1/orders/';
var
  ApiPath, ResponseStr, DataStr: string;
  StatusCode: Integer;
  JSONRoot, BuyerObj, AddressObj, PaymentObj: TJSONObject;
  PaymentsArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  ADetalhe.IdOrder := AOrderId;

  ApiPath := API_PATH_BASE + TNetEncoding.URL.Encode(AOrderId);
  ADetalhe.RawJSON := ExecuteGet(ApiPath, ATenantID, AAccessToken, StatusCode);

  DoLog('GetOrderDetail (' + AOrderId + '): ' + ADetalhe.RawJSON);

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

    JSONRoot.TryGetValue<string>('status', ADetalhe.Status);
    // {ATENCAO} nome do campo de data (orderDate/createdAt) e' o mesmo
    // chute duplo ja usado no GetOrders - parse defensivo (se o formato
    // real nao for ISO8601, cai em 0 em vez de estourar excecao).
    if not JSONRoot.TryGetValue<string>('orderDate', DataStr) then
      JSONRoot.TryGetValue<string>('createdAt', DataStr);
    if DataStr <> '' then
    begin
      try
        ADetalhe.OrderDate := ISO8601ToDate(DataStr, False);
      except
        ADetalhe.OrderDate := 0;
      end;
    end;
    // {ATENCAO} campos abaixo sao 100% estimativa - nunca confirmados.
    if not JSONRoot.TryGetValue<Double>('total', ADetalhe.TotalAmount) then
      JSONRoot.TryGetValue<Double>('amount', ADetalhe.TotalAmount);

    if JSONRoot.TryGetValue<TJSONObject>('buyer', BuyerObj) then
    begin
      BuyerObj.TryGetValue<string>('name', ADetalhe.BuyerName);
      BuyerObj.TryGetValue<string>('document', ADetalhe.BuyerDocument);
      BuyerObj.TryGetValue<string>('email', ADetalhe.BuyerEmail);
      BuyerObj.TryGetValue<string>('phone', ADetalhe.BuyerPhone);
    end;

    if JSONRoot.TryGetValue<TJSONObject>('shippingAddress', AddressObj) then
    begin
      AddressObj.TryGetValue<string>('street', ADetalhe.ShippingStreet);
      AddressObj.TryGetValue<string>('number', ADetalhe.ShippingNumber);
      AddressObj.TryGetValue<string>('complement', ADetalhe.ShippingComplement);
      AddressObj.TryGetValue<string>('neighborhood', ADetalhe.ShippingNeighborhood);
      AddressObj.TryGetValue<string>('city', ADetalhe.ShippingCity);
      AddressObj.TryGetValue<string>('state', ADetalhe.ShippingState);
      AddressObj.TryGetValue<string>('zipCode', ADetalhe.ShippingZipCode);
    end;

    // payments[].method e' confirmado no exemplo de sandbox de criacao
    // de pedido - assume que a CONSULTA devolve no mesmo formato.
    if JSONRoot.TryGetValue<TJSONArray>('payments', PaymentsArr) and (PaymentsArr.Count > 0) then
    begin
      PaymentObj := PaymentsArr.Items[0] as TJSONObject;
      PaymentObj.TryGetValue<string>('method', ADetalhe.PaymentMethod);
    end;

    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TMagaluOpenAPIClient.MarkDeliveryShipped(const AAccessToken, ATenantID, ADeliveryId,
  ATrackingNumber: string; out AErrorMessage: string): Boolean;
var
  ApiPath, ResponseStr, BodyStr: string;
  StatusCode: Integer;
  BodyJSON: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';

  ApiPath := '/seller/v1/deliveries/' + TNetEncoding.URL.Encode(ADeliveryId) + '/shippings';

  if ATrackingNumber <> '' then
  begin
    // {ATENCAO} campo "tracking_code" e' um chute - a doc oficial nao
    // mostra o corpo dessa chamada. Se der erro 400/422, comece revisando
    // esse nome de campo primeiro.
    BodyJSON := TJSONObject.Create;
    try
      BodyJSON.AddPair('tracking_code', ATrackingNumber);
      BodyStr := BodyJSON.ToJSON;
    finally
      BodyJSON.Free;
    end;
  end
  else
    BodyStr := '{}';

  ResponseStr := ExecutePost(ApiPath, BodyStr, ATenantID, AAccessToken, StatusCode);

  // Doc oficial mostra 201 como resposta de sucesso.
  if (StatusCode <> 200) and (StatusCode <> 201) and (StatusCode <> 204) then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('Entrega ' + ADeliveryId + ' marcada como enviada com sucesso.');
end;

function TMagaluOpenAPIClient.GetSkuInfo(const AAccessToken, ATenantID, ASku: string;
  out AResponseJSON: string; out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  // {FIX} CONFIRMADO na documentacao oficial (developers.magalu.com/docs/
  // apis/products/ref/portfolios-v-1-get-skus): e' "/seller/v1/portfolios/
  // skus/{sku}" (com "portfolios" no plural), nao "/v1/portfolio/skus/{sku}".
  ApiPath := '/seller/v1/portfolios/skus/' + TNetEncoding.URL.Encode(ASku);

  AResponseJSON := ExecuteGet(ApiPath, ATenantID, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, AResponseJSON]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog('SKU ' + ASku + ' consultado com sucesso.');
end;

function TMagaluOpenAPIClient.GetSkus(const AAccessToken, ATenantID: string;
  out AOffers: TMagaluOfferArray; out AErrorMessage: string): Boolean;
const
  API_PATH = '/seller/v1/portfolios/skus';
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONValue: TJSONValue;
  JSONObj, Item: TJSONObject;
  JSONArr: TJSONArray;
  I: Integer;
  PriceObj: TJSONObject;
  PriceVal: Double;
  DataTxt: string;
  DataAlt: TDateTime;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AOffers, 0);

  ResponseStr := ExecuteGet(API_PATH, ATenantID, AAccessToken, StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  JSONValue := TJSONObject.ParseJSONValue(ResponseStr);
  try
    // {ATENCAO} formato do envelope chutado - mesma logica defensiva
    // usada em GetDeliveries (array na raiz, ou dentro de results/data/skus).
    JSONArr := nil;
    if JSONValue is TJSONArray then
      JSONArr := TJSONArray(JSONValue)
    else if JSONValue is TJSONObject then
    begin
      JSONObj := TJSONObject(JSONValue);
      if not JSONObj.TryGetValue<TJSONArray>('results', JSONArr) then
        if not JSONObj.TryGetValue<TJSONArray>('data', JSONArr) then
          JSONObj.TryGetValue<TJSONArray>('skus', JSONArr);
    end;

    if not Assigned(JSONArr) then
    begin
      AErrorMessage := 'Nao foi possivel identificar o array de SKUs na resposta - ' +
        'formato inesperado (ver log da resposta crua acima).';
      DoLog(AErrorMessage);
      Exit;
    end;

    SetLength(AOffers, JSONArr.Count);
    for I := 0 to JSONArr.Count - 1 do
    begin
      Item := JSONArr.Items[I] as TJSONObject;

      if not Item.TryGetValue<string>('sku', AOffers[I].Sku) then
        Item.TryGetValue<string>('id', AOffers[I].Sku);

      if not Item.TryGetValue<string>('description', AOffers[I].Description) then
        if not Item.TryGetValue<string>('name', AOffers[I].Description) then
          Item.TryGetValue<string>('title', AOffers[I].Description);

      Item.TryGetValue<string>('status', AOffers[I].Status);

      // {NAO CONFIRMADO} Ultima alteracao do SKU. Ainda nao vimos uma
      // resposta real do Magalu, entao tenta os nomes usuais (ISO 8601).
      // Se nenhum vier, a coluna fica em branco - nao e' erro.
      DataTxt := '';
      if (Item.TryGetValue<string>('updated_at', DataTxt) or
          Item.TryGetValue<string>('updatedAt', DataTxt) or
          Item.TryGetValue<string>('last_update', DataTxt)) and
         TryISO8601ToDate(DataTxt, DataAlt, False) then
        AOffers[I].LastUpdated := DataAlt;

      // Preco - tenta campo direto (salePrice/listPrice/price) ou dentro
      // de um sub-objeto "price"/"prices" (padrao comum em APIs de
      // portfolio de outros marketplaces).
      if Item.TryGetValue<Double>('salePrice', PriceVal) or
         Item.TryGetValue<Double>('listPrice', PriceVal) or
         Item.TryGetValue<Double>('price', PriceVal) then
        AOffers[I].Price := PriceVal
      else if Item.TryGetValue<TJSONObject>('price', PriceObj) then
      begin
        if not PriceObj.TryGetValue<Double>('salePrice', AOffers[I].Price) then
          PriceObj.TryGetValue<Double>('listPrice', AOffers[I].Price);
      end;

      // Estoque - tenta campo direto (quantity/stock) ou sub-objeto.
      if not Item.TryGetValue<Integer>('quantity', AOffers[I].Stock) then
        Item.TryGetValue<Integer>('stock', AOffers[I].Stock);
    end;

    Result := True;
    DoLog(Format('%d SKU(s) encontrado(s).', [Length(AOffers)]));
  finally
    JSONValue.Free;
  end;
end;

function TMagaluOpenAPIClient.UpdatePrice(const AAccessToken, ATenantID, ASku: string;
  ANovoPreco: Double; out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  BodyJSON: TJSONObject;
  ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  // {FIX} CONFIRMADO na documentacao oficial (developers.magalu.com/docs/
  // apis/products/ref/portfolios-v-1-patch-prices): e' PATCH
  // "/seller/v1/portfolios/prices/{sku}" - SKU vai na URL, nao no corpo
  // (o codigo antigo mandava PUT "/v1/portfolio/prices" com o sku dentro
  // do JSON, formato errado em 2 pontos diferentes).
  ApiPath := '/seller/v1/portfolios/prices/' + TNetEncoding.URL.Encode(ASku);

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('listPrice', TJSONNumber.Create(ANovoPreco));
    BodyJSON.AddPair('salePrice', TJSONNumber.Create(ANovoPreco));

    ResponseStr := ExecutePatch(ApiPath, BodyJSON.ToJSON, ATenantID, AAccessToken, StatusCode);
  finally
    BodyJSON.Free;
  end;

  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog(Format('Preço do SKU %s atualizado para %.2f', [ASku, ANovoPreco]));
end;

function TMagaluOpenAPIClient.UpdateStock(const AAccessToken, ATenantID, ASku: string;
  ANovoEstoque: Integer; out AErrorMessage: string): Boolean;
var
  ApiPath: string;
  BodyJSON: TJSONObject;
  ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  // {FIX} CONFIRMADO na documentacao oficial (developers.magalu.com/docs/
  // apis/products/ref/portfolios-v-1-patch-stocks): e' PATCH
  // "/seller/v1/portfolios/stocks/{sku}" - SKU vai na URL, nao no corpo
  // (mesmo erro que tinha em UpdatePrice - PUT errado + sku no lugar
  // errado). Isso e' o que vai corrigir o F2 (Enviar Dados) pra Magalu.
  ApiPath := '/seller/v1/portfolios/stocks/' + TNetEncoding.URL.Encode(ASku);

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('quantity', TJSONNumber.Create(ANovoEstoque));

    ResponseStr := ExecutePatch(ApiPath, BodyJSON.ToJSON, ATenantID, AAccessToken, StatusCode);
  finally
    BodyJSON.Free;
  end;

  if StatusCode >= 400 then
  begin
    AErrorMessage := Format('HTTP %d: %s', [StatusCode, ResponseStr]);
    DoLog(AErrorMessage);
    Exit;
  end;

  Result := True;
  DoLog(Format('Estoque do SKU %s atualizado para %d', [ASku, ANovoEstoque]));
end;

end.
