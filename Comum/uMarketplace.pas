unit uMarketplace;

interface
  uses
    System.SysUtils, System.Classes, System.DateUtils, System.SyncObjs,
    System.IniFiles, System.IOUtils, System.StrUtils, System.JSON,
    System.NetEncoding,
    Winapi.Windows, Winapi.ShellAPI,
    Vcl.Forms, // Application.ProcessMessages
    IdHTTPServer, IdContext, IdCustomHTTPServer, IdGlobal,
    DM, SATFuncoesBD, {uDOOCA, uTRAY, uiFoodMercado,} DMZ,
    Shopee.OpenAPI.Client,
    Amazon.SPAPI.Client,
    Magalu.OpenAPI.Client,
    MercadoLivre.OpenAPI.Client,
    TikTokShop.OpenAPI.Client;

type
  // {ATENCAO} a ORDEM aqui e' a mesma do combo dbcmbTipoSATEcommerce do
  // SATLojas (LOJAS.dfm: Items.Strings + Values.Strings) e o valor ordinal
  // vai gravado em LOJAS.Cashback_TipoServidor / MARKETPLACE_COD. Marketplace
  // novo entra sempre NO FIM - inserir no meio renumera todos os seguintes e
  // corrompe o que ja esta gravado no banco do cliente.
  TMarketplaces = (Nenhum, VTex, Bagy, Tray, iFoodMercado, NuvemShop, Shopee, MercadoLivre, Magalu, Amazon, TikTokShop);

  TMarketplace = record
    Cod: TMarketplaces;
    Loja: String;
    Key: String;
    App: String;
    Token: String;
    ClientId: String;
    ClientSecret: String;
    UsuarioDB: String;
    SenhaDB: String;
    // --- Campos adicionados para os marketplaces OAuth (Shopee/Mercado Livre/
    // Magalu/Amazon). Nao remexi nos campos acima pra nao quebrar nada que ja
    // usa Key/ClientId/ClientSecret pro Tray/iFood/etc - so acrescentei.
    // AccountID e String (nao Int64!) porque o Seller ID da Amazon e' alfa-
    // numerico (ex: "A1B2C3D4E5") - o Shop ID numerico da Shopee e' convertido
    // pra String aqui e de volta pra Int64 internamente so' quando chama o
    // TShopeeOpenAPIClient (que exige Int64 na assinatura dele).
    AccountID: String;      // Shop ID (Shopee) / Seller ID (ML, Magalu, Amazon)
    RefreshToken: String;
    TokenExpiraEm: TDateTime;

    // --- Campos novos: credenciais de desenvolvedor agora vem do banco
    // (tabela Lojas), nao mais de arquivo .ini. O CHAMADOR (SATLojas ou
    // SATSincroniaMarketplace) preenche esses campos ANTES de chamar
    // Conectar/Desconectar/TestarConexao, lendo da loja certa:
    //   ClientId     -> Shopee: Partner ID (Dev) | Amazon/Magalu: Client ID (Dev)
    //   ClientSecret -> Shopee: Partner Key (Dev) | Amazon/Magalu: Client Secret (Dev)
    //   App          -> Amazon: Application ID (Dev) - nao usado por Shopee/Magalu
    //   Sandbox      -> True = Homologacao, False = Producao (persistido na
    //                   loja em MARKETPLACE_SANDBOX - AJUSTAR o nome do campo
    //                   se o real usado no banco for diferente)
    Sandbox: Boolean;
    // So usado no atalho Amazon+Homologacao: token colado manualmente no
    // memo exclusivo da tela (Sandbox Application do Solution Provider
    // Portal nao tem fluxo de login, so entrega um refresh token pronto).
    RefreshTokenManualSandbox: String;
  end;

  { TMarketplaceOAuthListener
    Servidor HTTP local temporario, generico para qualquer marketplace OAuth.
    Sobe numa porta livre em 127.0.0.1, espera UMA requisicao de callback
    (que a pagina-ponte do Cloudflare Worker devolve via fetch() em JS depois
    que o vendedor autoriza a loja no navegador), e derruba sozinho.
    Reaproveitado por Shopee agora, e por Mercado Livre/Magalu/Amazon depois. }
  TMarketplaceOAuthResultado = record
    Recebido: Boolean;
    Sucesso: Boolean;
    Code: string;
    AccountID: string;   // shop_id / selling_partner_id / seller_id, conforme o marketplace
    MensagemErro: string;
  end;

  TMarketplaceOAuthListener = class
  private
    FServer: TIdHTTPServer;
    FPorta: Integer;
    FState: string;
    FResultado: TMarketplaceOAuthResultado;
    FLock: TCriticalSection;
    procedure OnCommandGet(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    function PortaEstaLivre(const APorta: Integer): Boolean;
    function EncontrarPortaLivre: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Iniciar: string;                                 // devolve o "state" (porta embutida)
    function AguardarCallback(const ATimeoutSegundos: Integer = 180): Boolean;
    procedure Parar;
    property Resultado: TMarketplaceOAuthResultado read FResultado;
    property State: string read FState;
  end;

  TDClassPadraoMarketplaces = class(TComponent)
  private
    function AbrirNavegador(const AURL: string): Boolean;

    // --- Shopee ---
    function ConectarShopee: String;
    function DesconectarShopee: String;
    function TestarConexaoShopee: String;

    // --- Amazon ---
    function ConectarAmazon: String;
    function DesconectarAmazon: String;
    function TestarConexaoAmazon: String;

    // --- Magalu ---
    function ConectarMagalu: String;
    function DesconectarMagalu: String;
    function TestarConexaoMagalu: String;

    // --- Mercado Livre ---
    function ConectarMercadoLivre: String;
    function DesconectarMercadoLivre: String;
    function TestarConexaoMercadoLivre: String;

    // --- TikTok Shop ---
    function ConectarTikTokShop: String;
    function DesconectarTikTokShop: String;
    function TestarConexaoTikTokShop: String;
  public
    oMarketplace: TMarketplace;

    function TestarConexaoMarketplace(TMarketplace: TMarketplaces): String;

    // Dispara o fluxo de autorizacao (abre navegador + escuta o callback local).
    // Ao terminar com sucesso, oMarketplace.AccountID/Token/RefreshToken/
    // TokenExpiraEm ficam preenchidos - quem chamou precisa gravar esses 4
    // valores nos campos Marketplace_ClientID/Marketplace_Token/Marketplace_Key/
    // Marketplace_BD da tabela Lojas logo em seguida (Edit + Post).
    function ConectarMarketplace(TMarketplace: TMarketplaces): String;

    // Renova o access token quando ele esta vencido ou perto de vencer, sem
    // fazer nenhuma chamada de dados - diferente do TestarConexaoMarketplace,
    // que renova E ainda bate na API pra confirmar. Pensado pra ser chamado
    // antes de cada operacao do SATSincroniaMarketplace, que fica horas aberto.
    // Devolve '' quando nao precisou renovar OU renovou com sucesso.
    // {IMPORTANTE} com ARenovou = True o CHAMADOR precisa regravar
    // Marketplace_Token, Marketplace_Key e Marketplace_BD na tabela Lojas.
    // Nao e' opcional: Magalu e Mercado Livre devolvem um refresh token NOVO a
    // cada renovacao e invalidam o anterior - sem regravar, a proxima
    // renovacao falha e a loja cai.
    function RenovarTokenSeNecessario(AMarketplace: TMarketplaces;
      out ARenovou: Boolean): String;
    // Limpa localmente (zera oMarketplace.AccountID/Token/RefreshToken/
    // TokenExpiraEm) - quem chamou grava os campos limpos na tabela Lojas.
    function DesconectarMarketplace(TMarketplace: TMarketplaces): String;
  end;

// Nome amigavel do marketplace, usado em mensagens pro usuario (ex: aviso de
// "loja ja conectada a outro marketplace").
function NomeMarketplace(const AMarketplace: TMarketplaces): String;

// Desmembra o Marketplace_ClientID do TikTok Shop, que guarda DOIS valores
// (shop_id e shop_cipher) separados por "|" - ver a nota de armazenamento em
// ConectarTikTokShop. Aceita valor sem separador (devolve tudo como ShopId e
// cipher vazio), pra nao quebrar com dado gravado antes/pela metade.
procedure SepararShopIdECipherTikTok(const AAccountID: string;
  out AShopId, AShopCipher: string);

// Mesma ideia, um nivel abaixo: no TikTok o que se vende e' o SKU, nao o
// produto - entao PRODUTOS_MARKETPLACE.CODPRODUTONOMARKETPLACE guarda
// "product_id|sku_id". Estoque e itens de pedido precisam dos dois.
procedure SepararProdutoESkuTikTok(const ACodProdutoNoMarketplace: string;
  out AProductId, ASkuId: string);

// Monta a chave composta, pra nunca ter concatenacao solta espalhada.
function MontarChaveProdutoTikTok(const AProductId, ASkuId: string): string;

const
  // Separador usado no campo unico que guarda shop_id + shop_cipher do
  // TikTok. "|" nao aparece em nenhum dos dois valores (id e numerico,
  // cipher e base64-url), entao e' seguro como delimitador.
  SEPARADOR_TIKTOK_SHOP = '|';

  // URLs fixas do Worker cadastradas como redirect_uri em cada marketplace.
  // Ajustar pro dominio real de voces antes de testar. Pode ser o MESMO
  // Worker pras duas (o worker.js normaliza os nomes de parametro por
  // provedor) - so' o "path" muda pra facilitar organizacao/logs.
  URL_WORKER_CALLBACK_SHOPEE = 'https://shopee-oauth-callback.denisripol.workers.dev/callback';
  URL_WORKER_CALLBACK_AMAZON = 'https://amazon-oauth-callback.denisripol.workers.dev/callback';
  URL_WORKER_CALLBACK_MAGALU = 'https://magalu-oauth-callback.denisripol.workers.dev/callback';
  // {ATENCAO} esse Worker foi criado hoje (24/08) usando o MODELO ANTIGO
  // (mostra o code na tela pra copiar manualmente, sem o fetch()
  // automatico de volta pro listener local) - precisa ser reescrito pra
  // seguir o mesmo padrao automatico que a Shopee ja usa (ConectarShopee
  // abaixo), senao ConectarMercadoLivre vai ficar esperando o
  // AguardarCallback pra sempre e vai dar timeout. Ver aviso detalhado
  // na implementacao de ConectarMercadoLivre.
  URL_WORKER_CALLBACK_MERCADOLIVRE = 'https://mercadolivre-oauth-callback.denisripol.workers.dev/callback';

  // {ATENCAO} o TikTok Shop e' o unico que NAO recebe o redirect_uri na URL
  // de autorizacao - essa URL precisa ser cadastrada no painel do app, e a
  // constante fica aqui so' como documentacao de qual e' a URL esperada (o
  // codigo nao a envia). O Worker ainda NAO EXISTE: precisa ser criado no
  // mesmo modelo automatico da Shopee (fetch() de volta pro listener local
  // usando o "state"), senao o AguardarCallback vai dar timeout.
  URL_WORKER_CALLBACK_TIKTOKSHOP = 'https://tiktokshop-oauth-callback.denisripol.workers.dev/callback';

  // Marketplace ID da Amazon - A2Q3Y263D00KWC = Brasil (fixo, mesmo pros
  // dois ambientes - so muda se um dia vender em outro pais na regiao NA).
  AMAZON_MARKETPLACE_ID_BRASIL = 'A2Q3Y263D00KWC';

  // Scopes da aplicacao Magalu (mesmos definidos no "idm client create"
  // original).
  MAGALU_SCOPES_PADRAO =
    'open:order-order-seller:read open:order-invoice-seller:read ' +
    'open:order-logistics-seller:read open:order-logistics-seller:write ' +
    'open:order-delivery-seller:read open:order-delivery-seller:write ' +
    'open:portfolio-prices-seller:read open:portfolio-prices-seller:write ' +
    'open:portfolio-skus-seller:read open:portfolio-skus-seller:write ' +
    'open:portfolio-stocks-seller:read open:portfolio-stocks-seller:write';

implementation

{ TDClassPadraoCashback }

function GerarTokenAleatorio: string;
begin
  Result := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '');
end;

function NomeMarketplace(const AMarketplace: TMarketplaces): String;
begin
  case AMarketplace of
    VTex: Result := 'VTex';
    Bagy: Result := 'Bagy';
    Tray: Result := 'Tray';
    iFoodMercado: Result := 'iFood Mercado';
    NuvemShop: Result := 'NuvemShop';
    Shopee: Result := 'Shopee';
    MercadoLivre: Result := 'Mercado Livre';
    Magalu: Result := 'Magalu';
    Amazon: Result := 'Amazon';
    TikTokShop: Result := 'TikTok Shop';
  else
    Result := 'Nenhum';
  end;
end;

procedure SepararShopIdECipherTikTok(const AAccountID: string;
  out AShopId, AShopCipher: string);
var
  P: Integer;
begin
  P := Pos(SEPARADOR_TIKTOK_SHOP, AAccountID);
  if P > 0 then
  begin
    AShopId := Copy(AAccountID, 1, P - 1);
    AShopCipher := Copy(AAccountID, P + Length(SEPARADOR_TIKTOK_SHOP), MaxInt);
  end
  else
  begin
    // Dado antigo/parcial: assume que o que tem e' o shop_id. Sem cipher, as
    // chamadas de loja vao falhar - e' proposital que falhe alto, em vez de
    // sair chamando a API com identificador incompleto.
    AShopId := AAccountID;
    AShopCipher := '';
  end;
end;

procedure SepararProdutoESkuTikTok(const ACodProdutoNoMarketplace: string;
  out AProductId, ASkuId: string);
var
  P: Integer;
begin
  P := Pos(SEPARADOR_TIKTOK_SHOP, ACodProdutoNoMarketplace);
  if P > 0 then
  begin
    AProductId := Copy(ACodProdutoNoMarketplace, 1, P - 1);
    ASkuId := Copy(ACodProdutoNoMarketplace, P + Length(SEPARADOR_TIKTOK_SHOP), MaxInt);
  end
  else
  begin
    // Vinculo gravado antes da chave composta (ou pela metade): sem sku_id
    // nao da' pra mexer em estoque, e quem chama trata isso como erro.
    AProductId := ACodProdutoNoMarketplace;
    ASkuId := '';
  end;
end;

function MontarChaveProdutoTikTok(const AProductId, ASkuId: string): string;
begin
  Result := AProductId + SEPARADOR_TIKTOK_SHOP + ASkuId;
end;

function DecodificarBase64URL(const ASegmento: string): string;
var
  S: string;
  Padding: Integer;
  Bytes: TBytes;
begin
  // JWT usa Base64URL (troca +/ por -_ e nao usa padding =) - converte pro
  // Base64 padrao antes de decodificar com TNetEncoding.
  S := ASegmento.Replace('-', '+').Replace('_', '/');
  Padding := (4 - (Length(S) mod 4)) mod 4;
  S := S + StringOfChar('=', Padding);
  Bytes := TNetEncoding.Base64.DecodeStringToBytes(S);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function ExtrairTenantIdDoToken(const AAccessToken: string): string;
var
  Partes: TArray<string>;
  PayloadJSON: string;
  JSONValue: TJSONValue;
begin
  // O Tenant ID (identificador da "conta/visao" - seller, no nosso caso) ja
  // vem embutido como claim "tenant" dentro do proprio access_token (JWT),
  // sem precisar de uma chamada extra a API. Formato JWT: header.payload.signature
  Result := '';
  Partes := AAccessToken.Split(['.']);
  if Length(Partes) < 2 then
    Exit; // token nao parece ser um JWT (nao tem pelo menos header.payload)

  PayloadJSON := DecodificarBase64URL(Partes[1]);

  JSONValue := TJSONObject.ParseJSONValue(PayloadJSON);
  if not Assigned(JSONValue) then
    Exit;

  try
    if JSONValue is TJSONObject then
      TJSONObject(JSONValue).TryGetValue<string>('tenant', Result);
  finally
    JSONValue.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TMarketplaceOAuthListener
--------------------------------------------------------------------------- }

constructor TMarketplaceOAuthListener.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FServer := TIdHTTPServer.Create(nil);
  FServer.OnCommandGet := OnCommandGet;
  FResultado.Recebido := False;
end;

destructor TMarketplaceOAuthListener.Destroy;
begin
  Parar;
  FServer.Free;
  FLock.Free;
  inherited;
end;

function TMarketplaceOAuthListener.PortaEstaLivre(const APorta: Integer): Boolean;
var
  TesteServer: TIdHTTPServer;
begin
  Result := True;
  TesteServer := TIdHTTPServer.Create(nil);
  try
    try
      TesteServer.Bindings.Clear;
      with TesteServer.Bindings.Add do
      begin
        IP := '127.0.0.1';
        Port := APorta;
      end;
      TesteServer.Active := True;
    except
      Result := False;
    end;
  finally
    TesteServer.Active := False;
    TesteServer.Free;
  end;
end;

function TMarketplaceOAuthListener.EncontrarPortaLivre: Integer;
var
  Porta: Integer;
begin
  for Porta := 51037 to 51087 do
    if PortaEstaLivre(Porta) then
      Exit(Porta);

  raise Exception.Create('Nao foi possivel encontrar uma porta local livre ' +
    'para o callback do OAuth (faixa 51037-51087 ocupada).');
end;

function TMarketplaceOAuthListener.Iniciar: string;
begin
  FPorta := EncontrarPortaLivre;
  FState := Format('%d-%s', [FPorta, GerarTokenAleatorio]);
  FResultado.Recebido := False;

  FServer.Bindings.Clear;
  with FServer.Bindings.Add do
  begin
    IP := '127.0.0.1';
    Port := FPorta;
  end;
  FServer.Active := True;

  Result := FState;
end;

procedure TMarketplaceOAuthListener.OnCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  StateRecebido, CodeRecebido, AccountIdRecebido, ErroRecebido: string;
begin
  if Pos('/callback', ARequestInfo.Document) <> 1 then
  begin
    AResponseInfo.ResponseNo := 404;
    Exit;
  end;

  StateRecebido     := ARequestInfo.Params.Values['state'];
  CodeRecebido      := ARequestInfo.Params.Values['code'];
  // shop_id (Shopee) / selling_partner_id (Amazon) / seller_id (Magalu, ML)
  AccountIdRecebido := ARequestInfo.Params.Values['shop_id'];
  ErroRecebido      := ARequestInfo.Params.Values['error'];

  FLock.Enter;
  try
    FResultado.Recebido := True;

    if StateRecebido <> FState then
    begin
      FResultado.Sucesso := False;
      FResultado.MensagemErro := 'State invalido - possivel CSRF ou callback de ' +
        'uma tentativa anterior expirada.';
    end
    else if ErroRecebido <> '' then
    begin
      FResultado.Sucesso := False;
      FResultado.MensagemErro := 'O marketplace retornou erro: ' + ErroRecebido;
    end
    else if CodeRecebido = '' then
    begin
      FResultado.Sucesso := False;
      FResultado.MensagemErro := 'Callback recebido sem "code".';
    end
    else
    begin
      FResultado.Sucesso := True;
      FResultado.Code := CodeRecebido;
      FResultado.AccountID := AccountIdRecebido;
    end;
  finally
    FLock.Leave;
  end;

  AResponseInfo.ContentType := 'text/html; charset=utf-8';
  AResponseInfo.ContentText :=
    '<html><head><meta charset="utf-8"></head>' +
    '<body style="font-family:sans-serif;text-align:center;margin-top:80px">' +
    '<h2>' + IfThen(FResultado.Sucesso, 'Conectado com sucesso!',
                     'Nao foi possivel concluir a conexao.') + '</h2>' +
    '<p>Pode fechar esta janela e voltar para o SAT Sistemas.</p>' +
    '</body></html>';
  AResponseInfo.ResponseNo := 200;
end;

function TMarketplaceOAuthListener.AguardarCallback(const ATimeoutSegundos: Integer): Boolean;
var
  Inicio: TDateTime;
begin
  Inicio := Now;
  Result := False;
  while SecondsBetween(Now, Inicio) < ATimeoutSegundos do
  begin
    Application.ProcessMessages;
    FLock.Enter;
    try
      if FResultado.Recebido then
      begin
        Result := True;
        Break;
      end;
    finally
      FLock.Leave;
    end;
    Sleep(150);
  end;
end;

procedure TMarketplaceOAuthListener.Parar;
begin
  if Assigned(FServer) and FServer.Active then
    FServer.Active := False;
end;

{ ---------------------------------------------------------------------------
  TDClassPadraoMarketplaces
--------------------------------------------------------------------------- }

function TDClassPadraoMarketplaces.AbrirNavegador(const AURL: string): Boolean;
begin
  Result := ShellExecute(0, 'open', PChar(AURL), nil, nil, SW_SHOWNORMAL) > 32;
end;

function TDClassPadraoMarketplaces.ConectarShopee: String;
var
  PartnerID: Int64;
  StateGerado, RedirectComState, URLAutorizacao: string;
  Cliente: TShopeeOpenAPIClient;
  Listener: TMarketplaceOAuthListener;
  TokenInfo: TShopeeTokenInfo;
begin
  Result := '';

  PartnerID := StrToInt64Def(oMarketplace.ClientId, 0);
  if (PartnerID = 0) or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor da Shopee nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV).';
    Exit;
  end;

  Listener := TMarketplaceOAuthListener.Create;
  try
    StateGerado := Listener.Iniciar;
    RedirectComState := URL_WORKER_CALLBACK_SHOPEE + '?state=' + StateGerado;

    Cliente := TShopeeOpenAPIClient.Create(PartnerID, oMarketplace.ClientSecret,
      RedirectComState, oMarketplace.Sandbox);
    try
      URLAutorizacao := Cliente.BuildAuthorizationURL;

      if not AbrirNavegador(URLAutorizacao) then
      begin
        Result := 'Nao foi possivel abrir o navegador padrao.';
        Exit;
      end;

      if not Listener.AguardarCallback(180) then
      begin
        Result := 'Tempo esgotado aguardando a autorizacao (3 minutos). Tente novamente.';
        Exit;
      end;

      if not Listener.Resultado.Sucesso then
      begin
        Result := Listener.Resultado.MensagemErro;
        Exit;
      end;

      TokenInfo := Cliente.ExchangeCodeForTokens(Listener.Resultado.Code,
        StrToInt64Def(Listener.Resultado.AccountID, 0));

      if not TokenInfo.Success then
      begin
        Result := 'Falha ao trocar o codigo por token: ' + TokenInfo.ErrorMessage;
        Exit;
      end;

      // ATENCAO - bug conhecido do sandbox da Shopee (mesmo documentado no
      // ticket aberto com eles): o campo ShopID dentro da RESPOSTA do
      // ExchangeCodeForTokens pode vir com um valor bugado, diferente do
      // shop_id real que veio no callback do OAuth (Listener.Resultado.
      // AccountID). Sempre confia no shop_id do CALLBACK, nunca no da
      // resposta do token.
      oMarketplace.AccountID := Listener.Resultado.AccountID;
      oMarketplace.Token := TokenInfo.AccessToken;
      oMarketplace.RefreshToken := TokenInfo.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, TokenInfo.ExpireIn);
      // Result = '' = sucesso. Quem chamou grava oMarketplace.AccountID/Token/
      // RefreshToken/TokenExpiraEm em Marketplace_ClientID/Marketplace_Token/
      // Marketplace_Key/Marketplace_BD e faz Post no QLojas.
    finally
      Cliente.Free;
    end;
  finally
    Listener.Free;
  end;
end;

function TDClassPadraoMarketplaces.DesconectarShopee: String;
begin
  // Shopee Open Platform nao expoe endpoint de revogacao de token - "desconectar"
  // e' limpar localmente. Quem chamou grava os campos ja zerados na tabela Lojas.
  oMarketplace.AccountID := '';
  oMarketplace.Token := '';
  oMarketplace.RefreshToken := '';
  oMarketplace.TokenExpiraEm := 0;
  Result := '';
end;

function TDClassPadraoMarketplaces.TestarConexaoShopee: String;
var
  PartnerID: Int64;
  Cliente: TShopeeOpenAPIClient;
  RespostaJSON: string;
  NovoToken: TShopeeTokenInfo;
begin
  Result := '';

  if (oMarketplace.AccountID = '') or (oMarketplace.Token = '') then
  begin
    Result := 'Loja ainda nao conectada. Clique em "Conectar" primeiro.';
    Exit;
  end;

  PartnerID := StrToInt64Def(oMarketplace.ClientId, 0);
  if (PartnerID = 0) or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor da Shopee nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV).';
    Exit;
  end;

  Cliente := TShopeeOpenAPIClient.Create(PartnerID, oMarketplace.ClientSecret,
    '', oMarketplace.Sandbox);
  try
    // Access token perto de expirar (margem de 5 min) -> renova antes de
    // testar, pra nao dar falso negativo por token vencido.
    if (oMarketplace.TokenExpiraEm > 0) and
       (Now >= IncMinute(oMarketplace.TokenExpiraEm, -5)) then
    begin
      NovoToken := Cliente.RefreshAccessToken(oMarketplace.RefreshToken,
        StrToInt64Def(oMarketplace.AccountID, 0));
      if not NovoToken.Success then
      begin
        Result := 'Token expirado e nao foi possivel renovar: ' + NovoToken.ErrorMessage +
          '. Sera necessario clicar em "Conectar" novamente.';
        Exit;
      end;

      oMarketplace.Token := NovoToken.AccessToken;
      // So substitui o refresh token se veio um novo - varios provedores nao
      // retornam refresh_token na renovacao (mantem o mesmo), e sobrescrever
      // com vazio derrubaria a conexao na proxima tentativa.
      if NovoToken.RefreshToken <> '' then
        oMarketplace.RefreshToken := NovoToken.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, NovoToken.ExpireIn);
      // Token renovado - quem chamou precisa regravar Marketplace_Token/
      // Marketplace_Key/Marketplace_BD na tabela Lojas apos esse teste.
    end;

    if not Cliente.TestConnection(oMarketplace.Token,
         StrToInt64Def(oMarketplace.AccountID, 0), RespostaJSON) then
      Result := 'Falha no teste de conexao: ' + RespostaJSON;
  finally
    Cliente.Free;
  end;
end;

function TDClassPadraoMarketplaces.ConectarAmazon: String;
var
  StateGerado, RedirectComState, URLAutorizacao: string;
  Cliente: TAmazonSPAPIClient;
  Listener: TMarketplaceOAuthListener;
  TokenInfo: TAmazonTokenInfo;
begin
  Result := '';

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') or
     (oMarketplace.App = '') then
  begin
    Result := 'Credenciais de desenvolvedor da Amazon nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV/' +
      'MARKETPLACE_APP_DEV_ID).';
    Exit;
  end;

  // Atalho de sandbox: a Amazon nao tem "loja de teste com login" tipo a
  // Shopee - quem cria um Sandbox Application no Solution Provider Portal ja
  // recebe um Refresh Token pronto, sem precisar de nenhuma autorizacao via
  // navegador. Colado no campo exclusivo da tela (visivel so' quando Amazon +
  // Homologacao) - se estiver preenchido, pula o fluxo de navegador inteiro.
  if oMarketplace.Sandbox and (oMarketplace.RefreshTokenManualSandbox <> '') then
  begin
    Cliente := TAmazonSPAPIClient.Create(oMarketplace.ClientId, oMarketplace.ClientSecret,
      '', AMAZON_MARKETPLACE_ID_BRASIL, oMarketplace.Sandbox);
    try
      TokenInfo := Cliente.RefreshAccessToken(oMarketplace.RefreshTokenManualSandbox);

      if not TokenInfo.Success then
      begin
        Result := 'Falha ao trocar o Refresh Token de sandbox por access token: ' +
          TokenInfo.ErrorMessage;
        Exit;
      end;

      // O Sandbox Application nao tem um selling_partner_id real associado -
      // usa um marcador fixo so pra indicar que a loja esta "conectada" via
      // esse atalho.
      oMarketplace.AccountID := 'SANDBOX';
      oMarketplace.Token := TokenInfo.AccessToken;
      // O refresh token do Sandbox Application e' fixo/reutilizavel - mantem
      // o mesmo que foi colado.
      oMarketplace.RefreshToken := oMarketplace.RefreshTokenManualSandbox;
      oMarketplace.TokenExpiraEm := IncSecond(Now, TokenInfo.ExpiresIn);
    finally
      Cliente.Free;
    end;
    Exit;
  end;

  // --- Fluxo normal via navegador (producao, ou sandbox com self-authorization
  // usando sua propria conta real de Seller Central) ---
  Listener := TMarketplaceOAuthListener.Create;
  try
    StateGerado := Listener.Iniciar;
    RedirectComState := URL_WORKER_CALLBACK_AMAZON + '?state=' + StateGerado;

    Cliente := TAmazonSPAPIClient.Create(oMarketplace.ClientId, oMarketplace.ClientSecret,
      RedirectComState, AMAZON_MARKETPLACE_ID_BRASIL, oMarketplace.Sandbox);
    try
      // Diferente da Shopee, a URL de autorizacao da Amazon usa o
      // ApplicationID (do Solution Provider Portal, nao e' o ClientID) e
      // aponta pro Seller Central - o "state" e o mesmo gerado pelo listener.
      URLAutorizacao := Cliente.BuildAuthorizationURL(oMarketplace.App, StateGerado);

      if not AbrirNavegador(URLAutorizacao) then
      begin
        Result := 'Nao foi possivel abrir o navegador padrao.';
        Exit;
      end;

      if not Listener.AguardarCallback(180) then
      begin
        Result := 'Tempo esgotado aguardando a autorizacao (3 minutos). Tente novamente.';
        Exit;
      end;

      if not Listener.Resultado.Sucesso then
      begin
        Result := Listener.Resultado.MensagemErro;
        Exit;
      end;

      // A Amazon chama o parametro de "spapi_oauth_code" (nao "code"), e o
      // worker.js ja normaliza isso pro nosso listener generico antes de
      // redirecionar - aqui so recebemos o Code ja normalizado.
      TokenInfo := Cliente.ExchangeCodeForTokens(Listener.Resultado.Code);

      if not TokenInfo.Success then
      begin
        Result := 'Falha ao trocar o codigo por token: ' + TokenInfo.ErrorMessage;
        Exit;
      end;

      // AccountID aqui e' o selling_partner_id (Seller ID, alfanumerico) -
      // ja vem pronto do callback, nao precisa de chamada extra a API.
      oMarketplace.AccountID := Listener.Resultado.AccountID;
      oMarketplace.Token := TokenInfo.AccessToken;
      oMarketplace.RefreshToken := TokenInfo.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, TokenInfo.ExpiresIn);
      // Result = '' = sucesso. Quem chamou grava oMarketplace.AccountID/Token/
      // RefreshToken/TokenExpiraEm em Marketplace_ClientID/Marketplace_Token/
      // Marketplace_Key/Marketplace_BD e faz Post no QLojas.
    finally
      Cliente.Free;
    end;
  finally
    Listener.Free;
  end;
end;

function TDClassPadraoMarketplaces.DesconectarAmazon: String;
begin
  // SP-API nao expoe endpoint de revogacao de token pelo lado do app -
  // "desconectar" e' limpar localmente. Quem chamou grava os campos ja
  // zerados na tabela Lojas. (O vendedor tambem pode revogar do lado dele,
  // no Seller Central, independente disso.)
  oMarketplace.AccountID := '';
  oMarketplace.Token := '';
  oMarketplace.RefreshToken := '';
  oMarketplace.TokenExpiraEm := 0;
  Result := '';
end;

function TDClassPadraoMarketplaces.TestarConexaoAmazon: String;
var
  Cliente: TAmazonSPAPIClient;
  RespostaJSON: string;
  NovoToken: TAmazonTokenInfo;
begin
  Result := '';

  if (oMarketplace.AccountID = '') or (oMarketplace.Token = '') then
  begin
    Result := 'Loja ainda nao conectada. Clique em "Conectar" primeiro.';
    Exit;
  end;

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor da Amazon nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV).';
    Exit;
  end;

  Cliente := TAmazonSPAPIClient.Create(oMarketplace.ClientId, oMarketplace.ClientSecret,
    '', AMAZON_MARKETPLACE_ID_BRASIL, oMarketplace.Sandbox);
  try
    if (oMarketplace.TokenExpiraEm > 0) and
       (Now >= IncMinute(oMarketplace.TokenExpiraEm, -5)) then
    begin
      NovoToken := Cliente.RefreshAccessToken(oMarketplace.RefreshToken);
      if not NovoToken.Success then
      begin
        Result := 'Token expirado e nao foi possivel renovar: ' + NovoToken.ErrorMessage +
          '. Sera necessario clicar em "Conectar" novamente.';
        Exit;
      end;

      oMarketplace.Token := NovoToken.AccessToken;
      // LWA normalmente NAO devolve um novo refresh_token na renovacao
      // (mantem o mesmo) - so substitui se realmente veio um novo.
      if NovoToken.RefreshToken <> '' then
        oMarketplace.RefreshToken := NovoToken.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, NovoToken.ExpiresIn);
      // Token renovado - quem chamou precisa regravar Marketplace_Token/
      // Marketplace_Key/Marketplace_BD na tabela Lojas apos esse teste.
    end;

    if not Cliente.TestConnection(oMarketplace.Token, RespostaJSON) then
      Result := 'Falha no teste de conexao: ' + RespostaJSON;
  finally
    Cliente.Free;
  end;
end;

function TDClassPadraoMarketplaces.ConectarMagalu: String;
var
  StateGerado, URLAutorizacao: string;
  Cliente: TMagaluOpenAPIClient;
  Listener: TMarketplaceOAuthListener;
  TokenInfo: TMagaluTokenInfo;
  TenantID: string;
begin
  Result := '';

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor do Magalu nao cadastradas para ' +
      'esta loja (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV).';
    Exit;
  end;

  Listener := TMarketplaceOAuthListener.Create;
  try
    StateGerado := Listener.Iniciar;

    // Diferente de Shopee/Amazon, o Magalu e' OAuth2 "classico" - o state
    // volta sozinho como parametro proprio no redirect (nao precisamos
    // embutir na redirect_uri). A redirect_uri fica fixa e limpa, e PRECISA
    // bater exatamente com o que estiver cadastrado via "idm client update
    // --redirect-uris".
    Cliente := TMagaluOpenAPIClient.Create(oMarketplace.ClientId, oMarketplace.ClientSecret,
      URL_WORKER_CALLBACK_MAGALU, MAGALU_SCOPES_PADRAO, oMarketplace.Sandbox);
    try
      URLAutorizacao := Cliente.BuildAuthorizationURL(StateGerado);

      if not AbrirNavegador(URLAutorizacao) then
      begin
        Result := 'Nao foi possivel abrir o navegador padrao.';
        Exit;
      end;

      if not Listener.AguardarCallback(180) then
      begin
        Result := 'Tempo esgotado aguardando a autorizacao (3 minutos). Tente novamente.';
        Exit;
      end;

      if not Listener.Resultado.Sucesso then
      begin
        Result := Listener.Resultado.MensagemErro;
        Exit;
      end;

      TokenInfo := Cliente.ExchangeCodeForTokens(Listener.Resultado.Code);

      if not TokenInfo.Success then
      begin
        Result := 'Falha ao trocar o codigo por token: ' + TokenInfo.ErrorMessage;
        Exit;
      end;

      // O Magalu nao devolve nenhum "ID da conta" no proprio callback OAuth,
      // mas o Tenant ID (a "conta" seller) ja vem embutido no proprio
      // access_token (JWT) gracas ao "choose_tenants=true" na URL de
      // autorizacao - decodifica localmente em vez de chamar uma API extra
      // (o endpoint GetSellerTenantId da unit e' de um tutorial antigo/alpha
      // que nao existe mais nos dominios atuais - dava 404).
      TenantID := ExtrairTenantIdDoToken(TokenInfo.AccessToken);

      if TenantID = '' then
      begin
        Result := 'Login autorizado, mas nao foi possivel extrair o Tenant ID ' +
          '(seller) do token recebido. Verifique se o claim "tenant" existe no ' +
          'JWT (pode ter um nome/formato diferente do esperado).';
        Exit;
      end;

      oMarketplace.AccountID := TenantID;
      oMarketplace.Token := TokenInfo.AccessToken;
      oMarketplace.RefreshToken := TokenInfo.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, TokenInfo.ExpiresIn);
      // Result = '' = sucesso. Quem chamou grava oMarketplace.AccountID/Token/
      // RefreshToken/TokenExpiraEm em Marketplace_ClientID/Marketplace_Token/
      // Marketplace_Key/Marketplace_BD e faz Post no QLojas.
    finally
      Cliente.Free;
    end;
  finally
    Listener.Free;
  end;
end;

function TDClassPadraoMarketplaces.DesconectarMagalu: String;
begin
  // Magalu tambem nao expoe endpoint de revogacao pelo lado do app -
  // "desconectar" e' limpar localmente. Quem chamou grava os campos ja
  // zerados na tabela Lojas.
  oMarketplace.AccountID := '';
  oMarketplace.Token := '';
  oMarketplace.RefreshToken := '';
  oMarketplace.TokenExpiraEm := 0;
  Result := '';
end;

function TDClassPadraoMarketplaces.TestarConexaoMagalu: String;
var
  Cliente: TMagaluOpenAPIClient;
  NovoToken: TMagaluTokenInfo;
begin
  Result := '';

  if (oMarketplace.AccountID = '') or (oMarketplace.Token = '') then
  begin
    Result := 'Loja ainda nao conectada. Clique em "Conectar" primeiro.';
    Exit;
  end;

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor do Magalu nao cadastradas para ' +
      'esta loja (verifique MARKETPLACE_ID_DEV/MARKETPLACE_KEY_DEV).';
    Exit;
  end;

  Cliente := TMagaluOpenAPIClient.Create(oMarketplace.ClientId, oMarketplace.ClientSecret,
    '', MAGALU_SCOPES_PADRAO, oMarketplace.Sandbox);
  try
    // O refresh token do Magalu SO PODE SER USADO UMA VEZ - cada renovacao
    // gera um novo que precisa substituir o anterior imediatamente (o antigo
    // e' invalidado no ato). Por isso a margem de seguranca aqui e' maior
    // (10 min) e quem chamar esta funcao TEM que regravar os campos na
    // tabela Lojas logo em seguida, sem pular esse passo.
    if (oMarketplace.TokenExpiraEm > 0) and
       (Now >= IncMinute(oMarketplace.TokenExpiraEm, -10)) then
    begin
      NovoToken := Cliente.RefreshAccessToken(oMarketplace.RefreshToken);
      if not NovoToken.Success then
      begin
        Result := 'Token expirado e nao foi possivel renovar: ' + NovoToken.ErrorMessage +
          '. Sera necessario clicar em "Conectar" novamente.';
        Exit;
      end;

      oMarketplace.Token := NovoToken.AccessToken;
      // Aqui SEMPRE substitui (diferente de Shopee/Amazon) - o refresh token
      // antigo do Magalu ja foi invalidado nesse exato momento pelo servidor.
      if NovoToken.RefreshToken <> '' then
        oMarketplace.RefreshToken := NovoToken.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, NovoToken.ExpiresIn);
    end;

    // Nao ha um "TestConnection" dedicado no cliente do Magalu, e o endpoint
    // whoami/tenants esta quebrado (404, era de um tutorial alpha antigo) -
    // usa a mesma decodificacao local do JWT como teste leve: se o token
    // ainda tiver o claim "tenant" legivel, consideramos valido.
    if ExtrairTenantIdDoToken(oMarketplace.Token) = '' then
      Result := 'Falha no teste de conexao: nao foi possivel extrair o Tenant ID do token atual.';
  finally
    Cliente.Free;
  end;
end;

function TDClassPadraoMarketplaces.ConectarMercadoLivre: String;
var
  StateGerado, URLAutorizacao: string;
  Cliente: TMercadoLivreOpenAPIClient;
  Listener: TMarketplaceOAuthListener;
  TokenInfo: TMercadoLivreTokenInfo;
begin
  Result := '';

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor do Mercado Livre nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA).';
    Exit;
  end;

  Listener := TMarketplaceOAuthListener.Create;
  try
    StateGerado := Listener.Iniciar;
    // {CORRECAO - erro real} O Mercado Livre EXIGE que o redirect_uri seja
    // EXATAMENTE igual ao cadastrado no DevCenter, SEM nenhuma informacao
    // variavel (diferente da Shopee, que tolera "?state=..." concatenado -
    // por isso o ConectarShopee faz isso, mas nao pode ser copiado aqui).
    // A doc oficial do proprio Mercado Livre documenta esse erro exato:
    // "Desculpe, nao foi possivel conectar o aplicativo a sua conta" e'
    // causado justamente por um redirect_uri com parametro variavel. O
    // "state" ja vai separado, como parametro proprio da URL de
    // autorizacao (BuildAuthorizationURL abaixo) - nao precisa (e nao
    // pode) ir embutido no redirect_uri pro Mercado Livre.
    Cliente := TMercadoLivreOpenAPIClient.Create(oMarketplace.ClientId,
      oMarketplace.ClientSecret, URL_WORKER_CALLBACK_MERCADOLIVRE, oMarketplace.Sandbox);
    try
      URLAutorizacao := Cliente.BuildAuthorizationURL(StateGerado);

      if not AbrirNavegador(URLAutorizacao) then
      begin
        Result := 'Nao foi possivel abrir o navegador padrao.';
        Exit;
      end;

      if not Listener.AguardarCallback(180) then
      begin
        Result := 'Tempo esgotado aguardando a autorizacao (3 minutos). Tente novamente.';
        Exit;
      end;

      if not Listener.Resultado.Sucesso then
      begin
        Result := Listener.Resultado.MensagemErro;
        Exit;
      end;

      TokenInfo := Cliente.ExchangeCodeForTokens(Listener.Resultado.Code);

      if not TokenInfo.Success then
      begin
        Result := 'Falha ao trocar o codigo por token: ' + TokenInfo.ErrorMessage;
        Exit;
      end;

      // {ATENCAO} diferente da Shopee (que exige o shop_id vindo do
      // CALLBACK por causa de um bug documentado no sandbox), o Mercado
      // Livre devolve o seller ID (user_id) direto na resposta do token -
      // nao ha' motivo pra preferir Listener.Resultado.AccountID aqui (que
      // alias sempre vem vazio pro ML, ja que o redirect do OAuth deles
      // so' traz "code" e "state", sem nenhum id de conta).
      oMarketplace.AccountID := TokenInfo.UserId;
      oMarketplace.Token := TokenInfo.AccessToken;
      oMarketplace.RefreshToken := TokenInfo.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, TokenInfo.ExpiresIn);
    finally
      Cliente.Free;
    end;
  finally
    Listener.Free;
  end;
end;

function TDClassPadraoMarketplaces.DesconectarMercadoLivre: String;
begin
  // {ATENCAO} nao confirmamos um endpoint de revogacao de token do
  // Mercado Livre na pesquisa de hoje (24/08) - "desconectar" e' limpar
  // localmente, mesmo padrao ja usado pra Shopee (que tambem nao expoe
  // revogacao). Se um endpoint de revoke existir e for encontrado depois,
  // e' so' chamar ele aqui antes de zerar os campos.
  oMarketplace.AccountID := '';
  oMarketplace.Token := '';
  oMarketplace.RefreshToken := '';
  oMarketplace.TokenExpiraEm := 0;
  Result := '';
end;

function TDClassPadraoMarketplaces.TestarConexaoMercadoLivre: String;
var
  Cliente: TMercadoLivreOpenAPIClient;
  RespostaJSON: string;
  NovoToken: TMercadoLivreTokenInfo;
begin
  Result := '';

  if (oMarketplace.AccountID = '') or (oMarketplace.Token = '') then
  begin
    Result := 'Loja ainda nao conectada. Clique em "Conectar" primeiro.';
    Exit;
  end;

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor do Mercado Livre nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA).';
    Exit;
  end;

  Cliente := TMercadoLivreOpenAPIClient.Create(oMarketplace.ClientId,
    oMarketplace.ClientSecret, '', oMarketplace.Sandbox);
  try
    // Access token perto de expirar (margem de 5 min) -> renova antes de
    // testar, pra nao dar falso negativo por token vencido. Access token
    // do ML dura 6h (21600s), confirmado na doc oficial.
    if (oMarketplace.TokenExpiraEm > 0) and
       (Now >= IncMinute(oMarketplace.TokenExpiraEm, -5)) then
    begin
      NovoToken := Cliente.RefreshAccessToken(oMarketplace.RefreshToken);
      if not NovoToken.Success then
      begin
        Result := 'Token expirado e nao foi possivel renovar: ' + NovoToken.ErrorMessage +
          '. Sera necessario clicar em "Conectar" novamente.';
        Exit;
      end;

      oMarketplace.Token := NovoToken.AccessToken;
      // {ATENCAO} o Mercado Livre pode devolver um refresh_token NOVO a
      // cada renovacao (revogando o antigo) - diferente de outros
      // provedores que mantem o mesmo. Por isso aqui SEMPRE substitui
      // (nao so' "se veio um novo"), pra nunca ficar com um refresh_token
      // desatualizado que a Amazon/Shopee ja teriam revogado.
      if NovoToken.RefreshToken <> '' then
        oMarketplace.RefreshToken := NovoToken.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, NovoToken.ExpiresIn);
      // Token renovado - quem chamou precisa regravar Marketplace_Token/
      // Marketplace_Key/Marketplace_BD na tabela Lojas apos esse teste.
    end;

    if not Cliente.TestConnection(oMarketplace.Token, oMarketplace.AccountID, RespostaJSON) then
      Result := 'Falha no teste de conexao: ' + RespostaJSON;
  finally
    Cliente.Free;
  end;
end;

function TDClassPadraoMarketplaces.ConectarTikTokShop: String;
var
  StateGerado, URLAutorizacao, ErroMsg: string;
  Cliente: TTikTokShopOpenAPIClient;
  Listener: TMarketplaceOAuthListener;
  TokenInfo: TTikTokShopTokenInfo;
  Lojas: TTikTokShopLojaArray;
begin
  Result := '';

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor do TikTok Shop nao cadastradas para ' +
      'esta loja/ambiente (app_key/app_secret em MARKETPLACE_USUARIO/MARKETPLACE_SENHA).';
    Exit;
  end;

  // {ATENCAO} diferente dos outros quatro, o TikTok NAO monta a URL de
  // autorizacao com client_id: ele usa o "service_id" do app. Sem ele a tela
  // de autorizacao nem abre, entao vale checar antes de gastar o navegador.
  if oMarketplace.App = '' then
  begin
    Result := 'Service ID do aplicativo TikTok Shop nao cadastrado para esta ' +
      'loja/ambiente (MARKETPLACE_APP_DEV_ID). Ele aparece no painel do app, ' +
      'na secao de autorizacao.';
    Exit;
  end;

  Listener := TMarketplaceOAuthListener.Create;
  try
    StateGerado := Listener.Iniciar;
    // {ATENCAO} o redirect_uri NAO vai na URL (o TikTok usa o que estiver
    // cadastrado no painel do app) - por isso, diferente da Shopee, nao ha'
    // nada a concatenar aqui. O Worker cadastrado la' precisa devolver o
    // "code" pro listener local usando o "state", igual os outros fazem.
    Cliente := TTikTokShopOpenAPIClient.Create(oMarketplace.ClientId,
      oMarketplace.ClientSecret, oMarketplace.App, oMarketplace.Sandbox);
    try
      URLAutorizacao := Cliente.BuildAuthorizationURL(StateGerado);

      if not AbrirNavegador(URLAutorizacao) then
      begin
        Result := 'Nao foi possivel abrir o navegador padrao.';
        Exit;
      end;

      if not Listener.AguardarCallback(180) then
      begin
        Result := 'Tempo esgotado aguardando a autorizacao (3 minutos). Tente novamente.';
        Exit;
      end;

      if not Listener.Resultado.Sucesso then
      begin
        Result := Listener.Resultado.MensagemErro;
        Exit;
      end;

      TokenInfo := Cliente.ExchangeCodeForTokens(Listener.Resultado.Code);

      if not TokenInfo.Success then
      begin
        Result := 'Falha ao trocar o codigo por token: ' + TokenInfo.ErrorMessage;
        Exit;
      end;

      oMarketplace.Token := TokenInfo.AccessToken;
      oMarketplace.RefreshToken := TokenInfo.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, TokenInfo.ExpiresIn);

      // O callback do TikTok NAO traz identificador de loja (so' code/state),
      // e o token sozinho tambem nao serve pra chamar nada: e' preciso o
      // shop_cipher. Por isso a conexao so' esta completa depois desta
      // chamada extra - nenhum dos outros quatro precisa dela.
      if not Cliente.GetAuthorizedShops(oMarketplace.Token, Lojas, ErroMsg) then
      begin
        Result := 'Token obtido, mas nao foi possivel listar as lojas autorizadas: ' +
          ErroMsg;
        Exit;
      end;

      if Length(Lojas) = 0 then
      begin
        Result := 'A autorizacao foi concluida, mas nenhuma loja ficou vinculada ao ' +
          'aplicativo. Refaca a autorizacao selecionando a loja na tela do TikTok.';
        Exit;
      end;

      // {DECISAO DE ARMAZENAMENTO} o TikTok precisa de DOIS identificadores
      // (shop_id e shop_cipher) e a tabela Lojas so' tem um campo pra isso
      // (Marketplace_ClientID). Em vez de pedir uma coluna nova ao cliente,
      // os dois vao juntos, separados por "|" - quem le usa
      // uMarketplace.SepararShopIdECipherTikTok pra desmembrar. Se um dia
      // existir uma coluna dedicada, e' so' mudar nesses dois pontos.
      // {ATENCAO} usa a PRIMEIRA loja da lista. Vendedor com mais de uma loja
      // no mesmo app vai precisar de uma tela de escolha aqui - fica pra
      // quando aparecer um caso real (os outros marketplaces do projeto
      // tambem assumem uma conta por loja do SAT).
      oMarketplace.Loja := Lojas[0].Nome;
      oMarketplace.AccountID := Lojas[0].ShopId + SEPARADOR_TIKTOK_SHOP + Lojas[0].Cipher;
    finally
      Cliente.Free;
    end;
  finally
    Listener.Free;
  end;
end;

function TDClassPadraoMarketplaces.DesconectarTikTokShop: String;
begin
  // Mesmo padrao de Shopee/Mercado Livre: nao ha' endpoint de revogacao
  // confirmado na doc publica da Partner API - "desconectar" e' limpar
  // localmente. A autorizacao em si continua valendo do lado do TikTok ate'
  // o vendedor remover o app pelo painel dele.
  oMarketplace.AccountID := '';
  oMarketplace.Token := '';
  oMarketplace.RefreshToken := '';
  oMarketplace.TokenExpiraEm := 0;
  Result := '';
end;

function TDClassPadraoMarketplaces.TestarConexaoTikTokShop: String;
var
  Cliente: TTikTokShopOpenAPIClient;
  RespostaJSON, ShopId, ShopCipher: string;
  NovoToken: TTikTokShopTokenInfo;
begin
  Result := '';

  if (oMarketplace.AccountID = '') or (oMarketplace.Token = '') then
  begin
    Result := 'Loja ainda nao conectada. Clique em "Conectar" primeiro.';
    Exit;
  end;

  if (oMarketplace.ClientId = '') or (oMarketplace.ClientSecret = '') then
  begin
    Result := 'Credenciais de desenvolvedor do TikTok Shop nao cadastradas para ' +
      'esta loja/ambiente (verifique MARKETPLACE_USUARIO/MARKETPLACE_SENHA).';
    Exit;
  end;

  SepararShopIdECipherTikTok(oMarketplace.AccountID, ShopId, ShopCipher);

  Cliente := TTikTokShopOpenAPIClient.Create(oMarketplace.ClientId,
    oMarketplace.ClientSecret, oMarketplace.App, oMarketplace.Sandbox);
  try
    // Token perto de expirar (margem de 5 min) -> renova antes de testar, pra
    // nao dar falso negativo por token vencido.
    if (oMarketplace.TokenExpiraEm > 0) and
       (Now >= IncMinute(oMarketplace.TokenExpiraEm, -5)) then
    begin
      NovoToken := Cliente.RefreshAccessToken(oMarketplace.RefreshToken);
      if not NovoToken.Success then
      begin
        Result := 'Token expirado e nao foi possivel renovar: ' + NovoToken.ErrorMessage +
          '. Sera necessario clicar em "Conectar" novamente.';
        Exit;
      end;

      oMarketplace.Token := NovoToken.AccessToken;
      // {ATENCAO} o TikTok devolve um refresh_token NOVO a cada renovacao -
      // igual ao Mercado Livre, sempre substitui, pra nunca ficar com um
      // refresh antigo que o servidor ja invalidou.
      if NovoToken.RefreshToken <> '' then
        oMarketplace.RefreshToken := NovoToken.RefreshToken;
      oMarketplace.TokenExpiraEm := IncSecond(Now, NovoToken.ExpiresIn);
      // Token renovado - quem chamou precisa regravar Marketplace_Token/
      // Marketplace_Key/Marketplace_BD na tabela Lojas apos esse teste.
    end;

    if not Cliente.TestConnection(oMarketplace.Token, ShopCipher, RespostaJSON) then
      Result := 'Falha no teste de conexao: ' + RespostaJSON;
  finally
    Cliente.Free;
  end;
end;

function TDClassPadraoMarketplaces.RenovarTokenSeNecessario(
  AMarketplace: TMarketplaces; out ARenovou: Boolean): String;
var
  ClienteShopee: TShopeeOpenAPIClient;
  ClienteAmazon: TAmazonSPAPIClient;
  ClienteMagalu: TMagaluOpenAPIClient;
  ClienteML: TMercadoLivreOpenAPIClient;
  ClienteTikTok: TTikTokShopOpenAPIClient;
  AccessTokenNovo, RefreshTokenNovo, ErroMsg: string;
  SegundosValidade, MargemMinutos: Integer;
  OK: Boolean;
begin
  Result := '';
  ARenovou := False;
  AccessTokenNovo := '';
  RefreshTokenNovo := '';
  ErroMsg := '';
  SegundosValidade := 0;
  OK := False;
  // Sem validade conhecida nao da' pra decidir - deixa a chamada seguir e, se
  // o token estiver mesmo vencido, o proprio marketplace responde o erro.
  // Acontece em loja conectada por versao antiga, que nao gravava a validade.
  if oMarketplace.TokenExpiraEm <= 0 then
    Exit;
  // Margem pra nao estourar no meio de uma operacao longa. O Magalu usa 10
  // minutos porque o refresh token dele e' de uso unico: se a renovacao pegar
  // o token ja' vencido, nao ha segunda chance.
  if AMarketplace = TMarketplaces.Magalu then
    MargemMinutos := 10
  else
    MargemMinutos := 5;
  if Now < IncMinute(oMarketplace.TokenExpiraEm, -MargemMinutos) then
    Exit;
  if oMarketplace.RefreshToken = '' then
  begin
    Result := 'O token de acesso expirou e esta loja nao tem refresh token ' +
      'gravado. Reconecte a loja no SATLojas.';
    Exit;
  end;
  case AMarketplace of
    TMarketplaces.Shopee:
      begin
        ClienteShopee := TShopeeOpenAPIClient.Create(
          StrToInt64Def(oMarketplace.ClientId, 0), oMarketplace.ClientSecret, '',
          oMarketplace.Sandbox);
        try
          with ClienteShopee.RefreshAccessToken(oMarketplace.RefreshToken,
                 StrToInt64Def(oMarketplace.AccountID, 0)) do
          begin
            OK := Success;
            AccessTokenNovo := AccessToken;
            RefreshTokenNovo := RefreshToken;
            // {ATENCAO} so' a Shopee chama esse campo de ExpireIn - os outros
            // quatro usam ExpiresIn. Nao unificar sem mexer no cliente dela.
            SegundosValidade := ExpireIn;
            ErroMsg := ErrorMessage;
          end;
        finally
          ClienteShopee.Free;
        end;
      end;
    TMarketplaces.Amazon:
      begin
        ClienteAmazon := TAmazonSPAPIClient.Create(oMarketplace.ClientId,
          oMarketplace.ClientSecret, '', AMAZON_MARKETPLACE_ID_BRASIL,
          oMarketplace.Sandbox);
        try
          with ClienteAmazon.RefreshAccessToken(oMarketplace.RefreshToken) do
          begin
            OK := Success;
            AccessTokenNovo := AccessToken;
            RefreshTokenNovo := RefreshToken;
            SegundosValidade := ExpiresIn;
            ErroMsg := ErrorMessage;
          end;
        finally
          ClienteAmazon.Free;
        end;
      end;
    TMarketplaces.Magalu:
      begin
        ClienteMagalu := TMagaluOpenAPIClient.Create(oMarketplace.ClientId,
          oMarketplace.ClientSecret, '', MAGALU_SCOPES_PADRAO, oMarketplace.Sandbox);
        try
          with ClienteMagalu.RefreshAccessToken(oMarketplace.RefreshToken) do
          begin
            OK := Success;
            AccessTokenNovo := AccessToken;
            RefreshTokenNovo := RefreshToken;
            SegundosValidade := ExpiresIn;
            ErroMsg := ErrorMessage;
          end;
        finally
          ClienteMagalu.Free;
        end;
      end;
    TMarketplaces.MercadoLivre:
      begin
        ClienteML := TMercadoLivreOpenAPIClient.Create(oMarketplace.ClientId,
          oMarketplace.ClientSecret, '', oMarketplace.Sandbox);
        try
          with ClienteML.RefreshAccessToken(oMarketplace.RefreshToken) do
          begin
            OK := Success;
            AccessTokenNovo := AccessToken;
            RefreshTokenNovo := RefreshToken;
            SegundosValidade := ExpiresIn;
            ErroMsg := ErrorMessage;
          end;
        finally
          ClienteML.Free;
        end;
      end;
    TMarketplaces.TikTokShop:
      begin
        ClienteTikTok := TTikTokShopOpenAPIClient.Create(oMarketplace.ClientId,
          oMarketplace.ClientSecret, oMarketplace.App, oMarketplace.Sandbox);
        try
          with ClienteTikTok.RefreshAccessToken(oMarketplace.RefreshToken) do
          begin
            OK := Success;
            AccessTokenNovo := AccessToken;
            RefreshTokenNovo := RefreshToken;
            SegundosValidade := ExpiresIn;
            ErroMsg := ErrorMessage;
          end;
        finally
          ClienteTikTok.Free;
        end;
      end;
  else
    // Marketplace sem fluxo OAuth (VTex, Bagy, Tray, iFood, NuvemShop) - nao
    // tem token com validade pra renovar.
    Exit;
  end;
  if not OK then
  begin
    Result := 'O token de acesso expirou e nao foi possivel renova-lo: ' +
      ErroMsg + '. Reconecte a loja no SATLojas.';
    Exit;
  end;
  oMarketplace.Token := AccessTokenNovo;
  // So' substitui o refresh token se veio um novo. Shopee e Amazon costumam
  // devolver vazio e manter o mesmo - sobrescrever com vazio derrubaria a
  // conexao na renovacao seguinte.
  if RefreshTokenNovo <> '' then
    oMarketplace.RefreshToken := RefreshTokenNovo;
  oMarketplace.TokenExpiraEm := IncSecond(Now, SegundosValidade);
  ARenovou := True;
end;

function TDClassPadraoMarketplaces.TestarConexaoMarketplace(
  TMarketplace: TMarketplaces): String;
begin
  case TMarketplace of
    Nenhum: ;
    VTex:
    begin

    end;
    Bagy:
    begin
      {var bagy := TDClassPadrao.Create(nil, DZ.ZDatabase);
      try
        bagy.acao := uDOOCA.sCriando;
        bagy.TestarConexaoDooca;
      finally
        bagy.Free;
      end;}
    end;
    Tray:
    begin
      {var tray := TTRClassPadrao.Create(nil, DZ.ZDatabase);
      try
        tray.acao := uTRAY.sCriando;
        tray.EcommerceStore := oMarketplace.Loja;
        tray.ConsumerKey := oMarketplace.Key;
        tray.ConsumerSecret :=  oMarketplace.ClientSecret;
        tray.AppCode := oMarketplace.ClientId;

        tray.TestarConexaoTray;
      finally
        tray.Free;
      end;}
    end;
    iFoodMercado:
    begin
      {var iFoodMercado := TiFood.Create;
      try
        iFoodMercado.Client_ID := oMarketplace.ClientId;
        iFoodMercado.Client_Secret := oMarketplace.ClientSecret;

        if iFoodMercado.Conectar then
        begin
          if iFoodMercado.RespostaString <> '' then
          begin
            Result := iFoodMercado.RespostaString;
            Exit;
          end;
        end;
      finally
        iFoodMercado.Free;
      end;}
    end;
    NuvemShop:
    begin

    end;
    Shopee:
    begin
      Result := TestarConexaoShopee;
    end;
    MercadoLivre:
    begin
      Result := TestarConexaoMercadoLivre;
    end;
    TikTokShop:
    begin
      Result := TestarConexaoTikTokShop;
    end;
    Magalu:
    begin
      Result := TestarConexaoMagalu;
    end;
    Amazon:
    begin
      Result := TestarConexaoAmazon;
    end;
  end;
end;

function TDClassPadraoMarketplaces.ConectarMarketplace(
  TMarketplace: TMarketplaces): String;
begin
  Result := '';
  case TMarketplace of
    Nenhum, VTex, Bagy, Tray, iFoodMercado, NuvemShop:
      Result := 'Conexao automatica ainda nao implementada para este marketplace.';
    Shopee:
      Result := ConectarShopee;
    Magalu:
      Result := ConectarMagalu;
    Amazon:
      Result := ConectarAmazon;
    MercadoLivre:
      Result := ConectarMercadoLivre;
    TikTokShop:
      Result := ConectarTikTokShop;
  end;
end;

function TDClassPadraoMarketplaces.DesconectarMarketplace(
  TMarketplace: TMarketplaces): String;
begin
  Result := '';
  case TMarketplace of
    Nenhum, VTex, Bagy, Tray, iFoodMercado, NuvemShop:
      Result := 'Desconexao ainda nao implementada para este marketplace.';
    Shopee:
      Result := DesconectarShopee;
    Magalu:
      Result := DesconectarMagalu;
    Amazon:
      Result := DesconectarAmazon;
    MercadoLivre:
      Result := DesconectarMercadoLivre;
    TikTokShop:
      Result := DesconectarTikTokShop;
  end;
end;

end.
