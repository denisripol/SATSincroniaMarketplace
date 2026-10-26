// ============================================================================
// UNIT: MercadoLivre.OpenAPI.Client
// OBJETIVO: Client REST para a API do Mercado Livre (Marketplace Brasil).
// Cobre OAuth (Conectar/Desconectar), Pedidos (orders/search) e Ofertas
// (items/search + multiget de detalhe).
//
// ENDPOINTS CONFIRMADOS (24/08/2026, documentacao oficial +
// confirmado num exemplo real de codigo Delphi de terceiro usando o
// mesmo endpoint de orders/search):
//   Autorizacao (tela de login):  https://auth.mercadolivre.com.br/authorization
//   Troca/Refresh de token:       https://api.mercadolibre.com/oauth/token
//   Pedidos:                      https://api.mercadolibre.com/orders/search?seller=ID
//   Detalhe de 1 pedido:          https://api.mercadolibre.com/orders/ID
//   IDs dos itens do vendedor:    https://api.mercadolibre.com/users/ID/items/search
//   Detalhe de itens (multiget):  https://api.mercadolibre.com/items?ids=ID1,ID2,...
//   Dados do usuario autenticado: https://api.mercadolibre.com/users/me
//
// {ATENCAO} Repara que o dominio de AUTORIZACAO (auth.mercadolivre.com.br)
// e' DIFERENTE do dominio das CHAMADAS DE API (api.mercadolibre.com, sem
// ".br"!) - erro comum de quem integra pela primeira vez.
//
// SANDBOX: o Mercado Livre NAO tem um ambiente de sandbox separado (URL
// diferente) como Shopee/Amazon/Magalu tem - o "teste" e' feito com um
// "usuario de teste" (conta fake criada pelo proprio Mercado Livre) mas
// batendo nos MESMOS endpoints de producao. Por isso FSandbox existe
// aqui so por consistencia de interface com os outros clients, mas NAO
// muda a URL base.
// ============================================================================
unit MercadoLivre.OpenAPI.Client;

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
  // Mesmo tipo de evento de log usado por Shopee/Amazon/Magalu:
  // "of object" (metodo de instancia), NAO TProc<string> (metodo anonimo).
  // As telas atribuem Cliente.OnLog := Log, onde Log e' um metodo do form -
  // com TProc<string> isso da E2010 Incompatible types.
  TMercadoLivreLogEvent = procedure(const AMessage: string) of object;

  TMercadoLivreTokenInfo = record
    Success: Boolean;
    AccessToken: string;
    RefreshToken: string;
    Scope: string;
    ExpiresIn: Integer;   // segundos ate expirar o AccessToken (6h = 21600, confirmado)
    UserId: string;       // seller ID - ja vem pronto na resposta do token, sem precisar de outra chamada
    ErrorMessage: string;
  end;

  TMercadoLivreOrder = record
    OrderId: string;
    Status: string;          // paid, confirmed, payment_required, cancelled etc
    DateCreated: TDateTime;
    DateLastUpdated: TDateTime;
    TotalAmount: Double;
    BuyerId: string;
    BuyerNickname: string;
    ShippingId: string;      // shipping.id - vazio em pedido sem Mercado Envios
                             // ("a combinar" com o comprador)
    ShippingStatus: string;  // NAO vem no /orders/search: o chamador preenche
                             // com GetShipmentStatus (pending, handling,
                             // ready_to_ship, shipped, delivered,
                             // not_delivered, cancelled)
  end;
  TMercadoLivreOrderArray = TArray<TMercadoLivreOrder>;

  TMercadoLivreItem = record
    ItemId: string;
    Title: string;
    Price: Double;
    AvailableQuantity: Integer;
    SoldQuantity: Integer;
    Status: string;      // active, paused, closed, under_review
    Permalink: string;   // URL publica do anuncio
    LastUpdated: TDateTime; // last_updated, em hora local. 0 = nao veio
  end;
  TMercadoLivreItemArray = TArray<TMercadoLivreItem>;


  // ========================================================================
  // Cadastro de produto NOVO (publicacao de anuncio)
  // ------------------------------------------------------------------------
  // Fluxo confirmado na documentacao oficial (26/08/2026):
  //   1. GET  /sites/{site}/domain_discovery/search?limit=N&q=...
  //          -> preditor de categoria: sugere categoria a partir do titulo
  //   2. GET  /categories/{id}/attributes
  //          -> atributos daquela categoria (variam por categoria; BRAND e
  //             MODEL sao obrigatorios pra publicar)
  //   3. GET  /users/{id}/available_listing_type/{tipo}?category_id=...
  //          -> confere se o tipo de anuncio esta disponivel pra essa conta
  //             e categoria (devolve available + cause + code)
  //   4. POST /items                      -> cria o anuncio
  //   5. POST /items/{id}/description     -> descricao (chamada SEPARADA,
  //          texto plano; NAO vai dentro do corpo do POST /items)
  //
  // Diferente da Amazon, aqui NAO e' preciso GTIN/EAN nem isencao pra
  // publicar - o vendedor publica com o proprio ID de anuncio.
  // ========================================================================

  // Sugestao do preditor de categoria.
  TMercadoLivreCategoriaSugerida = record
    DomainId: string;      // ex: "MLB-CELLPHONES"
    DomainName: string;    // ex: "Celulares"
    CategoryId: string;    // ex: "MLB1055" - e' isso que vai no category_id
    CategoryName: string;  // ex: "Celulares e Smartphones"
    // Atributos que o proprio preditor ja deduziu do texto buscado
    // (BRAND/MODEL/LINE com value_id e value_name prontos) - vem como JSON
    // cru pra tela poder aproveitar direto no payload sem re-parsear campo
    // a campo. Fica '' quando o preditor nao deduziu nada.
    AtributosPreditosJSON: string;
  end;
  TMercadoLivreCategoriaSugeridaArray = TArray<TMercadoLivreCategoriaSugerida>;

  // Um atributo de categoria (GET /categories/{id}/attributes).
  TMercadoLivreAtributo = record
    Id: string;              // ex: "BRAND"
    Nome: string;            // ex: "Marca"
    ValueType: string;       // string, number, number_unit, list, boolean...
    Obrigatorio: Boolean;    // tags.required
    PermiteVariacao: Boolean;// tags.allow_variations
    // Quando value_type = "list", os valores aceitos, no formato
    // "id|nome" (ex: "5601|BGH"). Vazio nos demais tipos.
    ValoresPermitidos: TArray<string>;
  end;
  TMercadoLivreAtributoArray = TArray<TMercadoLivreAtributo>;

  // Produto do CATALOGO do Mercado Livre - o equivalente do ASIN da Amazon:
  // um produto que JA existe no catalogo do ML, em cima do qual o vendedor
  // publica uma OFERTA (catalog_product_id + catalog_listing=true) em vez de
  // criar um anuncio do zero. Preenchido tanto pelo /products/search quanto
  // pelo /products/{id} - as duas respostas usam os mesmos nomes de campo.
  TMercadoLivreProdutoCatalogo = record
    ProductId: string;   // ex: "MLB15144995" - e' o catalog_product_id
    Nome: string;        // name - ja vem bem descritivo (marca + modelo + specs)
    Status: string;      // active / inactive - so' da' pra publicar em active
    DomainId: string;    // ex: "MLB-CELLPHONES"
    CategoryId: string;  // {ATENCAO} nem sempre vem - ver LerProdutoCatalogo
    Resumo: string;      // 3 primeiros atributos, so' pra diferenciar na lista
    PictureUrl: string;  // primeira imagem do catalogo, quando houver
  end;
  TMercadoLivreProdutoCatalogoArray = TArray<TMercadoLivreProdutoCatalogo>;

  // --- Detalhe de pedido (GET /orders/{id}) ---
  // Estrutura confirmada na documentacao oficial (developers.mercadolibre,
  // "Obtener una orden"): order_items[].item{id,title,variation_id} +
  // quantity + unit_price + currency_id; buyer{id}; payments[]{id,
  // transaction_amount,currency_id,status,date_created,
  // date_last_modified}; shipping{id}; total_amount; status;
  // date_created; date_closed.
  TMercadoLivreOrderItem = record
    ItemId: string;        // order_items[].item.id (ex: "MLB12345678")
    Title: string;         // order_items[].item.title
    SellerSku: string;     // order_items[].item.seller_sku - SKU do proprio
                           // vendedor. {ATENCAO} vem null quando o anuncio
                           // nao tem SKU cadastrado; nesse caso o chamador
                           // deve cair pro ItemId como chave.
    VariationId: string;   // order_items[].item.variation_id (null quando sem variacao)
    Quantity: Double;      // order_items[].quantity
    UnitPrice: Double;     // order_items[].unit_price (JA e' unitario -
                           // diferente da Amazon, que manda o total da linha)
    CurrencyId: string;    // order_items[].currency_id
    SaleFee: Double;       // order_items[].sale_fee - tarifa de venda do ML
                           // por item. Leitura defensiva: nao aparece no
                           // exemplo da doc que consultamos, so' em respostas
                           // reais; fica 0 se nao vier.
  end;
  TMercadoLivreOrderItemArray = TArray<TMercadoLivreOrderItem>;

  TMercadoLivreOrderDetail = record
    OrderId: string;
    Status: string;                // paid, confirmed, cancelled etc
    StatusDetail: string;
    DateCreated: TDateTime;
    DateClosed: TDateTime;
    LastUpdated: TDateTime;
    TotalAmount: Double;
    CurrencyId: string;
    BuyerId: string;
    BuyerNickname: string;         // {ATENCAO} o ML deixou de devolver dados
                                   // pessoais do comprador no /orders para
                                   // pedidos com Mercado Envios 2 - o nome
                                   // real vem do billing_info (ver
                                   // GetOrderBillingInfo)
    ShippingId: string;            // shipping.id - necessario pro GetShipment
    // Resumo do primeiro pagamento aprovado (o ML permite varios pagamentos
    // por pedido; a OE/PGTOS do SAT so tem espaco pra um).
    PaymentId: string;
    PaymentStatus: string;
    PaymentMethod: string;         // payment_method_id / payment_type - leitura
                                   // defensiva, fica vazio se nao vier
    PaymentDateApproved: TDateTime;
    TransactionAmount: Double;     // payments[].transaction_amount
    ShippingCost: Double;          // payments[].shipping_cost - leitura defensiva
    TotalPaidAmount: Double;       // payments[].total_paid_amount - leitura defensiva
    Items: TMercadoLivreOrderItemArray;
    RawJSON: string;               // resposta crua, pra montar os campos OBS
                                   // sem precisar de um campo dedicado pra cada
  end;

  // --- Dados de faturamento do comprador (GET /orders/{id}/billing_info) ---
  // {ATENCAO} exige o header 'x-version: 2' no Brasil (MLB) - confirmado na
  // documentacao oficial "Billing data" (25/06/2024). E' a UNICA fonte
  // confirmada de nome real + CPF/CNPJ do comprador, ja que o /orders
  // deixou de devolver dado pessoal.
  TMercadoLivreBillingInfo = record
    Nome: string;          // buyer.billing_info.name (+ last_name quando houver)
    DocTipo: string;       // identification.type - "CPF" ou "CNPJ" no MLB
    DocNumero: string;     // identification.number
    Rua: string;           // address.street_name
    Numero: string;        // address.street_number
    Complemento: string;   // address.comment
    Bairro: string;        // address.neighborhood
    Cidade: string;        // address.city_name
    Estado: string;        // address.state.name
    Cep: string;           // address.zip_code
    Pais: string;          // address.country_id
  end;

  // --- Envio (GET /shipments/{id}) ---
  // {ATENCAO} exige o header 'x-format-new: true' - no formato novo o antigo
  // "receiver_address" passou a ser "destination.shipping_address"
  // (confirmado na documentacao oficial de Shipments). Lemos os DOIS
  // formatos por seguranca. O endereco de destino so' fica visivel depois
  // que o pagamento e' confirmado, e receiver_phone vem ofuscado (so' vem de
  // verdade em Mercado Envios 1).
  TMercadoLivreShipment = record
    ShipmentId: string;
    Status: string;
    Substatus: string;
    TrackingNumber: string;
    LogisticMode: string;   // logistic.mode (me1, me2, self_service...)
    LogisticType: string;   // logistic.type (drop_off, xd_drop_off...)
    ReceiverPhone: string;
    AddressLine: string;    // linha pronta, quando o ML devolve
    Rua: string;
    Numero: string;
    Complemento: string;
    Bairro: string;
    Cidade: string;
    Estado: string;
    Cep: string;
    Pais: string;
  end;

  TMercadoLivreOpenAPIClient = class
  private
    FClientId: string;
    FClientSecret: string;
    FRedirectURI: string;
    FSandbox: Boolean; // ver nota no cabecalho do arquivo - nao muda URL base
    FHTTPClient: TNetHTTPClient;
    FOnLog: TMercadoLivreLogEvent;
    procedure DoLog(const AMsg: string);
    function ExecuteGet(const AApiPath, AQueryExtra, AAccessToken: string;
      out AStatusCode: Integer): string; overload;
    // Mesma coisa, mas permitindo headers extras - billing_info exige
    // 'x-version: 2' e shipments exige 'x-format-new: true'.
    function ExecuteGet(const AApiPath, AQueryExtra, AAccessToken: string;
      const AHeadersExtra: TNetHeaders; out AStatusCode: Integer): string; overload;
    function ExecutePut(const AApiPath, ABodyJSON, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ExecutePost(const AApiPath, ABodyJSON, AAccessToken: string;
      out AStatusCode: Integer): string;
    function ParseTokenResponse(const AResponseStr: string; AStatusCode: Integer): TMercadoLivreTokenInfo;
  public
    constructor Create(const AClientId, AClientSecret, ARedirectURI: string; ASandbox: Boolean);
    destructor Destroy; override;

    property OnLog: TMercadoLivreLogEvent read FOnLog write FOnLog;

    // --- OAuth (Conectar/Desconectar) ---

    // Monta a URL que o usuario (vendedor) precisa abrir no navegador pra
    // logar e autorizar o app. Repara no dominio DIFERENTE (.com.br) do
    // usado nas chamadas de API (.com, sem .br).
    function BuildAuthorizationURL(const AState: string): string;

    // Troca o "code" (recebido no redirect apos autorizacao) por um
    // access_token + refresh_token. O UserId (seller ID) ja vem pronto
    // na resposta - nao precisa de uma chamada separada a /users/me.
    function ExchangeCodeForTokens(const ACode: string): TMercadoLivreTokenInfo;

    // Renova o access_token usando o refresh_token - {ATENCAO} o
    // Mercado Livre pode devolver um NOVO refresh_token na resposta
    // (revogando o antigo) - sempre persistir o refresh_token mais
    // recente devolvido, nunca assumir que o antigo continua valido.
    function RefreshAccessToken(const ARefreshToken: string): TMercadoLivreTokenInfo;

    // Testa se o token ainda e' valido chamando /users/me (endpoint mais
    // leve possivel so pra confirmar autenticacao) - devolve o JSON bruto
    // em ARespostaJSON, util pra log/diagnostico quando falhar.
    function TestConnection(const AAccessToken, AAccountID: string;
      out ARespostaJSON: string): Boolean;

    // --- Pedidos ---
    // {ATENCAO} orders/search devolve os pedidos DIRETO no array de
    // resultados (nao so' IDs, diferente de items/search) - confirmado
    // contra exemplo real de integracao.
    function GetOrders(const AAccessToken, ASellerId: string;
      out AOrders: TMercadoLivreOrderArray; out AErrorMessage: string): Boolean;

    // Detalhe completo de UM pedido (itens, pagamento, id do envio).
    // {ATENCAO} o /orders pode responder HTTP 206 (Partial Content) quando
    // parte dos dados nao esta disponivel - o header X-Content-Missing diz
    // o que faltou (buyer, feedback, mediations, seller, shipping). Isso NAO
    // e' erro: tratamos 200 e 206 como sucesso, como a propria doc orienta.
    function GetOrderDetail(const AAccessToken, AOrderId: string;
      out ADetail: TMercadoLivreOrderDetail; out AErrorMessage: string): Boolean;

    // Nome real + CPF/CNPJ + endereco de cobranca do comprador.
    // Fonte confirmada e unica pra esses dados no Brasil (o /orders nao
    // devolve mais dado pessoal em pedidos com Mercado Envios 2).
    function GetOrderBillingInfo(const AAccessToken, AOrderId: string;
      out ABilling: TMercadoLivreBillingInfo; out AErrorMessage: string): Boolean;

    // Endereco de ENTREGA + rastreio, a partir do shipping.id que vem no
    // GetOrderDetail. Retorna False (sem quebrar o fluxo do chamador)
    // quando o pedido nao tem envio associado ou o endereco ainda esta
    // oculto por falta de confirmacao de pagamento.
    function GetShipment(const AAccessToken, AShipmentId: string;
      out AShipment: TMercadoLivreShipment; out AErrorMessage: string): Boolean;

    // So' o status do envio (mesmo GET /shipments/{id} do GetShipment), pra
    // ser chamado pedido a pedido na listagem. Diferente do GetShipment, NAO
    // grava a resposta crua no log - ela traz endereco do comprador.
    function GetShipmentStatus(const AAccessToken, AShipmentId: string;
      out AStatus, ASubstatus, AErrorMessage: string): Boolean;

    // --- Etiqueta de envio (Mercado Envios) ---
    // Baixa o PDF da etiqueta de UM envio (GET /shipment_labels?
    // shipment_ids={id}&response_type=pdf - confirmado na documentacao
    // oficial). Diferente da Shopee, o ML NAO tem um passo de "gerar" a
    // etiqueta antes: ela ja existe assim que o envio e' criado, entao aqui
    // so' existe o download.
    // {ATENCAO} so' se aplica a pedidos com Mercado Envios (me1/me2). Envio
    // por conta do vendedor (custom/self_service sem ME) nao tem etiqueta do
    // ML - nesse caso a API responde com um JSON de erro em vez do PDF, e o
    // metodo devolve False com a mensagem crua no AErrorMessage.
    function DownloadShipmentLabel(const AAccessToken, AShipmentId: string;
      out APdfBytes: TBytes; out AErrorMessage: string): Boolean;

    // --- Estoque ---
    // Atualiza o estoque de UM item (PUT /items/{id}, body
    // {"available_quantity": N} - confirmado na documentacao oficial).
    // {ATENCAO} isso e' o caminho "classico" - vendedores que usam o
    // programa "Full" ou "Estoque Distribuido/Flex" do Mercado Livre
    // gerenciam estoque por deposito, com um fluxo diferente (baseado em
    // user_product_id, algo como PUT /user-products/{id}/stock/type/...)
    // que esse metodo NAO cobre - se o cliente usar Full/Flex, revisar
    // antes de usar. Confirmar isso quando tivermos um vendedor real
    // testando.
    function UpdateStock(const AAccessToken, AItemId: string; AQuantity: Integer;
      out AErrorMessage: string): Boolean;

    // Estoque E preco na MESMA chamada. Diferente dos outros quatro marketplaces,
    // o Mercado Livre aceita os dois campos no mesmo PUT /items/{id} - entao o F2
    // usa este metodo em vez de duas chamadas, o que reduz pela metade as
    // requisicoes e elimina o caso de o estoque passar e o preco falhar.
    // ANovoPreco <= 0 envia SO o estoque (produto sem preco valido no cadastro).
    // {ATENCAO} anuncio com variacoes tem estoque e preco POR VARIACAO - este
    // metodo mexe no nivel do item, que e' o caminho certo so' pra anuncio sem
    // variacao, mesmo limite que ja valia pro estoque.
    function UpdateStockAndPrice(const AAccessToken, AItemId: string;
      AQuantity: Integer; ANovoPreco: Double; out AErrorMessage: string): Boolean;

    // --- Ofertas ---
    // items/search so devolve os IDS dos anuncios do vendedor - usar
    // GetItemsDetails depois pra pegar titulo/preco/estoque de cada um.
    function GetItemIds(const AAccessToken, ASellerId: string;
      out AItemIds: TArray<string>; out AErrorMessage: string): Boolean;

    // Multiget - busca detalhe de ATE 20 itens de uma vez (limite da
    // API). Se AItemIds tiver mais de 20, o chamador precisa dividir em
    // lotes.
    function GetItemsDetails(const AAccessToken: string; const AItemIds: TArray<string>;
      out AItems: TMercadoLivreItemArray; out AErrorMessage: string): Boolean;

    // --- Cadastro de produto novo (ver bloco de tipos la em cima) ---

    // Preditor de categoria: a partir de um texto (o titulo do produto),
    // sugere as categorias mais provaveis. ASiteId e' "MLB" no Brasil.
    // A doc recomenda limit=3 pra dar opcoes ao vendedor, igual o site faz.
    function PredictCategory(const AAccessToken, ASiteId, ATexto: string;
      const ALimite: Integer; out ACategorias: TMercadoLivreCategoriaSugeridaArray;
      out AErrorMessage: string): Boolean;

    // Atributos de uma categoria. Devolve tambem o JSON cru (ARawJSON) pra
    // tela poder mostrar a lista completa ao usuario sem baixar de novo -
    // mesmo padrao do "Ver Schema Completo" da tela da Amazon.
    function GetCategoryAttributes(const AAccessToken, ACategoryId: string;
      out AAtributos: TMercadoLivreAtributoArray; out ARawJSON: string;
      out AErrorMessage: string): Boolean;

    // Confere se um tipo de anuncio (free / gold_special / gold_pro ...)
    // esta disponivel pra essa conta nessa categoria. Quando nao esta, o
    // proprio Mercado Livre devolve o motivo em ACause - ex: "You have more
    // than 5 transactions in the last year." pro tipo "free".
    // Result = False significa FALHA NA CHAMADA; "consultou e nao esta
    // disponivel" e' Result = True com ADisponivel = False.
    function CheckListingTypeAvailable(const AAccessToken, AUserId,
      AListingTypeId, ACategoryId: string; out ADisponivel: Boolean;
      out ACause: string; out AErrorMessage: string): Boolean;

    // Cria o anuncio. ABodyJSON e' o payload completo montado pela tela
    // (title, category_id, price, currency_id, available_quantity,
    // buying_mode, listing_type_id, condition, pictures, attributes...).
    // {ATENCAO} a descricao NAO entra aqui - ver SetItemDescription.
    function CreateItem(const AAccessToken, ABodyJSON: string;
      out AItemId, ARespostaJSON, AErrorMessage: string): Boolean;

    // Descricao do anuncio - chamada SEPARADA, feita depois de o item ja
    // existir. So aceita TEXTO PLANO (sem HTML/negrito/fonte); quebra de
    // linha e' #10. Tentar POST numa publicacao que JA tem descricao
    // devolve 400 - nesse caso o certo e' editar, nao criar de novo.
    function SetItemDescription(const AAccessToken, AItemId, ATextoPlano: string;
      out AErrorMessage: string): Boolean;

    // --- Oferta em cima de produto de CATALOGO ---
    // Busca produtos no catalogo do ML por texto livre. So' traz produtos
    // com status "active" (os inativos nao aceitam oferta nova).
    // Lista vazia NAO e' erro - devolve True com 0 itens.
    function SearchCatalogProducts(const AAccessToken, ASiteId, ATexto: string;
      const ALimite: Integer; out AProdutos: TMercadoLivreProdutoCatalogoArray;
      out AErrorMessage: string): Boolean;

    // Detalhe de UM produto de catalogo. Devolve tambem o JSON cru, pra tela
    // poder mostrar a ficha completa (mesmo padrao do "Ver Atributos").
    function GetCatalogProduct(const AAccessToken, AProductId: string;
      out AProduto: TMercadoLivreProdutoCatalogo;
      out ARawJSON, AErrorMessage: string): Boolean;

    // {NOTA} publicar a oferta de catalogo NAO precisa de metodo novo: usa o
    // mesmo CreateItem acima, so' que com um corpo diferente
    // (catalog_product_id + catalog_listing=true, sem title/category_id/
    // attributes - o ML tira tudo isso do proprio produto de catalogo).
  end;

implementation

function FormatarErroHTTP(AStatusCode: Integer; const AResponseStr, AContexto: string): string;
begin
  Result := Format('HTTP %d ao %s: %s', [AStatusCode, AContexto, AResponseStr]);
end;

{ TMercadoLivreOpenAPIClient }

constructor TMercadoLivreOpenAPIClient.Create(const AClientId, AClientSecret,
  ARedirectURI: string; ASandbox: Boolean);
begin
  inherited Create;
  FClientId := AClientId;
  FClientSecret := AClientSecret;
  FRedirectURI := ARedirectURI;
  FSandbox := ASandbox;
  FHTTPClient := TNetHTTPClient.Create(nil);
  FHTTPClient.ConnectionTimeout := 30000;
  FHTTPClient.ResponseTimeout := 30000;
end;

destructor TMercadoLivreOpenAPIClient.Destroy;
begin
  FHTTPClient.Free;
  inherited;
end;

procedure TMercadoLivreOpenAPIClient.DoLog(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

function TMercadoLivreOpenAPIClient.BuildAuthorizationURL(const AState: string): string;
begin
  // {ATENCAO} dominio .com.br - diferente do dominio das chamadas de API
  // (api.mercadolibre.com, sem ".br"). E' assim mesmo, confirmado na doc
  // oficial - nao e' erro de digitacao.
  Result := 'https://auth.mercadolivre.com.br/authorization' +
    '?response_type=code' +
    '&client_id=' + TNetEncoding.URL.Encode(FClientId) +
    '&redirect_uri=' + TNetEncoding.URL.Encode(FRedirectURI);
  if AState <> '' then
    Result := Result + '&state=' + TNetEncoding.URL.Encode(AState);
end;

function TMercadoLivreOpenAPIClient.ParseTokenResponse(const AResponseStr: string;
  AStatusCode: Integer): TMercadoLivreTokenInfo;
var
  JSONObj: TJSONObject;
begin
  Result.Success := False;
  Result.AccessToken := '';
  Result.RefreshToken := '';
  Result.Scope := '';
  Result.ExpiresIn := 0;
  Result.UserId := '';
  Result.ErrorMessage := '';

  if AStatusCode <> 200 then
  begin
    Result.ErrorMessage := FormatarErroHTTP(AStatusCode, AResponseStr, 'obter/renovar token');
    Exit;
  end;

  JSONObj := TJSONObject.ParseJSONValue(AResponseStr) as TJSONObject;
  if not Assigned(JSONObj) then
  begin
    Result.ErrorMessage := 'Resposta não é um JSON válido: ' + AResponseStr;
    Exit;
  end;
  try
    if not JSONObj.TryGetValue<string>('access_token', Result.AccessToken) then
    begin
      Result.ErrorMessage := 'Resposta sem access_token: ' + AResponseStr;
      Exit;
    end;
    JSONObj.TryGetValue<string>('refresh_token', Result.RefreshToken);
    JSONObj.TryGetValue<string>('scope', Result.Scope);
    JSONObj.TryGetValue<Integer>('expires_in', Result.ExpiresIn);
    // user_id vem como numero no JSON - le como Int64 e converte pra string
    if Assigned(JSONObj.GetValue('user_id')) then
      Result.UserId := JSONObj.GetValue<Int64>('user_id').ToString;
    Result.Success := True;
  finally
    JSONObj.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.ExchangeCodeForTokens(const ACode: string): TMercadoLivreTokenInfo;
var
  Response: IHTTPResponse;
  BodyStream: TStringStream;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  BodyStr :=
    'grant_type=authorization_code' +
    '&client_id=' + TNetEncoding.URL.Encode(FClientId) +
    '&client_secret=' + TNetEncoding.URL.Encode(FClientSecret) +
    '&code=' + TNetEncoding.URL.Encode(ACode) +
    '&redirect_uri=' + TNetEncoding.URL.Encode(FRedirectURI);

  BodyStream := TStringStream.Create(BodyStr, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Post('https://api.mercadolibre.com/oauth/token', BodyStream, nil,
        [TNetHeader.Create('Content-Type', 'application/x-www-form-urlencoded'),
         TNetHeader.Create('Accept', 'application/json')]);
      StatusCode := Response.StatusCode;
      ResponseStr := Response.ContentAsString(TEncoding.UTF8);
      DoLog('ExchangeCodeForTokens: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);
    except
      on E: Exception do
      begin
        StatusCode := 0;
        ResponseStr := E.Message;
        DoLog('Erro em ExchangeCodeForTokens: ' + E.Message);
      end;
    end;
  finally
    BodyStream.Free;
  end;

  Result := ParseTokenResponse(ResponseStr, StatusCode);
end;

function TMercadoLivreOpenAPIClient.RefreshAccessToken(const ARefreshToken: string): TMercadoLivreTokenInfo;
var
  Response: IHTTPResponse;
  BodyStream: TStringStream;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  BodyStr :=
    'grant_type=refresh_token' +
    '&client_id=' + TNetEncoding.URL.Encode(FClientId) +
    '&client_secret=' + TNetEncoding.URL.Encode(FClientSecret) +
    '&refresh_token=' + TNetEncoding.URL.Encode(ARefreshToken);

  BodyStream := TStringStream.Create(BodyStr, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Post('https://api.mercadolibre.com/oauth/token', BodyStream, nil,
        [TNetHeader.Create('Content-Type', 'application/x-www-form-urlencoded'),
         TNetHeader.Create('Accept', 'application/json')]);
      StatusCode := Response.StatusCode;
      ResponseStr := Response.ContentAsString(TEncoding.UTF8);
      DoLog('RefreshAccessToken: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);
    except
      on E: Exception do
      begin
        StatusCode := 0;
        ResponseStr := E.Message;
        DoLog('Erro em RefreshAccessToken: ' + E.Message);
      end;
    end;
  finally
    BodyStream.Free;
  end;

  Result := ParseTokenResponse(ResponseStr, StatusCode);
end;

function TMercadoLivreOpenAPIClient.ExecuteGet(const AApiPath, AQueryExtra,
  AAccessToken: string; out AStatusCode: Integer): string;
begin
  Result := ExecuteGet(AApiPath, AQueryExtra, AAccessToken, [], AStatusCode);
end;

function TMercadoLivreOpenAPIClient.ExecuteGet(const AApiPath, AQueryExtra,
  AAccessToken: string; const AHeadersExtra: TNetHeaders;
  out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  URL: string;
  Headers: TNetHeaders;
  I: Integer;
begin
  // {ATENCAO} dominio .com (SEM ".br") pras chamadas de API - diferente
  // do dominio de autorizacao usado em BuildAuthorizationURL.
  URL := 'https://api.mercadolibre.com' + AApiPath;
  if AQueryExtra <> '' then
    URL := URL + '?' + AQueryExtra;

  SetLength(Headers, 2 + Length(AHeadersExtra));
  Headers[0] := TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken);
  Headers[1] := TNetHeader.Create('Content-Type', 'application/json');
  for I := Low(AHeadersExtra) to High(AHeadersExtra) do
    Headers[2 + I] := AHeadersExtra[I];

  try
    Response := FHTTPClient.Get(URL, nil, Headers);
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

function TMercadoLivreOpenAPIClient.ExecutePut(const AApiPath, ABodyJSON,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  BodyStream: TStringStream;
  URL: string;
begin
  URL := 'https://api.mercadolibre.com' + AApiPath;
  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Put(URL, BodyStream, nil,
        [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken),
         TNetHeader.Create('Content-Type', 'application/json')]);
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

function TMercadoLivreOpenAPIClient.UpdateStock(const AAccessToken, AItemId: string;
  AQuantity: Integer; out AErrorMessage: string): Boolean;
var
  BodyJSON: TJSONObject;
  ResponseStr, BodyStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('available_quantity', TJSONNumber.Create(AQuantity));
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  ResponseStr := ExecutePut('/items/' + TNetEncoding.URL.Encode(AItemId), BodyStr,
    AAccessToken, StatusCode);

  DoLog('UpdateStock (' + AItemId + '): HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'atualizar estoque');
    Exit;
  end;

  Result := True;
end;

function TMercadoLivreOpenAPIClient.UpdateStockAndPrice(const AAccessToken,
  AItemId: string; AQuantity: Integer; ANovoPreco: Double;
  out AErrorMessage: string): Boolean;
var
  BodyJSON: TJSONObject;
  ResponseStr, BodyStr, OQue: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';
  OQue := 'atualizar';
  BodyJSON := TJSONObject.Create;
  try
    // {ATENCAO} AQuantity NEGATIVO significa "nao mexer no estoque" - o F2 usa
    // isso quando o produto esta marcado so' pra preco, ou tem estoque infinito.
    // Zero e' quantidade valida (produto esgotado), por isso o sentinela e' < 0.
    if AQuantity >= 0 then
    begin
      BodyJSON.AddPair('available_quantity', TJSONNumber.Create(AQuantity));
      OQue := 'atualizar estoque';
    end;
    if ANovoPreco > 0 then
    begin
      // Numero mesmo, nao string - o ML recusa preco entre aspas.
      BodyJSON.AddPair('price', TJSONNumber.Create(ANovoPreco));
      if OQue = 'atualizar estoque' then OQue := 'atualizar estoque e preco' else OQue := 'atualizar preco';
    end;
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;
  ResponseStr := ExecutePut('/items/' + TNetEncoding.URL.Encode(AItemId), BodyStr,
    AAccessToken, StatusCode);
  DoLog('UpdateStockAndPrice (' + AItemId + '): HTTP ' + StatusCode.ToString +
    ' ' + ResponseStr);
  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, OQue);
    Exit;
  end;
  Result := True;
end;


function TMercadoLivreOpenAPIClient.GetOrders(const AAccessToken, ASellerId: string;
  out AOrders: TMercadoLivreOrderArray; out AErrorMessage: string): Boolean;
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONRoot, Order, Seller, Shipping: TJSONObject;
  JSONResults: TJSONArray;
  ShippingIdValor: TJSONValue;
  I: Integer;
  DataStr: string;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AOrders, 0);

  ResponseStr := ExecuteGet('/orders/search', 'seller=' + TNetEncoding.URL.Encode(ASellerId),
    AAccessToken, StatusCode);

  DoLog('GetOrders: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar pedidos');
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    if not JSONRoot.TryGetValue<TJSONArray>('results', JSONResults) then
    begin
      Result := True; // sem "results" = sem pedido nenhum, mas sem erro
      Exit;
    end;

    SetLength(AOrders, JSONResults.Count);
    for I := 0 to JSONResults.Count - 1 do
    begin
      Order := JSONResults.Items[I] as TJSONObject;
      if not Order.TryGetValue<string>('id', AOrders[I].OrderId) then
        if Assigned(Order.GetValue('id')) then
          AOrders[I].OrderId := Order.GetValue<Int64>('id').ToString;
      Order.TryGetValue<string>('status', AOrders[I].Status);

      if Order.TryGetValue<string>('date_created', DataStr) then
        AOrders[I].DateCreated := ISO8601ToDate(DataStr, False);
      if Order.TryGetValue<string>('last_updated', DataStr) then
        AOrders[I].DateLastUpdated := ISO8601ToDate(DataStr, False);

      Order.TryGetValue<Double>('total_amount', AOrders[I].TotalAmount);

      if Order.TryGetValue<TJSONObject>('buyer', Seller) then
      begin
        if not Seller.TryGetValue<string>('id', AOrders[I].BuyerId) then
          if Assigned(Seller.GetValue('id')) then
            AOrders[I].BuyerId := Seller.GetValue<Int64>('id').ToString;
        Seller.TryGetValue<string>('nickname', AOrders[I].BuyerNickname);
      end;

      // shipping.id vem como numero ou null (pedido sem Mercado Envios).
      if Order.TryGetValue<TJSONObject>('shipping', Shipping) then
      begin
        ShippingIdValor := Shipping.GetValue('id');
        if Assigned(ShippingIdValor) and not (ShippingIdValor is TJSONNull) then
          AOrders[I].ShippingId := ShippingIdValor.Value;
      end;
    end;

    Result := True;
    DoLog(Format('%d pedido(s) encontrado(s).', [Length(AOrders)]));
  finally
    JSONRoot.Free;
  end;
end;

// Le um valor string de um objeto JSON aninhado por caminho ("a.b.c").
// Devolve '' quando qualquer nivel do caminho nao existe - leitura
// sempre defensiva, pra um campo ausente nunca derrubar o parsing todo.
function ValorJSONAninhado(AObj: TJSONObject; const ACaminho: string): string;
var
  Partes: TArray<string>;
  Atual: TJSONObject;
  Valor: TJSONValue;
  I: Integer;
begin
  Result := '';
  if not Assigned(AObj) then
    Exit;
  Partes := ACaminho.Split(['.']);
  Atual := AObj;
  for I := Low(Partes) to High(Partes) - 1 do
  begin
    if not Atual.TryGetValue<TJSONObject>(Partes[I], Atual) then
      Exit;
    if not Assigned(Atual) then
      Exit;
  end;
  Valor := Atual.GetValue(Partes[High(Partes)]);
  if Assigned(Valor) and not (Valor is TJSONNull) then
    Result := Valor.Value;
end;

// Le um id que a API do Mercado Livre as vezes manda como numero e as
// vezes como string (acontece com order id, buyer id, shipping id).
function IdComoString(AObj: TJSONObject; const ANome: string): string;
var
  Valor: TJSONValue;
begin
  Result := '';
  if not Assigned(AObj) then
    Exit;
  Valor := AObj.GetValue(ANome);
  if Assigned(Valor) and not (Valor is TJSONNull) then
    Result := Valor.Value;
end;

function TMercadoLivreOpenAPIClient.GetOrderDetail(const AAccessToken, AOrderId: string;
  out ADetail: TMercadoLivreOrderDetail; out AErrorMessage: string): Boolean;
var
  ResponseStr, DataStr: string;
  StatusCode: Integer;
  JSONRoot, Obj, ItemObj, PagObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := False;
  AErrorMessage := '';
  ADetail := Default(TMercadoLivreOrderDetail);

  ResponseStr := ExecuteGet('/orders/' + TNetEncoding.URL.Encode(AOrderId), '',
    AAccessToken, StatusCode);

  DoLog('GetOrderDetail: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  // 206 = Partial Content: a doc oficial diz que isso NAO e' erro - parte
  // dos dados nao veio (o header X-Content-Missing lista quais), mas o que
  // veio e' valido e normalmente suficiente.
  if not (StatusCode in [200, 206]) then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar detalhe do pedido');
    Exit;
  end;

  if StatusCode = 206 then
    DoLog('Aviso: o Mercado Livre respondeu 206 (dados parciais) para o pedido ' +
      AOrderId + ' - algum bloco (comprador, envio, etc.) pode vir vazio.');

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    ADetail.RawJSON := ResponseStr;

    ADetail.OrderId := IdComoString(JSONRoot, 'id');
    if ADetail.OrderId = '' then
      ADetail.OrderId := AOrderId;
    JSONRoot.TryGetValue<string>('status', ADetail.Status);
    ADetail.StatusDetail := ValorJSONAninhado(JSONRoot, 'status_detail');
    JSONRoot.TryGetValue<Double>('total_amount', ADetail.TotalAmount);
    JSONRoot.TryGetValue<string>('currency_id', ADetail.CurrencyId);

    if JSONRoot.TryGetValue<string>('date_created', DataStr) and (DataStr <> '') then
      ADetail.DateCreated := ISO8601ToDate(DataStr, False);
    if JSONRoot.TryGetValue<string>('date_closed', DataStr) and (DataStr <> '') then
      ADetail.DateClosed := ISO8601ToDate(DataStr, False);
    if JSONRoot.TryGetValue<string>('last_updated', DataStr) and (DataStr <> '') then
      ADetail.LastUpdated := ISO8601ToDate(DataStr, False);

    // Comprador: no Mercado Envios 2 o ML devolve praticamente so o id
    // aqui - nome e documento vem do GetOrderBillingInfo.
    if JSONRoot.TryGetValue<TJSONObject>('buyer', Obj) then
    begin
      ADetail.BuyerId := IdComoString(Obj, 'id');
      Obj.TryGetValue<string>('nickname', ADetail.BuyerNickname);
    end;

    // Envio: so o id vem aqui; o endereco de entrega exige GetShipment.
    if JSONRoot.TryGetValue<TJSONObject>('shipping', Obj) then
      ADetail.ShippingId := IdComoString(Obj, 'id');

    // Pagamentos: pode vir mais de um (pagamento dividido, retentativa).
    // Prioriza o primeiro APROVADO; se nenhum estiver aprovado, usa o
    // primeiro da lista, so pra nao ficar sem informacao nenhuma.
    if JSONRoot.TryGetValue<TJSONArray>('payments', Arr) and (Arr.Count > 0) then
    begin
      PagObj := nil;
      for I := 0 to Arr.Count - 1 do
      begin
        Obj := Arr.Items[I] as TJSONObject;
        if SameText(ValorJSONAninhado(Obj, 'status'), 'approved') then
        begin
          PagObj := Obj;
          Break;
        end;
      end;
      if not Assigned(PagObj) then
        PagObj := Arr.Items[0] as TJSONObject;

      ADetail.PaymentId := IdComoString(PagObj, 'id');
      PagObj.TryGetValue<string>('status', ADetail.PaymentStatus);
      PagObj.TryGetValue<Double>('transaction_amount', ADetail.TransactionAmount);
      // Leitura defensiva - esses tres nao aparecem no exemplo da doc que
      // consultamos, so em respostas reais; ficam vazios/zero se nao vierem.
      ADetail.PaymentMethod := ValorJSONAninhado(PagObj, 'payment_method_id');
      if ADetail.PaymentMethod = '' then
        ADetail.PaymentMethod := ValorJSONAninhado(PagObj, 'payment_type');
      PagObj.TryGetValue<Double>('shipping_cost', ADetail.ShippingCost);
      PagObj.TryGetValue<Double>('total_paid_amount', ADetail.TotalPaidAmount);
      if PagObj.TryGetValue<string>('date_approved', DataStr) and (DataStr <> '') then
        ADetail.PaymentDateApproved := ISO8601ToDate(DataStr, False);
    end;

    // Itens.
    if JSONRoot.TryGetValue<TJSONArray>('order_items', Arr) then
    begin
      SetLength(ADetail.Items, Arr.Count);
      for I := 0 to Arr.Count - 1 do
      begin
        Obj := Arr.Items[I] as TJSONObject;
        Obj.TryGetValue<Double>('quantity', ADetail.Items[I].Quantity);
        Obj.TryGetValue<Double>('unit_price', ADetail.Items[I].UnitPrice);
        Obj.TryGetValue<string>('currency_id', ADetail.Items[I].CurrencyId);
        Obj.TryGetValue<Double>('sale_fee', ADetail.Items[I].SaleFee);

        if Obj.TryGetValue<TJSONObject>('item', ItemObj) then
        begin
          ADetail.Items[I].ItemId := IdComoString(ItemObj, 'id');
          ItemObj.TryGetValue<string>('title', ADetail.Items[I].Title);
          ADetail.Items[I].SellerSku := ValorJSONAninhado(ItemObj, 'seller_sku');
          ADetail.Items[I].VariationId := IdComoString(ItemObj, 'variation_id');
        end;
      end;
    end;

    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.GetOrderBillingInfo(const AAccessToken, AOrderId: string;
  out ABilling: TMercadoLivreBillingInfo; out AErrorMessage: string): Boolean;
var
  ResponseStr, Sobrenome: string;
  StatusCode: Integer;
  JSONRoot: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  ABilling := Default(TMercadoLivreBillingInfo);

  // {ATENCAO} o header 'x-version: 2' e' obrigatorio no Brasil (MLB) -
  // sem ele o ML responde no formato antigo (additional_info como lista de
  // pares type/value), que este parsing nao entende.
  ResponseStr := ExecuteGet('/orders/' + TNetEncoding.URL.Encode(AOrderId) + '/billing_info',
    '', AAccessToken, [TNetHeader.Create('x-version', '2')], StatusCode);

  DoLog('GetOrderBillingInfo: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr,
      'buscar dados de faturamento do comprador');
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    ABilling.Nome := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.name');
    Sobrenome := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.last_name');
    if Sobrenome <> '' then
      ABilling.Nome := Trim(ABilling.Nome + ' ' + Sobrenome);

    ABilling.DocTipo := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.identification.type');
    ABilling.DocNumero := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.identification.number');

    ABilling.Rua := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.street_name');
    ABilling.Numero := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.street_number');
    ABilling.Complemento := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.comment');
    ABilling.Bairro := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.neighborhood');
    ABilling.Cidade := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.city_name');
    ABilling.Estado := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.state.name');
    ABilling.Cep := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.zip_code');
    ABilling.Pais := ValorJSONAninhado(JSONRoot, 'buyer.billing_info.address.country_id');

    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.GetShipment(const AAccessToken, AShipmentId: string;
  out AShipment: TMercadoLivreShipment; out AErrorMessage: string): Boolean;
var
  ResponseStr, Prefixo: string;
  StatusCode: Integer;
  JSONRoot: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  AShipment := Default(TMercadoLivreShipment);

  if Trim(AShipmentId) = '' then
  begin
    AErrorMessage := 'Pedido sem envio associado (shipping.id vazio).';
    Exit;
  end;

  // {ATENCAO} o header 'x-format-new: true' e' obrigatorio - e' ele que
  // troca o antigo "receiver_address" pelo "destination.shipping_address".
  ResponseStr := ExecuteGet('/shipments/' + TNetEncoding.URL.Encode(AShipmentId), '',
    AAccessToken, [TNetHeader.Create('x-format-new', 'true')], StatusCode);

  DoLog('GetShipment: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar dados do envio');
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    AShipment.ShipmentId := IdComoString(JSONRoot, 'id');
    JSONRoot.TryGetValue<string>('status', AShipment.Status);
    JSONRoot.TryGetValue<string>('substatus', AShipment.Substatus);
    JSONRoot.TryGetValue<string>('tracking_number', AShipment.TrackingNumber);
    AShipment.LogisticMode := ValorJSONAninhado(JSONRoot, 'logistic.mode');
    AShipment.LogisticType := ValorJSONAninhado(JSONRoot, 'logistic.type');

    // Formato novo (x-format-new) usa destination.shipping_address; o
    // formato antigo usava receiver_address. Tenta o novo e cai no antigo,
    // pra funcionar mesmo se o header for ignorado por algum motivo.
    Prefixo := 'destination.shipping_address';
    if ValorJSONAninhado(JSONRoot, Prefixo + '.zip_code') = '' then
      Prefixo := 'receiver_address';

    AShipment.AddressLine := ValorJSONAninhado(JSONRoot, Prefixo + '.address_line');
    AShipment.Rua := ValorJSONAninhado(JSONRoot, Prefixo + '.street_name');
    AShipment.Numero := ValorJSONAninhado(JSONRoot, Prefixo + '.street_number');
    AShipment.Complemento := ValorJSONAninhado(JSONRoot, Prefixo + '.comment');
    AShipment.Bairro := ValorJSONAninhado(JSONRoot, Prefixo + '.neighborhood.name');
    AShipment.Cidade := ValorJSONAninhado(JSONRoot, Prefixo + '.city.name');
    AShipment.Estado := ValorJSONAninhado(JSONRoot, Prefixo + '.state.name');
    AShipment.Cep := ValorJSONAninhado(JSONRoot, Prefixo + '.zip_code');
    AShipment.Pais := ValorJSONAninhado(JSONRoot, Prefixo + '.country.name');

    // {ATENCAO} o ML ofusca o telefone do destinatario nesse endpoint - so
    // vem de verdade em pedidos Mercado Envios 1.
    AShipment.ReceiverPhone := ValorJSONAninhado(JSONRoot, 'destination.receiver_phone');
    if AShipment.ReceiverPhone = '' then
      AShipment.ReceiverPhone := ValorJSONAninhado(JSONRoot, 'receiver_phone');

    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.GetShipmentStatus(const AAccessToken,
  AShipmentId: string; out AStatus, ASubstatus, AErrorMessage: string): Boolean;
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONRoot: TJSONObject;
begin
  Result := False;
  AStatus := '';
  ASubstatus := '';
  AErrorMessage := '';

  if Trim(AShipmentId) = '' then
  begin
    AErrorMessage := 'Pedido sem envio associado (shipping.id vazio).';
    Exit;
  end;

  ResponseStr := ExecuteGet('/shipments/' + TNetEncoding.URL.Encode(AShipmentId), '',
    AAccessToken, [TNetHeader.Create('x-format-new', 'true')], StatusCode);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar status do envio');
    DoLog('GetShipmentStatus (' + AShipmentId + '): HTTP ' + StatusCode.ToString +
      ' ' + AErrorMessage);
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    JSONRoot.TryGetValue<string>('status', AStatus);
    JSONRoot.TryGetValue<string>('substatus', ASubstatus);
    // So' o status no log - a resposta crua tem o endereco do comprador.
    DoLog('GetShipmentStatus (' + AShipmentId + '): HTTP 200 status=' + AStatus +
      ' substatus=' + ASubstatus);
    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.DownloadShipmentLabel(const AAccessToken,
  AShipmentId: string; out APdfBytes: TBytes; out AErrorMessage: string): Boolean;
var
  URL, Preview: string;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
begin
  // {ATENCAO} esse endpoint devolve o PDF BINARIO direto (nao um JSON) - por
  // isso NAO passa pelo ExecuteGet compartilhado, que le a resposta como
  // texto. Mesmo padrao ja usado no DownloadShippingDocument da Shopee.
  Result := False;
  AErrorMessage := '';
  SetLength(APdfBytes, 0);

  if Trim(AShipmentId) = '' then
  begin
    AErrorMessage := 'Pedido sem envio associado (shipping.id vazio) - nao ha etiqueta pra baixar.';
    DoLog(AErrorMessage);
    Exit;
  end;

  URL := 'https://api.mercadolibre.com/shipment_labels' +
    '?shipment_ids=' + TNetEncoding.URL.Encode(AShipmentId) +
    '&response_type=pdf';

  Headers := [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken)];
  try
    Response := FHTTPClient.Get(URL, nil, Headers);

    if Response.StatusCode >= 400 then
    begin
      AErrorMessage := FormatarErroHTTP(Response.StatusCode,
        Response.ContentAsString(TEncoding.UTF8), 'baixar etiqueta');
      DoLog(AErrorMessage);
      Exit;
    end;

    // Quando o envio existe mas nao tem etiqueta do ML disponivel (envio por
    // conta do vendedor, etiqueta ainda nao liberada etc), o ML responde 200
    // com um JSON de erro no lugar do PDF - todo PDF comeca com "%PDF".
    Preview := Response.ContentAsString(TEncoding.UTF8);
    if not Preview.StartsWith('%PDF') then
    begin
      AErrorMessage := 'O Mercado Livre devolveu uma resposta que nao e um PDF: ' + Preview;
      DoLog(AErrorMessage);
      Exit;
    end;

    Response.ContentStream.Position := 0;
    SetLength(APdfBytes, Response.ContentStream.Size);
    if Length(APdfBytes) > 0 then
      Response.ContentStream.ReadBuffer(APdfBytes[0], Response.ContentStream.Size);

    Result := Length(APdfBytes) > 0;
    if not Result then
    begin
      AErrorMessage := 'O Mercado Livre devolveu a etiqueta vazia (0 bytes).';
      DoLog(AErrorMessage);
      Exit;
    end;

    DoLog(Format('DownloadShipmentLabel (%s): %d bytes recebidos.',
      [AShipmentId, Length(APdfBytes)]));
  except
    on E: Exception do
    begin
      AErrorMessage := 'Erro na requisicao de download da etiqueta: ' + E.Message;
      DoLog(AErrorMessage);
    end;
  end;
end;

function TMercadoLivreOpenAPIClient.GetItemIds(const AAccessToken, ASellerId: string;
  out AItemIds: TArray<string>; out AErrorMessage: string): Boolean;
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONRoot: TJSONObject;
  JSONResults: TJSONArray;
  I: Integer;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AItemIds, 0);

  ResponseStr := ExecuteGet('/users/' + TNetEncoding.URL.Encode(ASellerId) + '/items/search',
    '', AAccessToken, StatusCode);

  DoLog('GetItemIds: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar IDs de itens');
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    if not JSONRoot.TryGetValue<TJSONArray>('results', JSONResults) then
    begin
      Result := True; // sem "results" = sem item nenhum, mas sem erro
      Exit;
    end;

    SetLength(AItemIds, JSONResults.Count);
    for I := 0 to JSONResults.Count - 1 do
      AItemIds[I] := (JSONResults.Items[I] as TJSONString).Value;

    Result := True;
    DoLog(Format('%d ID(s) de item encontrado(s).', [Length(AItemIds)]));
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.GetItemsDetails(const AAccessToken: string;
  const AItemIds: TArray<string>; out AItems: TMercadoLivreItemArray;
  out AErrorMessage: string): Boolean;
var
  ResponseStr, IdsConcatenados: string;
  StatusCode: Integer;
  JSONRoot: TJSONArray;
  Wrapper, ItemBody: TJSONObject;
  I: Integer;
  Codigo: Integer;
  DataTxt: string;
  DataAlt: TDateTime;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AItems, 0);

  if Length(AItemIds) = 0 then
  begin
    Result := True;
    Exit;
  end;
  if Length(AItemIds) > 20 then
  begin
    AErrorMessage := 'GetItemsDetails aceita no maximo 20 IDs por vez (limite da API de multiget) - divida em lotes.';
    Exit;
  end;

  IdsConcatenados := string.Join(',', AItemIds);
  ResponseStr := ExecuteGet('/items', 'ids=' + TNetEncoding.URL.Encode(IdsConcatenados),
    AAccessToken, StatusCode);

  DoLog('GetItemsDetails: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar detalhe de itens');
    Exit;
  end;

  // {ATENCAO} multiget devolve um ARRAY na raiz (nao um objeto com
  // "results") - cada elemento tem "code" (status HTTP daquele item
  // especifico) + "body" (o item em si) - um item invalido/removido nao
  // quebra os outros, so' vem com code != 200 pra aquele item.
  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONArray;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um array JSON válido';
    Exit;
  end;
  try
    SetLength(AItems, JSONRoot.Count);
    for I := 0 to JSONRoot.Count - 1 do
    begin
      Wrapper := JSONRoot.Items[I] as TJSONObject;
      Codigo := 200;
      Wrapper.TryGetValue<Integer>('code', Codigo);
      if (Codigo <> 200) or not Wrapper.TryGetValue<TJSONObject>('body', ItemBody) then
        Continue; // item com erro individual - pula, nao quebra os outros

      if not ItemBody.TryGetValue<string>('id', AItems[I].ItemId) then
        if Assigned(ItemBody.GetValue('id')) then
          AItems[I].ItemId := ItemBody.GetValue<Int64>('id').ToString;
      ItemBody.TryGetValue<string>('title', AItems[I].Title);
      ItemBody.TryGetValue<Double>('price', AItems[I].Price);
      ItemBody.TryGetValue<Integer>('available_quantity', AItems[I].AvailableQuantity);
      ItemBody.TryGetValue<Integer>('sold_quantity', AItems[I].SoldQuantity);
      ItemBody.TryGetValue<string>('status', AItems[I].Status);
      ItemBody.TryGetValue<string>('permalink', AItems[I].Permalink);
      // Ultima alteracao do anuncio, ISO 8601 em UTC
      // (ex: 2026-10-14T18:22:05.000Z) - convertida para hora local.
      DataTxt := '';
      if ItemBody.TryGetValue<string>('last_updated', DataTxt) and
         TryISO8601ToDate(DataTxt, DataAlt, False) then
        AItems[I].LastUpdated := DataAlt;
    end;

    Result := True;
    DoLog(Format('%d item(ns) detalhado(s).', [Length(AItems)]));
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.ExecutePost(const AApiPath, ABodyJSON,
  AAccessToken: string; out AStatusCode: Integer): string;
var
  Response: IHTTPResponse;
  Body: TStringStream;
begin
  Body := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Post('https://api.mercadolibre.com' + AApiPath, Body, nil,
        [TNetHeader.Create('Authorization', 'Bearer ' + AAccessToken),
         TNetHeader.Create('Content-Type', 'application/json'),
         TNetHeader.Create('Accept', 'application/json')]);
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
    Body.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.PredictCategory(const AAccessToken, ASiteId,
  ATexto: string; const ALimite: Integer;
  out ACategorias: TMercadoLivreCategoriaSugeridaArray;
  out AErrorMessage: string): Boolean;
var
  ResponseStr, Query: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  Arr: TJSONArray;
  Obj: TJSONObject;
  AttrsArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(ACategorias, 0);

  Query := 'q=' + TNetEncoding.URL.Encode(ATexto);
  if ALimite > 0 then
    Query := 'limit=' + ALimite.ToString + '&' + Query;

  ResponseStr := ExecuteGet('/sites/' + TNetEncoding.URL.Encode(ASiteId) +
    '/domain_discovery/search', Query, AAccessToken, StatusCode);

  DoLog('PredictCategory: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'prever a categoria');
    Exit;
  end;

  // A resposta do preditor e' um ARRAY na raiz (nao um objeto com
  // "results", diferente do orders/search e do items/search).
  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  if not Assigned(Raiz) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    if not (Raiz is TJSONArray) then
    begin
      // Sem sugestao nenhuma nao e' erro - so' devolve lista vazia pra tela
      // pedir outra palavra-chave.
      Result := True;
      Exit;
    end;
    Arr := TJSONArray(Raiz);
    SetLength(ACategorias, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      Obj := Arr.Items[I] as TJSONObject;
      Obj.TryGetValue<string>('domain_id', ACategorias[I].DomainId);
      Obj.TryGetValue<string>('domain_name', ACategorias[I].DomainName);
      Obj.TryGetValue<string>('category_id', ACategorias[I].CategoryId);
      Obj.TryGetValue<string>('category_name', ACategorias[I].CategoryName);
      if Obj.TryGetValue<TJSONArray>('attributes', AttrsArr) and (AttrsArr.Count > 0) then
        ACategorias[I].AtributosPreditosJSON := AttrsArr.ToJSON
      else
        ACategorias[I].AtributosPreditosJSON := '';
    end;
    Result := True;
    DoLog(Format('%d categoria(s) sugerida(s).', [Length(ACategorias)]));
  finally
    Raiz.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.GetCategoryAttributes(const AAccessToken,
  ACategoryId: string; out AAtributos: TMercadoLivreAtributoArray;
  out ARawJSON: string; out AErrorMessage: string): Boolean;
var
  StatusCode, I, J, N: Integer;
  Raiz: TJSONValue;
  Arr, ValoresArr: TJSONArray;
  Obj, TagsObj, ValorObj: TJSONObject;
  ValorId, ValorNome: string;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AAtributos, 0);

  ARawJSON := ExecuteGet('/categories/' + TNetEncoding.URL.Encode(ACategoryId) +
    '/attributes', '', AAccessToken, StatusCode);

  DoLog('GetCategoryAttributes (' + ACategoryId + '): HTTP ' + StatusCode.ToString);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ARawJSON, 'buscar atributos da categoria');
    Exit;
  end;

  Raiz := TJSONObject.ParseJSONValue(ARawJSON);
  if not Assigned(Raiz) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    if not (Raiz is TJSONArray) then
    begin
      AErrorMessage := 'Resposta de atributos não veio como lista';
      Exit;
    end;
    Arr := TJSONArray(Raiz);
    SetLength(AAtributos, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      Obj := Arr.Items[I] as TJSONObject;
      Obj.TryGetValue<string>('id', AAtributos[I].Id);
      Obj.TryGetValue<string>('name', AAtributos[I].Nome);
      Obj.TryGetValue<string>('value_type', AAtributos[I].ValueType);

      AAtributos[I].Obrigatorio := False;
      AAtributos[I].PermiteVariacao := False;
      if Obj.TryGetValue<TJSONObject>('tags', TagsObj) then
      begin
        TagsObj.TryGetValue<Boolean>('required', AAtributos[I].Obrigatorio);
        TagsObj.TryGetValue<Boolean>('allow_variations', AAtributos[I].PermiteVariacao);
      end;

      SetLength(AAtributos[I].ValoresPermitidos, 0);
      if Obj.TryGetValue<TJSONArray>('values', ValoresArr) then
      begin
        N := 0;
        SetLength(AAtributos[I].ValoresPermitidos, ValoresArr.Count);
        for J := 0 to ValoresArr.Count - 1 do
        begin
          ValorObj := ValoresArr.Items[J] as TJSONObject;
          ValorId := '';
          ValorNome := '';
          ValorObj.TryGetValue<string>('id', ValorId);
          ValorObj.TryGetValue<string>('name', ValorNome);
          if (ValorId <> '') or (ValorNome <> '') then
          begin
            AAtributos[I].ValoresPermitidos[N] := ValorId + '|' + ValorNome;
            Inc(N);
          end;
        end;
        SetLength(AAtributos[I].ValoresPermitidos, N);
      end;
    end;
    Result := True;
    DoLog(Format('%d atributo(s) na categoria %s.', [Length(AAtributos), ACategoryId]));
  finally
    Raiz.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.CheckListingTypeAvailable(const AAccessToken,
  AUserId, AListingTypeId, ACategoryId: string; out ADisponivel: Boolean;
  out ACause: string; out AErrorMessage: string): Boolean;
var
  ResponseStr: string;
  StatusCode: Integer;
  JSONRoot: TJSONObject;
begin
  Result := False;
  ADisponivel := False;
  ACause := '';
  AErrorMessage := '';

  ResponseStr := ExecuteGet('/users/' + TNetEncoding.URL.Encode(AUserId) +
    '/available_listing_type/' + TNetEncoding.URL.Encode(AListingTypeId),
    'category_id=' + TNetEncoding.URL.Encode(ACategoryId), AAccessToken, StatusCode);

  DoLog('CheckListingTypeAvailable (' + AListingTypeId + '): HTTP ' +
    StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr,
      'consultar disponibilidade do tipo de anuncio');
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ResponseStr) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    JSONRoot.TryGetValue<Boolean>('available', ADisponivel);
    JSONRoot.TryGetValue<string>('cause', ACause);
    Result := True;
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.CreateItem(const AAccessToken, ABodyJSON: string;
  out AItemId, ARespostaJSON, AErrorMessage: string): Boolean;
var
  StatusCode: Integer;
  JSONRoot: TJSONObject;
begin
  Result := False;
  AItemId := '';
  AErrorMessage := '';

  DoLog('CreateItem body enviado: ' + ABodyJSON);
  ARespostaJSON := ExecutePost('/items', ABodyJSON, AAccessToken, StatusCode);
  DoLog('CreateItem: HTTP ' + StatusCode.ToString + ' ' + ARespostaJSON);

  // O Mercado Livre responde 201 na criacao; aceita 200 tambem por
  // seguranca, caso mude.
  if not (StatusCode in [200, 201]) then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ARespostaJSON, 'criar o anuncio');
    Exit;
  end;

  JSONRoot := TJSONObject.ParseJSONValue(ARespostaJSON) as TJSONObject;
  if not Assigned(JSONRoot) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    AItemId := IdComoString(JSONRoot, 'id');
    if AItemId = '' then
    begin
      AErrorMessage := 'O Mercado Livre respondeu sucesso mas não devolveu o ID do anúncio.';
      Exit;
    end;
    Result := True;
    DoLog('Anuncio criado: ' + AItemId);
  finally
    JSONRoot.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.SetItemDescription(const AAccessToken,
  AItemId, ATextoPlano: string; out AErrorMessage: string): Boolean;
var
  BodyObj: TJSONObject;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  BodyObj := TJSONObject.Create;
  try
    // TJSONObject ja cuida de escapar quebra de linha e acentuacao.
    BodyObj.AddPair('plain_text', ATextoPlano);
    BodyStr := BodyObj.ToJSON;
  finally
    BodyObj.Free;
  end;

  ResponseStr := ExecutePost('/items/' + TNetEncoding.URL.Encode(AItemId) +
    '/description', BodyStr, AAccessToken, StatusCode);

  DoLog('SetItemDescription: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if not (StatusCode in [200, 201]) then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'gravar a descricao do anuncio');
    Exit;
  end;

  Result := True;
end;

// ----------------------------------------------------------------------------
// Catalogo do Mercado Livre (oferta em cima de produto que JA existe)
// ----------------------------------------------------------------------------
// Le os campos comuns a /products/search e /products/{id} num record so -
// as duas respostas usam os MESMOS nomes de campo, so' que o detalhe traz
// mais coisa. Nao devolve nada: preenche AProduto por referencia.
procedure LerProdutoCatalogo(AObj: TJSONObject; var AProduto: TMercadoLivreProdutoCatalogo);
var
  AttrsArr, PicsArr: TJSONArray;
  AttrObj, PicObj: TJSONObject;
  I: Integer;
  NomeAttr, ValorAttr, Resumo: string;
begin
  AObj.TryGetValue<string>('id', AProduto.ProductId);
  AObj.TryGetValue<string>('name', AProduto.Nome);
  AObj.TryGetValue<string>('status', AProduto.Status);
  AObj.TryGetValue<string>('domain_id', AProduto.DomainId);
  // {ATENCAO} nem todo produto de catalogo devolve category_id (depende do
  // dominio) - por isso a leitura e' defensiva e a tela trata vazio.
  AObj.TryGetValue<string>('category_id', AProduto.CategoryId);

  // Resumo: os 3 primeiros atributos, so' pra dar contexto na lista (o
  // "name" do catalogo ja e' bem descritivo, mas dois produtos parecidos
  // costumam se diferenciar justamente nos atributos).
  Resumo := '';
  if AObj.TryGetValue<TJSONArray>('attributes', AttrsArr) then
    for I := 0 to AttrsArr.Count - 1 do
    begin
      if I >= 3 then
        Break;
      if not (AttrsArr.Items[I] is TJSONObject) then
        Continue;
      AttrObj := TJSONObject(AttrsArr.Items[I]);
      NomeAttr := '';
      ValorAttr := '';
      AttrObj.TryGetValue<string>('name', NomeAttr);
      AttrObj.TryGetValue<string>('value_name', ValorAttr);
      if (NomeAttr <> '') and (ValorAttr <> '') then
      begin
        if Resumo <> '' then
          Resumo := Resumo + ' | ';
        Resumo := Resumo + NomeAttr + ': ' + ValorAttr;
      end;
    end;
  AProduto.Resumo := Resumo;

  AProduto.PictureUrl := '';
  if AObj.TryGetValue<TJSONArray>('pictures', PicsArr) and (PicsArr.Count > 0) then
    if PicsArr.Items[0] is TJSONObject then
    begin
      PicObj := TJSONObject(PicsArr.Items[0]);
      PicObj.TryGetValue<string>('url', AProduto.PictureUrl);
    end;
end;

function TMercadoLivreOpenAPIClient.SearchCatalogProducts(const AAccessToken,
  ASiteId, ATexto: string; const ALimite: Integer;
  out AProdutos: TMercadoLivreProdutoCatalogoArray;
  out AErrorMessage: string): Boolean;
var
  ResponseStr, Query: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AProdutos, 0);

  // status=active e' obrigatorio na pratica: sem ele a busca traz produtos
  // de catalogo desativados, em cima dos quais nao da' pra publicar.
  Query := 'status=active' +
    '&site_id=' + TNetEncoding.URL.Encode(ASiteId) +
    '&q=' + TNetEncoding.URL.Encode(ATexto);
  if ALimite > 0 then
    Query := Query + '&limit=' + ALimite.ToString;

  ResponseStr := ExecuteGet('/products/search', Query, AAccessToken, StatusCode);

  DoLog('SearchCatalogProducts: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar no catalogo');
    Exit;
  end;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  if not Assigned(Raiz) then
  begin
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    // Diferente do preditor de categoria (array na raiz), aqui a resposta e'
    // um objeto com "results" - mesmo formato do orders/search.
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONArray>('results', Arr)) then
    begin
      // Nenhum resultado nao e' erro - devolve lista vazia pra tela pedir
      // outra palavra-chave.
      Result := True;
      Exit;
    end;
    SetLength(AProdutos, Arr.Count);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
        LerProdutoCatalogo(TJSONObject(Arr.Items[I]), AProdutos[I]);
    Result := True;
    DoLog(Format('%d produto(s) de catalogo encontrado(s).', [Length(AProdutos)]));
  finally
    Raiz.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.GetCatalogProduct(const AAccessToken,
  AProductId: string; out AProduto: TMercadoLivreProdutoCatalogo;
  out ARawJSON, AErrorMessage: string): Boolean;
var
  StatusCode: Integer;
  Raiz: TJSONValue;
begin
  Result := False;
  AErrorMessage := '';
  ARawJSON := '';
  AProduto := Default(TMercadoLivreProdutoCatalogo);

  ARawJSON := ExecuteGet('/products/' + TNetEncoding.URL.Encode(AProductId), '',
    AAccessToken, StatusCode);

  DoLog('GetCatalogProduct: HTTP ' + StatusCode.ToString + ' ' + ARawJSON);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ARawJSON, 'buscar o produto do catalogo');
    Exit;
  end;

  Raiz := TJSONObject.ParseJSONValue(ARawJSON);
  if not (Raiz is TJSONObject) then
  begin
    Raiz.Free;
    AErrorMessage := 'Resposta não é um JSON válido';
    Exit;
  end;
  try
    LerProdutoCatalogo(TJSONObject(Raiz), AProduto);
    Result := AProduto.ProductId <> '';
    if not Result then
      AErrorMessage := 'O Mercado Livre nao devolveu o id do produto de catalogo.';
  finally
    Raiz.Free;
  end;
end;

function TMercadoLivreOpenAPIClient.TestConnection(const AAccessToken, AAccountID: string;
  out ARespostaJSON: string): Boolean;
var
  StatusCode: Integer;
begin
  ARespostaJSON := ExecuteGet('/users/me', '', AAccessToken, StatusCode);
  DoLog('TestConnection: HTTP ' + StatusCode.ToString + ' ' + ARespostaJSON);
  Result := StatusCode = 200;
end;

end.
