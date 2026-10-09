// ============================================================================
// UNIT: uModosCadastroProduto
// OBJETIVO: Ponto UNICO de manutencao pra dizer quais "modos" de cadastro
// de produto cada marketplace suporta hoje - usado pelo roteador do botao
// "Incluir Produto" (uRoteadorIncluirProduto) pra decidir se abre a tela
// direto ou se precisa perguntar pro usuario qual modo ele quer.
//
// Ao integrar um marketplace novo (Magalu, Mercado Livre, TikTok Shop) ou
// ao adicionar um modo novo pra um marketplace existente, o ajuste fica SO
// na funcao ModosCadastroSuportados abaixo - nenhuma tela precisa mudar.
// ============================================================================
unit uModosCadastroProduto;
interface
uses
  uMarketplace;
type
  // mcpOfertaSimples: o produto ja existe no catalogo do marketplace
  // (Amazon: tem ASIN; Mercado Livre: tem catalog_product_id; etc) - so
  // cria uma oferta de venda em cima dele. Mais rapido, menos campos.
  //
  // mcpProdutoCompleto: o produto ainda nao existe no marketplace -
  // cadastro completo (categoria/productType, atributos obrigatorios,
  // imagens etc). Mais lento, pode exigir aprovacao do marketplace.
  TModoCadastroProduto = (mcpOfertaSimples, mcpProdutoCompleto);
  TModosCadastroProduto = set of TModoCadastroProduto;
function ModosCadastroSuportados(const ACodMarketplace: Integer): TModosCadastroProduto;
function TituloModoCadastro(const AModo: TModoCadastroProduto): string;
function SubtituloModoCadastro(const AModo: TModoCadastroProduto): string;
implementation
function ModosCadastroSuportados(const ACodMarketplace: Integer): TModosCadastroProduto;
begin
  case TMarketplaces(ACodMarketplace) of
    TMarketplaces.Shopee:
      // Shopee so tem cadastro completo (add_item) implementado ate' agora
      // - nao ha' conceito de "oferta em cima de item ja existente" no
      // fluxo atual.
      Result := [mcpProdutoCompleto];
    TMarketplaces.Amazon:
      // Amazon suporta os dois: oferta em cima de ASIN existente
      // (CreateOfferForExistingASIN) e cadastro completo do zero via
      // Product Type Definitions API (uFrmCadastrarProdutoAmazonNovo).
      Result := [mcpOfertaSimples, mcpProdutoCompleto];
    // {TODO} Magalu: existe endpoint de criacao de SKU na Open API
    // (portfolios-v-1-post-skus, confirmado), MAS a doc publica nao expoe
    // como consultar categoria/atributos obrigatorios por categoria (algo
    // que a propria FAQ do Magalu confirma que existe e varia por
    // categoria, igual o productType da Amazon) - sem isso, seria
    // implementar as cegas um fluxo do tamanho do uFrmCadastrarProdutoAmazonNovo
    // inteiro. Decisao (20/08/2026): aguardar conta de vendedor real +
    // acesso ao portal logado do desenvolvedor pra mapear esses dois
    // endpoints antes de codar.
    //
    TMarketplaces.MercadoLivre:
      // Mercado Livre suporta os dois, cada um com tela dedicada:
      //   mcpOfertaSimples   -> oferta em cima de produto de CATALOGO
      //     (catalog_product_id, o equivalente do ASIN da Amazon) -
      //     uFrmCadastrarOfertaCatalogoMercadoLivre.
      //   mcpProdutoCompleto -> anuncio novo do zero, com preditor de
      //     categoria + atributos por categoria + POST /items -
      //     uFrmCadastrarProdutoMercadoLivreNovo.
      // As duas telas sao proprias do ML porque a API dele nao se parece
      // com a da Amazon em nenhum dos dois modos.
      Result := [mcpOfertaSimples, mcpProdutoCompleto];
    TMarketplaces.TikTokShop:
      // TikTok: cadastro completo em uFrmCadastrarProdutoTikTokNovo - categoria
      // recomendada + atributos da categoria + upload de imagem + POST de
      // produto. Mesmo padrao das telas da Amazon e do Mercado Livre.
      //
      // {TODO} O TikTok tambem tem catalogo proprio (produto ja existente na
      // plataforma), que seria o equivalente do mcpOfertaSimples. Nao
      // implementado - quando for, acrescentar mcpOfertaSimples aqui E tratar
      // o caso no roteador, porque a uFrmCadastrarProdutoMarketplace de hoje
      // so' sabe fazer oferta simples da Amazon.
      Result := [mcpProdutoCompleto];
  else
    Result := [];
  end;
end;
function TituloModoCadastro(const AModo: TModoCadastroProduto): string;
begin
  case AModo of
    mcpOfertaSimples: Result := 'Produto já existe no marketplace';
    mcpProdutoCompleto: Result := 'Produto novo';
  else
    Result := '';
  end;
end;
function SubtituloModoCadastro(const AModo: TModoCadastroProduto): string;
begin
  case AModo of
    mcpOfertaSimples:
      Result := 'Você já tem o código do produto no catálogo do marketplace ' +
        '(ASIN, ID de catálogo etc) - só cria uma oferta de venda em cima dele. Mais rápido.';
    mcpProdutoCompleto:
      Result := 'O produto ainda não existe no marketplace - cadastro completo ' +
        '(nome, categoria, atributos, imagens). Pode levar mais tempo até aparecer disponível.';
  else
    Result := '';
  end;
end;
end.
