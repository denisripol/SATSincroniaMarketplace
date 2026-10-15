// ============================================================================
// UNIT: TikTokShop.OpenAPI.Client
// OBJETIVO: Client REST para a TikTok Shop Partner API (v2). Cobre OAuth
// (Conectar/Desconectar/testar), pedidos, ofertas, estoque, despacho,
// etiqueta e cancelamentos.
//
// SCOPES NECESSARIOS no Partner Center (pacotes "Gerenciar a API"):
//   seller.authorization.info  -> shop_cipher (Get Authorized Shops)
//   seller.order.info          -> pedidos
//   seller.product.basic       -> ofertas (Search Products)
//   seller.product.write       -> estoque (Update Inventory) e criacao de
//                                 produto (Create Product)
//   seller.logistics           -> depositos (warehouse_id)
//   seller.fulfillment.basic   -> despachar + etiqueta
//   seller.return_refund.basic -> cancelamentos
//   seller.finance.info        -> valor de repasse (GetOrderSettlement)
// {ATENCAO} acrescentar scope depois obriga TODOS os lojistas a
// reautorizar o app - por isso a lista acima ja inclui o que ainda nao
// esta implementado.
//
// TRES COISAS QUE SAO DIFERENTES DOS OUTROS QUATRO MARKETPLACES - vale ler
// antes de mexer aqui:
//
//   1. NAO EXISTE redirect_uri na URL de autorizacao. A URL de retorno e'
//      FIXA, cadastrada no painel do app, e a URL de autorizacao so' leva
//      "service_id" (identificador do app) + "state". Por isso o service_id
//      e' um dado de DESENVOLVEDOR, guardado junto com app_key/app_secret -
//      e nao da' pra apontar o callback pra um Worker diferente por loja.
//
//   2. TODA chamada de API (menos as de token) precisa de ASSINATURA
//      HMAC-SHA256 - mais parecido com a Shopee do que com o ML/Magalu.
//      A formula esta em ComputeSign abaixo.
//
//   3. Chamada de loja precisa de shop_cipher, NAO do shop_id. O cipher e'
//      um "apelido" opaco que vem do /authorization/202309/shops e e' o que
//      identifica a loja nas chamadas seguintes. Ou seja, conectar no TikTok
//      guarda DOIS identificadores, nao um - ver a nota de armazenamento em
//      uMarketplace.ConectarTikTokShop.
//
// RESPOSTA "200 COM ERRO": como a Shopee, o TikTok responde HTTP 200 e
// sinaliza erro logico no corpo, no campo "code" (0 = sucesso). Ler so' o
// status HTTP da falso positivo - por isso todo parse aqui confere o code.
//
// SANDBOX: nao existe host separado - o ambiente de teste do TikTok e' uma
// LOJA DE TESTE nos mesmos endpoints de producao, igual ao Mercado Livre.
// Confirmado pelo cliente em 28/08/2026. O service_id tambem e' o mesmo nos
// dois ambientes (o TikTok tem um app so'), entao MARKETPLACE_APP_DEV_ID e
// MARKETPLACE_APP_DEV_ID_SANDBOX recebem o MESMO valor - diferente da
// Amazon, que tem um App ID por ambiente.
//   {ATENCAO} NAO EXISTE "app de sandbox". A loja de teste (Partner Center >
//   Kits de desenvolvimento > Lojas de Desenvolvimento do Seller Center) e
//   autorizada com as credenciais do app de PRODUCAO mesmo - confirmado na
//   pratica em 06/09/2026. O ID da loja de teste (que o painel mostra como
//   "ID do vendedor" / "ID da loja") NAO vai em campo nenhum do cadastro: ele
//   chega sozinho pela autorizacao e termina no MARKETPLACE_CLIENTID, junto
//   com o shop_cipher. Colocar esse ID no MARKETPLACE_APP_DEV_ID_SANDBOX faz
//   a tela de autorizacao responder "This service does not exist" - o erro
//   aparece no navegador, nao volta pro nosso codigo, entao o Conectar so
//   fica esperando ate estourar os 3 minutos.
//
// {ATENCAO} Esta unit foi escrita a partir da documentacao publica da
// Partner API, SEM um app real pra exercitar (a conta de desenvolvedor
// ainda vai ser criada). Os endpoints e a formula de assinatura seguem o
// que a doc descreve, mas nada aqui foi confirmado contra o servidor -
// tratar como "pronto pra testar", nao como "testado".
// ============================================================================
unit TikTokShop.OpenAPI.Client;

interface

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.JSON,
  System.NetEncoding,
  System.DateUtils,
  System.Hash,
  System.IOUtils,
  System.Net.Mime,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient;

type
  // Mesmo tipo de evento de log dos outros clients: "of object" (metodo de
  // instancia), NAO TProc<string> - as telas fazem Cliente.OnLog := Log.
  TTikTokShopLogEvent = procedure(const AMessage: string) of object;

  TTikTokShopTokenInfo = record
    Success: Boolean;
    AccessToken: string;
    RefreshToken: string;
    ExpiresIn: Integer;         // segundos ate o access_token expirar
    RefreshExpiresIn: Integer;  // segundos ate o refresh_token expirar
    OpenId: string;             // id do usuario que autorizou
    SellerName: string;
    ErrorMessage: string;
  end;

  // Uma loja autorizada. O par (ShopId, Cipher) e' o que precisa ser
  // guardado - o Cipher e' o que vai nas chamadas seguintes.
  TTikTokShopLoja = record
    ShopId: string;
    Cipher: string;
    Nome: string;
    Regiao: string;    // ex: "BR"
    Codigo: string;    // "code" - identificador curto que aparece no painel
  end;
  TTikTokShopLojaArray = TArray<TTikTokShopLoja>;

  // ==========================================================================
  // Pedidos / Ofertas / Estoque
  // --------------------------------------------------------------------------
  // {ATENCAO} TODOS os endpoints daqui pra baixo sao da familia "202309" da
  // Partner API e foram escritos a partir da documentacao publica, SEM app
  // real pra exercitar. Mesma ressalva do cabecalho da unit: pronto pra
  // testar, nao testado.
  //
  // {IMPORTANTE} No TikTok, o produto tem DOIS niveis: product_id (o anuncio)
  // e sku_id (a variacao vendida). Estoque e pedido trabalham no nivel de
  // SKU, nao de produto - por isso a chave que o projeto guarda em
  // PRODUTOS_MARKETPLACE.CODPRODUTONOMARKETPLACE e' o par
  // "product_id|sku_id" (ver SepararProdutoESkuTikTok em uMarketplace).
  // ==========================================================================

  TTikTokShopOrderItem = record
    LineItemId: string;      // line_items[].id
    ProductId: string;       // line_items[].product_id
    ProductName: string;     // line_items[].product_name
    SkuId: string;           // line_items[].sku_id
    SellerSku: string;       // line_items[].seller_sku - SKU do vendedor;
                             // vem vazio quando o anuncio nao tem SKU proprio
    SkuName: string;         // line_items[].sku_name (ex: "Azul, M")
    Quantidade: Double;      // o TikTok manda UMA LINHA POR UNIDADE - ver
                             // AgruparItensTikTok no parse
    OriginalPrice: Double;   // line_items[].original_price
    SalePrice: Double;       // line_items[].sale_price
    Currency: string;
  end;
  TTikTokShopOrderItemArray = TArray<TTikTokShopOrderItem>;

  // Resumo usado na grade de pedidos.
  TTikTokShopOrder = record
    OrderId: string;
    Status: string;          // UNPAID, AWAITING_SHIPMENT, AWAITING_COLLECTION,
                             // IN_TRANSIT, DELIVERED, COMPLETED, CANCELLED
    CreateTime: TDateTime;
    UpdateTime: TDateTime;
    TotalAmount: Double;
    Currency: string;
    BuyerEmail: string;
  end;
  TTikTokShopOrderArray = TArray<TTikTokShopOrder>;

  TTikTokShopOrderDetail = record
    OrderId: string;
    Status: string;
    CreateTime: TDateTime;
    UpdateTime: TDateTime;
    PaidTime: TDateTime;
    DeliveryTime: TDateTime;
    TotalAmount: Double;
    OriginalTotalProduct: Double;
    ShippingFee: Double;
    Currency: string;
    PaymentMethod: string;
    BuyerEmail: string;
    BuyerMessage: string;
    // {CONFIRMADO 06/09/2026} o TikTok DEVOLVE o CPF do comprador, nos campos
    // "cpf" e "cpf_name" da raiz do pedido - visto em pedido real de loja de
    // teste BR. Documentacao anterior dizia o contrario e estava errada. O
    // cpf_name e' o titular do CPF, que nao e' necessariamente o mesmo do
    // recipient_address.name (destinatario da entrega).
    Cpf: string;
    CpfName: string;
    // Endereco de entrega (recipient_address)
    RecipientName: string;
    RecipientPhone: string;
    EnderecoLinha: string;   // address_detail / full_address
    Bairro: string;
    Cidade: string;
    Estado: string;
    Cep: string;
    Pais: string;
    // Envio
    ShippingProvider: string;
    // Opcao de entrega do pedido. As transportadoras disponiveis sao POR
    // opcao de entrega, nao por loja - e' a chave do GetShippingProviders.
    DeliveryOptionId: string;
    // SELLER = envio por conta do lojista ("Shipped by seller"); nesse modo o
    // TikTok NAO emite etiqueta (erro 21042103) - ver GetShippingLabelUrl.
    ShippingType: string;
    TrackingNumber: string;
    // Pacotes do pedido - necessario pra baixar etiqueta (a etiqueta e' por
    // PACOTE, nao por pedido).
    PackageIds: TArray<string>;
    Itens: TTikTokShopOrderItemArray;
    RawJSON: string;         // resposta crua, pra montar os campos OBS da baixa
  end;

  TTikTokShopSku = record
    SkuId: string;
    SellerSku: string;
    Preco: Double;
    Currency: string;
    Estoque: Integer;
    WarehouseId: string;     // primeiro deposito com estoque - ver GetWarehouses
  end;
  TTikTokShopSkuArray = TArray<TTikTokShopSku>;

  TTikTokShopProduct = record
    ProductId: string;
    Title: string;
    Status: string;          // ACTIVATE, DRAFT, SELLER_DEACTIVATED, ...
    Skus: TTikTokShopSkuArray;
  end;
  TTikTokShopProductArray = TArray<TTikTokShopProduct>;

  TTikTokShopWarehouse = record
    Id: string;
    Nome: string;
    Tipo: string;            // SALES_WAREHOUSE / RETURN_WAREHOUSE
  end;
  TTikTokShopWarehouseArray = TArray<TTikTokShopWarehouse>;

  // Transportadora do vendedor ("Seller Shipping"). O id daqui e' obrigatorio
  // no ShipPackage quando o envio e' por conta do lojista.
  TTikTokShopTransportadora = record
    Id: string;
    Nome: string;
  end;
  TTikTokShopTransportadoraArray = TArray<TTikTokShopTransportadora>;

  // ==========================================================================
  // Cadastro de produto NOVO (publicacao de anuncio)
  // --------------------------------------------------------------------------
  // Fluxo, na mesma logica das telas da Amazon e do Mercado Livre:
  //   1. POST /product/202309/categories/recommend
  //          -> sugere a categoria a partir do titulo
  //   2. GET  /product/202309/categories/{id}/attributes
  //          -> atributos daquela categoria (variam por categoria)
  //   3. GET  /product/202309/brands
  //          -> o TikTok exige brand_id; nao aceita marca em texto livre
  //   4. POST /product/202309/images/upload
  //          -> sobe CADA imagem e devolve um "uri" interno
  //   5. POST /product/202309/products      -> cria o produto
  //
  // {ATENCAO} DUAS DIFERENCAS que quebram quem vem da tela do ML/Shopee:
  //   - IMAGEM: o TikTok NAO aceita URL publica. Cada imagem tem que ser
  //     enviada como ARQUIVO e vira um "uri" interno. Por isso a tela pede
  //     caminho de arquivo local, nao link.
  //   - ESTOQUE: o SKU criado ja nasce com estoque num DEPOSITO especifico -
  //     nao existe "estoque solto". Reaproveita o GetWarehouses.
  // ==========================================================================

  TTikTokShopCategoriaSugerida = record
    Id: string;
    Nome: string;      // nome da folha; quando vem o caminho completo, o caminho
    EhFolha: Boolean;  // so' categoria-folha aceita produto
  end;
  TTikTokShopCategoriaSugeridaArray = TArray<TTikTokShopCategoriaSugerida>;

  TTikTokShopAtributo = record
    Id: string;
    Nome: string;
    Tipo: string;              // PRODUCT_PROPERTY / SALES_PROPERTY
    Obrigatorio: Boolean;
    // Valores aceitos, no formato "id|nome" - mesmo padrao ja usado nos
    // atributos do Mercado Livre e nos motivos de recusa do TikTok.
    ValoresPermitidos: TArray<string>;
  end;
  TTikTokShopAtributoArray = TArray<TTikTokShopAtributo>;

  TTikTokShopMarca = record
    Id: string;
    Nome: string;
  end;
  TTikTokShopMarcaArray = TArray<TTikTokShopMarca>;

  TTikTokShopOpenAPIClient = class
  private
    FAppKey: string;
    FAppSecret: string;
    FServiceId: string;
    FSandbox: Boolean;
    FHTTPClient: TNetHTTPClient;
    FOnLog: TTikTokShopLogEvent;
    procedure DoLog(const AMsg: string);
    function BaseURL: string;
    function AuthBaseURL: string;
    function CurrentTimestamp: Int64;
    // Assinatura HMAC-SHA256 exigida em toda chamada de API (menos token).
    function ComputeSign(const AApiPath: string; AParams: TStrings;
      const ABody: string): string;
    // GET assinado. AParams sao os parametros ESPECIFICOS da chamada (sem
    // app_key/timestamp/sign, que sao acrescentados aqui).
    function ExecuteGetAssinado(const AApiPath: string; AParams: TStrings;
      const AAccessToken: string; out AStatusCode: Integer): string;
    // POST assinado. Diferente do GET, o CORPO tambem entra na assinatura.
    function ExecutePostAssinado(const AApiPath: string; AParams: TStrings;
      const ABodyJSON, AAccessToken: string; out AStatusCode: Integer): string;
    function ParseTokenResponse(const AResponseStr: string;
      AStatusCode: Integer): TTikTokShopTokenInfo;
  public
    constructor Create(const AAppKey, AAppSecret, AServiceId: string;
      ASandbox: Boolean);
    destructor Destroy; override;

    // Tela de autorizacao do vendedor. {ATENCAO} sem redirect_uri: o retorno
    // e' o que estiver cadastrado no painel do app (ver cabecalho da unit).
    function BuildAuthorizationURL(const AState: string): string;

    // Troca o auth_code (que chega no callback) por access/refresh token.
    // Nao leva assinatura - e' um endpoint de outro dominio.
    function ExchangeCodeForTokens(const AAuthCode: string): TTikTokShopTokenInfo;

    // Renova o access_token. {ATENCAO} o TikTok devolve um refresh_token
    // NOVO a cada renovacao - quem chama precisa regravar os dois.
    function RefreshAccessToken(const ARefreshToken: string): TTikTokShopTokenInfo;

    // Lojas que o vendedor autorizou pra este app. E' aqui que sai o
    // shop_cipher de cada loja - sem essa chamada nao da' pra fazer mais
    // nada no TikTok. Serve tambem como teste de conexao.
    function GetAuthorizedShops(const AAccessToken: string;
      out ALojas: TTikTokShopLojaArray; out AErrorMessage: string): Boolean;

    // Teste de conexao: confirma que o token responde e, quando informado,
    // que o cipher guardado ainda consta entre as lojas autorizadas.
    function TestConnection(const AAccessToken, AShopCipher: string;
      out ARespostaJSON: string): Boolean;

    // --- Pedidos ---
    // Lista os pedidos criados a partir de ADataDe. O TikTok pagina por
    // "page_token"; este metodo ja percorre todas as paginas.
    // {ATENCAO} o filtro de data e' por create_time em EPOCH (segundos).
    function GetOrders(const AAccessToken, AShopCipher: string;
      const ADataDe: TDateTime; out APedidos: TTikTokShopOrderArray;
      out AErrorMessage: string): Boolean;

    // Detalhe completo de UM pedido (GET /order/202309/orders?ids=...).
    // Devolve tambem o JSON cru, usado pra montar os campos OBS da baixa.
    function GetOrderDetail(const AAccessToken, AShopCipher, AOrderId: string;
      out ADetalhe: TTikTokShopOrderDetail; out AErrorMessage: string): Boolean;

    // URL do PDF da etiqueta de um PACOTE (nao do pedido). O TikTok nao
    // devolve o binario: devolve uma URL temporaria pra baixar.
    // {ATENCAO} ADocumentType: 'SHIPPING_LABEL' so funciona quando o envio e
    // da plataforma. Em pedido "Shipped by seller" (shipping_type = SELLER) o
    // TikTok recusa com 21042103 - nesse modo quem emite a etiqueta e a
    // transportadora do lojista, nao o marketplace. Confirmado em 06/09/2026.
    function GetShippingLabelUrl(const AAccessToken, AShopCipher, APackageId,
      ADocumentType: string;
      out AUrl: string; out AErrorMessage: string): Boolean;

    // --- Ofertas / Produtos ---
    // Produtos do vendedor, com os SKUs de cada um (id, seller_sku, preco e
    // estoque). Ja percorre todas as paginas.
    function SearchProducts(const AAccessToken, AShopCipher: string;
      out AProdutos: TTikTokShopProductArray; out AErrorMessage: string): Boolean;

    // --- Estoque ---
    // Depositos da loja. Necessario porque o update de estoque exige
    // warehouse_id, e o TikTok nao aceita "o padrao".
    function GetWarehouses(const AAccessToken, AShopCipher: string;
      out ADepositos: TTikTokShopWarehouseArray; out AErrorMessage: string): Boolean;

    // Atualiza o estoque de UM sku, num deposito.
    function UpdateInventory(const AAccessToken, AShopCipher, AProductId,
      ASkuId, AWarehouseId: string; AQuantidade: Integer;
      out AErrorMessage: string): Boolean;

    // Atualiza o PRECO de UM sku. Endpoint separado do estoque - diferente do
    // Mercado Livre, onde os dois cabem na mesma chamada.
    // {ATENCAO} nao mexe em promocao. O TikTok trata campanha e preco riscado em
    // recursos proprios; este metodo altera so' o preco de tabela do sku.
    function UpdatePrice(const AAccessToken, AShopCipher, AProductId,
      ASkuId: string; ANovoPreco: Double; out AErrorMessage: string): Boolean;

    // --- Despacho (Fulfillment Basic) ---
    // Despacha UM pacote. Dois modos, conforme o vendedor:
    //   - "TikTok Shipping": nao manda rastreio - a plataforma cuida do envio
    //     e e' so' depois desta chamada que a etiqueta fica disponivel.
    //   - "Seller Shipping": manda rastreio + id da transportadora, que vem do
    //     GetShippingProviders (pacote Logistics Basic).
    // {IMPORTANTE} O Get Package Shipping Document (a etiqueta) so' funciona
    // DEPOIS deste ShipPackage - confirmado na descricao do proprio scope no
    // Partner Center. Nao existe "gerar etiqueta antes de despachar" no TikTok.
    // Lista as transportadoras aceitas pela loja. O id devolvido aqui e' o
    // shipping_provider_id exigido pelo ShipPackage no modo Seller Shipping.
    // {ATENCAO} sem ele o TikTok recusa de duas formas diferentes, conforme o
    // caso: code 21004030 ("empty provider id") quando nao vai rastreio, e
    // code 36009004 ("ShippingProviderId of SelfShipment is a required field")
    // quando vai. Confirmado em 06/09/2026.
    function GetShippingProviders(const AAccessToken, AShopCipher,
      ADeliveryOptionId: string;
      out ATransportadoras: TTikTokShopTransportadoraArray;
      out AErrorMessage: string): Boolean;

    function ShipPackage(const AAccessToken, AShopCipher, APackageId,
      ATrackingNumber, AShippingProviderId: string;
      out AErrorMessage: string): Boolean;

    // --- Cancelamento (Return & Refund Basic) ---
    // O TikTok identifica um pedido de cancelamento por "cancel_id", NAO pelo
    // id do pedido - e a grade da tela so' tem o id do pedido. Por isso todo
    // fluxo de aprovar/reprovar comeca por esta busca.
    // Devolve ACancelId vazio (com Result = True) quando o pedido nao tem
    // cancelamento pendente - isso NAO e' erro, e' o caso normal.
    function SearchCancellations(const AAccessToken, AShopCipher, AOrderId: string;
      out ACancelId, ACancelStatus: string; out AErrorMessage: string): Boolean;

    // Aceita o cancelamento pedido pelo comprador.
    function ApproveCancellation(const AAccessToken, AShopCipher, ACancelId: string;
      out AErrorMessage: string): Boolean;

    // Recusa o cancelamento pedido pelo comprador. AReasonKey tem que ser uma
    // das chaves devolvidas por GetRejectReasons - texto livre e' recusado.
    function RejectCancellation(const AAccessToken, AShopCipher, ACancelId,
      AReasonKey: string; out AErrorMessage: string): Boolean;

    // Motivos de recusa aceitos para ESTE cancelamento. Cada item vem no
    // formato "chave|descricao" pra tela poder mostrar o texto e enviar a
    // chave, mesmo padrao usado nos valores de atributo do Mercado Livre.
    function GetRejectReasons(const AAccessToken, AShopCipher, ACancelId: string;
      out AMotivos: TArray<string>; out AErrorMessage: string): Boolean;

    // --- Financeiro (Finance Information) ---
    // Valor LIQUIDO efetivamente repassado ao vendedor por UM pedido, mais o
    // total de tarifas descontadas. E' o equivalente do escrow da Shopee e do
    // NetAmount da Finances API da Amazon.
    // {ATENCAO} so' responde depois que o TikTok LIQUIDA o pedido - pedido
    // recem-pago ainda nao tem lancamento, e nesse caso devolve False com uma
    // mensagem explicando (nao e' erro de integracao).
    function GetOrderSettlement(const AAccessToken, AShopCipher, AOrderId: string;
      out ASettlementAmount, AFeeAmount: Double; out ACurrency: string;
      out AErrorMessage: string): Boolean;

    // --- Cadastro de produto novo (ver bloco de tipos la em cima) ---
    // Sugere a categoria a partir do titulo. So' categoria-FOLHA aceita
    // produto - o campo EhFolha do resultado diz quais servem.
    function RecommendCategory(const AAccessToken, AShopCipher, ATitulo: string;
      out ACategorias: TTikTokShopCategoriaSugeridaArray;
      out AErrorMessage: string): Boolean;

    // Atributos de uma categoria. Devolve tambem o JSON cru, pra tela poder
    // mostrar a lista completa sem baixar de novo (mesmo padrao do "Ver
    // Atributos" das telas da Amazon e do Mercado Livre).
    function GetCategoryAttributes(const AAccessToken, AShopCipher,
      ACategoryId: string; out AAtributos: TTikTokShopAtributoArray;
      out ARawJSON, AErrorMessage: string): Boolean;

    // Marcas. {ATENCAO} o TikTok exige brand_id no produto - nao aceita marca
    // em texto livre, diferente da Shopee.
    function GetBrands(const AAccessToken, AShopCipher, AFiltroNome: string;
      out AMarcas: TTikTokShopMarcaArray; out AErrorMessage: string): Boolean;

    // Sobe UMA imagem e devolve o "uri" interno do TikTok, que e' o que vai
    // no corpo do CreateProduct. {ATENCAO} nao existe caminho por URL publica:
    // tem que ser arquivo local.
    // {ATENCAO} este e o unico endpoint do arquivo que NAO leva shop_cipher
    // - a imagem nao pertence a uma loja, e mandar o parametro faz o TikTok
    // responder HTTP 400 com code 36009004 ("The 'shop_cipher' query
    // parameter is not required for this request"). Confirmado em
    // 06/09/2026. Por isso nem recebe o cipher aqui: sem o parametro na
    // assinatura do metodo, ninguem reintroduz por engano.
    function UploadProductImage(const AAccessToken,
      ACaminhoArquivo: string; out AUri: string;
      out AErrorMessage: string): Boolean;

    // Cria o produto. ABodyJSON e' o payload completo montado pela tela.
    // {IMPORTANTE} devolve product_id E o sku_id do primeiro SKU criado: a
    // chave que o projeto guarda em PRODUTOS_MARKETPLACE e' o par
    // "product_id|sku_id", e sem o sku_id o F2 de estoque nao funciona.
    function CreateProduct(const AAccessToken, AShopCipher, ABodyJSON: string;
      out AProductId, ASkuId, ARespostaJSON, AErrorMessage: string): Boolean;

    property OnLog: TTikTokShopLogEvent read FOnLog write FOnLog;
  end;

function HMACSHA256Hex(const AKey, AMessage: string): string;

implementation

function HMACSHA256Hex(const AKey, AMessage: string): string;
begin
  // Mesma ordem de parametros usada no client da Shopee: primeiro os dados
  // (a string base a assinar), depois a chave secreta.
  Result := LowerCase(THashSHA2.GetHMAC(AMessage, AKey, THashSHA2.TSHA2Version.SHA256));
end;

// Erro logico do TikTok: HTTP 200 com "code" != 0 no corpo. Devolve '' quando
// a resposta indica sucesso, ou a mensagem pronta quando indica erro.
function ErroLogicoTikTok(const AResponseStr, AContexto: string): string;
var
  Raiz: TJSONValue;
  Code: Integer;
  Mensagem: string;
begin
  Result := '';
  Raiz := TJSONObject.ParseJSONValue(AResponseStr);
  if not (Raiz is TJSONObject) then
  begin
    Raiz.Free;
    Result := Format('Resposta invalida ao %s: %s', [AContexto, AResponseStr]);
    Exit;
  end;
  try
    Code := -1;
    TJSONObject(Raiz).TryGetValue<Integer>('code', Code);
    if Code = 0 then
      Exit;
    Mensagem := '';
    TJSONObject(Raiz).TryGetValue<string>('message', Mensagem);
    Result := Format('Erro %d ao %s: %s', [Code, AContexto,
      IfThen(Mensagem = '', AResponseStr, Mensagem)]);
  finally
    Raiz.Free;
  end;
end;

function FormatarErroHTTP(AStatusCode: Integer; const AResponseStr, AContexto: string): string;
begin
  Result := Format('HTTP %d ao %s: %s', [AStatusCode, AContexto, AResponseStr]);
end;

{ TTikTokShopOpenAPIClient }

constructor TTikTokShopOpenAPIClient.Create(const AAppKey, AAppSecret,
  AServiceId: string; ASandbox: Boolean);
begin
  inherited Create;
  FAppKey := AAppKey;
  FAppSecret := AAppSecret;
  FServiceId := AServiceId;
  FSandbox := ASandbox;
  FHTTPClient := TNetHTTPClient.Create(nil);
  FHTTPClient.ConnectionTimeout := 30000;
  FHTTPClient.ResponseTimeout := 30000;
end;

destructor TTikTokShopOpenAPIClient.Destroy;
begin
  FHTTPClient.Free;
  inherited;
end;

procedure TTikTokShopOpenAPIClient.DoLog(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

function TTikTokShopOpenAPIClient.BaseURL: string;
begin
  // {ATENCAO} O TikTok NAO tem um host de sandbox separado: o ambiente de
  // teste e' uma LOJA DE TESTE batendo nos MESMOS endpoints de producao -
  // mesma situacao do Mercado Livre (ver o cabecalho daquele client).
  // Por isso FSandbox NAO muda a URL base, e existe aqui so' por
  // consistencia de interface com Shopee/Amazon/Magalu, que tem host proprio.
  Result := 'https://open-api.tiktokglobalshop.com';
end;

function TTikTokShopOpenAPIClient.AuthBaseURL: string;
begin
  // Dominio de TOKEN e' outro, e nao muda entre producao e sandbox.
  Result := 'https://auth.tiktok-shops.com';
end;

function TTikTokShopOpenAPIClient.CurrentTimestamp: Int64;
begin
  Result := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now));
end;

function TTikTokShopOpenAPIClient.ComputeSign(const AApiPath: string;
  AParams: TStrings; const ABody: string): string;
var
  Chaves: TStringList;
  BaseString, Nome: string;
  I: Integer;
begin
  // Formula documentada pelo TikTok:
  //   1. pega os parametros de query, MENOS "sign" e "access_token";
  //   2. ordena por nome;
  //   3. concatena nome+valor, sem separador nenhum;
  //   4. poe o caminho da API na frente;
  //   5. poe o corpo (quando houver JSON) no fim;
  //   6. envolve tudo com o app_secret nas DUAS pontas;
  //   7. HMAC-SHA256 com o app_secret, em hex minusculo.
  // {ATENCAO} os valores entram CRUS aqui (sem URL-encode) - o encode e' so'
  // pra montar a URL. Assinar o valor codificado e' o erro classico dessa API.
  Chaves := TStringList.Create;
  try
    for I := 0 to AParams.Count - 1 do
    begin
      Nome := AParams.Names[I];
      if (Nome = '') or SameText(Nome, 'sign') or SameText(Nome, 'access_token') then
        Continue;
      Chaves.Add(Nome);
    end;
    Chaves.Sort;

    BaseString := AApiPath;
    for I := 0 to Chaves.Count - 1 do
      BaseString := BaseString + Chaves[I] + AParams.Values[Chaves[I]];

    if ABody <> '' then
      BaseString := BaseString + ABody;

    BaseString := FAppSecret + BaseString + FAppSecret;
  finally
    Chaves.Free;
  end;
  Result := HMACSHA256Hex(FAppSecret, BaseString);
end;

function TTikTokShopOpenAPIClient.ExecuteGetAssinado(const AApiPath: string;
  AParams: TStrings; const AAccessToken: string; out AStatusCode: Integer): string;
var
  Params: TStringList;
  URL, QueryStr, Nome: string;
  Headers: TNetHeaders;
  Response: IHTTPResponse;
  I: Integer;
begin
  Params := TStringList.Create;
  try
    // Copia os parametros da chamada e acrescenta os obrigatorios de toda
    // requisicao. O "sign" so' pode ser calculado depois que todos os outros
    // ja estao na lista.
    if Assigned(AParams) then
      Params.Assign(AParams);
    Params.Values['app_key'] := FAppKey;
    Params.Values['timestamp'] := IntToStr(CurrentTimestamp);
    Params.Values['sign'] := ComputeSign(AApiPath, Params, '');

    QueryStr := '';
    for I := 0 to Params.Count - 1 do
    begin
      Nome := Params.Names[I];
      if Nome = '' then
        Continue;
      if QueryStr <> '' then
        QueryStr := QueryStr + '&';
      QueryStr := QueryStr + Nome + '=' +
        TNetEncoding.URL.Encode(Params.Values[Nome]);
    end;

    URL := BaseURL + AApiPath;
    if QueryStr <> '' then
      URL := URL + '?' + QueryStr;
  finally
    Params.Free;
  end;

  // O access token do TikTok vai em HEADER proprio (x-tts-access-token), nao
  // como "Authorization: Bearer" e nem como parametro de query.
  Headers := [TNetHeader.Create('x-tts-access-token', AAccessToken),
              TNetHeader.Create('Content-Type', 'application/json')];

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

function TTikTokShopOpenAPIClient.BuildAuthorizationURL(const AState: string): string;
begin
  // {ATENCAO} sem redirect_uri de proposito - ver item 1 do cabecalho.
  Result := 'https://services.tiktokshop.com/open/authorize' +
    '?service_id=' + TNetEncoding.URL.Encode(FServiceId) +
    '&state=' + TNetEncoding.URL.Encode(AState);
end;

function TTikTokShopOpenAPIClient.ParseTokenResponse(const AResponseStr: string;
  AStatusCode: Integer): TTikTokShopTokenInfo;
var
  Raiz: TJSONValue;
  Obj, DataObj: TJSONObject;
  Code: Integer;
  Mensagem: string;
begin
  Result := Default(TTikTokShopTokenInfo);

  if AStatusCode <> 200 then
  begin
    Result.ErrorMessage := FormatarErroHTTP(AStatusCode, AResponseStr,
      'obter/renovar token');
    Exit;
  end;

  Raiz := TJSONObject.ParseJSONValue(AResponseStr);
  if not (Raiz is TJSONObject) then
  begin
    Raiz.Free;
    Result.ErrorMessage := 'Resposta do token nao e um JSON valido: ' + AResponseStr;
    Exit;
  end;
  try
    Obj := TJSONObject(Raiz);
    Code := -1;
    Obj.TryGetValue<Integer>('code', Code);
    if Code <> 0 then
    begin
      Mensagem := '';
      Obj.TryGetValue<string>('message', Mensagem);
      Result.ErrorMessage := Format('Erro %d ao obter/renovar token: %s',
        [Code, IfThen(Mensagem = '', AResponseStr, Mensagem)]);
      Exit;
    end;

    if not Obj.TryGetValue<TJSONObject>('data', DataObj) then
    begin
      Result.ErrorMessage := 'Resposta do token sem o bloco "data": ' + AResponseStr;
      Exit;
    end;

    DataObj.TryGetValue<string>('access_token', Result.AccessToken);
    DataObj.TryGetValue<string>('refresh_token', Result.RefreshToken);
    DataObj.TryGetValue<string>('open_id', Result.OpenId);
    DataObj.TryGetValue<string>('seller_name', Result.SellerName);
    // {ATENCAO} o TikTok manda a EXPIRACAO ABSOLUTA (epoch em segundos) nos
    // campos *_expire_in, nao a duracao. Converte pra "segundos a partir de
    // agora" aqui, pra ficar igual aos outros clients (Shopee/ML/Magalu
    // mandam duracao) e o chamador poder fazer IncSecond(Now, ExpiresIn)
    // sem se preocupar com qual e' qual.
    DataObj.TryGetValue<Integer>('access_token_expire_in', Result.ExpiresIn);
    DataObj.TryGetValue<Integer>('refresh_token_expire_in', Result.RefreshExpiresIn);
    if Result.ExpiresIn > 1000000000 then
      Result.ExpiresIn := Result.ExpiresIn - CurrentTimestamp;
    if Result.RefreshExpiresIn > 1000000000 then
      Result.RefreshExpiresIn := Result.RefreshExpiresIn - CurrentTimestamp;

    Result.Success := Result.AccessToken <> '';
    if not Result.Success then
      Result.ErrorMessage := 'O TikTok nao devolveu access_token: ' + AResponseStr;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.ExchangeCodeForTokens(
  const AAuthCode: string): TTikTokShopTokenInfo;
var
  URL, ResponseStr: string;
  Response: IHTTPResponse;
  StatusCode: Integer;
begin
  // {ATENCAO} os endpoints de token NAO levam assinatura e ficam em outro
  // dominio (auth.tiktok-shops.com) - por isso nao passam pelo
  // ExecuteGetAssinado. O app_secret vai na propria query aqui.
  URL := AuthBaseURL + '/api/v2/token/get' +
    '?app_key=' + TNetEncoding.URL.Encode(FAppKey) +
    '&app_secret=' + TNetEncoding.URL.Encode(FAppSecret) +
    '&auth_code=' + TNetEncoding.URL.Encode(AAuthCode) +
    '&grant_type=authorized_code';

  StatusCode := 0;
  ResponseStr := '';
  try
    Response := FHTTPClient.Get(URL);
    StatusCode := Response.StatusCode;
    ResponseStr := Response.ContentAsString(TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Result := Default(TTikTokShopTokenInfo);
      Result.ErrorMessage := 'Erro na chamada de troca de codigo por token: ' + E.Message;
      DoLog(Result.ErrorMessage);
      Exit;
    end;
  end;

  // {IMPORTANTE} nao logar a URL: ela carrega o app_secret em texto puro.
  DoLog('ExchangeCodeForTokens: HTTP ' + StatusCode.ToString);
  Result := ParseTokenResponse(ResponseStr, StatusCode);
  if not Result.Success then
    DoLog(Result.ErrorMessage);
end;

function TTikTokShopOpenAPIClient.RefreshAccessToken(
  const ARefreshToken: string): TTikTokShopTokenInfo;
var
  URL, ResponseStr: string;
  Response: IHTTPResponse;
  StatusCode: Integer;
begin
  URL := AuthBaseURL + '/api/v2/token/refresh' +
    '?app_key=' + TNetEncoding.URL.Encode(FAppKey) +
    '&app_secret=' + TNetEncoding.URL.Encode(FAppSecret) +
    '&refresh_token=' + TNetEncoding.URL.Encode(ARefreshToken) +
    '&grant_type=refresh_token';

  StatusCode := 0;
  ResponseStr := '';
  try
    Response := FHTTPClient.Get(URL);
    StatusCode := Response.StatusCode;
    ResponseStr := Response.ContentAsString(TEncoding.UTF8);
  except
    on E: Exception do
    begin
      Result := Default(TTikTokShopTokenInfo);
      Result.ErrorMessage := 'Erro na chamada de renovacao de token: ' + E.Message;
      DoLog(Result.ErrorMessage);
      Exit;
    end;
  end;

  DoLog('RefreshAccessToken: HTTP ' + StatusCode.ToString);
  Result := ParseTokenResponse(ResponseStr, StatusCode);
  if not Result.Success then
    DoLog(Result.ErrorMessage);
end;

function TTikTokShopOpenAPIClient.GetAuthorizedShops(const AAccessToken: string;
  out ALojas: TTikTokShopLojaArray; out AErrorMessage: string): Boolean;
const
  API_PATH = '/authorization/202309/shops';
var
  ResponseStr: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, ShopObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(ALojas, 0);

  ResponseStr := ExecuteGetAssinado(API_PATH, nil, AAccessToken, StatusCode);
  DoLog('GetAuthorizedShops: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'listar as lojas autorizadas');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'listar as lojas autorizadas');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('shops', Arr)) then
    begin
      // Sem lojas nao e' erro de chamada - e' vendedor que autorizou o app
      // mas nao vinculou nenhuma loja. Quem chama trata isso.
      Result := True;
      Exit;
    end;

    SetLength(ALojas, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      ShopObj := TJSONObject(Arr.Items[I]);
      ShopObj.TryGetValue<string>('id', ALojas[I].ShopId);
      ShopObj.TryGetValue<string>('cipher', ALojas[I].Cipher);
      ShopObj.TryGetValue<string>('name', ALojas[I].Nome);
      ShopObj.TryGetValue<string>('region', ALojas[I].Regiao);
      ShopObj.TryGetValue<string>('code', ALojas[I].Codigo);
    end;
    Result := True;
    DoLog(Format('%d loja(s) autorizada(s).', [Length(ALojas)]));
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.GetShippingProviders(const AAccessToken,
  AShopCipher, ADeliveryOptionId: string;
  out ATransportadoras: TTikTokShopTransportadoraArray;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, ProvObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(ATransportadoras, 0);

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecuteGetAssinado('/logistics/202309/delivery_options/' +
      TNetEncoding.URL.Encode(ADeliveryOptionId) + '/shipping_providers',
      Params, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetShippingProviders: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr,
      'listar as transportadoras');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'listar as transportadoras');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('shipping_providers', Arr)) then
    begin
      // Sem lista nao e' erro de chamada - a tela avisa e oferece digitar o id.
      Result := True;
      Exit;
    end;
    SetLength(ATransportadoras, Arr.Count);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        ProvObj := TJSONObject(Arr.Items[I]);
        ProvObj.TryGetValue<string>('id', ATransportadoras[I].Id);
        ProvObj.TryGetValue<string>('name', ATransportadoras[I].Nome);
      end;
    Result := True;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.ShipPackage(const AAccessToken, AShopCipher,
  APackageId, ATrackingNumber, AShippingProviderId: string;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  Body, SelfObj: TJSONObject;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  if Trim(APackageId) = '' then
  begin
    AErrorMessage := 'Pedido sem pacote gerado - nao ha o que despachar.';
    Exit;
  end;

  Body := TJSONObject.Create;
  try
    // Corpo vazio = "TikTok Shipping" (a plataforma cuida do envio). Com
    // rastreio = "Seller Shipping" (o vendedor usa transportadora propria).
    if Trim(ATrackingNumber) <> '' then
    begin
      SelfObj := TJSONObject.Create;
      SelfObj.AddPair('tracking_number', Trim(ATrackingNumber));
      if Trim(AShippingProviderId) <> '' then
        SelfObj.AddPair('shipping_provider_id', Trim(AShippingProviderId));
      Body.AddPair('self_shipment', SelfObj);
    end;
    BodyStr := Body.ToJSON;
  finally
    Body.Free;
  end;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecutePostAssinado(
      '/fulfillment/202309/packages/' + TNetEncoding.URL.Encode(APackageId) + '/ship',
      Params, BodyStr, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('ShipPackage (' + APackageId + '): HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'despachar o pacote');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'despachar o pacote');
  Result := AErrorMessage = '';
end;

function TTikTokShopOpenAPIClient.SearchCancellations(const AAccessToken,
  AShopCipher, AOrderId: string; out ACancelId, ACancelStatus: string;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  Body: TJSONObject;
  IdsArr: TJSONArray;
  BodyStr, ResponseStr: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, CancelObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  ACancelId := '';
  ACancelStatus := '';

  Body := TJSONObject.Create;
  try
    IdsArr := TJSONArray.Create;
    IdsArr.Add(AOrderId);
    Body.AddPair('order_ids', IdsArr);
    BodyStr := Body.ToJSON;
  finally
    Body.Free;
  end;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    Params.Values['page_size'] := '20';
    ResponseStr := ExecutePostAssinado('/return_refund/202309/cancellations/search',
      Params, BodyStr, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('SearchCancellations (' + AOrderId + '): HTTP ' + StatusCode.ToString +
    ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar o cancelamento');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'buscar o cancelamento');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    // Sem bloco/lista = pedido sem cancelamento pendente. Result = True com
    // ACancelId vazio: quem chama trata isso como "nao ha o que aprovar".
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('cancellations', Arr)) then
    begin
      Result := True;
      Exit;
    end;
    // Pega o primeiro que ainda esta aguardando decisao do vendedor. Se
    // nenhum estiver, devolve o primeiro mesmo - a API dira' que nao cabe
    // acao, com mensagem melhor do que qualquer chute nosso.
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      CancelObj := TJSONObject(Arr.Items[I]);
      if ACancelId = '' then
      begin
        CancelObj.TryGetValue<string>('cancel_id', ACancelId);
        CancelObj.TryGetValue<string>('cancel_status', ACancelStatus);
      end;
      if CancelObj.GetValue<string>('cancel_status', '').ToUpper.Contains('PENDING') then
      begin
        CancelObj.TryGetValue<string>('cancel_id', ACancelId);
        CancelObj.TryGetValue<string>('cancel_status', ACancelStatus);
        Break;
      end;
    end;
    Result := True;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.ApproveCancellation(const AAccessToken,
  AShopCipher, ACancelId: string; out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecutePostAssinado(
      '/return_refund/202309/cancellations/' + TNetEncoding.URL.Encode(ACancelId) +
      '/approve', Params, '{}', AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('ApproveCancellation (' + ACancelId + '): HTTP ' + StatusCode.ToString +
    ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'aprovar o cancelamento');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'aprovar o cancelamento');
  Result := AErrorMessage = '';
end;

function TTikTokShopOpenAPIClient.RejectCancellation(const AAccessToken,
  AShopCipher, ACancelId, AReasonKey: string; out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  Body: TJSONObject;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  Body := TJSONObject.Create;
  try
    // {ATENCAO} o motivo NAO e' texto livre: tem que ser uma das chaves que o
    // GetRejectReasons devolve pra ESTE cancelamento.
    Body.AddPair('decision_reason', AReasonKey);
    BodyStr := Body.ToJSON;
  finally
    Body.Free;
  end;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecutePostAssinado(
      '/return_refund/202309/cancellations/' + TNetEncoding.URL.Encode(ACancelId) +
      '/reject', Params, BodyStr, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('RejectCancellation (' + ACancelId + '): HTTP ' + StatusCode.ToString +
    ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'reprovar o cancelamento');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'reprovar o cancelamento');
  Result := AErrorMessage = '';
end;

function TTikTokShopOpenAPIClient.GetRejectReasons(const AAccessToken,
  AShopCipher, ACancelId: string; out AMotivos: TArray<string>;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr, Chave, Texto: string;
  StatusCode, I, Total: Integer;
  Raiz: TJSONValue;
  DataObj, MotivoObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AMotivos, 0);

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    Params.Values['cancel_or_return_id'] := ACancelId;
    Params.Values['locale'] := 'pt-BR';
    ResponseStr := ExecuteGetAssinado('/return_refund/202309/reject_reasons',
      Params, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetRejectReasons (' + ACancelId + '): HTTP ' + StatusCode.ToString +
    ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'listar os motivos de recusa');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'listar os motivos de recusa');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('reject_reasons', Arr)) then
    begin
      Result := True; // sem lista nao e' erro de chamada
      Exit;
    end;
    SetLength(AMotivos, Arr.Count);
    Total := 0;
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      MotivoObj := TJSONObject(Arr.Items[I]);
      Chave := '';
      Texto := '';
      MotivoObj.TryGetValue<string>('reason', Chave);
      MotivoObj.TryGetValue<string>('reason_text', Texto);
      if Chave = '' then
        Continue;
      // "chave|descricao" - a tela mostra a descricao e envia a chave.
      AMotivos[Total] := Chave + '|' + IfThen(Texto = '', Chave, Texto);
      Inc(Total);
    end;
    SetLength(AMotivos, Total);
    Result := True;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.GetOrderSettlement(const AAccessToken,
  AShopCipher, AOrderId: string; out ASettlementAmount, AFeeAmount: Double;
  out ACurrency: string; out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr, Valor: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, TransObj: TJSONObject;
  Arr: TJSONArray;
  Achou: Boolean;
begin
  Result := False;
  AErrorMessage := '';
  ASettlementAmount := 0;
  AFeeAmount := 0;
  ACurrency := '';
  Achou := False;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecuteGetAssinado(
      '/finance/202309/orders/' + TNetEncoding.URL.Encode(AOrderId) +
      '/statement_transactions', Params, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetOrderSettlement (' + AOrderId + '): HTTP ' + StatusCode.ToString +
    ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr,
      'obter o repasse do pedido');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'obter o repasse do pedido');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('statement_transactions', Arr)) then
    begin
      // Pedido ainda nao liquidado (o TikTok so' gera a transacao depois de
      // fechar o ciclo financeiro) - NAO e' erro de chamada, e' cedo demais.
      AErrorMessage := 'O TikTok ainda nao gerou o lancamento financeiro deste ' +
        'pedido - o repasse so fica disponivel depois da liquidacao.';
      Exit;
    end;

    // Um pedido pode ter MAIS DE UM lancamento (venda, ajuste, reembolso
    // parcial) - soma todos, senao o repasse de um pedido com ajuste sai
    // errado. Mesmo raciocinio do escrow da Shopee, que ja e' um valor
    // consolidado.
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      TransObj := TJSONObject(Arr.Items[I]);
      // {ATENCAO} valores monetarios do TikTok vem como STRING, aqui tambem.
      if TransObj.TryGetValue<string>('settlement_amount', Valor) then
      begin
        ASettlementAmount := ASettlementAmount +
          StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
        Achou := True;
      end;
      if TransObj.TryGetValue<string>('fee_amount', Valor) then
        AFeeAmount := AFeeAmount + StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
      if ACurrency = '' then
        TransObj.TryGetValue<string>('currency', ACurrency);
    end;

    Result := Achou;
    if not Result then
      AErrorMessage := 'O TikTok devolveu lancamentos sem o valor de repasse ' +
        '(settlement_amount): ' + ResponseStr;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.RecommendCategory(const AAccessToken,
  AShopCipher, ATitulo: string; out ACategorias: TTikTokShopCategoriaSugeridaArray;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  Body: TJSONObject;
  BodyStr, ResponseStr, FolhaId: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, CatObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(ACategorias, 0);

  Body := TJSONObject.Create;
  try
    Body.AddPair('product_title', ATitulo);
    BodyStr := Body.ToJSON;
  finally
    Body.Free;
  end;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecutePostAssinado('/product/202309/categories/recommend',
      Params, BodyStr, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('RecommendCategory: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'sugerir a categoria');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'sugerir a categoria');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj)) then
    begin
      Result := True; // sem sugestao nao e' erro
      Exit;
    end;

    // O TikTok devolve a folha recomendada em leaf_category_id e, quando
    // existe, o caminho ate' ela em categories[]. A tela precisa da FOLHA:
    // categoria intermediaria nao aceita produto.
    FolhaId := '';
    DataObj.TryGetValue<string>('leaf_category_id', FolhaId);

    if DataObj.TryGetValue<TJSONArray>('categories', Arr) and (Arr.Count > 0) then
    begin
      SetLength(ACategorias, Arr.Count);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then
          Continue;
        CatObj := TJSONObject(Arr.Items[I]);
        CatObj.TryGetValue<string>('id', ACategorias[I].Id);
        CatObj.TryGetValue<string>('local_name', ACategorias[I].Nome);
        if ACategorias[I].Nome = '' then
          CatObj.TryGetValue<string>('name', ACategorias[I].Nome);
        if not CatObj.TryGetValue<Boolean>('is_leaf', ACategorias[I].EhFolha) then
          ACategorias[I].EhFolha := (FolhaId <> '') and (ACategorias[I].Id = FolhaId);
      end;
    end
    else if FolhaId <> '' then
    begin
      // So veio o id da folha, sem o caminho - devolve ela sozinha.
      SetLength(ACategorias, 1);
      ACategorias[0].Id := FolhaId;
      ACategorias[0].Nome := '(categoria recomendada)';
      ACategorias[0].EhFolha := True;
    end;

    Result := True;
    DoLog(Format('%d categoria(s) sugerida(s).', [Length(ACategorias)]));
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.GetCategoryAttributes(const AAccessToken,
  AShopCipher, ACategoryId: string; out AAtributos: TTikTokShopAtributoArray;
  out ARawJSON, AErrorMessage: string): Boolean;
var
  Params: TStringList;
  StatusCode, I, J, Total: Integer;
  Raiz: TJSONValue;
  DataObj, AttrObj, ValObj: TJSONObject;
  Arr, ValsArr: TJSONArray;
  Chave, Texto: string;
begin
  Result := False;
  AErrorMessage := '';
  ARawJSON := '';
  SetLength(AAtributos, 0);

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    Params.Values['locale'] := 'pt-BR';
    ARawJSON := ExecuteGetAssinado(
      '/product/202309/categories/' + TNetEncoding.URL.Encode(ACategoryId) +
      '/attributes', Params, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetCategoryAttributes: HTTP ' + StatusCode.ToString + ' ' + ARawJSON);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ARawJSON, 'listar os atributos da categoria');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ARawJSON, 'listar os atributos da categoria');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ARawJSON);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('attributes', Arr)) then
    begin
      Result := True; // categoria sem atributo declarado nao e' erro
      Exit;
    end;

    SetLength(AAtributos, Arr.Count);
    Total := 0;
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      AttrObj := TJSONObject(Arr.Items[I]);
      AttrObj.TryGetValue<string>('id', AAtributos[Total].Id);
      AttrObj.TryGetValue<string>('name', AAtributos[Total].Nome);
      AttrObj.TryGetValue<string>('type', AAtributos[Total].Tipo);
      if not AttrObj.TryGetValue<Boolean>('is_requried', AAtributos[Total].Obrigatorio) then
        // {ATENCAO} a doc do TikTok tem o campo grafado "is_requried" (com o
        // erro de digitacao) em algumas versoes e "is_required" em outras -
        // tenta os dois em vez de assumir um.
        AttrObj.TryGetValue<Boolean>('is_required', AAtributos[Total].Obrigatorio);

      if AttrObj.TryGetValue<TJSONArray>('values', ValsArr) then
      begin
        SetLength(AAtributos[Total].ValoresPermitidos, ValsArr.Count);
        for J := 0 to ValsArr.Count - 1 do
        begin
          if not (ValsArr.Items[J] is TJSONObject) then
            Continue;
          ValObj := TJSONObject(ValsArr.Items[J]);
          Chave := '';
          Texto := '';
          ValObj.TryGetValue<string>('id', Chave);
          ValObj.TryGetValue<string>('name', Texto);
          AAtributos[Total].ValoresPermitidos[J] := Chave + '|' + Texto;
        end;
      end;
      Inc(Total);
    end;
    SetLength(AAtributos, Total);
    Result := True;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.GetBrands(const AAccessToken, AShopCipher,
  AFiltroNome: string; out AMarcas: TTikTokShopMarcaArray;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, MarcaObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AMarcas, 0);

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    Params.Values['page_size'] := '50';
    if Trim(AFiltroNome) <> '' then
      Params.Values['brand_name'] := Trim(AFiltroNome);
    ResponseStr := ExecuteGetAssinado('/product/202309/brands', Params,
      AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetBrands: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'listar as marcas');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'listar as marcas');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('brands', Arr)) then
    begin
      Result := True;
      Exit;
    end;
    SetLength(AMarcas, Arr.Count);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        MarcaObj := TJSONObject(Arr.Items[I]);
        MarcaObj.TryGetValue<string>('id', AMarcas[I].Id);
        MarcaObj.TryGetValue<string>('name', AMarcas[I].Nome);
      end;
    Result := True;
    DoLog(Format('%d marca(s) encontrada(s).', [Length(AMarcas)]));
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.UploadProductImage(const AAccessToken,
  ACaminhoArquivo: string; out AUri: string;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/product/202309/images/upload';
var
  Params: TStringList;
  URL, QueryStr, Nome, ResponseStr: string;
  Headers: TNetHeaders;
  FormData: TMultipartFormData;
  Response: IHTTPResponse;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  AUri := '';

  if not TFile.Exists(ACaminhoArquivo) then
  begin
    AErrorMessage := 'Arquivo de imagem nao encontrado: ' + ACaminhoArquivo;
    Exit;
  end;

  Params := TStringList.Create;
  try
    // Sem shop_cipher aqui de proposito - ver a nota na declaracao.
    Params.Values['app_key'] := FAppKey;
    Params.Values['timestamp'] := IntToStr(CurrentTimestamp);
    // {ATENCAO} em multipart o CORPO NAO entra na assinatura - so' os
    // parametros de query. Assinar o arquivo junto faria toda chamada de
    // upload falhar com erro de assinatura.
    Params.Values['sign'] := ComputeSign(API_PATH, Params, '');

    QueryStr := '';
    for I := 0 to Params.Count - 1 do
    begin
      Nome := Params.Names[I];
      if Nome = '' then
        Continue;
      if QueryStr <> '' then
        QueryStr := QueryStr + '&';
      QueryStr := QueryStr + Nome + '=' + TNetEncoding.URL.Encode(Params.Values[Nome]);
    end;
    URL := BaseURL + API_PATH + '?' + QueryStr;
  finally
    Params.Free;
  end;

  DoLog('Enviando imagem para o TikTok: ' + ExtractFileName(ACaminhoArquivo));

  FormData := TMultipartFormData.Create;
  try
    FormData.AddFile('data', ACaminhoArquivo);
    FormData.AddField('use_case', 'MAIN_IMAGE');
    Headers := [TNetHeader.Create('x-tts-access-token', AAccessToken)];
    try
      Response := FHTTPClient.Post(URL, FormData, nil, Headers);
      StatusCode := Response.StatusCode;
      ResponseStr := Response.ContentAsString(TEncoding.UTF8);
    except
      on E: Exception do
      begin
        AErrorMessage := 'Erro no envio da imagem: ' + E.Message;
        DoLog(AErrorMessage);
        Exit;
      end;
    end;
  finally
    FormData.Free;
  end;

  DoLog('UploadProductImage: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'enviar a imagem');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'enviar a imagem');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if (Raiz is TJSONObject) and
       TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) then
      DataObj.TryGetValue<string>('uri', AUri);
    Result := AUri <> '';
    if not Result then
      AErrorMessage := 'O TikTok nao devolveu o identificador da imagem: ' + ResponseStr;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.CreateProduct(const AAccessToken, AShopCipher,
  ABodyJSON: string; out AProductId, ASkuId, ARespostaJSON,
  AErrorMessage: string): Boolean;
var
  Params: TStringList;
  StatusCode: Integer;
  Raiz: TJSONValue;
  DataObj, SkuObj: TJSONObject;
  SkusArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  AProductId := '';
  ASkuId := '';

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ARespostaJSON := ExecutePostAssinado('/product/202309/products', Params,
      ABodyJSON, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('CreateProduct: HTTP ' + StatusCode.ToString + ' ' + ARespostaJSON);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ARespostaJSON, 'criar o produto');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ARespostaJSON, 'criar o produto');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ARespostaJSON);
  try
    if (Raiz is TJSONObject) and
       TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) then
    begin
      DataObj.TryGetValue<string>('product_id', AProductId);
      // Pega o sku_id do PRIMEIRO SKU. A tela cria um SKU so' por produto; se
      // um dia passar a criar variacoes, isso precisa devolver a lista toda.
      if DataObj.TryGetValue<TJSONArray>('skus', SkusArr) and (SkusArr.Count > 0) and
         (SkusArr.Items[0] is TJSONObject) then
      begin
        SkuObj := TJSONObject(SkusArr.Items[0]);
        SkuObj.TryGetValue<string>('id', ASkuId);
      end;
    end;
    Result := AProductId <> '';
    if not Result then
      AErrorMessage := 'O TikTok nao devolveu o id do produto criado: ' + ARespostaJSON
    else if ASkuId = '' then
      // Produto criado mas sem sku_id na resposta: a tela avisa, porque o
      // vinculo com o produto fisico fica incompleto (F2 nao vai funcionar).
      DoLog('Aviso: o TikTok criou o produto ' + AProductId + ' mas nao devolveu ' +
        'o sku_id - o vinculo em PRODUTOS_MARKETPLACE ficara incompleto.');
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.TestConnection(const AAccessToken,
  AShopCipher: string; out ARespostaJSON: string): Boolean;
var
  Lojas: TTikTokShopLojaArray;
  ErroMsg: string;
  I: Integer;
begin
  ARespostaJSON := '';
  Result := GetAuthorizedShops(AAccessToken, Lojas, ErroMsg);
  if not Result then
  begin
    ARespostaJSON := ErroMsg;
    Exit;
  end;

  if Length(Lojas) = 0 then
  begin
    Result := False;
    ARespostaJSON := 'O token respondeu, mas nenhuma loja esta autorizada para ' +
      'este aplicativo. Refaca a autorizacao escolhendo a loja.';
    Exit;
  end;

  // Cipher informado: confere se a loja guardada ainda esta na lista. Sem
  // isso, uma loja removida da autorizacao passaria no teste "porque o token
  // funciona", e so' quebraria depois, na primeira chamada de pedido.
  if AShopCipher <> '' then
  begin
    for I := Low(Lojas) to High(Lojas) do
      if Lojas[I].Cipher = AShopCipher then
        Exit; // Result ja e' True
    Result := False;
    ARespostaJSON := 'A loja conectada nao consta mais entre as lojas autorizadas ' +
      'deste aplicativo. Desconecte e conecte novamente.';
  end;
end;

// ----------------------------------------------------------------------------
// Pedidos / Ofertas / Estoque
// ----------------------------------------------------------------------------

// Converte epoch em segundos (formato que o TikTok usa em TODOS os campos de
// data) pra TDateTime local. Zero/ausente vira 0, nao 01/01/1970.
function EpochParaDataLocal(const AEpoch: Int64): TDateTime;
begin
  if AEpoch <= 0 then
    Result := 0
  else
    Result := TTimeZone.Local.ToLocalTime(UnixToDateTime(AEpoch));
end;

function DataLocalParaEpoch(const AData: TDateTime): Int64;
begin
  Result := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(AData));
end;

// {IMPORTANTE} o TikTok devolve UMA LINHA POR UNIDADE vendida em line_items:
// comprar 3 do mesmo SKU gera 3 entradas com quantidade implicita 1, cada uma
// com seu proprio line_item_id. Nenhum outro marketplace do projeto faz isso -
// Shopee/ML/Amazon/Magalu mandam quantidade agregada. Sem agrupar aqui, a
// baixa no SAT geraria 3 linhas de IOE de 1 unidade em vez de 1 linha de 3.
procedure AgruparItensTikTok(var AItens: TTikTokShopOrderItemArray);
var
  Agrupados: TTikTokShopOrderItemArray;
  I, J, Total: Integer;
  Achou: Boolean;
begin
  SetLength(Agrupados, Length(AItens));
  Total := 0;
  for I := Low(AItens) to High(AItens) do
  begin
    Achou := False;
    for J := 0 to Total - 1 do
      // Agrupa por SKU + preco: mesmo SKU com preco diferente (promocao
      // aplicada a parte das unidades) tem que continuar em linhas separadas,
      // senao o total da linha nao bate com o do pedido.
      if (Agrupados[J].SkuId = AItens[I].SkuId) and
         (Agrupados[J].SalePrice = AItens[I].SalePrice) then
      begin
        Agrupados[J].Quantidade := Agrupados[J].Quantidade + AItens[I].Quantidade;
        // Guarda os line_item_id todos, separados por virgula - o de-para
        // manda o id do item pro campo OBS, e perder os demais atrapalharia
        // conferencia depois.
        Agrupados[J].LineItemId := Agrupados[J].LineItemId + ',' + AItens[I].LineItemId;
        Achou := True;
        Break;
      end;
    if not Achou then
    begin
      Agrupados[Total] := AItens[I];
      Inc(Total);
    end;
  end;
  SetLength(Agrupados, Total);
  AItens := Agrupados;
end;

function TTikTokShopOpenAPIClient.ExecutePostAssinado(const AApiPath: string;
  AParams: TStrings; const ABodyJSON, AAccessToken: string;
  out AStatusCode: Integer): string;
var
  Params: TStringList;
  URL, QueryStr, Nome: string;
  Headers: TNetHeaders;
  BodyStream: TStringStream;
  Response: IHTTPResponse;
  I: Integer;
begin
  Params := TStringList.Create;
  try
    if Assigned(AParams) then
      Params.Assign(AParams);
    Params.Values['app_key'] := FAppKey;
    Params.Values['timestamp'] := IntToStr(CurrentTimestamp);
    // {ATENCAO} no POST o CORPO entra na assinatura - por isso ComputeSign
    // recebe ABodyJSON aqui e string vazia no GET.
    Params.Values['sign'] := ComputeSign(AApiPath, Params, ABodyJSON);

    QueryStr := '';
    for I := 0 to Params.Count - 1 do
    begin
      Nome := Params.Names[I];
      if Nome = '' then
        Continue;
      if QueryStr <> '' then
        QueryStr := QueryStr + '&';
      QueryStr := QueryStr + Nome + '=' + TNetEncoding.URL.Encode(Params.Values[Nome]);
    end;

    URL := BaseURL + AApiPath;
    if QueryStr <> '' then
      URL := URL + '?' + QueryStr;
  finally
    Params.Free;
  end;

  Headers := [TNetHeader.Create('x-tts-access-token', AAccessToken),
              TNetHeader.Create('Content-Type', 'application/json')];

  BodyStream := TStringStream.Create(ABodyJSON, TEncoding.UTF8);
  try
    try
      Response := FHTTPClient.Post(URL, BodyStream, nil, Headers);
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

// Le os campos de um objeto "order" (o mesmo formato aparece no
// orders/search e no orders?ids=, so' que o segundo traz mais campos).
procedure LerResumoPedidoTikTok(AObj: TJSONObject; var APedido: TTikTokShopOrder);
var
  Epoch: Int64;
  PayObj: TJSONObject;
  Valor: string;
begin
  AObj.TryGetValue<string>('id', APedido.OrderId);
  AObj.TryGetValue<string>('status', APedido.Status);
  Epoch := 0;
  if AObj.TryGetValue<Int64>('create_time', Epoch) then
    APedido.CreateTime := EpochParaDataLocal(Epoch);
  Epoch := 0;
  if AObj.TryGetValue<Int64>('update_time', Epoch) then
    APedido.UpdateTime := EpochParaDataLocal(Epoch);
  AObj.TryGetValue<string>('buyer_email', APedido.BuyerEmail);
  if AObj.TryGetValue<TJSONObject>('payment', PayObj) then
  begin
    // {ATENCAO} o TikTok manda valores monetarios como STRING ("123.45"),
    // nao como numero - ler como Double direto devolve 0.
    if PayObj.TryGetValue<string>('total_amount', Valor) then
      APedido.TotalAmount := StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
    PayObj.TryGetValue<string>('currency', APedido.Currency);
  end;
end;

// Cidade/estado/bairro do TikTok nao sao campos soltos: vem em
// district_info[], um array com um nivel por granularidade, identificado por
// "address_level" (L0=pais, L1=estado, L2=cidade, L3=bairro). Le por nivel e
// cai pro "address_level_name" em texto quando o codigo nao vier.
procedure LerNiveisEnderecoTikTok(AEndObj: TJSONObject;
  var AEstado, ACidade, ABairro: string);
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Nivel, NomeNivel, Nome: string;
begin
  if not AEndObj.TryGetValue<TJSONArray>('district_info', Arr) then
    Exit;
  for I := 0 to Arr.Count - 1 do
  begin
    if not (Arr.Items[I] is TJSONObject) then
      Continue;
    Obj := TJSONObject(Arr.Items[I]);
    Nivel := '';
    NomeNivel := '';
    Nome := '';
    Obj.TryGetValue<string>('address_level', Nivel);
    Obj.TryGetValue<string>('address_level_name', NomeNivel);
    Obj.TryGetValue<string>('address_name', Nome);
    if Nome = '' then
      Continue;
    if SameText(Nivel, 'L1') or SameText(NomeNivel, 'State') then
      AEstado := Nome
    else if SameText(Nivel, 'L2') or SameText(NomeNivel, 'City') then
      ACidade := Nome
    else if SameText(Nivel, 'L3') or SameText(NomeNivel, 'District') then
      ABairro := Nome;
  end;
end;

function TTikTokShopOpenAPIClient.GetOrders(const AAccessToken, AShopCipher: string;
  const ADataDe: TDateTime; out APedidos: TTikTokShopOrderArray;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/order/202309/orders/search';
var
  Params: TStringList;
  BodyJSON: TJSONObject;
  ResponseStr, BodyStr, PageToken: string;
  StatusCode, I, Total, Paginas: Integer;
  Raiz: TJSONValue;
  DataObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(APedidos, 0);
  Total := 0;
  PageToken := '';
  Paginas := 0;

  BodyJSON := TJSONObject.Create;
  try
    BodyJSON.AddPair('create_time_ge', TJSONNumber.Create(DataLocalParaEpoch(ADataDe)));
    BodyStr := BodyJSON.ToJSON;
  finally
    BodyJSON.Free;
  end;

  repeat
    Params := TStringList.Create;
    try
      Params.Values['shop_cipher'] := AShopCipher;
      Params.Values['page_size'] := '50';
      Params.Values['sort_field'] := 'create_time';
      Params.Values['sort_order'] := 'DESC';
      if PageToken <> '' then
        Params.Values['page_token'] := PageToken;
      ResponseStr := ExecutePostAssinado(API_PATH, Params, BodyStr, AAccessToken, StatusCode);
    finally
      Params.Free;
    end;

    DoLog('GetOrders: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

    if StatusCode <> 200 then
    begin
      AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar pedidos');
      Exit;
    end;

    AErrorMessage := ErroLogicoTikTok(ResponseStr, 'buscar pedidos');
    if AErrorMessage <> '' then
      Exit;

    PageToken := '';
    Raiz := TJSONObject.ParseJSONValue(ResponseStr);
    try
      if not ((Raiz is TJSONObject) and
              TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj)) then
      begin
        Result := True; // sem "data" = sem pedidos, nao e' erro
        Exit;
      end;

      if DataObj.TryGetValue<TJSONArray>('orders', Arr) then
      begin
        SetLength(APedidos, Total + Arr.Count);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            LerResumoPedidoTikTok(TJSONObject(Arr.Items[I]), APedidos[Total]);
            Inc(Total);
          end;
        SetLength(APedidos, Total);
      end;

      DataObj.TryGetValue<string>('next_page_token', PageToken);
    finally
      Raiz.Free;
    end;

    Inc(Paginas);
    // Trava de seguranca: 40 paginas x 50 = 2000 pedidos. Passou disso, e'
    // filtro de data errado ou loop de paginacao - melhor parar e avisar do
    // que ficar chamando a API pra sempre.
    if Paginas >= 40 then
    begin
      DoLog('Aviso: parou na pagina 40 de pedidos (limite de seguranca) - ' +
        'reduza o periodo consultado se faltou pedido.');
      Break;
    end;
  until PageToken = '';

  Result := True;
  DoLog(Format('%d pedido(s) encontrado(s) em %d pagina(s).', [Length(APedidos), Paginas]));
end;

function TTikTokShopOpenAPIClient.GetOrderDetail(const AAccessToken, AShopCipher,
  AOrderId: string; out ADetalhe: TTikTokShopOrderDetail;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/order/202309/orders';
var
  Params: TStringList;
  ResponseStr, Valor: string;
  StatusCode, I: Integer;
  Epoch: Int64;
  Raiz: TJSONValue;
  DataObj, OrderObj, PayObj, EndObj, ItemObj, PacoteObj: TJSONObject;
  Arr, ItensArr, PacotesArr: TJSONArray;
  Resumo: TTikTokShopOrder;
  Itens: TTikTokShopOrderItemArray;
begin
  Result := False;
  AErrorMessage := '';
  ADetalhe := Default(TTikTokShopOrderDetail);

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    Params.Values['ids'] := AOrderId;
    ResponseStr := ExecuteGetAssinado(API_PATH, Params, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetOrderDetail: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar detalhe do pedido');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'buscar detalhe do pedido');
  if AErrorMessage <> '' then
    Exit;

  ADetalhe.RawJSON := ResponseStr;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('orders', Arr) and
            (Arr.Count > 0) and (Arr.Items[0] is TJSONObject)) then
    begin
      AErrorMessage := 'O TikTok nao devolveu o pedido ' + AOrderId + '.';
      Exit;
    end;
    OrderObj := TJSONObject(Arr.Items[0]);

    // Campos que o resumo ja sabe ler (id/status/datas/total/moeda/email)
    Resumo := Default(TTikTokShopOrder);
    LerResumoPedidoTikTok(OrderObj, Resumo);
    ADetalhe.OrderId := Resumo.OrderId;
    ADetalhe.Status := Resumo.Status;
    ADetalhe.CreateTime := Resumo.CreateTime;
    ADetalhe.UpdateTime := Resumo.UpdateTime;
    ADetalhe.TotalAmount := Resumo.TotalAmount;
    ADetalhe.Currency := Resumo.Currency;
    ADetalhe.BuyerEmail := Resumo.BuyerEmail;

    Epoch := 0;
    if OrderObj.TryGetValue<Int64>('paid_time', Epoch) then
      ADetalhe.PaidTime := EpochParaDataLocal(Epoch);
    Epoch := 0;
    if OrderObj.TryGetValue<Int64>('delivery_time', Epoch) then
      ADetalhe.DeliveryTime := EpochParaDataLocal(Epoch);

    OrderObj.TryGetValue<string>('payment_method_name', ADetalhe.PaymentMethod);
    OrderObj.TryGetValue<string>('buyer_message', ADetalhe.BuyerMessage);
    OrderObj.TryGetValue<string>('cpf', ADetalhe.Cpf);
    OrderObj.TryGetValue<string>('cpf_name', ADetalhe.CpfName);
    OrderObj.TryGetValue<string>('shipping_provider', ADetalhe.ShippingProvider);
    OrderObj.TryGetValue<string>('delivery_option_id', ADetalhe.DeliveryOptionId);
    OrderObj.TryGetValue<string>('shipping_type', ADetalhe.ShippingType);
    OrderObj.TryGetValue<string>('tracking_number', ADetalhe.TrackingNumber);

    // Valores monetarios do bloco payment vem como STRING (ver nota em
    // LerResumoPedidoTikTok).
    if OrderObj.TryGetValue<TJSONObject>('payment', PayObj) then
    begin
      if PayObj.TryGetValue<string>('shipping_fee', Valor) then
        ADetalhe.ShippingFee := StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
      if PayObj.TryGetValue<string>('original_total_product_price', Valor) then
        ADetalhe.OriginalTotalProduct := StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
    end;

    if OrderObj.TryGetValue<TJSONObject>('recipient_address', EndObj) then
    begin
      EndObj.TryGetValue<string>('name', ADetalhe.RecipientName);
      EndObj.TryGetValue<string>('phone_number', ADetalhe.RecipientPhone);
      EndObj.TryGetValue<string>('address_detail', ADetalhe.EnderecoLinha);
      if ADetalhe.EnderecoLinha = '' then
        EndObj.TryGetValue<string>('full_address', ADetalhe.EnderecoLinha);
      EndObj.TryGetValue<string>('postal_code', ADetalhe.Cep);
      EndObj.TryGetValue<string>('region_code', ADetalhe.Pais);
      // {ATENCAO} cidade/estado/bairro do TikTok vem dentro de
      // district_info[], um array com um nivel por granularidade
      // (pais > estado > cidade > bairro), identificado por
      // "address_level_name". Le por nivel, do maior pro menor.
      LerNiveisEnderecoTikTok(EndObj, ADetalhe.Estado, ADetalhe.Cidade, ADetalhe.Bairro);
    end;

    if OrderObj.TryGetValue<TJSONArray>('packages', PacotesArr) then
    begin
      SetLength(ADetalhe.PackageIds, PacotesArr.Count);
      for I := 0 to PacotesArr.Count - 1 do
        if PacotesArr.Items[I] is TJSONObject then
        begin
          PacoteObj := TJSONObject(PacotesArr.Items[I]);
          PacoteObj.TryGetValue<string>('id', ADetalhe.PackageIds[I]);
        end;
    end;

    if OrderObj.TryGetValue<TJSONArray>('line_items', ItensArr) then
    begin
      SetLength(Itens, ItensArr.Count);
      for I := 0 to ItensArr.Count - 1 do
      begin
        if not (ItensArr.Items[I] is TJSONObject) then
          Continue;
        ItemObj := TJSONObject(ItensArr.Items[I]);
        ItemObj.TryGetValue<string>('id', Itens[I].LineItemId);
        ItemObj.TryGetValue<string>('product_id', Itens[I].ProductId);
        ItemObj.TryGetValue<string>('product_name', Itens[I].ProductName);
        ItemObj.TryGetValue<string>('sku_id', Itens[I].SkuId);
        ItemObj.TryGetValue<string>('seller_sku', Itens[I].SellerSku);
        ItemObj.TryGetValue<string>('sku_name', Itens[I].SkuName);
        ItemObj.TryGetValue<string>('currency', Itens[I].Currency);
        if ItemObj.TryGetValue<string>('original_price', Valor) then
          Itens[I].OriginalPrice := StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
        if ItemObj.TryGetValue<string>('sale_price', Valor) then
          Itens[I].SalePrice := StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
        // Uma linha = uma unidade (ver AgruparItensTikTok).
        Itens[I].Quantidade := 1;
      end;
      AgruparItensTikTok(Itens);
      ADetalhe.Itens := Itens;
    end;

    Result := ADetalhe.OrderId <> '';
    if not Result then
      AErrorMessage := 'O TikTok devolveu o pedido sem id.';
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.GetShippingLabelUrl(const AAccessToken,
  AShopCipher, APackageId, ADocumentType: string; out AUrl: string;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr: string;
  StatusCode: Integer;
  Raiz: TJSONValue;
  DataObj: TJSONObject;
begin
  Result := False;
  AErrorMessage := '';
  AUrl := '';

  if Trim(APackageId) = '' then
  begin
    AErrorMessage := 'Pedido sem pacote gerado - nao ha etiqueta. Lembrando ' +
      'que o TikTok so libera a etiqueta DEPOIS do despacho (Ship Package).';
    Exit;
  end;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    Params.Values['document_type'] := ADocumentType;
    Params.Values['document_size'] := 'A6';
    ResponseStr := ExecuteGetAssinado(
      '/fulfillment/202309/packages/' + TNetEncoding.URL.Encode(APackageId) +
      '/shipping_documents', Params, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetShippingLabelUrl: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'obter a etiqueta');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'obter a etiqueta');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if (Raiz is TJSONObject) and
       TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) then
      DataObj.TryGetValue<string>('doc_url', AUrl);
    Result := AUrl <> '';
    if not Result then
      AErrorMessage := 'O TikTok respondeu sem a URL da etiqueta: ' + ResponseStr;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.SearchProducts(const AAccessToken,
  AShopCipher: string; out AProdutos: TTikTokShopProductArray;
  out AErrorMessage: string): Boolean;
const
  API_PATH = '/product/202309/products/search';
var
  Params: TStringList;
  ResponseStr, PageToken, Valor: string;
  StatusCode, I, J, K, Total, Paginas, Qtd: Integer;
  Raiz: TJSONValue;
  DataObj, ProdObj, SkuObj, PrecoObj, InvObj: TJSONObject;
  Arr, SkusArr, InvArr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(AProdutos, 0);
  Total := 0;
  PageToken := '';
  Paginas := 0;

  repeat
    Params := TStringList.Create;
    try
      Params.Values['shop_cipher'] := AShopCipher;
      Params.Values['page_size'] := '50';
      if PageToken <> '' then
        Params.Values['page_token'] := PageToken;
      // Corpo vazio: sem filtro de status, pra trazer tambem o que esta
      // pausado/reprovado - a tela mostra o status e o usuario decide.
      ResponseStr := ExecutePostAssinado(API_PATH, Params, '{}', AAccessToken, StatusCode);
    finally
      Params.Free;
    end;

    DoLog('SearchProducts: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

    if StatusCode <> 200 then
    begin
      AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'buscar produtos');
      Exit;
    end;

    AErrorMessage := ErroLogicoTikTok(ResponseStr, 'buscar produtos');
    if AErrorMessage <> '' then
      Exit;

    PageToken := '';
    Raiz := TJSONObject.ParseJSONValue(ResponseStr);
    try
      if not ((Raiz is TJSONObject) and
              TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj)) then
      begin
        Result := True;
        Exit;
      end;

      if DataObj.TryGetValue<TJSONArray>('products', Arr) then
      begin
        SetLength(AProdutos, Total + Arr.Count);
        for I := 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[I] is TJSONObject) then
            Continue;
          ProdObj := TJSONObject(Arr.Items[I]);
          ProdObj.TryGetValue<string>('id', AProdutos[Total].ProductId);
          ProdObj.TryGetValue<string>('title', AProdutos[Total].Title);
          ProdObj.TryGetValue<string>('status', AProdutos[Total].Status);

          if ProdObj.TryGetValue<TJSONArray>('skus', SkusArr) then
          begin
            SetLength(AProdutos[Total].Skus, SkusArr.Count);
            for J := 0 to SkusArr.Count - 1 do
            begin
              if not (SkusArr.Items[J] is TJSONObject) then
                Continue;
              SkuObj := TJSONObject(SkusArr.Items[J]);
              SkuObj.TryGetValue<string>('id', AProdutos[Total].Skus[J].SkuId);
              SkuObj.TryGetValue<string>('seller_sku', AProdutos[Total].Skus[J].SellerSku);
              if SkuObj.TryGetValue<TJSONObject>('price', PrecoObj) then
              begin
                // {ATENCAO} o TikTok nao usa um campo so' pra preco, e nem sempre
                // manda os tres. Visto em 14/10/2026, sandbox e producao: veio
                // apenas "tax_exclusive_price", sem "sale_price" nenhum - e como o
                // codigo so' lia sale_price, a tela mostrava 0,00 pra todo produto.
                // Le na ordem do mais especifico pro mais generico. Valor vem como
                // STRING, igual todo monetario deles.
                Valor := '';
                if not PrecoObj.TryGetValue<string>('sale_price', Valor) then
                  if not PrecoObj.TryGetValue<string>('tax_inclusive_price', Valor) then
                    PrecoObj.TryGetValue<string>('tax_exclusive_price', Valor);
                if Valor <> '' then
                  AProdutos[Total].Skus[J].Preco :=
                    StrToFloatDef(Valor, 0, TFormatSettings.Invariant);
                PrecoObj.TryGetValue<string>('currency', AProdutos[Total].Skus[J].Currency);
              end;
              // Estoque e' por DEPOSITO - soma todos e guarda o primeiro
              // warehouse_id, que e' o usado no update (ver UpdateInventory).
              if SkuObj.TryGetValue<TJSONArray>('inventory', InvArr) then
                for K := 0 to InvArr.Count - 1 do
                  if InvArr.Items[K] is TJSONObject then
                  begin
                    InvObj := TJSONObject(InvArr.Items[K]);
                    Qtd := 0;
                    InvObj.TryGetValue<Integer>('quantity', Qtd);
                    AProdutos[Total].Skus[J].Estoque :=
                      AProdutos[Total].Skus[J].Estoque + Qtd;
                    if AProdutos[Total].Skus[J].WarehouseId = '' then
                      InvObj.TryGetValue<string>('warehouse_id',
                        AProdutos[Total].Skus[J].WarehouseId);
                  end;
            end;
          end;
          Inc(Total);
        end;
        SetLength(AProdutos, Total);
      end;

      DataObj.TryGetValue<string>('next_page_token', PageToken);
    finally
      Raiz.Free;
    end;

    Inc(Paginas);
    if Paginas >= 40 then
    begin
      DoLog('Aviso: parou na pagina 40 de produtos (limite de seguranca).');
      Break;
    end;
  until PageToken = '';

  Result := True;
  DoLog(Format('%d produto(s) encontrado(s) em %d pagina(s).', [Length(AProdutos), Paginas]));
end;

function TTikTokShopOpenAPIClient.GetWarehouses(const AAccessToken,
  AShopCipher: string; out ADepositos: TTikTokShopWarehouseArray;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  ResponseStr: string;
  StatusCode, I: Integer;
  Raiz: TJSONValue;
  DataObj, WhObj: TJSONObject;
  Arr: TJSONArray;
begin
  Result := False;
  AErrorMessage := '';
  SetLength(ADepositos, 0);

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecuteGetAssinado('/logistics/202309/warehouses', Params,
      AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('GetWarehouses: HTTP ' + StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'listar os depositos');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'listar os depositos');
  if AErrorMessage <> '' then
    Exit;

  Raiz := TJSONObject.ParseJSONValue(ResponseStr);
  try
    if not ((Raiz is TJSONObject) and
            TJSONObject(Raiz).TryGetValue<TJSONObject>('data', DataObj) and
            DataObj.TryGetValue<TJSONArray>('warehouses', Arr)) then
    begin
      Result := True;
      Exit;
    end;
    SetLength(ADepositos, Arr.Count);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        WhObj := TJSONObject(Arr.Items[I]);
        WhObj.TryGetValue<string>('id', ADepositos[I].Id);
        WhObj.TryGetValue<string>('name', ADepositos[I].Nome);
        WhObj.TryGetValue<string>('type', ADepositos[I].Tipo);
      end;
    Result := True;
  finally
    Raiz.Free;
  end;
end;

function TTikTokShopOpenAPIClient.UpdateInventory(const AAccessToken, AShopCipher,
  AProductId, ASkuId, AWarehouseId: string; AQuantidade: Integer;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  Body, SkuObj, InvObj: TJSONObject;
  SkusArr, InvArr: TJSONArray;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';

  if (AProductId = '') or (ASkuId = '') then
  begin
    AErrorMessage := 'Vinculo do TikTok incompleto: e necessario product_id E sku_id ' +
      '(o campo CODPRODUTONOMARKETPLACE guarda os dois separados por "|").';
    Exit;
  end;
  if AWarehouseId = '' then
  begin
    AErrorMessage := 'Deposito (warehouse_id) nao informado - o TikTok exige ele no ' +
      'update de estoque, nao existe "deposito padrao".';
    Exit;
  end;

  Body := TJSONObject.Create;
  try
    InvObj := TJSONObject.Create;
    InvObj.AddPair('warehouse_id', AWarehouseId);
    InvObj.AddPair('quantity', TJSONNumber.Create(AQuantidade));
    InvArr := TJSONArray.Create;
    InvArr.AddElement(InvObj);

    SkuObj := TJSONObject.Create;
    SkuObj.AddPair('id', ASkuId);
    SkuObj.AddPair('inventory', InvArr);

    SkusArr := TJSONArray.Create;
    SkusArr.AddElement(SkuObj);
    Body.AddPair('skus', SkusArr);
    BodyStr := Body.ToJSON;
  finally
    Body.Free;
  end;

  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecutePostAssinado(
      '/product/202309/products/' + TNetEncoding.URL.Encode(AProductId) +
      '/inventory/update', Params, BodyStr, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;

  DoLog('UpdateInventory (' + AProductId + '/' + ASkuId + '): HTTP ' +
    StatusCode.ToString + ' ' + ResponseStr);

  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'atualizar estoque');
    Exit;
  end;

  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'atualizar estoque');
  Result := AErrorMessage = '';
end;

function TTikTokShopOpenAPIClient.UpdatePrice(const AAccessToken, AShopCipher,
  AProductId, ASkuId: string; ANovoPreco: Double;
  out AErrorMessage: string): Boolean;
var
  Params: TStringList;
  Body, SkuObj, PrecoObj: TJSONObject;
  SkusArr: TJSONArray;
  BodyStr, ResponseStr: string;
  StatusCode: Integer;
begin
  Result := False;
  AErrorMessage := '';
  if (AProductId = '') or (ASkuId = '') then
  begin
    AErrorMessage := 'Vinculo do TikTok incompleto: e necessario product_id E sku_id ' +
      '(o campo CODPRODUTONOMARKETPLACE guarda os dois separados por "|").';
    Exit;
  end;
  if ANovoPreco <= 0 then
  begin
    AErrorMessage := 'Preco invalido (zero ou negativo) - nada enviado.';
    Exit;
  end;
  Body := TJSONObject.Create;
  try
    PrecoObj := TJSONObject.Create;
    // {ATENCAO} valor monetario vai como STRING no TikTok, nunca como numero -
    // mesma regra do cadastro de produto e do peso. Numero faz a chamada falhar
    // com erro de tipo, nao de valor, o que confunde o diagnostico.
    PrecoObj.AddPair('amount', FormatFloat('0.00', ANovoPreco,
      TFormatSettings.Invariant));
    PrecoObj.AddPair('currency', 'BRL');
    SkuObj := TJSONObject.Create;
    SkuObj.AddPair('id', ASkuId);
    SkuObj.AddPair('price', PrecoObj);
    SkusArr := TJSONArray.Create;
    SkusArr.AddElement(SkuObj);
    Body.AddPair('skus', SkusArr);
    BodyStr := Body.ToJSON;
  finally
    Body.Free;
  end;
  Params := TStringList.Create;
  try
    Params.Values['shop_cipher'] := AShopCipher;
    ResponseStr := ExecutePostAssinado(
      '/product/202309/products/' + TNetEncoding.URL.Encode(AProductId) +
      '/prices/update', Params, BodyStr, AAccessToken, StatusCode);
  finally
    Params.Free;
  end;
  DoLog('UpdatePrice (' + AProductId + '/' + ASkuId + '): HTTP ' +
    StatusCode.ToString + ' ' + ResponseStr);
  if StatusCode <> 200 then
  begin
    AErrorMessage := FormatarErroHTTP(StatusCode, ResponseStr, 'atualizar preco');
    Exit;
  end;
  AErrorMessage := ErroLogicoTikTok(ResponseStr, 'atualizar preco');
  Result := AErrorMessage = '';
end;

end.
