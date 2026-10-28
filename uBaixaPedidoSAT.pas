// ============================================================================
// UNIT: uBaixaPedidoSAT
// OBJETIVO: "Baixar" um pedido de marketplace no SAT - transformar o
// pedido em OE + IOE + PGTOS de verdade e emitir a venda via
// VENDA_EMITIR_251103A.
//
// MAPEAMENTO DE CAMPOS: baseado no de-para respondido pelo cliente em
// 22/08/2026 (SAT_BD_Shopee_De_para.xlsx) - cobre SOMENTE Shopee por
// enquanto. Amazon e Magalu ainda nao tem de-para respondido; quando
// vierem, a estrutura de TDadosPedidoSAT abaixo pode precisar crescer
// (campos que a Shopee tem e Amazon/Magalu nao, ou vice-versa).
//
// PADRAO DOS CAMPOS "OBS": o de-para do cliente aponta um bocado de
// campos da API (que nao tem coluna dedicada na OE/IOE) pro campo texto
// OBS. A pedido do cliente, cada um desses campos entra em OBS no
// formato "Nome do Campo -> Valor da API", um por linha - ver
// MontarTextoObs.
//
// JA RESOLVIDO PELO CLIENTE (fica registrado pra nao ser reaberto):
//   - oe.MOTIVO_E (recebe shipping_carrier) foi aumentado pra VARCHAR(100)
//     em 28/08/2026 - confirmado direto no banco.
//   - lojas.MARKETPLACE_FORMADEPGTO foi criado em 28/08/2026. O
//     BuscarFormaDePgtoDaLoja abaixo le esse campo; ele era o unico item
//     que travava a baixa de TODOS os marketplaces, inclusive a Shopee.
//   - VENDA_EMITIR_251103A e' mesmo a procedure atual - confirmado pelo
//     cliente em 28/08/2026. Se um dia sair uma versao nova, o nome esta
//     numa constante so' (ver a chamada em BaixarPedidoSAT).
//   - Tabela CLI: nome confirmado pelo cliente em 28/08/2026 (nao e'
//     CLIENTES). {NOTA} os NOMES DOS CAMPOS (cli.cli, cli.cpf, cli.codcli,
//     cli.telr, cli.endr, cli.cidr, cli.estr, cli.cepr, cli.pais) vieram do
//     de-para escrito pelo proprio cliente, mas nao foram conferidos um a um
//     no banco - se algum INSERT/UPDATE de CLI reclamar de coluna, e' ai.
//   - PROD/COD/PCIF - confirmado pelo cliente em 24/08/2026.
//   - "oe.total = SUM(ioe.Valortotal)": confirmado em 30/08/2026 que e'
//     mesmo o conceito de ioe.vcon (valor * quantidade). O "Valortotal" da
//     planilha era so' informativo, nao um campo diferente.
//   - Cliente sem CPF (Amazon e TikTok Shop): decidido em 30/08/2026 que o
//     cliente E' criado assim mesmo, com CPF NULL, e o CODCLI gerado vai
//     pra OE.CODCLI - ver BuscarOuCriarCliente.
//
// Nao ha mais pendencia de mapeamento em aberto para a baixa de pedido.
// ============================================================================
unit uBaixaPedidoSAT;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Data.DB, FireDAC.Comp.Client;

const
  // Procedure de emissao da venda. Nome confirmado pelo cliente em
  // 28/08/2026. Se sair uma versao nova, trocar SO aqui - o resto do
  // codigo referencia esta constante.
  PROCEDURE_VENDA_EMITIR = 'VENDA_EMITIR_251103A';

type
  // Um par (nome do campo em portugues/referencia, valor vindo da API) -
  // usado pra montar os campos OBS no formato pedido pelo cliente:
  // "Nome do Campo -> Valor da API", um por linha.
  TCampoObs = record
    Nome: string;
    Valor: string;
    constructor Create(const ANome, AValor: string);
  end;
  TCamposObsArray = TArray<TCampoObs>;

  // Item do pedido, ja normalizado - mapeamento confirmado pelo de-para
  // da Shopee (get_order_detail.item_list + get_escrow_detail.items[]).
  TItemPedidoSAT = record
    // --- Campos com coluna dedicada na IOE ---
    ItemIdMarketplace: string;    // item_id - so usado pra localizar
                                    // PRODUTOS_MARKETPLACE.CODPRODUTO (vira
                                    // ioe.cod via lookup, nao e' gravado direto)
    CodigoDeBarras: string;       // item_sku -> ioe.CODIGODEBARRAS
    IdItemPedido: string;         // order_item_id -> ioe.OBS ({CORRECAO
                                    // 24/08} ioe.id_item NAO e' auto-
                                    // incremento (confirmado pelo cliente
                                    // direto no banco) - e' um sequencial
                                    // gerado por MAX+1 em BaixarPedidoSAT.
                                    // O order_item_id do marketplace vai
                                    // pro OBS, junto com os outros campos
                                    // sem coluna dedicada)
    Tamanho: string;              // model_name -> ioe.TAMANHO
    Quantidade: Double;           // model_quantity_purchased -> ioe.QUANT
    PrecoDeVenda: Double;         // model_original_price -> ioe.PRECODEVENDA
    Valor: Double;                // model_discounted_price -> ioe.VALOR
    // --- Sem coluna dedicada - concatenados em ioe.obs ---
    // (item_name, model_id, model_sku, promotion_group_id,
    // product_location_id, e o detalhamento financeiro do
    // get_escrow_detail: original_price, sale_price, discounted_price,
    // seller_discount, shopee_discount, is_wholesale, is_add_on_deal,
    // is_main_item, weight)
    CamposObs: TCamposObsArray;
  end;
  TItensPedidoSATArray = TArray<TItemPedidoSAT>;

  // Dados do pedido, ja normalizados - mapeamento confirmado pelo
  // de-para da Shopee (get_order_detail + get_escrow_detail).
  TDadosPedidoSAT = record
    // --- Chave / identificacao ---
    Loja: Integer;
    CodMarketplace: Integer;
    CodPedidoMarketplace: string;       // order_sn -> oe.xped

    // --- Campos com coluna dedicada na OE ---
    StatusMarketplace: string;          // order_status -> oe.marketplace_status (varchar 20)
    DataCriacao: TDateTime;             // create_time -> oe.HORA
    DataUltimaAtualizacao: TDateTime;   // update_time -> oe.DATAHORADOENVIO
    ValorTotalPedido: Double;           // total_amount -> oe.TOTALDOPEDIDO
    FreteReal: Double;                  // actual_shipping_fee (get_order_detail) -> oe.frete
    Transportadora: string;             // shipping_carrier -> oe.MOTIVO_E ({ATENCAO} pedido do cliente: aumentar tamanho do campo no banco)
    DataColeta: TDateTime;              // pickup_done_time -> oe.data_ent
    ValorRepasse: Double;               // escrow_amount (get_escrow_detail) -> pgtos.VALOR_CON / pgtos.VALOR_PG

    // --- Cliente (upsert por CPF) ---
    CodClienteMarketplace: string;      // buyer_user_id (id do comprador na Shopee, so' referencia)
    NomeCliente: string;                // buyer_username -> cli.cli
    CpfCliente: string;                 // buyer_cpf_id -> cli.cpf (se achar CPF ja cadastrado, atualiza; senao insere)
    TelefoneEntrega: string;            // recipient_address.phone -> cli.telr
    EnderecoEntrega: string;            // recipient_address (rua+numero+bairro montado) -> cli.endr
    BairroEntrega: string;              // bairro do endereco de entrega -> cli.BAIR (varchar 20)
    CidadeEntrega: string;              // recipient_address.city -> cli.cidr
                                        // (e usada pra achar o codigo IBGE do
                                        // municipio -> cli.IBGECODIGODOMUNICIPIO)
    EstadoEntrega: string;              // recipient_address.state -> cli.estr
    CepEntrega: string;                 // recipient_address.zipcode -> cli.cepr
    PaisEntrega: string;                // recipient_address.country -> cli.pais

    // --- Sem coluna dedicada - concatenados em oe.obs ---
    // (pay_time, currency, estimated_shipping_fee,
    // actual_shipping_fee_confirmed, package_list, split_up,
    // payment_method, credit_card_number, buyer_cancel_reason,
    // cancel_by, cancel_reason, note, note_update_time, dropshipper,
    // dropshipper_phone, goods_to_declare, fulfillment_flag,
    // invoice_data, e o resumo financeiro do get_escrow_detail sem
    // campo dedicado: buyer_total_amount, buyer_payment_info.*,
    // actual_shipping_fee [versao do escrow], buyer_paid_shipping_fee,
    // shipping_fee_rebate_from_shopee, reverse_shipping_fee,
    // transaction_fee, commission_fee, service_fee,
    // buyer_transaction_fee, insurance_fee, vat,
    // seller_withholding_tax, coins, voucher_from_seller,
    // voucher_from_shopee, credit_card_promotion, return_order_sn_list)
    CamposObs: TCamposObsArray;

    Itens: TItensPedidoSATArray;
  end;

// Confere se esse pedido (LOJA + COD_MARKETPLACE + COD_PEDIDO_MARKETPLACE)
// ja foi baixado antes.
function PedidoJaBaixado(AQuery: TFDQuery; const ALoja, ACodMarketplace: Integer;
  const ACodPedidoMarketplace: string): Boolean;

// Monta o texto do campo OBS no formato pedido pelo cliente:
// "Nome do Campo -> Valor da API" (um por linha). Pula pares cujo Valor
// esteja vazio, pra nao poluir o campo com linhas sem informacao.
function MontarTextoObs(const ACampos: TCamposObsArray): string;

// Executa a baixa completa (OE + IOE + PGTOS + VENDA_EMITIR_251103A +
// MARKETPLACE_PEDIDOS) dentro de uma unica transacao. ARetornoProcedure e
// AErroInformacaoAdicional sao os 2 valores de retorno REAIS da procedure
// VENDA_EMITIR_251103A (RETORNO INTEGER, ERROINFORMACAOADICIONAL
// VARCHAR(1024)) - sempre preenchidos quando a procedure chega a ser
// executada (mesmo em caso de falha de negocio dela), pra o chamador
// poder logar os dois e o cliente entender exatamente o que aconteceu.
// RETORNO = 0 e' sucesso (confirmado pelo cliente apos teste real -
// 24/08); qualquer
// outro valor e' tratado aqui como falha (rollback automatico).
function BaixarPedidoSAT(AQuery: TFDQuery; const ADados: TDadosPedidoSAT;
  out ARetornoProcedure: Integer; out AErroInformacaoAdicional: string;
  out AErrorMessage: string): Boolean;

implementation

uses
  uMarketplace;

{ TCampoObs }

constructor TCampoObs.Create(const ANome, AValor: string);
begin
  Nome := ANome;
  Valor := AValor;
end;

function MontarTextoObs(const ACampos: TCamposObsArray): string;
var
  Linhas: TStringList;
  Campo: TCampoObs;
begin
  Linhas := TStringList.Create;
  try
    for Campo in ACampos do
      if Trim(Campo.Valor) <> '' then
        Linhas.Add(Campo.Nome + ' -> ' + Campo.Valor);
    Result := Linhas.Text;
  finally
    Linhas.Free;
  end;
end;

function PedidoJaBaixado(AQuery: TFDQuery; const ALoja, ACodMarketplace: Integer;
  const ACodPedidoMarketplace: string): Boolean;
begin
  AQuery.Close;
  AQuery.SQL.Text :=
    'SELECT ID FROM MARKETPLACE_PEDIDOS ' +
    'WHERE LOJA = :LOJA AND COD_MARKETPLACE = :COD_MARKETPLACE ' +
    'AND COD_PEDIDO_MARKETPLACE = :COD_PEDIDO_MARKETPLACE';
  AQuery.ParamByName('LOJA').AsInteger := ALoja;
  AQuery.ParamByName('COD_MARKETPLACE').AsInteger := ACodMarketplace;
  AQuery.ParamByName('COD_PEDIDO_MARKETPLACE').AsString := ACodPedidoMarketplace;
  AQuery.Open;
  try
    Result := not AQuery.IsEmpty;
  finally
    AQuery.Close;
  end;
end;

// Monta o padrao LIKE pra achar a cidade na tabela CIDADES, que guarda o
// nome sem acento e em maiusculo ("SAO PAULO") - o marketplace manda "São
// Paulo". Apostrofo e hifen viram "_" (qualquer caractere): a CIDADES grava
// "SANTA BARBARA D?OESTE" com um apostrofo diferente do ' que vem da API, e
// hifen/espaco aparecem trocados de um lado pro outro ("EMBU-GUACU").
function PadraoNomeCidade(const ACidade: string): string;
const
  COM_ACENTO = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  SEM_ACENTO = 'AAAAAEEEEIIIIOOOOOUUUUCN';
  CORINGA = '''’´`-';
var
  I, P: Integer;
begin
  Result := AnsiUpperCase(Trim(ACidade));
  for I := 1 to Length(Result) do
  begin
    P := Pos(Result[I], COM_ACENTO);
    if P > 0 then
      Result[I] := SEM_ACENTO[P]
    else if Pos(Result[I], CORINGA) > 0 then
      Result[I] := '_';
  end;
end;

// Codigo IBGE do municipio pela tabela CIDADES (cidade + UF). Devolve 0
// quando nao acha - o chamador grava NULL nesse caso. A tabela CEPS teria o
// codigo por CEP, mas vem vazia, entao a busca e' pelo nome.
function BuscarCodigoIBGE(AQuery: TFDQuery; const ACidade, AUF: string): Integer;
begin
  Result := 0;
  if (Trim(ACidade) = '') or (Trim(AUF) = '') then
    Exit;
  AQuery.Close;
  AQuery.SQL.Text :=
    'SELECT FIRST 1 CODIGOMUNICIPIODOIBGE FROM CIDADES ' +
    'WHERE ESTADO = :ESTADO AND UPPER(CIDADE) LIKE :CIDADE';
  AQuery.ParamByName('ESTADO').AsString := UpperCase(Trim(AUF));
  AQuery.ParamByName('CIDADE').AsString := PadraoNomeCidade(ACidade);
  AQuery.Open;
  try
    if not AQuery.IsEmpty then
      Result := AQuery.FieldByName('CODIGOMUNICIPIODOIBGE').AsInteger;
  finally
    AQuery.Close;
  end;
end;

// Parametros BAIR e IBGE do INSERT/UPDATE da CLI - vazio/0 vira NULL.
procedure DefinirBairroEIBGE(AQuery: TFDQuery; const ABairro: string;
  ACodIBGE: Integer);
begin
  if ABairro <> '' then
    AQuery.ParamByName('BAIR').AsString := ABairro
  else
  begin
    AQuery.ParamByName('BAIR').DataType := ftString;
    AQuery.ParamByName('BAIR').Clear;
  end;
  if ACodIBGE <> 0 then
    AQuery.ParamByName('IBGE').AsInteger := ACodIBGE
  else
  begin
    AQuery.ParamByName('IBGE').DataType := ftInteger;
    AQuery.ParamByName('IBGE').Clear;
  end;
end;

// Busca o cliente pelo CPF; se achar, devolve o CODCLI existente
// (atualizando nome/endereco); se nao achar, insere um novo e devolve o
// CODCLI recem-criado. {ATENCAO} nomes de tabela/campo (CLI, cli.codcli,
// cli.cli, cli.cpf, cli.telr, cli.endr, cli.cidr, cli.estr, cli.cepr,
// cli.pais) usados exatamente como vieram do de-para do cliente - troque
// aqui se o nome real for diferente. O gerador de CODCLI pra clientes
// novos tambem e' um TODO - usa MAX+1 como placeholder (mesmo padrao ja
// usado em TFrmOfertasMarketplace.ProximoCodigoProdutoMarketplace),
// trocar por GEN_ID se existir um gerador proprio da tabela CLI.
function BuscarOuCriarCliente(AQuery: TFDQuery; const ADados: TDadosPedidoSAT): Integer;
var
  TemCpf: Boolean;
  CodIBGE: Integer;
  Bairro: string;
begin
  Result := 0;
  TemCpf := Trim(ADados.CpfCliente) <> '';
  // Pedido do cliente 28/10/2026: preencher codigo IBGE do municipio e
  // bairro. CLI.BAIR e' VARCHAR(20) - corta pra nao estourar a coluna.
  CodIBGE := BuscarCodigoIBGE(AQuery, ADados.CidadeEntrega, ADados.EstadoEntrega);
  Bairro := Copy(Trim(ADados.BairroEntrega), 1, 20);

  // {DECISAO DO CLIENTE - 30/08/2026} Marketplace que nao devolve CPF
  // (Amazon e TikTok Shop) NAO fica mais sem cliente: o cliente e' criado
  // assim mesmo, com CPF NULL, e o CODCLI gerado vai pra OE.CODCLI. Nome e
  // endereco vem do pedido normalmente - so' o CPF fica em branco.
  //
  // {ATENCAO} sem CPF nao existe chave pra deduplicar, entao CADA pedido
  // desses cria um cliente NOVO: um comprador recorrente da Amazon vira
  // varios registros em CLI. Foi aceito assim pelo cliente. Se um dia
  // incomodar, o caminho e' guardar o id do comprador no marketplace
  // (ADados.CodClienteMarketplace, que ja vem preenchido) numa coluna
  // propria da CLI e deduplicar por ela.
  if TemCpf then
  begin
    AQuery.Close;
    AQuery.SQL.Text := 'SELECT CODCLI FROM CLI WHERE CPF = :CPF';
    AQuery.ParamByName('CPF').AsString := ADados.CpfCliente;
    AQuery.Open;
    try
      if not AQuery.IsEmpty then
      begin
        Result := AQuery.FieldByName('CODCLI').AsInteger;
        AQuery.Close;

        // Cliente ja existe - atualiza nome/endereco com os dados mais
        // recentes vindos do pedido (o comprador pode ter mudado endereco
        // de entrega desde a ultima compra).
        // Bairro e IBGE: quando o pedido nao traz (NULL), mantem o que ja
        // estava no cadastro em vez de apagar.
        AQuery.SQL.Text :=
          'UPDATE CLI SET CLI = :CLI, TELR = :TELR, ENDR = :ENDR, ' +
          'CIDR = :CIDR, ESTR = :ESTR, CEPR = :CEPR, PAIS = :PAIS, ' +
          'BAIR = COALESCE(CAST(:BAIR AS VARCHAR(20)), BAIR), ' +
          'IBGECODIGODOMUNICIPIO = COALESCE(CAST(:IBGE AS INTEGER), IBGECODIGODOMUNICIPIO) ' +
          'WHERE CODCLI = :CODCLI';
        DefinirBairroEIBGE(AQuery, Bairro, CodIBGE);
        AQuery.ParamByName('CLI').AsString := ADados.NomeCliente;
        AQuery.ParamByName('TELR').AsString := ADados.TelefoneEntrega;
        AQuery.ParamByName('ENDR').AsString := ADados.EnderecoEntrega;
        AQuery.ParamByName('CIDR').AsString := ADados.CidadeEntrega;
        AQuery.ParamByName('ESTR').AsString := ADados.EstadoEntrega;
        AQuery.ParamByName('CEPR').AsString := StringReplace(ADados.CepEntrega, '-', '', [rfReplaceAll]);
        AQuery.ParamByName('PAIS').AsString := ADados.PaisEntrega;
        AQuery.ParamByName('CODCLI').AsInteger := Result;
        AQuery.ExecSQL;
        Exit;
      end;
    finally
      AQuery.Close;
    end;
  end;

  // Nao achou (ou nem procurou, por nao ter CPF) - insere cliente novo.
  // {TODO} MAX+1 e' placeholder - trocar por GEN_ID(gerador_da_CLI, 1)
  // se existir (evita corrida em ambiente multiusuario).
  AQuery.Close;
  AQuery.SQL.Text := 'SELECT COALESCE(MAX(CODCLI), 0) + 1 AS PROXIMO FROM CLI';
  AQuery.Open;
  Result := AQuery.FieldByName('PROXIMO').AsInteger;
  AQuery.Close;

  AQuery.SQL.Text :=
    'INSERT INTO CLI (CODCLI, CLI, CPF, TELR, ENDR, CIDR, ESTR, CEPR, PAIS, ' +
    'BAIR, IBGECODIGODOMUNICIPIO) ' +
    'VALUES (:CODCLI, :CLI, :CPF, :TELR, :ENDR, :CIDR, :ESTR, :CEPR, :PAIS, ' +
    ':BAIR, :IBGE)';
  AQuery.ParamByName('CODCLI').AsInteger := Result;
  DefinirBairroEIBGE(AQuery, Bairro, CodIBGE);
  AQuery.ParamByName('CLI').AsString := ADados.NomeCliente;
  // {ATENCAO} sem CPF grava NULL, nao string vazia: Clear e' o que zera o
  // parametro pra nulo no FireDAC. String vazia criaria um ''valor'' que
  // quebraria qualquer busca futura por CPF e atrapalharia a deduplicacao.
  if TemCpf then
    AQuery.ParamByName('CPF').AsString := ADados.CpfCliente
  else
    AQuery.ParamByName('CPF').Clear;
  AQuery.ParamByName('TELR').AsString := ADados.TelefoneEntrega;
  AQuery.ParamByName('ENDR').AsString := ADados.EnderecoEntrega;
  AQuery.ParamByName('CIDR').AsString := ADados.CidadeEntrega;
  AQuery.ParamByName('ESTR').AsString := ADados.EstadoEntrega;
  AQuery.ParamByName('CEPR').AsString := StringReplace(ADados.CepEntrega, '-', '', [rfReplaceAll]);
  AQuery.ParamByName('PAIS').AsString := ADados.PaisEntrega;
  AQuery.ExecSQL;
end;

// Localiza o CODPRODUTO interno a partir do item_id do marketplace, via
// PRODUTOS_MARKETPLACE (mesma tabela/join ja usada nas telas de Ofertas).
function BuscarCodProdutoPeloItem(AQuery: TFDQuery; const ACodMarketplace: Integer;
  const AItemIdMarketplace: string): Integer;
begin
  Result := 0;
  AQuery.Close;
  AQuery.SQL.Text :=
    'SELECT CODPRODUTO FROM PRODUTOS_MARKETPLACE ' +
    'WHERE CODMARKETPLACE = :CODMARKETPLACE AND CODPRODUTONOMARKETPLACE = :ITEM_ID';
  AQuery.ParamByName('CODMARKETPLACE').AsInteger := ACodMarketplace;
  AQuery.ParamByName('ITEM_ID').AsString := AItemIdMarketplace;
  AQuery.Open;
  try
    if not AQuery.IsEmpty then
      Result := AQuery.FieldByName('CODPRODUTO').AsInteger;
  finally
    AQuery.Close;
  end;
end;

// Busca o custo (CIF) do produto - usado no calculo de ioe.Lbru
// (Lucro Bruto) = (valor - pcif) * quantidade. {CONFIRMADO} tabela real
// e' PROD (campo COD), corrigido em 24/08 - antes estava PRODUTOS/
// CODPRODUTO, nome errado.
function BuscarCustoProduto(AQuery: TFDQuery; const ACodProduto: Integer): Double;
begin
  Result := 0;
  if ACodProduto = 0 then
    Exit;
  AQuery.Close;
  AQuery.SQL.Text := 'SELECT PCIF FROM PROD WHERE COD = :CODPRODUTO';
  AQuery.ParamByName('CODPRODUTO').AsInteger := ACodProduto;
  AQuery.Open;
  try
    if not AQuery.IsEmpty then
      Result := AQuery.FieldByName('PCIF').AsFloat;
  finally
    AQuery.Close;
  end;
end;

// Busca o codigo da forma de pagamento configurado na loja
// (LOJAS.MARKETPLACE_FORMADEPGTO) - usado em pgtos.ent. Campo criado pelo
// cliente em 28/08/2026.
// {ATENCAO} continua sendo chamada ANTES de qualquer INSERT de proposito:
// se a loja nao estiver com a forma de pagamento configurada, a baixa falha
// aqui e a transacao inteira faz rollback, sem gravar nada pela metade.
function BuscarFormaDePgtoDaLoja(AQuery: TFDQuery; const ALoja: Integer): Integer;
begin
  AQuery.Close;
  AQuery.SQL.Text := 'SELECT MARKETPLACE_FORMADEPGTO FROM LOJAS WHERE LOJA = :LOJA';
  AQuery.ParamByName('LOJA').AsInteger := ALoja;
  AQuery.Open;
  try
    if AQuery.IsEmpty then
      raise Exception.Create('Loja ' + ALoja.ToString + ' nao encontrada.');
    Result := AQuery.FieldByName('MARKETPLACE_FORMADEPGTO').AsInteger;
    // Antes passava com 0 e o pagamento ficava sem codigo/descricao na
    // tela de pedidos do SAT (visto no cliente em 27/10/2026).
    if Result = 0 then
      raise Exception.Create('Loja ' + ALoja.ToString + ' sem forma de pagamento ' +
        'de marketplace configurada (LOJAS.MARKETPLACE_FORMADEPGTO). Configure ' +
        'no cadastro da loja e baixe o pedido de novo.');
  finally
    AQuery.Close;
  end;
end;

// Loja de entrega da loja conectada (LOJAS.CODLOJAENTREGA) - vai pra
// IOE.LOJAENTR de cada item (pedido do cliente 27/10/2026). Mesma regra do
// F2: sem loja de entrega cadastrada a baixa nao continua. Chamada ANTES de
// qualquer INSERT, entao a falha nao deixa nada gravado pela metade.
function BuscarLojaEntregaDaLoja(AQuery: TFDQuery; const ALoja: Integer): Integer;
begin
  AQuery.Close;
  AQuery.SQL.Text := 'SELECT CODLOJAENTREGA FROM LOJAS WHERE LOJA = :LOJA';
  AQuery.ParamByName('LOJA').AsInteger := ALoja;
  AQuery.Open;
  try
    if AQuery.IsEmpty then
      raise Exception.Create('Loja ' + ALoja.ToString + ' nao encontrada.');
    Result := AQuery.FieldByName('CODLOJAENTREGA').AsInteger;
    if Result = 0 then
      raise Exception.Create('Loja ' + ALoja.ToString + ' sem loja de entrega ' +
        'cadastrada (LOJAS.CODLOJAENTREGA). Cadastre a loja de entrega e ' +
        'baixe o pedido de novo.');
  finally
    AQuery.Close;
  end;
end;

function BaixarPedidoSAT(AQuery: TFDQuery; const ADados: TDadosPedidoSAT;
  out ARetornoProcedure: Integer; out AErroInformacaoAdicional: string;
  out AErrorMessage: string): Boolean;
var
  CodOE: Integer;
  CodCli: Integer;
  I: Integer;
  CodProdutoItem: Integer;
  CustoItem: Double;
  VConItem, LBruItem: Double;
  SomaLBruto, SomaTotal, SomaValorCon: Double;
  ObsCabecalho: string;
  FormaDePgto: Integer;
  LojaEntrega: Integer;
  ProximoIdItem: Integer;
begin
  Result := False;
  AErrorMessage := '';
  // {ATENCAO} -1 (nao 0!) e' o sentinela de "procedure ainda nao
  // executada" - como RETORNO = 0 agora significa SUCESSO (confirmado
  // pelo cliente), usar 0 como valor inicial ficaria ambiguo (o
  // chamador nao conseguiria distinguir "deu certo" de "nem rodou
  // ainda", por exemplo quando a baixa falha ANTES de chegar na
  // procedure - pedido duplicado, erro ao criar cliente, etc).
  ARetornoProcedure := -1;
  AErroInformacaoAdicional := '';

  if PedidoJaBaixado(AQuery, ADados.Loja, ADados.CodMarketplace,
       ADados.CodPedidoMarketplace) then
  begin
    AErrorMessage := 'Este pedido ja foi baixado no SAT anteriormente.';
    Exit;
  end;

  if Length(ADados.Itens) = 0 then
  begin
    AErrorMessage := 'Pedido sem itens - nao ha o que baixar.';
    Exit;
  end;

  AQuery.Connection.StartTransaction;
  try
    CodCli := BuscarOuCriarCliente(AQuery, ADados);

    // Pre-calcula os totais somados dos itens (oe.Lbruto, oe.total,
    // oe.VALOR_CON) ANTES de inserir a OE, pra nao precisar de um UPDATE
    // separado depois. {ATENCAO} "oe.total = SUM(ioe.Valortotal)" no
    // de-para do cliente referencia um campo "Valortotal" que nao esta
    // definido em nenhum outro lugar da planilha - assumimos que e' o
    // mesmo que ioe.vcon (valor * quantidade) ate confirmar com o
    // cliente.
    SomaLBruto := 0;
    SomaTotal := 0;
    SomaValorCon := 0;
    for I := Low(ADados.Itens) to High(ADados.Itens) do
    begin
      CodProdutoItem := BuscarCodProdutoPeloItem(AQuery, ADados.CodMarketplace,
        ADados.Itens[I].ItemIdMarketplace);
      CustoItem := BuscarCustoProduto(AQuery, CodProdutoItem);
      VConItem := ADados.Itens[I].Valor * ADados.Itens[I].Quantidade;
      LBruItem := (ADados.Itens[I].Valor - CustoItem) * ADados.Itens[I].Quantidade;
      SomaLBruto := SomaLBruto + LBruItem;
      SomaValorCon := SomaValorCon + VConItem;
      SomaTotal := SomaTotal + VConItem; // {ATENCAO} ver nota acima sobre "Valortotal"
    end;

    // Busca a forma de pagamento da loja ANTES de inserir qualquer coisa -
    // se a loja nao tiver MARKETPLACE_FORMADEPGTO configurado, falha aqui
    // (rollback automatico no except abaixo, nada fica gravado pela metade).
    FormaDePgto := BuscarFormaDePgtoDaLoja(AQuery, ADados.Loja);
    LojaEntrega := BuscarLojaEntregaDaLoja(AQuery, ADados.Loja);

    //Inclusão tela de Pedidos.... INSERT INTO OE
    ObsCabecalho := MontarTextoObs(ADados.CamposObs);
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO OE (DATA, XPED, MARKETPLACE_STATUS, HORA, ' +
      'DATAHORADOENVIO, TOTALDOPEDIDO, TOTAL, LBRUTO, VALOR_CON, FRETE, ' +
      'MOTIVO_E, DATA_ENT, CODCLI, OBS, ACRESCIMOFINANCEIRO, TIPO, DIG) ' +
      'VALUES (CURRENT_DATE, :XPED, :MARKETPLACE_STATUS, :HORA, ' +
      ':DATAHORADOENVIO, :TOTALDOPEDIDO, :TOTAL, :LBRUTO, :VALOR_CON, ' +
      ':FRETE, :MOTIVO_E, :DATA_ENT, :CODCLI, :OBS, :ACRESCIMOFINANCEIRO, ' +
      // TIPO fixo 'O' pra todos os marketplaces (pedido do cliente, 26/10/2026).
      '''O'', :DIG) ' +
      'RETURNING ID_OE';
    // DIG = nome do marketplace de origem ("Shopee", "Mercado Livre"...),
    // pedido do cliente 26/10/2026. Coluna VARCHAR(25) - o maior nome hoje
    // tem 13 caracteres.
    AQuery.ParamByName('DIG').AsString :=
      NomeMarketplace(TMarketplaces(ADados.CodMarketplace));
    AQuery.ParamByName('XPED').AsString := ADados.CodPedidoMarketplace;
    AQuery.ParamByName('MARKETPLACE_STATUS').AsString := ADados.StatusMarketplace;
    AQuery.ParamByName('HORA').AsDateTime := ADados.DataCriacao;
    AQuery.ParamByName('DATAHORADOENVIO').AsDateTime := ADados.DataUltimaAtualizacao;
    AQuery.ParamByName('TOTALDOPEDIDO').AsFloat := ADados.ValorTotalPedido;
    AQuery.ParamByName('TOTAL').AsFloat := SomaTotal;
    AQuery.ParamByName('LBRUTO').AsFloat := SomaLBruto;
    AQuery.ParamByName('VALOR_CON').AsFloat := SomaValorCon;
    AQuery.ParamByName('FRETE').AsFloat := ADados.FreteReal;
    // {ATENCAO} MOTIVO_E - cliente pediu pra aumentar o tamanho desse
    // campo no banco (shipping_carrier pode nao caber no tamanho atual).
    AQuery.ParamByName('MOTIVO_E').AsString := ADados.Transportadora;
    if ADados.DataColeta > 0 then
      AQuery.ParamByName('DATA_ENT').AsDateTime := ADados.DataColeta
    else
      AQuery.ParamByName('DATA_ENT').Clear;
    if CodCli <> 0 then
      AQuery.ParamByName('CODCLI').AsInteger := CodCli
    else
      AQuery.ParamByName('CODCLI').Clear;
    AQuery.ParamByName('OBS').AsString := ObsCabecalho;
    // {CONFIRMADO} ACRESCIMOFINANCEIRO e' DOUBLE PRECISION NOT NULL sem
    // default no banco (achado em teste real 24/08) - nao faz parte do
    // de-para do marketplace, entao grava 0 sempre. Se mais colunas
    // NOT NULL sem default aparecerem em testes futuros, o padrao e' o
    // mesmo: adicionar aqui com valor 0 (numerico) ou '' (texto).
    AQuery.ParamByName('ACRESCIMOFINANCEIRO').AsFloat := 0;
    // RETURNING no Firebird devolve um mini-resultset de 1 linha - usa
    // .Open (nao .ExecSQL) pra conseguir ler o ID_OE gerado.
    AQuery.Open;
    CodOE := AQuery.FieldByName('ID_OE').AsInteger;
    AQuery.Close;

    //Inclusão tela de Itens do pedido... INSERT INTO IOE
    // {CORRECAO 24/08} IOE.ID_ITEM NAO e' auto-incremento (confirmado
    // pelo cliente direto no banco - a suposicao anterior estava
    // errada). Precisa ser unico em TODA a tabela IOE, entao calcula
    // aqui via MAX+1 antes do loop e incrementa localmente a cada item
    // inserido (evita reconsultar o banco a cada linha). Mesma ressalva
    // de sempre com MAX+1: nao e' 100% a prova de concorrencia em
    // ambiente multiusuario - se existir um GEN_ID proprio da IOE,
    // trocar por ele.
    AQuery.Close;
    AQuery.SQL.Text := 'SELECT COALESCE(MAX(ID_ITEM), 0) + 1 AS PROXIMO FROM IOE';
    AQuery.Open;
    ProximoIdItem := AQuery.FieldByName('PROXIMO').AsInteger;
    AQuery.Close;

    for I := Low(ADados.Itens) to High(ADados.Itens) do
    begin
      CodProdutoItem := BuscarCodProdutoPeloItem(AQuery, ADados.CodMarketplace,
        ADados.Itens[I].ItemIdMarketplace);
      CustoItem := BuscarCustoProduto(AQuery, CodProdutoItem);
      VConItem := ADados.Itens[I].Valor * ADados.Itens[I].Quantidade;
      LBruItem := (ADados.Itens[I].Valor - CustoItem) * ADados.Itens[I].Quantidade;

      AQuery.Close;
      AQuery.SQL.Text :=
        'INSERT INTO IOE (DATA, ID_OE, ID_ITEM, COD, CODIGODEBARRAS, ' +
        'TAMANHO, QUANT, PRECODEVENDA, VALOR, VCON, LBRU, OBS, LOJAENTR) ' +
        'VALUES (CURRENT_DATE, :ID_OE, :ID_ITEM, :COD, :CODIGODEBARRAS, ' +
        ':TAMANHO, :QUANT, :PRECODEVENDA, :VALOR, :VCON, :LBRU, :OBS, :LOJAENTR)';
      AQuery.ParamByName('ID_OE').AsInteger := CodOE;
      AQuery.ParamByName('LOJAENTR').AsInteger := LojaEntrega;
      AQuery.ParamByName('ID_ITEM').AsInteger := ProximoIdItem;
      Inc(ProximoIdItem);
      if CodProdutoItem <> 0 then
        AQuery.ParamByName('COD').AsInteger := CodProdutoItem
      else
        AQuery.ParamByName('COD').Clear;
      AQuery.ParamByName('CODIGODEBARRAS').AsString := ADados.Itens[I].CodigoDeBarras;
      // order_item_id do marketplace continua indo pro OBS (nao pro
      // ID_ITEM, que agora e' so um numero sequencial interno nosso) -
      // ver ExtrairCamposObsItem em uFrmPedidosMarketplace.pas.
      AQuery.ParamByName('TAMANHO').AsString := ADados.Itens[I].Tamanho;
      AQuery.ParamByName('QUANT').AsFloat := ADados.Itens[I].Quantidade;
      AQuery.ParamByName('PRECODEVENDA').AsFloat := ADados.Itens[I].PrecoDeVenda;
      AQuery.ParamByName('VALOR').AsFloat := ADados.Itens[I].Valor;
      AQuery.ParamByName('VCON').AsFloat := VConItem;
      AQuery.ParamByName('LBRU').AsFloat := LBruItem;
      AQuery.ParamByName('OBS').AsString := MontarTextoObs(ADados.Itens[I].CamposObs);
      AQuery.ExecSQL;
    end;

    //Inclusão do pagamentos... INSERT INTO PGTOS
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO PGTOS (DATA, ID_OE, ID_PG, ENT, VALOR_CON, VALOR_PG, NOME) ' +
      'VALUES (CURRENT_DATE, :ID_OE, 1, :ENT, :VALOR_CON, :VALOR_PG, :NOME)';
    AQuery.ParamByName('ID_OE').AsInteger := CodOE;
    // Nome do cliente no pagamento (pedido do cliente 28/10/2026) - coluna
    // VARCHAR(50).
    AQuery.ParamByName('NOME').AsString := Copy(ADados.NomeCliente, 1, 50);
    AQuery.ParamByName('ENT').AsInteger := FormaDePgto;
    AQuery.ParamByName('VALOR_CON').AsFloat := ADados.ValorRepasse;
    AQuery.ParamByName('VALOR_PG').AsFloat := ADados.ValorRepasse;
    AQuery.ExecSQL;

    // Emite a venda em cima da OE recem-criada. A procedure tem RETURNS
    // (RETORNO INTEGER, ERROINFORMACAOADICIONAL VARCHAR(1024)) - por
    // isso usa .Open (nao .ExecSQL), igual o RETURNING do INSERT da OE,
    // pra conseguir ler os 2 valores de retorno.
    AQuery.Close;
    AQuery.SQL.Text := 'EXECUTE PROCEDURE ' + PROCEDURE_VENDA_EMITIR +
      '(:CODOE, :DATAHOJE)';
    AQuery.ParamByName('CODOE').AsInteger := CodOE;
    AQuery.ParamByName('DATAHOJE').AsDateTime := Date;
    AQuery.Open;
    ARetornoProcedure := AQuery.FieldByName('RETORNO').AsInteger;
    AErroInformacaoAdicional := AQuery.FieldByName('ERROINFORMACAOADICIONAL').AsString;
    AQuery.Close;

    // RETORNO = 0 e' sucesso (confirmado pelo cliente apos teste real -
    // 24/08; "Retorno = 1" visto no corpo da procedure e' so o valor
    // inicial/pendente, sobrescrito antes do fim da execucao). Qualquer
    // valor diferente de 0 e' tratado como falha de negocio da propria
    // procedure - dispara a excecao pra cair no rollback do except
    // abaixo, com a mensagem da propria procedure.
    if ARetornoProcedure <> 0 then
      raise Exception.CreateFmt(
        '%s retornou %d: %s',
        [PROCEDURE_VENDA_EMITIR, ARetornoProcedure, AErroInformacaoAdicional]);

    // So grava o controle de baixa DEPOIS de tudo (OE/IOE/PGTOS/emissao)
    // ter dado certo - se algo acima falhar, o rollback desfaz tudo e o
    // pedido continua "nao baixado", podendo ser tentado de novo sem
    // deixar lixo pra tras.
    AQuery.Close;
    AQuery.SQL.Text :=
      'INSERT INTO MARKETPLACE_PEDIDOS (LOJA, COD_MARKETPLACE, ' +
      'COD_PEDIDO_MARKETPLACE, CODOE, DATABAIXA) VALUES ' +
      '(:LOJA, :COD_MARKETPLACE, :COD_PEDIDO_MARKETPLACE, :CODOE, :DATABAIXA)';
    AQuery.ParamByName('LOJA').AsInteger := ADados.Loja;
    AQuery.ParamByName('COD_MARKETPLACE').AsInteger := ADados.CodMarketplace;
    AQuery.ParamByName('COD_PEDIDO_MARKETPLACE').AsString := ADados.CodPedidoMarketplace;
    AQuery.ParamByName('CODOE').AsInteger := CodOE;
    AQuery.ParamByName('DATABAIXA').AsDateTime := Now;
    AQuery.ExecSQL;

    AQuery.Connection.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      if AQuery.Connection.InTransaction then
        AQuery.Connection.Rollback;
      AErrorMessage := 'Erro ao baixar pedido no SAT: ' + E.Message;
    end;
  end;
end;

end.
