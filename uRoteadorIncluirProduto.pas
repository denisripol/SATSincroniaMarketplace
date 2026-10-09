// ============================================================================
// UNIT: uRoteadorIncluirProduto
// OBJETIVO: Ponto UNICO de entrada pro botao "Incluir Produto" da tela de
// Ofertas - Marketplace. Decide sozinho, a partir de
// uModosCadastroProduto.ModosCadastroSuportados:
//   - marketplace sem nenhum modo suportado -> avisa e nao abre nada;
//   - marketplace com 1 modo so -> abre a tela certa direto (sem pedir
//     nada ao usuario) - e' o caso da Shopee hoje;
//   - marketplace com mais de 1 modo -> mostra o modal
//     uFrmEscolherTipoCadastro pra o usuario escolher, so DEPOIS abre a
//     tela certa - e' o caso da Amazon e do Mercado Livre hoje
//     (oferta simples x produto completo).
//
// Pra integrar um marketplace novo (Magalu, Mercado Livre, TikTok Shop):
//   1. Declarar o(s) modo(s) suportado(s) em uModosCadastroProduto.
//   2. Se o "produto completo" desse marketplace precisar de uma tela
//      dedicada (categoria/schema dinamico, como a Amazon), criar a tela
//      e adicionar um "if" no case abaixo apontando pra ela - se o modo
//      completo for simples o bastante pra reaproveitar
//      uFrmCadastrarProdutoMarketplace, nao precisa mexer aqui.
// ============================================================================
unit uRoteadorIncluirProduto;
interface
uses
  uModosCadastroProduto;
// Devolve True se algum produto foi cadastrado com sucesso durante a
// sessao (pra tela chamadora decidir se precisa dar refresh na grid de
// ofertas).
function AbrirTelaIncluirProduto(const ALoja, ACodMarketplace: Integer;
  const AAccountID, AToken, ADevClientId, ADevClientSecret: string;
  const ASandbox: Boolean): Boolean;
implementation
uses
  Vcl.Dialogs, uMarketplace, uFrmEscolherTipoCadastro,
  uFrmCadastrarProdutoMarketplace, uFrmCadastrarProdutoAmazonNovo,
  uFrmCadastrarProdutoMercadoLivreNovo,
  uFrmCadastrarOfertaCatalogoMercadoLivre,
  uFrmCadastrarProdutoTikTokNovo;
function AbrirTelaIncluirProduto(const ALoja, ACodMarketplace: Integer;
  const AAccountID, AToken, ADevClientId, ADevClientSecret: string;
  const ASandbox: Boolean): Boolean;
var
  Modos: TModosCadastroProduto;
  ModoEscolhido: TModoCadastroProduto;
begin
  Result := False;
  Modos := ModosCadastroSuportados(ACodMarketplace);

  if Modos = [] then
  begin
    ShowMessage('Cadastro de produto ainda nao disponivel para este marketplace.');
    Exit;
  end;

  if Modos = [mcpOfertaSimples] then
    ModoEscolhido := mcpOfertaSimples
  else if Modos = [mcpProdutoCompleto] then
    ModoEscolhido := mcpProdutoCompleto
  else if not TFrmEscolherTipoCadastro.Escolher(Modos, ModoEscolhido) then
    Exit; // usuario cancelou o dialogo de escolha

  case ModoEscolhido of
    mcpOfertaSimples:
      if TMarketplaces(ACodMarketplace) = TMarketplaces.MercadoLivre then
        // ML "oferta simples" = oferta em cima de produto do CATALOGO
        // (busca no /products/search + POST /items com catalog_product_id).
        // API completamente diferente da Amazon, por isso tela dedicada.
        Result := TFrmCadastrarOfertaCatalogoMercadoLivre.AbrirParaLoja(ALoja,
          ACodMarketplace, AAccountID, AToken, ADevClientId, ADevClientSecret,
          ASandbox)
      else
        // Amazon: a propria uFrmCadastrarProdutoMarketplace ja sabe lidar
        // com ela (CreateOfferForExistingASIN).
        Result := TFrmCadastrarProdutoMarketplace.AbrirParaLoja(ALoja, ACodMarketplace,
          AAccountID, AToken, ADevClientId, ADevClientSecret, ASandbox);
    mcpProdutoCompleto:
      if TMarketplaces(ACodMarketplace) = TMarketplaces.Amazon then
        // Amazon "produto completo" e' o fluxo generico com busca de
        // categoria/schema (Product Type Definitions API) - tela dedicada.
        Result := TFrmCadastrarProdutoAmazonNovo.AbrirParaLoja(ALoja, ACodMarketplace,
          AAccountID, AToken, ADevClientId, ADevClientSecret, ASandbox)
      else if TMarketplaces(ACodMarketplace) = TMarketplaces.MercadoLivre then
        // Mercado Livre "produto completo": preditor de categoria +
        // atributos por categoria + POST /items - mesma ideia da tela da
        // Amazon, mas com API propria, entao tela dedicada tambem.
        Result := TFrmCadastrarProdutoMercadoLivreNovo.AbrirParaLoja(ALoja, ACodMarketplace,
          AAccountID, AToken, ADevClientId, ADevClientSecret, ASandbox)
      else if TMarketplaces(ACodMarketplace) = TMarketplaces.TikTokShop then
        // TikTok "produto completo": categoria recomendada + atributos da
        // categoria + upload de imagem (arquivo, nao URL) + POST de produto.
        // Tela dedicada pelos mesmos motivos das outras duas.
        Result := TFrmCadastrarProdutoTikTokNovo.AbrirParaLoja(ALoja, ACodMarketplace,
          AAccountID, AToken, ADevClientId, ADevClientSecret, ASandbox)
      else
        // Shopee (e qualquer marketplace futuro cujo "produto completo"
        // seja simples o bastante pra caber na tela generica) usa a mesma
        // uFrmCadastrarProdutoMarketplace de sempre.
        Result := TFrmCadastrarProdutoMarketplace.AbrirParaLoja(ALoja, ACodMarketplace,
          AAccountID, AToken, ADevClientId, ADevClientSecret, ASandbox);
  end;
end;
end.
